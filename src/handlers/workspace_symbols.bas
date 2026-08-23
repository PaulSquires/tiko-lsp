'' ############################################################################
''  handlers/workspace_symbols.bas -- workspace/symbol, and building the index
'' ############################################################################

#include once "workspace_symbols.bi"
#include once "../workspace/workspace.bi"
#include once "../workspace/index_builder.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

'' ----------------------------------------------------------------------------
''  Building the index -- starting it, and taking delivery
'' ----------------------------------------------------------------------------
sub StartWorkspaceIndex( byref srv as Server )
    dim roots as PathArray

    for i as long = 0 to srv.WorkspaceFolders.Count( ) - 1
        dim as string root = UriToPath( srv.WorkspaceFolders[i].Uri )
        if( len(root) = 0 ) then
            '' A folder we cannot turn into a path -- an untitled workspace, or
            '' a scheme we do not handle. Saying so beats indexing nothing in
            '' silence.
            LogWarn( "workspace folder is not a file: " & srv.WorkspaceFolders[i].Uri )
            continue for
        end if
        roots.Push( root )
    next

    if( roots.IsEmpty( ) ) then
        LogInfo( "no workspace folder to index" )
        exit sub
    end if

    '' The live index resolves its own graph too: it holds the open buffers,
    '' and one of those may be the file the user is typing an #include into.
    srv.Index->SetSearchPaths( roots )

    '' Returns immediately. The next message is read while this runs.
    StartIndexBuild( roots )
    LogInfo( "workspace scan started in the background" )
end sub

'' The workspace folders as native paths -- the include graph's search list,
'' and what a scan walks.
private function WorkspaceRoots( byref srv as Server ) as PathArray
    dim roots as PathArray

    for i as long = 0 to srv.WorkspaceFolders.Count( ) - 1
        dim as string root = UriToPath( srv.WorkspaceFolders[i].Uri )
        if( len(root) > 0 ) then roots.Push( root )
    next

    return roots
end function

sub RefreshWorkspaceFiles( byref srv as Server, byref paths as PathArray )
    if( paths.IsEmpty( ) ) then exit sub

    dim roots as PathArray = WorkspaceRoots( srv )
    StartIndexRefresh( paths, roots )
    LogInfo( "re-indexing " & paths.Count( ) & " file(s) in the background" )
end sub

sub EnsureWorkspaceIndex( byref srv as Server )
    if( IndexBuildPending( ) = false ) then exit sub

    dim as double waited = timer( )
    dim as boolean isRefresh = IndexBuildIsRefresh( )
    dim as string summary
    dim as SymbolIndex ptr fresh = TakeIndexBuild( summary )
    if( fresh = 0 ) then exit sub

    if( isRefresh ) then
        '' A REFRESH holds only the files that changed, so it is merged rather
        '' than adopted -- adopting it would throw away the entire workspace to
        '' keep the handful of files a `git checkout` touched.
        srv.Index->Absorb( *fresh )
        delete fresh
    else
        srv.AdoptIndex( fresh )
    end if

    '' THE OPEN BUFFERS GO ON TOP, always. The worker indexed what is on disk,
    '' because it must not touch documents the message loop owns -- so a file
    '' the editor has open, and every edit made while the scan was running, is
    '' applied here. The buffer wins, which is the rule everywhere else in this
    '' server.
    dim uris as FB.Array( of string ) = srv.Documents.OpenUris( )
    for i as long = 0 to uris.Count( ) - 1
        dim as TextDocumentPtr doc = srv.Documents.Find( uris[i] )
        if( doc <> 0 ) then srv.Index->IndexText( doc->Uri( ), doc->FilePath( ), doc->Text( ), true )
    next

    '' Every file the index holds has just changed identity or arrived, so the
    '' graph is pointed at the new set. A merge is the case that needs it most:
    '' a refreshed header may have been renumbered by the files around it.
    dim roots as PathArray = WorkspaceRoots( srv )
    srv.Index->SetSearchPaths( roots )
    srv.Index->ResolveIncludes( )

    dim as double waitMs = ( timer( ) - waited ) * 1000
    if( waitMs >= 1 ) then summary &= " (waited " & int( waitMs ) & " ms for it)"

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

    '' There is no honest answer to "every symbol in the workspace" before the
    '' workspace has been read.
    EnsureWorkspaceIndex( srv )

    dim as IndexHitArray hits
    srv.Index->Query( queryText, 200, hits )

    dim as JsonNode list_ = rb.NewArray( )

    for i as long = 0 to hits.Count( ) - 1
        dim as SymbolInfo  sym = srv.Index->SymbolAt( hits[i].FileIndex, hits[i].SymIndex )
        dim as IndexedRange r  = srv.Index->RangeAt( hits[i].FileIndex, hits[i].SymIndex )

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
        rb.SetStr ( locNode, "uri", srv.Index->FileUri( hits[i].FileIndex ) )
        rb.SetNode( locNode, "range", range_ )

        dim as JsonNode node = rb.NewObject( )
        rb.SetStr ( node, "name", sym.Name_ )
        rb.SetInt ( node, "kind", clngint( sym.Kind_ ) )
        rb.SetNode( node, "location", locNode )

        '' containerName is what a picker shows on the right: the file, since
        '' that is what tells two `Init`s apart.
        rb.SetStr( node, "containerName", UriFileName( srv.Index->FileUri( hits[i].FileIndex ) ) )

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
    ''
    '' A scan already running is cancelled by StartIndexBuild: its answer would
    '' describe a set of folders that no longer exists.
    LogInfo( "workspace folders changed -- reindexing" )
    StartWorkspaceIndex( srv )
    return JsonNode( )
end function

sub RegisterWorkspaceHandlers( )
    RegisterHandler( LSP_WORKSPACE_SYMBOL, @OnWorkspaceSymbol )
    RegisterHandler( LSP_DID_CHANGE_FOLDERS, @OnDidChangeWorkspaceFolders )
end sub
