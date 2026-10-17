'' ############################################################################
''  handlers/document_symbols.bas -- textDocument/documentSymbol
''
''  The editor's outline. Answered as the HIERARCHICAL DocumentSymbol[] form,
''  not the flat SymbolInformation[] one, so a type's fields and methods nest
''  under it the way they are written.
'' ############################################################################

#import "std/containers"
#include once "document_symbols.bi"
#include once "../lsp/publish.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

'' Builds the children of `parent`, recursively. LOCALS ARE EXCLUDED: an
'' outline listing every DIM inside every procedure is unusable, and no editor
'' expects them there.
private function BuildSymbolNodes( byref rb as JsonBuilder, byval doc as TextDocumentPtr, _
                                   byref syms as SymbolTable, byval parent as long ) as JsonNode
    dim as JsonNode list_ = rb.NewArray( )
    dim as string body = doc->Text( )

    for i as long = 0 to syms.Count( ) - 1
        dim as SymbolInfo s = syms.Items[i]
        if( s.Parent <> parent ) then continue for
        if( s.IsLocal ) then continue for

        dim as JsonNode node = rb.NewObject( )
        rb.SetStr( node, "name", s.Name_ )
        if( len(s.Detail_) > 0 ) then rb.SetStr( node, "detail", s.Detail_ )
        rb.SetInt( node, "kind", clngint( s.Kind_ ) )

        '' `range` is the whole declaration and `selectionRange` is the name.
        '' The specification requires the second to be inside the first, and a
        '' client that gets it wrong shows the outline empty rather than
        '' complaining -- so both come from the same symbol, never mixed.
        rb.SetNode( node, "range", _
                    BuildLspRange( rb, body, doc->Index( ), s.RangeStart, s.RangeEnd ) )
        rb.SetNode( node, "selectionRange", _
                    BuildLspRange( rb, body, doc->Index( ), s.NameStart, s.NameEnd ) )

        '' `children` is omitted when there are none, rather than sent as an
        '' empty array: both are legal, and the shorter one is less to read in
        '' a trace.
        dim as long childCount = 0
        for k as long = 0 to syms.Count( ) - 1
            if( syms.Items[k].Parent = i andalso syms.Items[k].IsLocal = false ) then childCount += 1
        next

        if( childCount > 0 ) then
            rb.SetNode( node, "children", BuildSymbolNodes( rb, doc, syms, i ) )
        end if

        rb.PushNode( list_, node )
    next

    return list_
end function

private function OnDocumentSymbol( byref srv as Server, _
                                   byref req as RpcMessage, _
                                   byref rb as JsonBuilder, _
                                   byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )

    if( doc = 0 ) then
        '' Not an error: a client may ask about a document it has closed, and
        '' the answer is simply that there is nothing to show.
        LogDebug( "documentSymbol for a document that is not open: " & uriText )
        return rb.NewArray( )
    end if

    dim as long n = doc->Symbols( ).Count( )
    LogDebug( "documentSymbol " & UriFileName( uriText ) & ": " & n & " symbol(s)" )

    return BuildSymbolNodes( rb, doc, doc->Symbols( ), -1 )
end function

sub RegisterDocumentSymbolHandlers( )
    RegisterHandler( LSP_DOCUMENT_SYMBOL, @OnDocumentSymbol )
end sub
