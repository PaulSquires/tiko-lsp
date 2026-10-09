'' ############################################################################
''  handlers/signature_help.bas -- textDocument/signatureHelp
''
''  The popup that appears when a '(' is typed and follows the caret from one
''  argument to the next. It answers from the signature the parser recorded
''  when the procedure was declared -- no expression analysis, and no second
''  parse of the file.
''
''  OVERLOADS ARE COUNTED, NOT CHOSEN. Picking between `Add( long )` and
''  `Add( string )` needs the type of what the user has typed so far, which
''  needs the type system this server does not have. The first declaration is
''  shown and `activeSignature` stays 0; the client's "1 of 3" tells the truth
''  about what is known.
'' ############################################################################

#include once "signature_help.bi"
#include once "hover.bi"
#include once "completion.bi"
#include once "workspace_symbols.bi"
#include once "../workspace/index_builder.bi"
#include once "../analysis/signature.bi"
#include once "../utils/logging.bi"

'' Resolves the callee of a call context to a symbol in this document.
private function ResolveCallee( byval doc as TextDocumentPtr, byref ctx as CallContext, _
                                byref alternatives as long ) as long

    dim as string body = doc->Text( )
    dim as Token  tok  = doc->Tokens( )[ctx.NameTok]
    dim as string lowerName = lcase( TokenText( body, tok ) )

    '' `obj.Method(` is a member call and resolves as one -- the same split
    '' hover and completion make, and for the same reason.
    if( IsMemberAccess( body, doc->Tokens( ), ctx.NameTok ) ) then
        alternatives = 0
        dim as long idx = doc->Symbols( ).ResolveMember( lowerName )
        if( idx >= 0 ) then
            if( IsCallableKind( doc->Symbols( ).Items[idx].Kind_ ) = false ) then return -1
            alternatives = 1
        end if
        return idx
    end if

    return FindCallable( doc->Symbols( ), lowerName, ctx.NameTok, alternatives )
end function

'' A CALLEE THIS FILE DOES NOT DECLARE: a sub in another workspace file, or a
'' toolchain header's -- MessageBoxW from windows.bi. Answered from the index,
'' through the files this one can see first (FindDefinitionFrom), the same
'' lookup hover uses. Member calls stay file-local, as ResolveCallee has them:
'' which type's method is meant needs the type of the expression before the dot.
''
'' Never waits for the index: a popup is typed against, and the first keystroke
'' after opening a workspace must not block on a scan. Before the scan lands,
'' this simply finds nothing.
private function ResolveCalleeInIndex( byref srv as Server, byval doc as TextDocumentPtr, _
                                       byref ctx as CallContext, byref sym as SymbolInfo ) as boolean
    dim as string body = doc->Text( )
    dim as string lowerName = lcase( TokenText( body, doc->Tokens( )[ctx.NameTok] ) )
    dim as long here = srv.Index->IndexOfUri( doc->Uri( ) )

    if( IsMemberAccess( body, doc->Tokens( ), ctx.NameTok ) ) then
        '' `strings.PadLeft(` WHERE strings IS AN IMPORT'S ALIAS (tiko-lang ADR 0017):
        '' the module's public declaration, or what its exported macro names -- a std
        '' facade's `#define PadLeft FB.PadLeft` is shown as FB.PadLeft. Any other
        '' member call stays unresolved: which type's method is meant needs the type
        '' of the expression before the dot.
        if( here < 0 orelse ctx.NameTok < 2 ) then return false
        dim as string lowerBase = lcase( TokenText( body, doc->Tokens( )[ctx.NameTok - 2] ) )
        dim as IndexHit target
        dim as ExportHit xh
        if( srv.Index->ModuleMemberAt( here, lowerBase, lowerName, target, xh ) = 0 ) then return false
        if( target.FileIndex < 0 ) then return false
        sym = srv.Index->SymbolAt( target.FileIndex, target.SymIndex )
        return IsCallableKind( sym.Kind_ )
    end if

    dim as IndexHit hit
    if( srv.Index->FindDefinitionFrom( here, lowerName, hit ) = false ) then
        return false
    end if

    sym = srv.Index->SymbolAt( hit.FileIndex, hit.SymIndex )
    return IsCallableKind( sym.Kind_ )
end function

