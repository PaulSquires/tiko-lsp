'' ############################################################################
''  handlers/lifecycle.bas -- initialize / initialized / shutdown / exit
'' ############################################################################

#include once "lifecycle.bi"
#include once "workspace_symbols.bi"
#include once "watched_files.bi"
#include once "../workspace/index_builder.bi"
#include once "../workspace/modules.bi"
#include once "../workspace/metadata.bi"
#include once "fb/filesystem.bi"
#include once "../utils/logging.bi"

'' ----------------------------------------------------------------------------
''  initialize (request)
''
''  Records everything the client told us about itself -- phases 2 and 6 need
''  the workspace folders and the root URI, and there is no second chance to
''  ask -- then answers with the capabilities that actually work today.
'' ----------------------------------------------------------------------------
private function OnInitialize( byref srv as Server, _
                               byref req as RpcMessage, _
                               byref rb as JsonBuilder, _
                               byref err_ as RpcError ) as JsonNode

    dim as JsonValue params = req.Params( )

    if( params.IsObject( ) = false ) then
        err_.SetErr( RPC_INVALID_PARAMS, "initialize requires an InitializeParams object" )
        return JsonNode( )
    end if

    '' -- who is talking to us ------------------------------------------------
    srv.ClientProcessId = params.Member( "processId" ).AsLongInt( 0 )

    dim as JsonValue clientInfo = params.Member( "clientInfo" )
    srv.ClientName    = clientInfo.Member( "name"    ).AsString( "unknown" )
    srv.ClientVersion = clientInfo.Member( "version" ).AsString( "" )

    '' rootUri supersedes rootPath, which is deprecated but still sent by
    '' older clients. Take the URI when both are present.
    srv.RootUri = params.Member( "rootUri" ).AsString( "" )

    dim as string traceVal = params.Member( "trace" ).AsString( "" )
    if( len(traceVal) > 0 ) then srv.TraceValue = traceVal

    '' -- workspace folders ---------------------------------------------------
    srv.WorkspaceFolders.Clear( )
    for each folderVal in ArrayOf( params.Member( "workspaceFolders" ) )
        dim as WorkspaceFolder wf
        wf.Uri   = folderVal.Member( "uri"  ).AsString( "" )
        wf.Label = folderVal.Member( "name" ).AsString( "" )
        if( len(wf.Uri) > 0 ) then srv.WorkspaceFolders.Push( wf )
    next

    '' A client with no workspaceFolders but a rootUri is the single-folder
    '' case; normalise it now so phase 6 has one list to walk.
    if( srv.WorkspaceFolders.IsEmpty( ) andalso len(srv.RootUri) > 0 ) then
        dim as WorkspaceFolder wf
        wf.Uri   = srv.RootUri
        wf.Label = ""
        srv.WorkspaceFolders.Push( wf )
    end if

    '' -- where the toolchain's headers are ----------------------------------
    ''
    '' `initializationOptions.includePaths`: the directories a workspace's
    '' `#include "windows.bi"` is found in -- the compiler's -i paths, which
    '' live in a build configuration this server never reads. A string is
    '' taken as a one-element list. Without it the server falls back to
    '' TKO_INCLUDE, then to `inc` beside a `tiko` on PATH (ToolchainIncDir).
    ''
    '' Read HERE because the index worker starts on `initialized`, after this
    '' response: the directories are fixed before any thread can read them.
    dim as JsonValue incOpt = params.Member( "initializationOptions" ).Member( "includePaths" )
    dim incPaths as PathArray
    if( incOpt.IsString( ) ) then
        incPaths.Push( incOpt.AsString( "" ) )
    else
        for each incVal in ArrayOf( incOpt )
            dim as string d = incVal.AsString( "" )
            if( len(d) > 0 ) then incPaths.Push( d )
        next
    end if
    SetConfiguredIncludeDirs( incPaths )

    '' `initializationOptions.packagePaths`: where `#import "std/strings"` is found -- the
    '' toolchain's pkg/. Usually unnecessary: a `pkg` beside a configured include
    '' directory is found on its own (ToolchainPkgDir).
    dim as JsonValue pkgOpt = params.Member( "initializationOptions" ).Member( "packagePaths" )
    dim pkgPaths as PathArray
    if( pkgOpt.IsString( ) ) then
        pkgPaths.Push( pkgOpt.AsString( "" ) )
    else
        for each pkgVal in ArrayOf( pkgOpt )
            dim as string d = pkgVal.AsString( "" )
            if( len(d) > 0 ) then pkgPaths.Push( d )
        next
    end if
    SetConfiguredPackageDirs( pkgPaths )
    dim as string pkgDir = ToolchainPkgDir( )
    if( len(pkgDir) > 0 ) then
        LogInfo( "toolchain packages from " & pkgDir )
    else
        LogInfo( "toolchain packages: none found -- #import of std/... will not resolve" )
    end if

    '' `initializationOptions.compilerPath`: a tiko to ASK. With it, `tiko metadata` is read
    '' for each workspace folder's tiko.toml before every whole-workspace scan, and what it
    '' says about modules, -i roots, pkg/ and include directories comes first in resolution;
    '' `tiko/metadata` hands its targets to the client (workspace/metadata.bi). It is never
    '' run for diagnostics. Without it -- or when it fails -- nothing changes.
    dim as string comp = params.Member( "initializationOptions" ).Member( "compilerPath" ).AsString( "" )
    SetCompilerPath( "" )
    if( len(comp) > 0 ) then
