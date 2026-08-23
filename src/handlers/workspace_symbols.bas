'' ############################################################################
''  handlers/workspace_symbols.bas -- workspace/symbol, and building the index
'' ############################################################################

#include once "workspace_symbols.bi"
#include once "../workspace/workspace.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

'' ----------------------------------------------------------------------------
''  Building the index
'' ----------------------------------------------------------------------------
sub BuildWorkspaceIndex( byref srv as Server )
    dim as double started = timer( )

    srv.Index.Clear( )

    dim as WorkspaceScan scan
    for i as long = 0 to srv.WorkspaceFolders.Count( ) - 1
        dim as string root = UriToPath( srv.WorkspaceFolders[i].Uri )
        if( len(root) = 0 ) then
            '' A folder we cannot turn into a path -- an untitled workspace, or
            '' a scheme we do not handle. Saying so beats indexing nothing in
            '' silence.
            LogWarn( "workspace folder is not a file: " & srv.WorkspaceFolders[i].Uri )
            continue for
        end if

        LogInfo( "scanning " & root )
        ScanFolder( root, scan )
    next

    '' Every open buffer is indexed from its BUFFER, so a symbol typed but not
    '' saved is still found. Done first, so the disk pass skips those files.
    dim uris as FB.Array( of string ) = srv.Documents.OpenUris( )
    for i as long = 0 to uris.Count( ) - 1
        dim as TextDocumentPtr doc = srv.Documents.Find( uris[i] )
        if( doc <> 0 ) then srv.Index.IndexText( doc->Uri( ), doc->FilePath( ), doc->Text( ), true )
    next

    dim as long indexed = 0
    dim as long failed = 0

    for i as long = 0 to scan.Files.Count( ) - 1
        dim as string path_ = scan.Files[i]

        '' Already indexed from a buffer: the editor's copy wins.
        if( srv.Index.IndexOfUri( PathToUri( path_ ) ) >= 0 ) then continue for

        if( srv.Index.IndexPath( path_ ) ) then
            indexed += 1
        else
            failed += 1
        end if
    next

    dim as double elapsed = timer( ) - started
    dim as string summary = "indexed " & srv.Index.FileCount( ) & " file(s), " & _
                            srv.Index.SymbolCount( ) & " symbol(s) in " & _
                            int( elapsed * 1000 ) & " ms"

    if( failed > 0 ) then summary &= " (" & failed & " unreadable)"
    if( scan.Skipped > 0 ) then summary &= " (" & scan.Skipped & " unreadable folder(s))"
    if( scan.Truncated ) then
        summary &= " -- STOPPED at the " & WS_MAX_FILES & " file limit"
    end if

    LogInfo( summary )
    srv.SendLogMessage( LSPMSG_INFO, summary )
end sub

'' ----------------------------------------------------------------------------
''  workspace/symbol
'' ----------------------------------------------------------------------------
private function OnWorkspaceSymbol( byref srv as Server, _
                                    byref req as RpcMessage, _
                                    byref rb as JsonBuilder, _
                                    byref err_ as RpcError ) as JsonNode

    dim as string queryText = req.Params( ).Member( "query" ).AsString( "" )

    dim as IndexHitArray hits
    srv.Index.Query( queryText, 200, hits )

    dim as JsonNode list_ = rb.NewArray( )

    for i as long = 0 to hits.Count( ) - 1
        dim as SymbolInfo  sym = srv.Index.SymbolAt( hits[i].FileIndex, hits[i].SymIndex )
        dim as IndexedRange r  = srv.Index.RangeAt( hits[i].FileIndex, hits[i].SymIndex )

        '' SymbolInformation, not the 3.17 WorkspaceSymbol: the older shape is
        '' understood by every client, and this server has nothing to gain from
        '' the lazy-location form it replaced.
        dim as JsonNode start_ = rb.NewObject( )
        rb.SetInt( start_, "line", r.StartLine )
        rb.SetInt( start_, "character", r.StartChar )

        dim as JsonNode end_ = rb.NewObject( )
        rb.SetInt( end_, "line", r.EndLine )
        rb.SetInt( end_, "character", r.EndChar )

        dim as JsonNode range_ = rb.NewObject( )
        rb.SetNode( range_, "start", start_ )
        rb.SetNode( range_, "end", end_ )

        dim as JsonNode locNode = rb.NewObject( )
        rb.SetStr ( locNode, "uri", srv.Index.FileUri( hits[i].FileIndex ) )
        rb.SetNode( locNode, "range", range_ )

        dim as JsonNode node = rb.NewObject( )
        rb.SetStr ( node, "name", sym.Name_ )
        rb.SetInt ( node, "kind", clngint( sym.Kind_ ) )
        rb.SetNode( node, "location", locNode )

        '' containerName is what a picker shows on the right: the file, since
        '' that is what tells two `Init`s apart.
        rb.SetStr( node, "containerName", UriFileName( srv.Index.FileUri( hits[i].FileIndex ) ) )

        rb.PushNode( list_, node )
    next

    LogDebug( "workspace/symbol '" & queryText & "' -> " & hits.Count( ) & " hit(s)" )
    return list_
end function

'' ----------------------------------------------------------------------------
''  workspace/didChangeWorkspaceFolders
'' ----------------------------------------------------------------------------
private function OnDidChangeWorkspaceFolders( byref srv as Server, _
                                              byref req as RpcMessage, _
                                              byref rb as JsonBuilder, _
                                              byref err_ as RpcError ) as JsonNode

    dim as JsonValue event_ = req.Params( ).Member( "event" )

    for each removed in ArrayOf( event_.Member( "removed" ) )
        dim as string uriText = removed.Member( "uri" ).AsString( "" )
        for i as long = srv.WorkspaceFolders.Count( ) - 1 to 0 step -1
            if( srv.WorkspaceFolders[i].Uri = uriText ) then srv.WorkspaceFolders.Remove( i )
        next
    next

    for each added in ArrayOf( event_.Member( "added" ) )
        dim as WorkspaceFolder wf
        wf.Uri   = added.Member( "uri" ).AsString( "" )
        wf.Label = added.Member( "name" ).AsString( "" )
        if( len(wf.Uri) > 0 ) then srv.WorkspaceFolders.Push( wf )
    next

    '' Rebuilt rather than patched. A folder change is rare and a full scan is
    '' seconds at worst; keeping an incremental version correct across
    '' overlapping folders is not worth the bugs.
    LogInfo( "workspace folders changed -- reindexing" )
    BuildWorkspaceIndex( srv )
    return JsonNode( )
end function

sub RegisterWorkspaceHandlers( )
    RegisterHandler( LSP_WORKSPACE_SYMBOL, @OnWorkspaceSymbol )
    RegisterHandler( LSP_DID_CHANGE_FOLDERS, @OnDidChangeWorkspaceFolders )
end sub
