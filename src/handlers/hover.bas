'' ############################################################################
''  handlers/hover.bas -- textDocument/hover
'' ############################################################################

#include once "hover.bi"
#include once "workspace_symbols.bi"
#include once "../analysis/includes.bi"
#include once "../lsp/publish.bi"
#include once "../utils/logging.bi"

function ResolveAtOffset( byval doc as TextDocumentPtr, byval offset as long, _
                          byref wordRangeStart as long, byref wordRangeEnd as long ) as long
    wordRangeStart = offset
    wordRangeEnd   = offset
    if( doc = 0 ) then return -1

    dim as string body = doc->Text( )
    dim as long tokIdx = TokenIndexAt( doc->Tokens( ), offset )
    if( tokIdx < 0 ) then return -1

    dim as Token tok = doc->Tokens( )[tokIdx]

    '' Only a name resolves. Hovering a keyword, a number or a string is a
    '' legitimate thing for a user to do and the honest answer is nothing.
    if( tok.Kind <> TK_IDENT ) then return -1

    wordRangeStart = tok.Start_
    wordRangeEnd   = tok.Start_ + tok.Length_

    dim as string word_ = lcase( TokenText( body, tok ) )

    '' `customer.Name` is a different question from `Name`: the first is a
    '' member of something, the second is whatever is in scope here.
    if( IsMemberAccess( body, doc->Tokens( ), tokIdx ) ) then
        return doc->Symbols( ).ResolveMember( word_ )
    end if

    return doc->Symbols( ).Resolve( word_, offset )
end function

'' `alias.name` WHERE alias IS ONE OF THE DOCUMENT'S IMPORTS (tiko-lang ADR 0017): the
'' module's public declaration, or the macro it `#export`s -- shown as its `#define` and,
'' when that names a declaration (a std facade's `FB.PathJoin`), as that declaration too.
'' "" when the caret is on no such name.
private function ModuleMemberHover_( byref srv as Server, byval doc as TextDocumentPtr, _
                                     byval offset as long, byref wordStart as long, _
                                     byref wordEnd as long ) as string
    dim as long ti = TokenIndexAt( doc->Tokens( ), offset )
    if( ti < 2 ) then return ""
    dim as Token nameTok = doc->Tokens( )[ti]
    dim as Token dotTok  = doc->Tokens( )[ti - 1]
    dim as Token baseTok = doc->Tokens( )[ti - 2]
    if( nameTok.Kind <> TK_IDENT orelse dotTok.Kind <> TK_OP orelse baseTok.Kind <> TK_IDENT ) then return ""
    if( TokenText( doc->Text( ), dotTok ) <> "." ) then return ""
    dim as string alias_ = lcase( TokenText( doc->Text( ), baseTok ) )
    dim refs as ImportRefArray
    FindImports( doc->Text( ), doc->Tokens( ), refs )
    dim as boolean isAlias = false
    for i as long = 0 to refs.Count( ) - 1
        if( refs[i].Alias_ = alias_ ) then isAlias = true
    next
    if( isAlias = false ) then return ""

    EnsureWorkspaceIndex( srv )
    dim as long here = srv.Index->IndexOfUri( doc->Uri( ) )
    if( here < 0 ) then return ""
    dim as IndexHit sym
    dim as ExportHit exp_
    dim as long got = srv.Index->ModuleMemberAt( here, alias_, lcase( TokenText( doc->Text( ), nameTok ) ), sym, exp_ )
    if( got = 0 ) then return ""
    wordStart = nameTok.Start_
    wordEnd   = nameTok.Start_ + nameTok.Length_
    if( got = 1 ) then return SymbolHoverMarkdown( srv.Index->SymbolAt( sym.FileIndex, sym.SymIndex ) )
    dim as ExportEdge e = srv.Index->ExportAt( exp_.FileIndex, exp_.ExportIndex )
    dim as string md = "```tiko" & chr( 10 ) & "#define " & e.Name_
    if( len(e.Body) > 0 ) then md &= " " & e.Body
    md &= chr( 10 ) & "```" & chr( 10 ) & "*exported macro of `" & alias_ & "`*"
    if( sym.FileIndex >= 0 ) then
        md &= chr( 10 ) & chr( 10 ) & "---" & chr( 10 ) & chr( 10 ) & _
              SymbolHoverMarkdown( srv.Index->SymbolAt( sym.FileIndex, sym.SymIndex ) )
    end if
    return md
end function

private function OnHover( byref srv as Server, _
                          byref req as RpcMessage, _
                          byref rb as JsonBuilder, _
                          byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )
    if( doc = 0 ) then return rb.NewNull( )

    dim as JsonValue posVal = req.Params( ).Member( "position" )
    dim as long lineNo   = clng( posVal.Member( "line"      ).AsLongInt( 0 ) )
    dim as long charNo   = clng( posVal.Member( "character" ).AsLongInt( 0 ) )
    dim as long offset   = clng( doc->PositionToOffset( lineNo, charNo ) )

    dim as long wordStart, wordEnd
    dim as string markdown = ModuleMemberHover_( srv, doc, offset, wordStart, wordEnd )
    dim as long symIndex = -1
    if( len(markdown) = 0 ) then symIndex = ResolveAtOffset( doc, offset, wordStart, wordEnd )

    if( len(markdown) > 0 ) then
        '' A module's member, answered above.
    elseif( symIndex >= 0 ) then
        markdown = SymbolHoverMarkdown( doc->Symbols( ).Items[symIndex] )
    else
        markdown = BuiltinTypedefHoverMarkdown( doc->Text( ), doc->Tokens( ), offset )
    end if

    '' A null result is the correct answer for "nothing to say here", and is
    '' what stops an editor from showing an empty tooltip.
    if( len(markdown) = 0 ) then return rb.NewNull( )

    dim as JsonNode contents = rb.NewObject( )
    rb.SetStr( contents, "kind",  "markdown" )
    rb.SetStr( contents, "value", markdown )

    dim as JsonNode result_ = rb.NewObject( )
    rb.SetNode( result_, "contents", contents )
    rb.SetNode( result_, "range", _
                BuildLspRange( rb, doc->Text( ), doc->Index( ), wordStart, wordEnd ) )

    return result_
end function

sub RegisterHoverHandlers( )
    RegisterHandler( LSP_HOVER, @OnHover )
end sub
