'' ############################################################################
''  lsp/protocol.bi -- LSP constants and the capability document
''
''  Every protocol string the server knows lives here, so a method name is
''  never spelled out at a call site and a typo cannot become a silently
''  unreachable handler.
'' ############################################################################

#pragma once

#include once "../json/json.bi"
#include once "../analysis/semantic.bi"

const LSP_SERVER_NAME    = "tiko-lsp"
const LSP_SERVER_VERSION = "0.1.0"

'' The specification version this server is written against.
const LSP_SPEC_VERSION   = "3.17"

'' ----------------------------------------------------------------------------
''  Method names
''
''  Phase 1 implements the lifecycle group. The rest are listed as they are
''  implemented, not before.
'' ----------------------------------------------------------------------------
const LSP_INITIALIZE  = "initialize"
const LSP_INITIALIZED = "initialized"
const LSP_SHUTDOWN    = "shutdown"
const LSP_EXIT        = "exit"
const LSP_SET_TRACE   = "$/setTrace"
const LSP_LOG_TRACE   = "$/logTrace"
const LSP_CANCEL      = "$/cancelRequest"

'' Document synchronisation (phase 2).
const LSP_DID_OPEN   = "textDocument/didOpen"
const LSP_DID_CHANGE = "textDocument/didChange"
const LSP_DID_SAVE   = "textDocument/didSave"
const LSP_DID_CLOSE  = "textDocument/didClose"

'' Language features (phase 4).
const LSP_DOCUMENT_SYMBOL = "textDocument/documentSymbol"
const LSP_HOVER           = "textDocument/hover"
const LSP_DEFINITION      = "textDocument/definition"
const LSP_COMPLETION      = "textDocument/completion"

'' Workspace-wide (phase 6).
const LSP_REFERENCES        = "textDocument/references"
const LSP_WORKSPACE_SYMBOL  = "workspace/symbol"
const LSP_DID_CHANGE_FOLDERS = "workspace/didChangeWorkspaceFolders"

'' Watched files (phase 9). There is NO static capability for this one: a
'' server that wants to hear about files changed behind the editor's back has
'' to ask for it with client/registerCapability, at run time.
const LSP_DID_CHANGE_WATCHED = "workspace/didChangeWatchedFiles"
const LSP_REGISTER_CAPABILITY = "client/registerCapability"

'' The glob the server asks to be watched, and the kind bits: 1 create,
'' 2 change, 4 delete -- all three.
const LSP_WATCH_GLOB = "**/*.{bas,bi,inc}"
const LSP_WATCH_KIND = 7

'' Editing features (phase 7).
const LSP_PREPARE_RENAME     = "textDocument/prepareRename"
const LSP_RENAME             = "textDocument/rename"
const LSP_SIGNATURE_HELP     = "textDocument/signatureHelp"
const LSP_SEMANTIC_FULL      = "textDocument/semanticTokens/full"
const LSP_INLAY_HINT         = "textDocument/inlayHint"
const LSP_FORMATTING         = "textDocument/formatting"
const LSP_RANGE_FORMATTING   = "textDocument/rangeFormatting"
const LSP_CODE_ACTION        = "textDocument/codeAction"

'' Diagnostics are PUSHED (phase 3). There is no capability to advertise for
'' this: a server may publish whenever it likes, and the pull-based
'' textDocument/diagnostic of 3.17 is a separate feature this does not claim.
const LSP_PUBLISH_DIAGNOSTICS = "textDocument/publishDiagnostics"

'' Server -> client notifications used in phase 1.
const LSP_WINDOW_LOG_MESSAGE  = "window/logMessage"
const LSP_WINDOW_SHOW_MESSAGE = "window/showMessage"

'' ----------------------------------------------------------------------------
''  TextDocumentSyncKind
'' ----------------------------------------------------------------------------
enum LspSyncKind
    LSPSYNC_NONE        = 0
    LSPSYNC_FULL        = 1
    LSPSYNC_INCREMENTAL = 2
end enum

'' ----------------------------------------------------------------------------
''  MessageType, for window/logMessage and window/showMessage
'' ----------------------------------------------------------------------------
enum LspMessageType
    LSPMSG_ERROR   = 1
    LSPMSG_WARNING = 2
    LSPMSG_INFO    = 3
    LSPMSG_LOG     = 4
end enum

'' ----------------------------------------------------------------------------
''  Position encoding
''
''  LSP positions count UTF-16 CODE UNITS by default. The server records what
''  the client offered so phase 2's position conversion can honour it; until
''  document synchronisation exists, nothing depends on the value.
'' ----------------------------------------------------------------------------
const LSP_ENCODING_UTF8  = "utf-8"
const LSP_ENCODING_UTF16 = "utf-16"
const LSP_ENCODING_UTF32 = "utf-32"

'' ----------------------------------------------------------------------------
''  TraceValue
'' ----------------------------------------------------------------------------
const LSP_TRACE_OFF      = "off"
const LSP_TRACE_MESSAGES = "messages"
const LSP_TRACE_VERBOSE  = "verbose"

'' ----------------------------------------------------------------------------
''  Capability and result documents
'' ----------------------------------------------------------------------------

'' Builds the ServerCapabilities object. It advertises exactly what is
'' implemented -- see protocol.bas for why phase 1's is empty.
declare function LspBuildCapabilities( byref rb as JsonBuilder ) as JsonNode

'' Builds the { name, version } object returned as InitializeResult.serverInfo.
declare function LspBuildServerInfo( byref rb as JsonBuilder ) as JsonNode

'' True if `enc` is one of the three encodings the specification defines.
declare function LspIsKnownEncoding( byref enc as string ) as boolean
