'' ############################################################################
''  lsp/dispatcher.bas -- lifecycle state machine and method registry
'' ############################################################################

#include once "fb/map.bi"
#include once "dispatcher.bi"
#include once "../utils/logging.bi"

'' ############################################################################
''  Method registry
'' ############################################################################

type HandlerMap as FB.Map( of string, LspHandler )

dim shared as HandlerMap g_Handlers

sub RegisterHandler( byref methodName as string, byval fn_ as LspHandler )
    '' Put, not Add: re-registering a method REPLACES it, so a later phase can
    '' take over a method an earlier stub answers without unregistering first.
    g_Handlers.Put( methodName, fn_ )
end sub

function FindHandler( byref methodName as string ) as LspHandler
    dim as LspHandler fn_ = 0
    '' TryGet, not the indexer: m[k] INSERTS a default on a miss, which would
    '' turn every unknown method into a permanent null entry.
    if( g_Handlers.TryGet( methodName, fn_ ) ) then return fn_
    return 0
end function

function IsMethodRegistered( byref methodName as string ) as boolean
    return g_Handlers.Contains( methodName )
end function

sub ClearHandlers( )
    g_Handlers.Clear( )
end sub

function RegisteredCount( ) as long
    return g_Handlers.Count( )
end function

'' ############################################################################
''  Server
'' ############################################################################

constructor Server( )
    this.m_tp              = NULL
    this.m_state           = SRV_UNINITIALIZED
    this.m_running         = true
    this.m_shutdown        = false
    this.m_exitCode        = 0
    this.PositionEncoding  = LSP_ENCODING_UTF16
    this.TraceValue        = LSP_TRACE_OFF
    this.ClientProcessId   = 0
end constructor

sub Server.Attach( byval tp as StdioTransport ptr )
    this.m_tp = tp
end sub

function Server.State( ) as ServerState
    return this.m_state
end function

sub Server.SetState( byval st as ServerState )
    this.m_state = st
    if( st = SRV_SHUTDOWN ) then this.m_shutdown = true
end sub

function Server.IsRunning( ) as boolean
    return this.m_running
end function

function Server.ExitCode( ) as long
    return this.m_exitCode
end function

function Server.ShutdownReceived( ) as boolean
    return this.m_shutdown
end function

sub Server.RequestExit( )
    this.m_running = false
    '' The specification is explicit: exit without a preceding shutdown is an
    '' error, and the process must say so through its exit code.
    this.m_exitCode = iif( this.m_shutdown, 0, 1 )
end sub

'' ----------------------------------------------------------------------------
''  Outgoing
'' ----------------------------------------------------------------------------

function Server.SendRaw( byref payload as string ) as boolean
    if( this.m_tp = NULL ) then return false
    if( LogIsEnabled( LSPLOG_TRACE ) ) then LogTrace( "--> " & payload )
    return this.m_tp->WriteMessage( payload )
end function

sub Server.SendResponse( byref id as RpcId, byref rb as JsonBuilder, byval resultNode as JsonNode )
    dim as string payload = RpcBuildResponse( id, rb, resultNode )
    if( len(payload) = 0 ) then
        LogError( "failed to serialise response for id " & id.ToText( ) )
        exit sub
    end if
    this.SendRaw( payload )
end sub

sub Server.SendError( byref id as RpcId, byval codeVal as long, byref msgText as string )
    LogWarn( "error response " & codeVal & " for id " & id.ToText( ) & ": " & msgText )
    this.SendRaw( RpcBuildError( id, codeVal, msgText ) )
end sub

function Server.SendNotification( byref methodName as string, byref rb as JsonBuilder, byval paramsNode as JsonNode ) as boolean
    return this.SendRaw( RpcBuildNotification( methodName, rb, paramsNode ) )
end function

sub Server.SendLogMessage( byval kind as LspMessageType, byref text_ as string )
    '' Only meaningful once the client is listening; before initialize it has
    '' nowhere to put the message.
    if( this.m_state = SRV_UNINITIALIZED ) then exit sub

    dim as JsonBuilder rb
    dim as JsonNode params = rb.NewObject( )
    rb.SetInt( params, "type", clngint(kind) )
    rb.SetStr( params, "message", text_ )
    this.SendNotification( LSP_WINDOW_LOG_MESSAGE, rb, params )
end sub