#ifdef __FB_WIN32__
        if( FB.IsFile( comp ) = false andalso FB.IsFile( comp & ".exe" ) ) then comp &= ".exe"
#endif
        if( FB.IsFile( comp ) ) then
            SetCompilerPath( NormalizePath( comp ) )
            LogInfo( "compiler: " & CompilerPath( ) & " -- tiko metadata is read for each workspace manifest" )
        else
            LogWarn( "compilerPath is not a file: " & comp & " -- resolving without the compiler" )
        end if
    end if

    dim incDirs as PathArray = ToolchainIncDirs( )
    if( incDirs.IsEmpty( ) ) then
        LogInfo( "toolchain headers: none configured (initializationOptions.includePaths, " & _
                 "TKO_INCLUDE, or a tiko on PATH) -- Win32 and library names will be unknown" )
    else
        for i as long = 0 to incDirs.Count( ) - 1
            LogInfo( "toolchain headers from " & incDirs[i] )
        next
    end if
    for i as long = 0 to incPaths.Count( ) - 1
        dim as boolean used = false
        for k as long = 0 to incDirs.Count( ) - 1
            if( lcase( incDirs[k] ) = lcase( NormalizePath( incPaths[i] ) ) ) then used = true
        next
        if( used = false ) then LogWarn( "includePaths entry is not a directory: " & incPaths[i] )
    next

    '' -- what the client can accept back ------------------------------------
    ''
    '' Only two client capabilities change what this server SENDS, and both are
    '' read here rather than at the point of use, because InitializeParams is
    '' the only place they are ever offered.
    srv.SupportsDocumentChanges = params.Member( "capabilities" ) _
                                        .Member( "workspace" ) _
                                        .Member( "workspaceEdit" ) _
                                        .Member( "documentChanges" ).AsBoolean( false )

    srv.SupportsFileWatching    = params.Member( "capabilities" ) _
                                        .Member( "workspace" ) _
                                        .Member( "didChangeWatchedFiles" ) _
                                        .Member( "dynamicRegistration" ).AsBoolean( false )

    '' -- position encoding ---------------------------------------------------
    ''
    '' The client offers a list; the server picks one and echoes it in its
    '' capabilities. utf-16 is the protocol default and the only encoding this
    '' server will honour until phase 2 implements the conversion layer, so
    '' the choice is fixed -- but what the client offered is worth recording.
    dim as string offered = ""
    for each encVal in ArrayOf( params.Member( "capabilities" ) _
                                      .Member( "general" ) _
                                      .Member( "positionEncodings" ) )
        if( len(offered) > 0 ) then offered &= ", "
        offered &= encVal.AsString( "" )
    next
    srv.PositionEncoding = LSP_ENCODING_UTF16
    if( len(offered) > 0 ) then
        LogDebug( "client position encodings: " & offered & " -- using " & srv.PositionEncoding )
    end if

    LogInfo( "initialize from " & srv.ClientName & " " & srv.ClientVersion & _
             " (pid " & srv.ClientProcessId & "), " & _
             srv.WorkspaceFolders.Count( ) & " workspace folder(s)" )

    '' The server is usable from the moment this response is written. The
    '' `initialized` notification that follows is the client confirming it is
    '' ready to receive, not the gate on inbound requests.
    srv.SetState( SRV_INITIALIZED )

    '' -- the result ----------------------------------------------------------
    dim as JsonNode result_ = rb.NewObject( )
    rb.SetNode( result_, "capabilities", LspBuildCapabilities( rb ) )
    rb.SetNode( result_, "serverInfo",   LspBuildServerInfo( rb ) )
    return result_
