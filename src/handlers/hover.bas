'' ############################################################################
''  handlers/hover.bas -- textDocument/hover
'' ############################################################################

#include once "hover.bi"
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
    dim as long symIndex = ResolveAtOffset( doc, offset, wordStart, wordEnd )

    '' A null result is the correct answer for "nothing to say here", and is
    '' what stops an editor from showing an empty tooltip.
    if( symIndex < 0 ) then return rb.NewNull( )

    dim as SymbolInfo sym = doc->Symbols( ).Items[symIndex]

    dim as JsonNode contents = rb.NewObject( )
    rb.SetStr( contents, "kind",  "markdown" )
    rb.SetStr( contents, "value", SymbolHoverMarkdown( sym ) )

    dim as JsonNode result_ = rb.NewObject( )
    rb.SetNode( result_, "contents", contents )
    rb.SetNode( result_, "range", _
                BuildLspRange( rb, doc->Text( ), doc->Index( ), wordStart, wordEnd ) )

    return result_
end function

sub RegisterHoverHandlers( )
    RegisterHandler( LSP_HOVER, @OnHover )
end sub
