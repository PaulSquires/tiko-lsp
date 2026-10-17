'' ############################################################################
''  tests/test_framing.bas -- MessageFramer, the base-protocol byte parser
''
''  The framer is the one piece that MUST survive a hostile byte stream: it
''  sees whatever the pipe delivers, and a mistake here desynchronises the
''  session in a way that looks like a bug anywhere else.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#import "std/containers"
#include once "assert.bi"
#include once "../src/rpc/transport.bi"
#include once "crt.bi"

#ifdef __FB_WIN32__
    #include once "crt/io.bi"
    #include once "crt/fcntl.bi"
#else
    #include once "crt/unistd.bi"
#endif

const CR = chr(13)
const LF = chr(10)

'' Wraps a payload in a well-formed header block.
private function Framed( byref payload as string ) as string
    return "Content-Length: " & len(payload) & CR & LF & CR & LF & payload
end function

'' Feeds everything at once and asks for one message.
private function OneShot( byref wire as string, byref payload as string ) as FrameStatus
    dim as MessageFramer f
    f.Feed( wire )
    return f.NextMessage( payload )
end function

dim as string payload

'' ----------------------------------------------------------------------------
TestGroup( "well-formed framing" )

AssertEqInt( OneShot( Framed( "{""a"":1}" ), payload ), FRAME_OK, "a complete message parses" )
AssertEqStr( payload, "{""a"":1}", "payload is exactly the body" )

'' Content-Length: 0 is legal framing. The body is empty and the JSON layer,
'' not the framer, is what rejects it.
AssertEqInt( OneShot( "Content-Length: 0" & CR & LF & CR & LF, payload ), FRAME_OK, "zero-length body is framed" )
AssertEqStr( payload, "", "zero-length body is empty" )

scope
    '' The optional Content-Type header must be accepted and ignored, and an
    '' unknown header must not be fatal -- the base protocol is extensible.
    dim as string wire = "Content-Length: 7" & CR & LF & _
                         "Content-Type: application/vscode-jsonrpc; charset=utf-8" & CR & LF & _
                         "X-Editor: something" & CR & LF & CR & LF & _
                         "{""b"":2}"
    AssertEqInt( OneShot( wire, payload ), FRAME_OK, "extra headers are tolerated" )
    AssertEqStr( payload, "{""b"":2}", "extra headers do not disturb the body" )
end scope

scope
    '' Header names are case-insensitive and the value may be padded.
    dim as string wire = "content-length:   7   " & CR & LF & CR & LF & "{""c"":3}"
    AssertEqInt( OneShot( wire, payload ), FRAME_OK, "header name is case-insensitive" )
    AssertEqStr( payload, "{""c"":3}", "padded header value parses" )
end scope

scope
    '' The specification says CRLF. Bare LF is what every hand-written fixture
    '' and several clients actually produce, so it is accepted.
    dim as string wire = "Content-Length: 7" & LF & LF & "{""d"":4}"
    AssertEqInt( OneShot( wire, payload ), FRAME_OK, "bare LF headers are accepted" )
    AssertEqStr( payload, "{""d"":4}", "bare LF body is exact" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "the byte count is authoritative" )

scope
    '' A payload containing a blank line must not be re-scanned for headers.
    '' Only Content-Length decides where the message ends.
    dim as string body = "{""text"":""line1" & CR & LF & CR & LF & "line2""}"
    dim as MessageFramer f
    f.Feed( Framed( body ) )
    AssertEqInt( f.NextMessage( payload ), FRAME_OK, "embedded CRLFCRLF does not split a message" )
    AssertEqInt( len(payload), len(body), "embedded CRLFCRLF keeps the length" )
    AssertEqStr( payload, body, "embedded CRLFCRLF keeps the bytes" )
end scope

