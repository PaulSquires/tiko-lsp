'' ############################################################################
''  rpc/transport.bi -- base-protocol framing and the stdio stream
''
''  The LSP base protocol is HTTP-like: a header block, a blank line, then
''  exactly Content-Length BYTES of UTF-8 JSON.
''
''      Content-Length: 74<CR><LF>
''      Content-Type: application/vscode-jsonrpc; charset=utf-8<CR><LF>
''      <CR><LF>
''      {"jsonrpc":"2.0", ... }
''
''  Two types, split so the hard part is testable without a process:
''
''      MessageFramer   pure byte-level state machine. Feed() it whatever
''                      arrived; NextMessage() yields complete payloads. Knows
''                      nothing about files, handles or stdin.
''      StdioTransport  the framer plus the actual stdin/stdout plumbing.
''
''  A read from a pipe returns whatever bytes happen to be there: half a
''  header, three whole messages, or one byte. Nothing here assumes otherwise.
'' ############################################################################

#pragma once

'' Result of asking the framer for the next complete message.
enum FrameStatus
    FRAME_OK        = 0   '' payload filled in
    FRAME_NEED_MORE = 1   '' incomplete -- feed more bytes and ask again
    FRAME_ERROR     = 2   '' malformed header block; the stream is desynced
end enum

'' Result of a transport read.
enum TransportStatus
    TRANSPORT_OK    = 0
    TRANSPORT_EOF   = 1   '' peer closed stdin
    TRANSPORT_ERROR = 2   '' stream error, or a framing error
end enum

'' A message larger than this is refused rather than allocated. 64 MB is far
'' beyond any real LSP payload (the largest are didOpen of a huge file), and a
'' bogus Content-Length must not turn into a 4 GB allocation.
const FRAME_MAX_MESSAGE_BYTES = 64 * 1024 * 1024

'' ----------------------------------------------------------------------------
''  MessageFramer
'' ----------------------------------------------------------------------------
type MessageFramer
    private:
        m_buf     as string    '' bytes received, not yet consumed
        m_pos     as long      '' read cursor into m_buf, 0-based
        m_err     as string

        '' Cached header parse, so a message that arrives in fragments is not
        '' re-scanned on every Feed().
        m_haveHdr as boolean
        m_bodyAt  as long      '' 0-based offset of the payload's first byte
        m_bodyLen as long

        declare function ScanHeader( ) as FrameStatus
        declare sub      Compact( )

    public:
        declare constructor( )

        declare sub      Feed( byref chunk as string )
        declare function NextMessage( byref payload as string ) as FrameStatus

        declare function ErrorText ( ) as string
        declare function Pending   ( ) as long   '' unconsumed bytes buffered
        declare sub      Reset( )
end type

'' ----------------------------------------------------------------------------
''  StdioTransport
''
''  Owns the process's stdin/stdout. Construct exactly one.
'' ----------------------------------------------------------------------------
type StdioTransport
    private:
        m_framer as MessageFramer
        m_err    as string

    public:
        declare constructor( )

        declare function ReadMessage ( byref payload as string ) as TransportStatus
        declare function WriteMessage( byref payload as string ) as boolean

        declare function ErrorText( ) as string
end type
