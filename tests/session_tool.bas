'' ############################################################################
''  tests/session_tool.bas -- the end-to-end piped-session test
''
''  This is the "manually piped LSP messages" check, in two halves so it works
''  identically on Windows and Linux without a shell that can emit exact CRLF:
''
''      session_tool --write  session.bin      writes a scripted client session
''      tiko-lsp < session.bin > captured.bin  runs the real server
''      session_tool --check  captured.bin     asserts on what came back
''
''  The checker reuses the server's own MessageFramer, so the captured stream
''  is validated as framing AND as protocol -- a response that is well-formed
''  JSON but badly framed still fails.
'' ############################################################################

#include once "fb/array.bi"
#include once "assert.bi"
#include once "../src/rpc/transport.bi"
#include once "../src/json/json.bi"
#include once "../src/rpc/jsonrpc.bi"
#include once "../src/lsp/protocol.bi"

const CR = chr(13)
const LF = chr(10)

private function Frame( byref payload as string ) as string
    return "Content-Length: " & len(payload) & CR & LF & CR & LF & payload
end function

'' ----------------------------------------------------------------------------
''  The scripted client session
''
''  Every message here exercises one rule of the lifecycle, in an order a real
''  editor could produce.
'' ----------------------------------------------------------------------------
private function SessionBytes( ) as string
    dim as string s

    '' 1. initialize, with the shape a real client sends.
    s &= Frame( "{""jsonrpc"":""2.0"",""id"":1,""method"":""initialize""," & _
                """params"":{""processId"":4242," & _
                """clientInfo"":{""name"":""session_tool"",""version"":""1.0""}," & _
                """rootUri"":""file:///c%3A/dev/tiko""," & _
                """trace"":""messages""," & _
                """capabilities"":{""general"":{""positionEncodings"":[""utf-16"",""utf-8""]}}," & _
                """workspaceFolders"":[{""uri"":""file:///c%3A/dev/tiko"",""name"":""tiko""}]}}" )

    '' 2. the client confirms; the server answers with a window/logMessage.
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""initialized"",""params"":{}}" )

    '' 3. a request for something phase 1 does not implement -> MethodNotFound.
    s &= Frame( "{""jsonrpc"":""2.0"",""id"":2,""method"":""textDocument/hover""," & _
                """params"":{""textDocument"":{""uri"":""file:///x.bas""}," & _
                """position"":{""line"":0,""character"":0}}}" )

    '' 4. a second initialize, with a STRING id -> InvalidRequest, echoed with
    ''    the id still a string.
    s &= Frame( "{""jsonrpc"":""2.0"",""id"":""s-1"",""method"":""initialize"",""params"":{}}" )

    '' 5. a notification the server understands, and one it does not. Neither
    ''    may produce output.
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""$/setTrace"",""params"":{""value"":""verbose""}}" )
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""$/somethingUnknown"",""params"":{}}" )

    '' 6. a document opens, carrying a REAL syntax error -- a sub with no
    ''    `end sub`. Tracing is on, so each document notification produces a
    ''    $/logTrace, and each also produces a publishDiagnostics.
    ''        "sub Test( )" 11 + LF 1 + "print i" 7 = 19 bytes over 2 lines
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""textDocument/didOpen""," & _
                """params"":{""textDocument"":{""uri"":""file:///c%3A/dev/x.bas""," & _
                """languageId"":""freebasic"",""version"":1," & _
                """text"":""sub Test( )\nprint i""}}}" )

    '' 7. two edits in ONE didChange, the second expressed against the text as
    ''    the FIRST left it. Together they also FIX the error, so the
    ''    publishDiagnostics that follows must be EMPTY -- which is how an
    ''    editor clears a squiggle.
    ''        edit 1: `print i` -> `print 1`
    ''        edit 2: append a newline and `end sub`
    ''    Result: 11 + 1 + 7 + 1 + 7 = 27 bytes over 3 lines.
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""textDocument/didChange""," & _
                """params"":{""textDocument"":{""uri"":""file:///c%3A/dev/x.bas"",""version"":2}," & _
                """contentChanges"":[" & _
                "{""range"":{""start"":{""line"":1,""character"":6}," & _
                 """end"":{""line"":1,""character"":7}},""text"":""1""}," & _
                "{""range"":{""start"":{""line"":1,""character"":7}," & _
                 """end"":{""line"":1,""character"":7}},""text"":""\nend sub""}]}}" )

    '' 8. a change for a document that was never opened -- dropped in silence,
    ''    which means NO $/logTrace and no response.
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""textDocument/didChange""," & _
                """params"":{""textDocument"":{""uri"":""file:///c%3A/dev/never-opened.bas"",""version"":5}," & _
                """contentChanges"":[{""text"":""whatever""}]}}" )

    '' 9. save, then close.
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""textDocument/didSave""," & _
                """params"":{""textDocument"":{""uri"":""file:///c%3A/dev/x.bas""}}}" )
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""textDocument/didClose""," & _
                """params"":{""textDocument"":{""uri"":""file:///c%3A/dev/x.bas""}}}" )

    '' 10. broken JSON -> ParseError against a null id, and the session must
    ''     CONTINUE afterwards.
    s &= Frame( "{ this is not json" )

    '' 11. shutdown -> null result.
    s &= Frame( "{""jsonrpc"":""2.0"",""id"":3,""method"":""shutdown""}" )

    '' 12. a request after shutdown -> InvalidRequest.
    s &= Frame( "{""jsonrpc"":""2.0"",""id"":4,""method"":""textDocument/hover"",""params"":{}}" )

    '' 13. exit -> the process ends with code 0, because shutdown came first.
    s &= Frame( "{""jsonrpc"":""2.0"",""method"":""exit""}" )

    return s
end function

private function WriteSession( byref path as string ) as long
    dim as long f = freefile( )
    if( open( path for binary access write as #f ) <> 0 ) then
        print "session_tool: cannot write " & path
        return 1
    end if

    dim as string bytes_ = SessionBytes( )
    put #f, , bytes_
    close #f

    print "wrote " & len(bytes_) & " bytes to " & path
    return 0
end function

private function ReadWholeFile( byref path as string, byref outText as string ) as boolean
    dim as long f = freefile( )
    if( open( path for binary access read as #f ) <> 0 ) then return false

    dim as longint n = lof( f )
    outText = ""
    if( n > 0 ) then
        outText = space( n )
        get #f, , outText
    end if
    close #f
    return true
end function

'' ----------------------------------------------------------------------------
''  The checker
'' ----------------------------------------------------------------------------
private function CheckSession( byref path as string ) as long
    dim as string captured
    if( ReadWholeFile( path, captured ) = false ) then
        print "session_tool: cannot read " & path
        return 1
    end if

    '' -- reframe the captured stream ----------------------------------------
    TestGroup( "captured stream framing" )

    dim as MessageFramer f
    dim messages as FB.Array( of string )
    f.Feed( captured )

    do
        dim as string payload
        dim as FrameStatus st = f.NextMessage( payload )
        if( st = FRAME_ERROR ) then
            TestFail( "the server's output is well framed", f.ErrorText( ) )
            exit do
        end if
        if( st = FRAME_NEED_MORE ) then exit do
        messages.Push( payload )
    loop

    '' Fifteen, and exactly fifteen:
    ''    5 answers to requests (initialize, hover, second initialize,
    ''      shutdown, post-shutdown hover)
    ''    1 parse error
    ''    1 window/logMessage from `initialized`
    ''    4 $/logTrace   -- didOpen, didChange, didSave, didClose
    ''    4 publishDiagnostics, one after each of those
    '' and NOTHING for the two $/ notifications the server must swallow, nor
    '' for the didChange against a document that was never opened.
    AssertEqInt( f.Pending( ), 0, "the server's output ends on a message boundary" )
    AssertEqInt( messages.Count( ), 15, "the session produced exactly fifteen messages" )
    if( messages.Count( ) <> 15 ) then
        for i as long = 0 to messages.Count( ) - 1
            print "      [" & i & "] " & left( messages[i], 160 )
        next
        return TestSummary( "piped session" )
    end if

    '' -- 1. the initialize response ------------------------------------------
    TestGroup( "initialize response" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[0] ), "message 0 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqStr( r.Member( "jsonrpc" ).AsString( ), "2.0", "carries jsonrpc 2.0" )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 1, "answers id 1" )
        AssertTrue( r.Has( "result" ), "is a success response" )
        AssertTrue( r.Member( "result" ).Member( "capabilities" ).IsObject( ), "result has capabilities" )
        AssertEqStr( r.Member( "result" ).Member( "serverInfo" ).Member( "name" ).AsString( ), _
                     LSP_SERVER_NAME, "serverInfo names the server" )
        AssertEqStr( r.Member( "result" ).Member( "serverInfo" ).Member( "version" ).AsString( ), _
                     LSP_SERVER_VERSION, "serverInfo carries the version" )

        dim as JsonValue caps = r.Member( "result" ).Member( "capabilities" )
        AssertEqStr( caps.Member( "positionEncoding" ).AsString( ), LSP_ENCODING_UTF16, _
                     "the negotiated position encoding is stated" )
        AssertTrue ( caps.Member( "textDocumentSync" ).Member( "openClose" ).AsBoolean( ), _
                     "openClose is advertised" )
        AssertEqInt( caps.Member( "textDocumentSync" ).Member( "change" ).AsLongInt( ), _
                     clngint( LSPSYNC_INCREMENTAL ), "incremental sync is advertised" )
        AssertFalse( caps.Member( "textDocumentSync" ).Member( "save" ).Member( "includeText" ).AsBoolean( true ), _
                     "didSave is wanted without the text -- the buffer is already authoritative" )

        '' Still nothing that is not implemented. These land in phases 4-7 and
        '' must not appear before then.
        AssertFalse( caps.Has( "hoverProvider" ), "hover is NOT claimed" )
        AssertFalse( caps.Has( "completionProvider" ), "completion is NOT claimed" )
        AssertFalse( caps.Has( "definitionProvider" ), "definition is NOT claimed" )
        AssertFalse( caps.Has( "renameProvider" ), "rename is NOT claimed" )
    end scope

    '' -- 2. the window/logMessage triggered by `initialized` -------------------
    TestGroup( "initialized notification" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[1] ), "message 1 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqStr( r.Member( "method" ).AsString( ), LSP_WINDOW_LOG_MESSAGE, "is window/logMessage" )
        AssertFalse( r.Has( "id" ), "a notification carries no id" )
        AssertContains( r.Member( "params" ).Member( "message" ).AsString( ), LSP_SERVER_NAME, _
                        "the log message names the server" )
    end scope

    '' -- 3. MethodNotFound for an unimplemented request ------------------------
    TestGroup( "unimplemented method" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[2] ), "message 2 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 2, "answers id 2" )
        AssertEqInt( r.Member( "error" ).Member( "code" ).AsLongInt( ), RPC_METHOD_NOT_FOUND, _
                     "textDocument/hover is MethodNotFound" )
        AssertFalse( r.Has( "result" ), "an error response has no result" )
    end scope

    '' -- 4. a second initialize, string id ------------------------------------
    TestGroup( "second initialize" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[3] ), "message 3 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertTrue( r.Member( "id" ).IsString( ), "a string id is echoed AS A STRING" )
        AssertEqStr( r.Member( "id" ).AsString( ), "s-1", "the string id is echoed exactly" )
        AssertEqInt( r.Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_REQUEST, _
                     "a second initialize is InvalidRequest" )
    end scope

    '' -- 5..12. document synchronisation and diagnostics ---------------------
    ''
    '' didOpen/didChange/didSave/didClose are notifications and have no
    '' responses, so what proves the server tracked the buffer is what it sends
    '' on its own: a $/logTrace, then a publishDiagnostics.
    TestGroup( "document synchronisation and diagnostics" )
    scope
        dim as JsonDoc openTrace, openDiag, changeTrace, changeDiag
        AssertTrue( openTrace.Parse  ( messages[4] ), "message 4 is JSON" )
        AssertTrue( openDiag.Parse   ( messages[5] ), "message 5 is JSON" )
        AssertTrue( changeTrace.Parse( messages[6] ), "message 6 is JSON" )
        AssertTrue( changeDiag.Parse ( messages[7] ), "message 7 is JSON" )

        AssertEqStr( openTrace.Root( ).Member( "method" ).AsString( ), LSP_LOG_TRACE, "didOpen traced" )
        AssertContains( openTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didOpen x.bas", "the trace names the event and the file" )
        AssertContains( openTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "v1, 2 line(s), 19 byte(s)", "the opened buffer is measured correctly" )

        '' -- the diagnostic for the missing `end sub` -------------------------
        dim as JsonValue d = openDiag.Root( )
        AssertEqStr( d.Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, "diagnostics published" )
        AssertEqStr( d.Member( "params" ).Member( "uri" ).AsString( ), _
                     "file:///c%3A/dev/x.bas", "published against the right URI" )
        AssertEqInt( d.Member( "params" ).Member( "version" ).AsLongInt( ), 1, _
                     "carrying the document version" )
        AssertEqInt( d.Member( "params" ).Member( "diagnostics" ).Count( ), 1, _
                     "one diagnostic for the unclosed sub" )

        dim as JsonValue item = d.Member( "params" ).Member( "diagnostics" ).Item( 0 )
        AssertEqStr( item.Member( "code" ).AsString( ), "unclosed-block", "with a stable code" )
        AssertEqInt( item.Member( "severity" ).AsLongInt( ), 1, "at severity Error" )
        AssertEqStr( item.Member( "source" ).AsString( ), "tiko-lsp", "attributed to this server" )
        AssertContains( item.Member( "message" ).AsString( ), "'sub Test'", "naming the procedure" )

        '' The range must point at the SUB on line 0, characters 0 to 3.
        AssertEqInt( item.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 0, _
                     "the range starts on line 0" )
        AssertEqInt( item.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 0, _
                     "at character 0" )
        AssertEqInt( item.Member( "range" ).Member( "end" ).Member( "character" ).AsLongInt( ), 3, _
                     "and covers the keyword" )

        '' -- the edits fix it, so the next report must be EMPTY ---------------
        AssertContains( changeTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "2 edit(s)", "both content changes were applied" )
        AssertContains( changeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "v2, 3 line(s), 27 byte(s)", "the edits applied in order, against the evolving text" )

        AssertEqStr( changeDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "diagnostics republished after the change" )
        AssertEqInt( changeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "and the list is EMPTY -- which is what clears the squiggle" )
        AssertEqInt( changeDiag.Root( ).Member( "params" ).Member( "version" ).AsLongInt( ), 2, _
                     "against the new version" )
    end scope

    scope
        dim as JsonDoc saveTrace, saveDiag, closeTrace, closeDiag
        AssertTrue( saveTrace.Parse ( messages[8]  ), "message 8 is JSON" )
        AssertTrue( saveDiag.Parse  ( messages[9]  ), "message 9 is JSON" )
        AssertTrue( closeTrace.Parse( messages[10] ), "message 10 is JSON" )
        AssertTrue( closeDiag.Parse ( messages[11] ), "message 11 is JSON" )

        AssertContains( saveTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didSave x.bas", "the save names the file" )
        AssertEqStr( saveDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "a save republishes" )

        AssertContains( closeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "0 document(s) still open", "closing released the buffer" )
        AssertEqStr( closeDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "a close republishes" )
        AssertEqInt( closeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "with an empty list, so nothing is left on screen" )
        AssertFalse( closeDiag.Root( ).Member( "params" ).Has( "version" ), _
                     "and no version, because the document is gone" )
    end scope

    '' -- 13. the parse error ---------------------------------------------------
    TestGroup( "malformed message" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[12] ), "message 12 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertTrue( r.Member( "id" ).IsNull( ), "an unparseable request is answered with a null id" )
        AssertEqInt( r.Member( "error" ).Member( "code" ).AsLongInt( ), RPC_PARSE_ERROR, _
                     "broken JSON is a ParseError" )
    end scope

    '' -- 14. shutdown ---------------------------------------------------------
    TestGroup( "shutdown" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[13] ), "message 13 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 3, "answers id 3" )
        AssertTrue( r.Has( "result" ), "shutdown returns a result member" )
        AssertTrue( r.Member( "result" ).IsNull( ), "the shutdown result is null" )
    end scope

    '' -- 15. a request arriving after shutdown --------------------------------
    TestGroup( "post-shutdown request" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[14] ), "message 14 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 4, "answers id 4" )
        AssertEqInt( r.Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_REQUEST, _
                     "a request after shutdown is InvalidRequest" )
    end scope

    return TestSummary( "piped session" )
end function

'' ----------------------------------------------------------------------------
''  Entry point
'' ----------------------------------------------------------------------------
dim as string mode_ = command( 1 )
dim as string path_ = command( 2 )

if( len(path_) = 0 ) then
    print "usage: session_tool --write <file> | --check <file>"
    end 2
end if

select case lcase( mode_ )
    case "--write" : end WriteSession( path_ )
    case "--check" : end CheckSession( path_ )
    case else
        print "usage: session_tool --write <file> | --check <file>"
        end 2
end select
