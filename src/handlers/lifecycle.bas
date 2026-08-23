'' ############################################################################
''  handlers/lifecycle.bas -- initialize / initialized / shutdown / exit
'' ############################################################################

#include once "lifecycle.bi"
#include once "workspace_symbols.bi"
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

    '' -- what the client can accept back ------------------------------------
    ''
    '' Only two client capabilities change what this server SENDS, and both are
    '' read here rather than at the point of use, because InitializeParams is
    '' the only place they are ever offered.
    srv.SupportsDocumentChanges = params.Member( "capabilities" ) _
                                        .Member( "workspace" ) _
                                        .Member( "workspaceEdit" ) _
                                        .Member( "documentChanges" ).AsBoolean( false )

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

    '' The workspace scan happens HERE, not during `initialize`: the client is
    '' blocked waiting for that response, and a scan of a large tree would show
    '' up as a slow start. By now the editor is running and merely gets its
    '' cross-file answers a moment later.
    BuildWorkspaceIndex( srv )
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
    srv.Index.Clear( )
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