sub Server.SendTrace( byref text_ as string, byref detail as string = "" )
    if( this.TraceValue = LSP_TRACE_OFF ) then exit sub
    if( this.m_state = SRV_UNINITIALIZED ) then exit sub

    dim as JsonBuilder rb
    dim as JsonNode params = rb.NewObject( )
    rb.SetStr( params, "message", text_ )

    '' The `verbose` member is only legal -- and only useful -- at trace level
    '' "verbose"; at "messages" the client wants the headline alone.
    if( this.TraceValue = LSP_TRACE_VERBOSE andalso len(detail) > 0 ) then
        rb.SetStr( params, "verbose", detail )
    end if

    this.SendNotification( LSP_LOG_TRACE, rb, params )
end sub

'' ----------------------------------------------------------------------------
''  Incoming
'' ----------------------------------------------------------------------------

sub Server.HandleMessage( byref payload as string )
    if( LogIsEnabled( LSPLOG_TRACE ) ) then LogTrace( "<-- " & payload )

    dim as RpcMessage req
    dim as RpcError   parseErr

    if( req.ParseFrom( payload, parseErr ) = false ) then
        '' A message we cannot parse has no usable id, so the response carries
        '' a null one. That is what JSON-RPC 2.0 requires, and a client that
        '' was not waiting on an id simply ignores it.
        dim as RpcId nullId
        this.SendError( nullId, parseErr.Code( ), parseErr.Message_( ) )
        exit sub
    end if

    this.Dispatch( req )
end sub

sub Server.Dispatch( byref req as RpcMessage )
    dim as string     methodName = req.MethodName( )
    dim as RpcId      id         = req.Id( )
    dim as boolean    isRequest  = (req.Kind( ) = RPC_REQUEST)

    '' ---- a reply to something we sent ---------------------------------------
    if( req.Kind( ) = RPC_RESPONSE ) then
        '' Phase 1 sends no server-to-client requests, so there is nothing to
        '' correlate this with. Log it and move on rather than answering it,
        '' which would be a protocol error.
        LogDebug( "ignoring response for id " & id.ToText( ) )
        exit sub
    end if

    LogDebug( iif( isRequest, "request  ", "notify   " ) & methodName & _
              iif( isRequest, " (id " & id.ToText( ) & ")", "" ) )

    '' ---- lifecycle gating ----------------------------------------------------
    if( this.m_state = SRV_UNINITIALIZED ) then
        if( methodName <> LSP_INITIALIZE andalso methodName <> LSP_EXIT ) then
            if( isRequest ) then
                this.SendError( id, RPC_SERVER_NOT_INITIALIZED, _
                                "the server has not been initialized; send `initialize` first" )
            else
                '' Notifications before initialisation are dropped, not
                '' answered -- a notification never gets a reply.
                LogWarn( "dropping pre-initialize notification: " & methodName )
            end if
            exit sub
        end if
    elseif( this.m_state = SRV_SHUTDOWN ) then
        if( isRequest andalso methodName <> LSP_EXIT ) then
            this.SendError( id, RPC_INVALID_REQUEST, _
                            "the server is shutting down and accepts no further requests" )
            exit sub
        end if
    end if

    if( isRequest andalso methodName = LSP_INITIALIZE andalso this.m_state <> SRV_UNINITIALIZED ) then
        this.SendError( id, RPC_INVALID_REQUEST, "the server is already initialized" )
        exit sub
    end if

    '' ---- resolve -------------------------------------------------------------
    dim as LspHandler fn_ = FindHandler( methodName )

    if( fn_ = 0 ) then
        if( isRequest ) then
            '' Unknown "$/..." requests get MethodNotFound like any other; the
            '' specification says so explicitly, and a client that sends one is
            '' prepared for it.
            this.SendError( id, RPC_METHOD_NOT_FOUND, "unsupported method: " & methodName )
        else
            if( req.IsDollarMethod( ) ) then
                '' MUST be ignored in silence.
                LogTrace( "ignoring $/ notification: " & methodName )
            else
                LogDebug( "no handler for notification: " & methodName )
            end if
        end if
        exit sub
    end if

    '' ---- run -----------------------------------------------------------------
    dim as JsonBuilder rb
    dim as RpcError    err_
    dim as JsonNode    resultNode = fn_( this, req, rb, err_ )

    if( isRequest = false ) then
        '' A notification handler's return value is discarded. Its errors are
        '' logged, because there is no one to send them to.
        if( err_.IsSet( ) ) then
            LogWarn( "notification " & methodName & " failed: " & err_.Message_( ) )
        end if
        exit sub
    end if

    if( err_.IsSet( ) ) then
        this.SendError( id, err_.Code( ), err_.Message_( ) )
        exit sub
    end if

    this.SendResponse( id, rb, resultNode )
end sub