scope
    '' Content-Length counts BYTES, not characters. Two 3-byte CJK characters
    '' plus the quotes must come back whole.
    dim as string body = "{""s"":""" & chr(228,184,173) & chr(230,150,135) & """}"
    dim as MessageFramer f
    f.Feed( Framed( body ) )
    AssertEqInt( f.NextMessage( payload ), FRAME_OK, "UTF-8 payload frames" )
    AssertEqInt( len(payload), len(body), "UTF-8 byte count is preserved" )
    AssertEqStr( payload, body, "UTF-8 bytes are unaltered" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "fragmentation" )

scope
    '' One read is not one message: deliver a whole session one byte at a time
    '' and require exactly one message out, at the right moment.
    dim as string wire = Framed( "{""jsonrpc"":""2.0"",""id"":1}" )
    dim as MessageFramer f
    dim as long completed = 0

    for i as long = 1 to len(wire)
        f.Feed( mid( wire, i, 1 ) )
        dim as FrameStatus st = f.NextMessage( payload )
        if( st = FRAME_OK ) then completed += 1
        if( st = FRAME_ERROR ) then TestFail( "byte-at-a-time feed", f.ErrorText( ) )
    next

    AssertEqInt( completed, 1, "one byte at a time yields exactly one message" )
    AssertEqStr( payload, "{""jsonrpc"":""2.0"",""id"":1}", "byte-at-a-time payload is intact" )
end scope

scope
    '' Header complete, body still arriving: the cached header must not be
    '' re-parsed or consumed early.
    dim as MessageFramer f
    f.Feed( "Content-Length: 10" & CR & LF & CR & LF & "{""a"":" )
    AssertEqInt( f.NextMessage( payload ), FRAME_NEED_MORE, "partial body reports NEED_MORE" )
    f.Feed( "1234}" )
    AssertEqInt( f.NextMessage( payload ), FRAME_OK, "completed body reports OK" )
    AssertEqStr( payload, "{""a"":1234}", "torn body is reassembled" )
end scope

scope
    '' Several messages in one read, plus a trailing fragment.
    dim as MessageFramer f
    f.Feed( Framed( "{""n"":1}" ) & Framed( "{""n"":2}" ) & "Content-Length: 8" & CR & LF )

    AssertEqInt( f.NextMessage( payload ), FRAME_OK, "first of three parses" )
    AssertEqStr( payload, "{""n"":1}", "first payload" )
    AssertEqInt( f.NextMessage( payload ), FRAME_OK, "second of three parses" )
    AssertEqStr( payload, "{""n"":2}", "second payload" )
    AssertEqInt( f.NextMessage( payload ), FRAME_NEED_MORE, "trailing fragment waits" )

    f.Feed( CR & LF & "{""n"":33}" )
    AssertEqInt( f.NextMessage( payload ), FRAME_OK, "third completes after its blank line" )
    AssertEqStr( payload, "{""n"":33}", "third payload" )
    AssertEqInt( f.Pending( ), 0, "nothing is left buffered" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "malformed input" )

scope
    dim as MessageFramer f
    f.Feed( "Content-Type: text/plain" & CR & LF & CR & LF & "{}" )
    AssertEqInt( f.NextMessage( payload ), FRAME_ERROR, "missing Content-Length is an error" )
    AssertContains( f.ErrorText( ), "Content-Length", "the error names the missing header" )
end scope

scope
    dim as MessageFramer f
    f.Feed( "Content-Length: abc" & CR & LF & CR & LF & "{}" )
    AssertEqInt( f.NextMessage( payload ), FRAME_ERROR, "non-numeric Content-Length is an error" )
end scope

scope
    dim as MessageFramer f
    f.Feed( "Content-Length: " & CR & LF & CR & LF )
    AssertEqInt( f.NextMessage( payload ), FRAME_ERROR, "empty Content-Length is an error" )
end scope

scope
    dim as MessageFramer f
    f.Feed( "this-is-not-a-header" & CR & LF & CR & LF & "{}" )
    AssertEqInt( f.NextMessage( payload ), FRAME_ERROR, "a header line without a colon is an error" )
end scope

scope
    '' A bogus length must be refused, not allocated.
    dim as MessageFramer f
    f.Feed( "Content-Length: 99999999999" & CR & LF & CR & LF )
    AssertEqInt( f.NextMessage( payload ), FRAME_ERROR, "an oversized Content-Length is refused" )
    AssertContains( f.ErrorText( ), "exceeds", "the error explains the limit" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "empty and idle streams" )

scope
    dim as MessageFramer f
    AssertEqInt( f.NextMessage( payload ), FRAME_NEED_MORE, "an empty framer waits" )
    f.Feed( "" )
    AssertEqInt( f.NextMessage( payload ), FRAME_NEED_MORE, "an empty feed changes nothing" )
    AssertEqInt( f.Pending( ), 0, "an empty framer buffers nothing" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "sustained traffic" )

scope
    '' 5000 messages through one framer: the buffer must be compacted, not
    '' grown without bound, and every payload must come back in order.
    dim as MessageFramer f
    dim as long ok_ = 0
    dim as long maxPending = 0

    for i as long = 1 to 5000
        f.Feed( Framed( "{""seq"":" & i & "}" ) )
        do
            dim as FrameStatus st = f.NextMessage( payload )
            if( st <> FRAME_OK ) then exit do
            if( payload = "{""seq"":" & i & "}" ) then ok_ += 1
        loop
        if( f.Pending( ) > maxPending ) then maxPending = f.Pending( )
    next

    AssertEqInt( ok_, 5000, "5000 messages round-trip in order" )
    AssertTrue( maxPending = 0, "the framer holds no residue between messages" )
end scope


'' ############################################################################
''  Reading from a LIVE pipe
''
''  The bug this exists for shipped, passed every test, and would have made the
''  server unusable with a real editor.
''
''  The reader used fread( buf, 1, 64K, stdin ), which does not return until it
''  has 64K or the stream ENDS. Every test fed the server a FILE, where the end
''  arrives immediately, so every test passed. An editor is not a file: it
''  sends `initialize`, keeps the pipe open, and waits for the answer -- and
''  the server sat inside fread waiting for 65,000 more bytes that were never
''  coming.
''
''  So this test is the only one in the suite that reads from a pipe with the
''  writing end STILL OPEN. It runs the read on a worker thread and gives it
''  two seconds, because the failure mode is a hang rather than a wrong answer,
''  and a suite that hangs tells you less than one that fails.
'' ############################################################################
TestGroup( "reading from a live pipe" )

dim shared as boolean         g_PipeDone
dim shared as TransportStatus g_PipeStatus
dim shared as string          g_PipePayload

private sub PipeReader( byval param as any ptr )
    dim as StdioTransport tp
    dim as string payload
    g_PipeStatus  = tp.ReadMessage( payload )
    g_PipePayload = payload
    g_PipeDone    = true
end sub

scope
    dim as long fds(0 to 1)

    #ifdef __FB_WIN32__
        '' _O_BINARY, and not for tidiness: a pipe left in TEXT mode
        '' expands every line feed the writer sends into a carriage
        '' return plus a line feed, which turns a correct
        '' Content-Length header into a corrupt one and leaves the
        '' reader waiting for bytes that will never arrive -- exactly
        '' the hang this test detects, arrived at from the other end.
        dim as long rc = _pipe( @fds(0), 64 * 1024, _O_BINARY )
    #else
        dim as long rc = pipe_( @fds(0) )   '' PIPE and WRITE are keywords: the crt names end in _
    #endif

    if( rc <> 0 ) then
        TestFail( "a pipe can be created", "the C library refused" )
    else
        '' The read end becomes this process's stdin, which is what the
        '' transport reads. The write end stays open in this thread -- that is
        '' the whole point: a live client does not close the pipe between
        '' messages.
        #ifdef __FB_WIN32__
            _dup2( fds(0), 0 )
        #else
            dup2( fds(0), 0 )
        #endif

        dim as string msg = Framed( "{""jsonrpc"":""2.0"",""id"":1,""method"":""initialize""}" )

        #ifdef __FB_WIN32__
            _write( fds(1), strptr(msg), len(msg) )
        #else
            write_( fds(1), strptr(msg), len(msg) )
        #endif

        g_PipeDone = false
        dim as any ptr th = threadcreate( @PipeReader, 0 )

        if( th = 0 ) then
            TestFail( "the reader thread starts", "threadcreate failed" )
        else
            '' Two seconds is a hundred times what the read needs and still
            '' short enough that a failure is a test result rather than a
            '' hung build.
            dim as double deadline = timer( ) + 2.0
            while( g_PipeDone = false andalso timer( ) < deadline )
                sleep 5, 1
            wend

            if( g_PipeDone = false ) then
                TestFail( "one message on an OPEN pipe is read at once", _
                          "the reader was still blocked after 2 seconds -- it is " & _
                          "waiting for bytes an editor will never send" )
            else
                threadwait( th )
                AssertTrue( g_PipeStatus = TRANSPORT_OK, _
                            "one message on an OPEN pipe is read at once" )
                AssertContains( g_PipePayload, """method"":""initialize""", _
                                "and comes back whole" )
            end if
        end if
    end if
end scope

end TestSummary( "framing" )