private function OnSignatureHelp( byref srv as Server, _
                                  byref req as RpcMessage, _
                                  byref rb as JsonBuilder, _
                                  byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )
    if( doc = 0 ) then return rb.NewNull( )

    dim as JsonValue posVal = req.Params( ).Member( "position" )
    dim as long lineNo = clng( posVal.Member( "line"      ).AsLongInt( 0 ) )
    dim as long charNo = clng( posVal.Member( "character" ).AsLongInt( 0 ) )
    dim as long offset = clng( doc->PositionToOffset( lineNo, charNo ) )

    dim as CallContext ctx
    if( FindCallContext( doc->Text( ), doc->Tokens( ), offset, ctx ) = false ) then return rb.NewNull( )

    dim as long alternatives = 0
    dim as SymbolInfo sym
    dim as boolean viaChain = false

    '' `obj.Method(` and `lg.Warn( ).Str(` -- a member call is the member of the
    '' TYPE before the dot, walked as member completion walks it. ResolveCallee
    '' matches the name alone, so it is the fallback, not the first answer. Only
    '' when the index is there: a popup is typed against, and never waits.
    if( IsMemberAccess( doc->Text( ), doc->Tokens( ), ctx.NameTok ) andalso _
        ( IndexBuildPending( ) = false orelse IndexBuildReady( ) ) ) then
        EnsureWorkspaceIndex( srv )
        dim as string lowerName = lcase( TokenText( doc->Text( ), doc->Tokens( )[ctx.NameTok] ) )
        if( ResolveChainMember( srv, doc, ctx.NameTok - 1, lowerName, false, sym, alternatives ) ) then
            viaChain = IsCallableKind( sym.Kind_ )
        end if
    end if

    if( viaChain = false ) then
        alternatives = 0
        dim as long symIndex = ResolveCallee( doc, ctx, alternatives )
        if( symIndex >= 0 ) then
            sym = doc->Symbols( ).Items[symIndex]
        else
            if( ResolveCalleeInIndex( srv, doc, ctx, sym ) = false ) then return rb.NewNull( )
            alternatives = 1
        end if
    end if

    dim as string label
    dim params as SigParamArray
    if( ParseSignature( sym.Name_, sym.Detail_, label, params ) = false ) then
        '' The name resolved to something that is not a procedure -- an array
        '' subscript, or a cast. Nothing to show, which is the right answer
        '' rather than an empty popup.
        return rb.NewNull( )
    end if

    dim as JsonNode paramList = rb.NewArray( )
    for i as long = 0 to params.Count( ) - 1
        dim as JsonNode p = rb.NewObject( )

        '' The [start, end) form, not the substring form: a substring match
        '' would highlight the first `a` in `(byval a as any ptr)` even when
        '' the caret is in a later parameter that happens to contain one.
        dim as JsonNode span = rb.NewArray( )
        rb.PushInt( span, params[i].LabelStart )
        rb.PushInt( span, params[i].LabelEnd )
        rb.SetNode( p, "label", span )

        rb.PushNode( paramList, p )
    next

    dim as JsonNode sig = rb.NewObject( )
    rb.SetStr ( sig, "label", label )
    rb.SetNode( sig, "parameters", paramList )

    if( len(sym.Doc_) > 0 ) then
        dim as JsonNode docNode = rb.NewObject( )
        rb.SetStr( docNode, "kind",  "markdown" )
        rb.SetStr( docNode, "value", sym.Doc_ )
        rb.SetNode( sig, "documentation", docNode )
    end if

    '' An argument index past the end of the list means the user is typing
    '' past what the procedure takes. Reporting it anyway would ask the client
    '' to highlight a parameter that does not exist, and some clients then
    '' show nothing at all, so it is clamped and the popup stays useful.
    dim as long active = ctx.ActiveArg
    if( params.Count( ) = 0 ) then
        active = 0
    elseif( active >= params.Count( ) ) then
        active = params.Count( ) - 1
    end if

    dim as JsonNode sigs = rb.NewArray( )
    rb.PushNode( sigs, sig )

    dim as JsonNode result_ = rb.NewObject( )
    rb.SetNode( result_, "signatures",      sigs )
    rb.SetInt ( result_, "activeSignature", 0 )
    rb.SetInt ( result_, "activeParameter",  active )

    LogDebug( "signature help: " & sym.Name_ & sym.Detail_ & ", argument " & active & _
              iif( alternatives > 1, " (" & alternatives & " overloads, first shown)", "" ) )
    return result_
end function

sub RegisterSignatureHelpHandlers( )
    RegisterHandler( LSP_SIGNATURE_HELP, @OnSignatureHelp )
end sub