end function

'' ----------------------------------------------------------------------------
''  initialized (notification)
'' ----------------------------------------------------------------------------
private function OnInitialized( byref srv as Server, _
                                byref req as RpcMessage, _
                                byref rb as JsonBuilder, _
                                byref err_ as RpcError ) as JsonNode
    LogInfo( "client reports initialized" )
    srv.SendLogMessage( LSPMSG_LOG, LSP_SERVER_NAME & " " & LSP_SERVER_VERSION & " ready" )

    '' Asking the client to watch the workspace comes FIRST, and before the
    '' scan rather than after it: a file changed while the scan runs then
    '' produces a notification the server can act on, instead of falling into
    '' the gap between "scanned" and "watched".
    RequestFileWatching( srv )

    '' The workspace scan is STARTED here and finishes on its own thread. It is
    '' not done during `initialize` because the client is blocked waiting for
    '' that response, and it is not done on this thread at all because a scan
    '' of a large tree is seconds long -- seconds in which the editor's first
    '' keystrokes would sit unread in the pipe.
    StartWorkspaceIndex( srv )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------
''  shutdown (request)
''
''  Must return a null result and MUST NOT exit the process -- that is what
''  `exit` is for. Everything expensive is released here so the wait for
''  `exit` costs nothing.
'' ----------------------------------------------------------------------------
private function OnShutdown( byref srv as Server, _
                             byref req as RpcMessage, _
                             byref rb as JsonBuilder, _
                             byref err_ as RpcError ) as JsonNode
    LogInfo( "shutdown requested" )
    srv.SetState( SRV_SHUTDOWN )
    srv.WorkspaceFolders.Clear( )
    '' A scan still running is stopped before anything it might write into is
    '' freed. `exit` follows within milliseconds, and a worker still walking a
    '' directory when the process ends is how a clean shutdown becomes a crash
    '' report.
    CancelIndexBuild( )
    srv.Index->Clear( )
    return rb.NewNull( )
end function

'' ----------------------------------------------------------------------------
''  exit (notification)
'' ----------------------------------------------------------------------------
private function OnExit( byref srv as Server, _
                         byref req as RpcMessage, _
                         byref rb as JsonBuilder, _
                         byref err_ as RpcError ) as JsonNode
    LogInfo( "exit received (shutdown " & iif( srv.ShutdownReceived( ), "was", "was NOT" ) & " received first)" )
    srv.RequestExit( )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------
''  $/setTrace (notification)
'' ----------------------------------------------------------------------------
private function OnSetTrace( byref srv as Server, _
                             byref req as RpcMessage, _
                             byref rb as JsonBuilder, _
                             byref err_ as RpcError ) as JsonNode
    dim as string newValue = req.Params( ).Member( "value" ).AsString( "" )
    select case newValue
        case LSP_TRACE_OFF, LSP_TRACE_MESSAGES, LSP_TRACE_VERBOSE
            srv.TraceValue = newValue
            LogDebug( "trace set to " & newValue )
        case else
            LogWarn( "ignoring $/setTrace with unknown value: " & newValue )
    end select
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------
''  $/cancelRequest (notification)
''
''  Registered rather than left to the unknown-method path so the intent is
''  visible: phase 1 handles one message at a time to completion, so by the
''  time a cancellation arrives its target has already been answered. When
''  phase 6 moves analysis off the message loop this grows a real body.
'' ----------------------------------------------------------------------------
private function OnCancelRequest( byref srv as Server, _
                                  byref req as RpcMessage, _
                                  byref rb as JsonBuilder, _
                                  byref err_ as RpcError ) as JsonNode
    dim as RpcId target
    target.FromJson( req.Params( ).Member( "id" ) )
    LogTrace( "cancel for id " & target.ToText( ) & " -- already completed" )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------

sub RegisterLifecycleHandlers( )
    RegisterHandler( LSP_INITIALIZE,  @OnInitialize )
    RegisterHandler( LSP_INITIALIZED, @OnInitialized )
    RegisterHandler( LSP_SHUTDOWN,    @OnShutdown )
    RegisterHandler( LSP_EXIT,        @OnExit )
    RegisterHandler( LSP_SET_TRACE,   @OnSetTrace )
    RegisterHandler( LSP_CANCEL,      @OnCancelRequest )
end sub
