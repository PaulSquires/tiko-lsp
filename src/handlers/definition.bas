'' ############################################################################
''  handlers/definition.bas -- textDocument/definition
''
''  Resolution is shared with hover, deliberately: an editor that shows one
''  thing in a tooltip and jumps somewhere else is worse than one that does
''  neither.
''
''  WITHIN ONE FILE, for now. A name declared in an #included header resolves
''  to nothing rather than to the wrong place; phase 6's workspace index is
''  what makes cross-file navigation possible.
'' ############################################################################

#include once "definition.bi"
#include once "hover.bi"
#include once "../lsp/publish.bi"
#include once "../utils/logging.bi"

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
    if( symIndex < 0 ) then return rb.NewNull( )

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
