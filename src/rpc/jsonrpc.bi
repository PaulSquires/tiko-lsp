'' ############################################################################
''  rpc/jsonrpc.bi -- JSON-RPC 2.0 message model
''
''  This layer knows about jsonrpc/id/method/params/result/error and nothing
''  about LSP. It is the boundary where a payload stops being text and starts
''  being a message.
''
''  The id of a request may be a number OR a string, and a response MUST echo
''  it back with the same type -- returning 1 for "1" is a protocol violation
''  that some clients silently drop. RpcId keeps the distinction.
'' ############################################################################

#pragma once

#include once "../json/json.bi"

'' ----------------------------------------------------------------------------
''  Standard error codes (JSON-RPC 2.0 plus the LSP-reserved range)
'' ----------------------------------------------------------------------------
const RPC_PARSE_ERROR            = -32700
const RPC_INVALID_REQUEST        = -32600
const RPC_METHOD_NOT_FOUND       = -32601
const RPC_INVALID_PARAMS         = -32602
const RPC_INTERNAL_ERROR         = -32603

'' LSP-specific, from the "Error Codes" section of the specification.
const RPC_SERVER_NOT_INITIALIZED = -32002
const RPC_UNKNOWN_ERROR_CODE     = -32001
const RPC_REQUEST_FAILED         = -32803
const RPC_SERVER_CANCELLED       = -32802
const RPC_CONTENT_MODIFIED       = -32801
const RPC_REQUEST_CANCELLED      = -32800

'' ----------------------------------------------------------------------------
''  RpcId -- a request identifier: absent, integer, or string
'' ----------------------------------------------------------------------------
enum RpcIdKind
    RPCID_NONE   = 0
    RPCID_INT    = 1
    RPCID_STRING = 2
end enum

type RpcId
    private:
        m_kind as RpcIdKind
        m_int  as longint
        m_str  as string

    public:
        declare constructor( )
        declare constructor( byval v as longint )
        declare constructor( byref v as string )

        declare sub      FromJson( byval v as JsonValue )
        declare function Kind    ( ) as RpcIdKind
        declare function IsNone  ( ) as boolean
        declare function IntValue( ) as longint
        declare function StrValue( ) as string

        '' Human-readable, for logs only -- never for the wire.
        declare function ToText( ) as string

        '' Writes the id into `obj` under key "id", preserving its type. An
        '' absent id is written as JSON null, which is what a response to an
        '' unparseable request requires.
        declare sub WriteTo( byref rb as JsonBuilder, byval obj as JsonNode )
end type

'' ----------------------------------------------------------------------------
''  RpcError -- an error a handler wants reported
''
''  Code 0 means "no error"; no JSON-RPC code is 0, so the sentinel is safe.
'' ----------------------------------------------------------------------------
type RpcError
    private:
        m_code as long
        m_msg  as string

    public:
        declare constructor( )
        declare sub      SetErr( byval code as long, byref msg as string )
        declare sub      Clear ( )
        declare function IsSet ( ) as boolean
        declare function Code  ( ) as long
        declare function Message_( ) as string
end type

'' ----------------------------------------------------------------------------
''  RpcMessage -- one parsed incoming message
'' ----------------------------------------------------------------------------
enum RpcMessageKind
    RPC_INVALID      = 0
    RPC_REQUEST      = 1   '' has method and id   -> a response is required
    RPC_NOTIFICATION = 2   '' has method, no id   -> a response is forbidden
    RPC_RESPONSE     = 3   '' has result or error -> a reply to us
end enum

type RpcMessage
    private:
        m_doc    as JsonDoc
        m_kind   as RpcMessageKind
        m_id     as RpcId
        m_method as string

    public:
        declare constructor( )

        '' Parses `text_`. Returns false and fills `err_` with the code the
        '' peer should be told about (-32700 for bad JSON, -32600 for JSON
        '' that is not a well-formed JSON-RPC message).
        declare function ParseFrom( byref text_ as string, byref err_ as RpcError ) as boolean

        declare function Kind      ( ) as RpcMessageKind
        declare function Id        ( ) as RpcId
        declare function MethodName( ) as string
        declare function Params    ( ) as JsonValue
        declare function Root      ( ) as JsonValue

        '' True for a request or notification whose method begins with "$/".
        '' The specification gives those a distinct rule: an unknown "$/"
        '' notification MUST be ignored, and an unknown "$/" request MUST be
        '' answered with MethodNotFound.
        declare function IsDollarMethod( ) as boolean
end type

'' ----------------------------------------------------------------------------
''  Serialisers
''
''  RpcBuildResponse takes the builder that owns `resultNode`, because a node
''  cannot move between documents. RpcBuildError and RpcBuildNotification make
''  their own where they need one.
'' ----------------------------------------------------------------------------
declare function RpcBuildResponse    ( byref id as RpcId, byref rb as JsonBuilder, byval resultNode as JsonNode ) as string
declare function RpcBuildError       ( byref id as RpcId, byval code as long, byref msg as string ) as string
declare function RpcBuildNotification( byref methodName as string, byref rb as JsonBuilder, byval paramsNode as JsonNode ) as string

'' A request FROM the server TO the client -- `client/registerCapability` is
'' the only one this server sends. The id is a string, deliberately: the
'' client's ids and the server's are separate spaces, and a string id can
'' never be mistaken for one of the client's numbers in a log.
declare function RpcBuildRequest     ( byref id as string, byref methodName as string, byref rb as JsonBuilder, byval paramsNode as JsonNode ) as string

'' Default human text for a standard code, for when a handler supplies none.
declare function RpcErrorText( byval code as long ) as string
