'' ############################################################################
''  lsp/dispatcher.bi -- the server object and the method registry
''
''  The dispatcher owns the lifecycle state machine. The rules it enforces are
''  in the specification's Lifecycle Messages section and are easy to get
''  subtly wrong, so each one is asserted in exactly one place (Dispatch):
''
''    - a REQUEST other than `initialize` before initialisation is answered
''      -32002 ServerNotInitialized;
''    - a NOTIFICATION other than `exit` before initialisation is dropped;
''    - a second `initialize` is answered -32600 InvalidRequest;
''    - any request after `shutdown` is answered -32600 InvalidRequest;
''    - `exit` ends the process: code 0 if `shutdown` came first, otherwise 1;
''    - an unknown `$/...` notification is ignored, and an unknown `$/...`
''      request is answered MethodNotFound.
'' ############################################################################

#pragma once

#include once "fb/array.bi"
#include once "../json/json.bi"
#include once "../rpc/jsonrpc.bi"
#include once "../rpc/transport.bi"
#include once "../document/document_manager.bi"
#include once "protocol.bi"

'' A container held as a FIELD must be a named instantiation: fbc cannot
'' instantiate a generic written inline in a field declaration.
type StringArray as FB.Array( of string )

'' One workspace folder as sent in InitializeParams.
type WorkspaceFolder
    Uri   as string
    Label as string          '' the protocol calls this "name"; NAME is a
                             '' FreeBASIC statement and cannot be a field of a
                             '' type that has member procedures.
end type

type WorkspaceFolderArray as FB.Array( of WorkspaceFolder )

enum ServerState
    SRV_UNINITIALIZED = 0   '' before a successful `initialize`
    SRV_INITIALIZED   = 1   '' normal operation
    SRV_SHUTDOWN      = 2   '' `shutdown` received; awaiting `exit`
end enum

'' ----------------------------------------------------------------------------
''  Server
''
''  Recorded client information is held in plain public fields -- it is data,
''  not behaviour, and a setter per field would be noise. Everything that
''  CHANGES state or writes to the wire is a method, so those paths stay in
''  one place.
'' ----------------------------------------------------------------------------
type Server
    public:
        '' -- recorded from InitializeParams ----------------------------------
        ClientName       as string
        ClientVersion    as string
        RootUri          as string
        PositionEncoding as string     '' negotiated; utf-16 unless agreed
        TraceValue       as string
        ClientProcessId  as longint
        WorkspaceFolders as WorkspaceFolderArray

        '' -- open buffers ----------------------------------------------------
        ''
        '' Every handler that needs source text goes through here, never
        '' through the filesystem: the editor's buffer is authoritative.
        Documents        as DocumentManager

        declare constructor( )

        declare sub Attach( byval tp as StdioTransport ptr )

        '' Parses one payload and does whatever it asks for, including sending
        '' the response. Never raises: a malformed message becomes an error
        '' response, and an unknown method becomes MethodNotFound.
        declare sub HandleMessage( byref payload as string )

        '' -- lifecycle -------------------------------------------------------
        declare function State           ( ) as ServerState
        declare sub      SetState        ( byval st as ServerState )
        declare function IsRunning       ( ) as boolean
        declare function ExitCode        ( ) as long
        declare sub      RequestExit     ( )
        declare function ShutdownReceived( ) as boolean

        '' -- outgoing --------------------------------------------------------
        declare function SendRaw         ( byref payload as string ) as boolean
        declare function SendNotification( byref methodName as string, byref rb as JsonBuilder, byval paramsNode as JsonNode ) as boolean
        declare sub      SendLogMessage  ( byval kind as LspMessageType, byref text_ as string )

        '' $/logTrace, the protocol's own debug channel. Silent unless the
        '' client asked for tracing with `trace` or `$/setTrace`; `detail` is
        '' sent only at "verbose". This is how a client sees what the server
        '' did with a notification that has no response.
        declare sub      SendTrace       ( byref text_ as string, byref detail as string = "" )

    private:
        m_tp        as StdioTransport ptr
        m_state     as ServerState
        m_running   as boolean
        m_shutdown  as boolean
        m_exitCode  as long

        declare sub Dispatch    ( byref req as RpcMessage )
        declare sub SendResponse( byref id as RpcId, byref rb as JsonBuilder, byval resultNode as JsonNode )
        declare sub SendError   ( byref id as RpcId, byval codeVal as long, byref msgText as string )
end type

'' ----------------------------------------------------------------------------
''  Handlers
''
''  A handler builds its result into `rb` and returns the node. To fail, it
''  sets `err_` and returns an invalid node. A notification handler returns an
''  invalid node and its result is discarded -- the dispatcher never replies to
''  a notification.
''
''  The registry is module state in dispatcher.bas rather than a Server field,
''  because a field typed with the handler pointer would need the pointer type
''  declared before Server, and the pointer type needs Server. One registry is
''  correct anyway: the handler table is a property of the program, not of an
''  instance.
'' ----------------------------------------------------------------------------
type LspHandler as function( byref srv as Server, _
                             byref req as RpcMessage, _
                             byref rb as JsonBuilder, _
                             byref err_ as RpcError ) as JsonNode

declare sub      RegisterHandler   ( byref methodName as string, byval fn_ as LspHandler )
declare function FindHandler       ( byref methodName as string ) as LspHandler
declare function IsMethodRegistered( byref methodName as string ) as boolean
declare sub      ClearHandlers     ( )
declare function RegisteredCount   ( ) as long
