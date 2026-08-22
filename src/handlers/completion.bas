'' ############################################################################
''  handlers/completion.bas -- textDocument/completion
''
''  The candidates come from analysis/completion.bas; this file's whole job is
''  turning them into CompletionItems and deciding what a client needs to be
''  told explicitly.
'' ############################################################################

#include once "completion.bi"
#include once "../analysis/completion.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

private function OnCompletion( byref srv as Server, _
                               byref req as RpcMessage, _
                               byref rb as JsonBuilder, _
                               byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )

    '' An empty list, not null: a client shows "no suggestions" for the first
    '' and may retry for the second.
    if( doc = 0 ) then return rb.NewArray( )

    dim as JsonValue posVal = req.Params( ).Member( "position" )
    dim as long lineNo = clng( posVal.Member( "line"      ).AsLongInt( 0 ) )
    dim as long charNo = clng( posVal.Member( "character" ).AsLongInt( 0 ) )
    dim as long offset = clng( doc->PositionToOffset( lineNo, charNo ) )

    dim as CompletionItemArray items
    CollectCompletions( doc->Text( ), doc->Tokens( ), doc->Symbols( ), offset, items )

    dim as JsonNode list_ = rb.NewArray( )

    for i as long = 0 to items.Count( ) - 1
        dim as CompletionItem it = items[i]

        dim as JsonNode node = rb.NewObject( )
        rb.SetStr( node, "label", it.Label )
        rb.SetInt( node, "kind",  clngint( it.Kind_ ) )
        if( len(it.Detail_) > 0 ) then rb.SetStr( node, "detail", it.Detail_ )

        if( len(it.Doc_) > 0 ) then
            dim as JsonNode docNode = rb.NewObject( )
            rb.SetStr( docNode, "kind",  "markdown" )
            rb.SetStr( docNode, "value", it.Doc_ )
            rb.SetNode( node, "documentation", docNode )
        end if

        '' sortText decides the ORDER, filterText decides what the client
        '' matches the typed prefix against, and insertText is what lands in
        '' the buffer. All three are stated rather than left to default,
        '' because the defaults all fall back to `label` and that would put a
        '' keyword above a local whenever the alphabet says so.
        rb.SetStr( node, "sortText",   chr( asc("0") + it.SortGroup ) & lcase( it.Label ) )
        rb.SetStr( node, "filterText", it.Label )
        rb.SetStr( node, "insertText", it.Label )

        rb.PushNode( list_, node )
    next

    LogDebug( "completion at " & UriFileName( uriText ) & " " & lineNo & ":" & charNo & _
              " -> " & items.Count( ) & " item(s)" )
    return list_
end function

sub RegisterCompletionHandlers( )
    RegisterHandler( LSP_COMPLETION, @OnCompletion )
end sub
