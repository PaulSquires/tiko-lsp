'' ############################################################################
''  handlers/definition.bas -- textDocument/definition
''
''  Resolution is shared with hover, deliberately: an editor that shows one
''  thing in a tooltip and jumps somewhere else is worse than one that does
''  neither.
''
''  THIS FILE FIRST, then the workspace. A name the open document declares
''  wins, because a local definition is what the user means; only when the file
''  has never heard of it does the index get asked, which is what makes a jump
''  into an #included header work.
'' ############################################################################

#include once "definition.bi"
#include once "hover.bi"
#include once "../lsp/publish.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

private function OnDefinition( byref srv as Server, _
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

    '' -- not in this file: ask the workspace ----------------------------------
    if( symIndex < 0 ) then
        dim as long tokIdx = TokenIndexAt( doc->Tokens( ), offset )
        if( tokIdx < 0 ) then return rb.NewNull( )
        if( doc->Tokens( )[tokIdx].Kind <> TK_IDENT ) then return rb.NewNull( )

        dim as string lowerName = lcase( TokenText( doc->Text( ), doc->Tokens( )[tokIdx] ) )

        dim as IndexHit hit
        if( srv.Index.FindDefinition( lowerName, hit ) = false ) then return rb.NewNull( )

        '' The index stores its ranges already converted, so nothing has to be
        '' read from disk to answer this.
        dim as IndexedRange r = srv.Index.RangeAt( hit.FileIndex, hit.SymIndex )

        dim as JsonNode start_ = rb.NewObject( )
        rb.SetInt( start_, "line", r.StartLine )
        rb.SetInt( start_, "character", r.StartChar )

        dim as JsonNode end_ = rb.NewObject( )
        rb.SetInt( end_, "line", r.EndLine )
        rb.SetInt( end_, "character", r.EndChar )

        dim as JsonNode range_ = rb.NewObject( )
        rb.SetNode( range_, "start", start_ )
        rb.SetNode( range_, "end", end_ )

        dim as JsonNode remote = rb.NewObject( )
        rb.SetStr ( remote, "uri", srv.Index.FileUri( hit.FileIndex ) )
        rb.SetNode( remote, "range", range_ )

        LogDebug( "definition (workspace): " & lowerName & " in " & _
                  UriFileName( srv.Index.FileUri( hit.FileIndex ) ) )
        return remote
    end if

    dim as SymbolInfo sym = doc->Symbols( ).Items[symIndex]

    '' A Location, not a LocationLink: the simple form every client supports,
    '' and the range is the NAME, so the editor puts the caret on it rather
    '' than selecting the whole procedure.
    dim as JsonNode location_ = rb.NewObject( )
    rb.SetStr( location_, "uri", doc->Uri( ) )
    rb.SetNode( location_, "range", _
                BuildLspRange( rb, doc->Text( ), doc->Index( ), sym.NameStart, sym.NameEnd ) )

    LogDebug( "definition: " & sym.Name_ & " at byte " & sym.NameStart )
    return location_
end function

sub RegisterDefinitionHandlers( )
    RegisterHandler( LSP_DEFINITION, @OnDefinition )
end sub
