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

'' A doubled quote is how a FreeBASIC literal spells one quote, and a JSON
'' payload is nothing but quotes. Q is one quote, so the messages below read
'' as JSON rather than as a hedge maze.
const Q = chr(34)

private function Frame( byref payload as string ) as string
    return "Content-Length: " & len(payload) & CR & LF & CR & LF & payload
end function

'' ----------------------------------------------------------------------------
''  The scripted client session
''
''  Every message exercises one rule, in an order a real editor could produce.
'' ----------------------------------------------------------------------------
private function SessionBytes( ) as string
    dim as string s

    '' 1. initialize, with the shape a real client sends.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "id" & Q & ":1," & Q & "method" & Q & ":" & Q & "initialize" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "processId" & Q & ":4242," & _
                Q & "clientInfo" & Q & ":{" & Q & "name" & Q & ":" & Q & "session_tool" & Q & "," & _
                Q & "version" & Q & ":" & Q & "1.0" & Q & "}," & _
                Q & "rootUri" & Q & ":" & Q & "file:///c%3A/dev/tiko" & Q & "," & _
                Q & "trace" & Q & ":" & Q & "messages" & Q & "," & _
                Q & "capabilities" & Q & ":{" & Q & "general" & Q & ":{" & _
                Q & "positionEncodings" & Q & ":[" & Q & "utf-16" & Q & "," & Q & "utf-8" & Q & "]}}," & _
                Q & "workspaceFolders" & Q & ":[{" & Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/tiko" & Q & "," & _
                Q & "name" & Q & ":" & Q & "tiko" & Q & "}]}}" )

    '' 2. the client confirms; the server answers with a window/logMessage.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "initialized" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 3. a request for something not implemented -> MethodNotFound.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":2," & _
                Q & "method" & Q & ":" & Q & "textDocument/references" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & Q & "uri" & Q & ":" & _
                Q & "file:///x.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":0," & Q & "character" & Q & ":0}}}" )

    '' 4. a second initialize, with a STRING id -> InvalidRequest, echoed with
    ''    the id still a string.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "id" & Q & ":" & Q & "s-1" & Q & "," & _
                Q & "method" & Q & ":" & Q & "initialize" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 5. a notification the server understands, and one it does not. Neither
    ''    may produce output.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "$/setTrace" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "value" & Q & ":" & Q & "verbose" & Q & "}}" )
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "$/somethingUnknown" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 6. a document opens, carrying a REAL syntax error -- a sub with no
    ''    `end sub`. Tracing is on, so each document notification produces a
    ''    $/logTrace, and each also produces a publishDiagnostics.
    ''
    ''        dim shared as long counter     26 bytes, `counter` at column 19
    ''        sub Test( )                    11
    ''        counter = 1                    11
    ''
    ''    26 + 1 + 11 + 1 + 11 = 50 bytes over 3 lines.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didOpen" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "," & _
                Q & "languageId" & Q & ":" & Q & "freebasic" & Q & "," & Q & "version" & Q & ":1," & _
                Q & "text" & Q & ":" & Q & "dim shared as long counter\nsub Test( )\ncounter = 1" & Q & "}}}" )

    '' 7. two edits in ONE didChange, the second expressed against the text as
    ''    the FIRST left it. Together they also FIX the error, so the
    ''    publishDiagnostics that follows must be EMPTY -- which is how an
    ''    editor clears a squiggle.
    ''
    ''        edit 1: the `1` on line 2 becomes `2`
    ''        edit 2: append a newline and `end sub`
    ''
    ''    Result: 50 + 8 = 58 bytes over 4 lines.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didChange" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "," & Q & "version" & Q & ":2}," & _
                Q & "contentChanges" & Q & ":[" & _
                "{" & Q & "range" & Q & ":{" & Q & "start" & Q & ":{" & Q & "line" & Q & ":2," & _
                Q & "character" & Q & ":10}," & Q & "end" & Q & ":{" & Q & "line" & Q & ":2," & _
                Q & "character" & Q & ":11}}," & Q & "text" & Q & ":" & Q & "2" & Q & "}," & _
                "{" & Q & "range" & Q & ":{" & Q & "start" & Q & ":{" & Q & "line" & Q & ":2," & _
                Q & "character" & Q & ":11}," & Q & "end" & Q & ":{" & Q & "line" & Q & ":2," & _
                Q & "character" & Q & ":11}}," & Q & "text" & Q & ":" & Q & "\nend sub" & Q & "}]}}" )

    '' 8. a change for a document that was never opened -- dropped in silence,
    ''    which means NO $/logTrace and no response.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didChange" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/never-opened.bas" & Q & "," & _
                Q & "version" & Q & ":5}," & _
                Q & "contentChanges" & Q & ":[{" & Q & "text" & Q & ":" & Q & "whatever" & Q & "}]}}" )

    '' 9. the language features, against the document as the edits left it: the
    ''    outline, then a hover and a definition on the USE of `counter` on
    ''    line 2, both of which must land on its declaration on line 0.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":5," & _
                Q & "method" & Q & ":" & Q & "textDocument/documentSymbol" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}}}" )

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":6," & _
                Q & "method" & Q & ":" & Q & "textDocument/hover" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":2," & Q & "character" & Q & ":3}}}" )

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":7," & _
                Q & "method" & Q & ":" & Q & "textDocument/definition" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":2," & Q & "character" & Q & ":3}}}" )

    '' 10. save, then close.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didSave" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}}}" )
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didClose" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}}}" )

    '' 11. broken JSON -> ParseError against a null id, and the session must
    ''     CONTINUE afterwards.
    s &= Frame( "{ this is not json" )

    '' 12. shutdown -> null result.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":3," & _
                Q & "method" & Q & ":" & Q & "shutdown" & Q & "}" )

    '' 13. a request after shutdown -> InvalidRequest.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":4," & _
                Q & "method" & Q & ":" & Q & "textDocument/hover" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 14. exit -> the process ends with code 0, because shutdown came first.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "exit" & Q & "}" )

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

    '' -- reframe the captured stream ------------------------------------------
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

    '' Eighteen, and exactly eighteen:
    ''    8 answers to requests -- initialize, references, second initialize,
    ''      documentSymbol, hover, definition, shutdown, post-shutdown hover
    ''    1 parse error
    ''    1 window/logMessage from `initialized`
    ''    4 $/logTrace          -- didOpen, didChange, didSave, didClose
    ''    4 publishDiagnostics, one after each of those
    '' and NOTHING for the two $/ notifications the server must swallow, nor
    '' for the didChange against a document that was never opened.
    AssertEqInt( f.Pending( ), 0, "the server's output ends on a message boundary" )
    AssertEqInt( messages.Count( ), 18, "the session produced exactly eighteen messages" )
    if( messages.Count( ) <> 18 ) then
        for i as long = 0 to messages.Count( ) - 1
            print "      [" & i & "] " & left( messages[i], 160 )
        next
        return TestSummary( "piped session" )
    end if

    '' -- 1. the initialize response --------------------------------------------
    TestGroup( "initialize response" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[0] ), "message 0 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqStr( r.Member( "jsonrpc" ).AsString( ), "2.0", "carries jsonrpc 2.0" )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 1, "answers id 1" )
        AssertTrue( r.Has( "result" ), "is a success response" )
        AssertEqStr( r.Member( "result" ).Member( "serverInfo" ).Member( "name" ).AsString( ), _
                     LSP_SERVER_NAME, "serverInfo names the server" )

        dim as JsonValue caps = r.Member( "result" ).Member( "capabilities" )
        AssertEqStr( caps.Member( "positionEncoding" ).AsString( ), LSP_ENCODING_UTF16, _
                     "the negotiated position encoding is stated" )
        AssertTrue ( caps.Member( "textDocumentSync" ).Member( "openClose" ).AsBoolean( ), _
                     "openClose is advertised" )
        AssertEqInt( caps.Member( "textDocumentSync" ).Member( "change" ).AsLongInt( ), _
                     clngint( LSPSYNC_INCREMENTAL ), "incremental sync is advertised" )

        '' Phase 4's three, and still nothing that is not implemented.
        AssertTrue ( caps.Member( "documentSymbolProvider" ).AsBoolean( ), "documentSymbol is claimed" )
        AssertTrue ( caps.Member( "hoverProvider" ).AsBoolean( ), "hover is claimed" )
        AssertTrue ( caps.Member( "definitionProvider" ).AsBoolean( ), "definition is claimed" )
        AssertFalse( caps.Has( "completionProvider" ), "completion is NOT claimed" )
        AssertFalse( caps.Has( "referencesProvider" ), "references is NOT claimed" )
        AssertFalse( caps.Has( "renameProvider" ), "rename is NOT claimed" )
    end scope

    '' -- 2. the window/logMessage triggered by `initialized` --------------------
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

    '' -- 3. MethodNotFound for an unimplemented request -------------------------
    TestGroup( "unimplemented method" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[2] ), "message 2 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 2, "answers id 2" )
        AssertEqInt( r.Member( "error" ).Member( "code" ).AsLongInt( ), RPC_METHOD_NOT_FOUND, _
                     "textDocument/references is MethodNotFound" )
        AssertFalse( r.Has( "result" ), "an error response has no result" )
    end scope

    '' -- 4. a second initialize, string id --------------------------------------
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

    '' -- 5..8. document synchronisation and diagnostics -------------------------
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
                        "v1, 3 line(s), 50 byte(s)", "the opened buffer is measured correctly" )

        '' -- the diagnostic for the missing `end sub` --------------------------
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
        AssertEqInt( item.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 1, _
                     "the range points at the SUB, on line 1" )
        AssertEqInt( item.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 0, _
                     "at character 0" )

        '' -- the edits fix it, so the next report must be EMPTY ----------------
        AssertContains( changeTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "2 edit(s)", "both content changes were applied" )
        AssertContains( changeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "v2, 4 line(s), 58 byte(s)", "the edits applied in order, against the evolving text" )

        AssertEqStr( changeDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "diagnostics republished after the change" )
        AssertEqInt( changeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "and the list is EMPTY -- which is what clears the squiggle" )
        AssertEqInt( changeDiag.Root( ).Member( "params" ).Member( "version" ).AsLongInt( ), 2, _
                     "against the new version" )
    end scope

    '' -- 9..11. the language features -------------------------------------------
    ''
    '' The outline, then a hover and a definition on the USE of `counter` on
    '' line 2, both of which have to land on its DECLARATION on line 0. That is
    '' the whole of phase 4 in three messages.
    TestGroup( "outline, hover and definition" )
    scope
        dim as JsonDoc outline_, hover_, defn_
        AssertTrue( outline_.Parse( messages[8]  ), "message 8 is JSON" )
        AssertTrue( hover_.Parse  ( messages[9]  ), "message 9 is JSON" )
        AssertTrue( defn_.Parse   ( messages[10] ), "message 10 is JSON" )

        '' -- documentSymbol ----------------------------------------------------
        dim as JsonValue syms = outline_.Root( ).Member( "result" )
        AssertEqInt( outline_.Root( ).Member( "id" ).AsLongInt( ), 5, "answers id 5" )
        AssertEqInt( syms.Count( ), 2, "the outline has two top-level symbols" )

        dim as JsonValue s0 = syms.Item( 0 )
        dim as JsonValue s1 = syms.Item( 1 )
        AssertEqStr( s0.Member( "name" ).AsString( ), "counter", "the variable is listed" )
        AssertEqInt( s0.Member( "kind" ).AsLongInt( ), 13, "as a Variable" )
        AssertEqStr( s0.Member( "detail" ).AsString( ), "as long", "with its type" )
        AssertEqStr( s1.Member( "name" ).AsString( ), "Test", "the procedure is listed" )
        AssertEqInt( s1.Member( "kind" ).AsLongInt( ), 12, "as a Function" )

        '' selectionRange is the NAME and must lie inside range, which is the
        '' whole declaration. A client that disagrees shows an empty outline
        '' rather than complaining.
        AssertEqInt( s1.Member( "selectionRange" ).Member( "start" ).Member( "line" ).AsLongInt( ), 1, _
                     "the selection range is the name, on line 1" )
        AssertEqInt( s1.Member( "selectionRange" ).Member( "start" ).Member( "character" ).AsLongInt( ), 4, _
                     "at the character the name starts" )
        AssertEqInt( s1.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 1, _
                     "the full range starts at the SUB" )
        AssertEqInt( s1.Member( "range" ).Member( "end" ).Member( "line" ).AsLongInt( ), 3, _
                     "and ends at the END SUB" )

        '' -- hover -------------------------------------------------------------
        dim as string markdown = hover_.Root( ).Member( "result" ).Member( "contents" ) _
                                       .Member( "value" ).AsString( )
        AssertEqInt( hover_.Root( ).Member( "id" ).AsLongInt( ), 6, "answers id 6" )
        AssertEqStr( hover_.Root( ).Member( "result" ).Member( "contents" ).Member( "kind" ).AsString( ), _
                     "markdown", "hover is markdown" )
        AssertContains( markdown, "counter as long", "showing the declaration" )
        AssertContains( markdown, "variable", "and what kind of thing it is" )
        AssertEqInt( hover_.Root( ).Member( "result" ).Member( "range" ) _
                           .Member( "start" ).Member( "line" ).AsLongInt( ), 2, _
                     "the hovered range is the word under the cursor" )

        '' -- definition --------------------------------------------------------
        dim as JsonValue defnLoc = defn_.Root( ).Member( "result" )
        AssertEqInt( defn_.Root( ).Member( "id" ).AsLongInt( ), 7, "answers id 7" )
        AssertEqStr( defnLoc.Member( "uri" ).AsString( ), "file:///c%3A/dev/x.bas", _
                     "the definition is in this file" )
        AssertEqInt( defnLoc.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 0, _
                     "a use on line 2 resolves to the declaration on line 0" )
        AssertEqInt( defnLoc.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 19, _
                     "at the character the NAME starts, not the line" )
        AssertEqInt( defnLoc.Member( "range" ).Member( "end" ).Member( "character" ).AsLongInt( ), 26, _
                     "and ending after it" )
    end scope

    '' -- 12..15. save and close ---------------------------------------------------
    scope
        dim as JsonDoc saveTrace, saveDiag, closeTrace, closeDiag
        AssertTrue( saveTrace.Parse ( messages[11] ), "message 11 is JSON" )
        AssertTrue( saveDiag.Parse  ( messages[12] ), "message 12 is JSON" )
        AssertTrue( closeTrace.Parse( messages[13] ), "message 13 is JSON" )
        AssertTrue( closeDiag.Parse ( messages[14] ), "message 14 is JSON" )

        AssertContains( saveTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didSave x.bas", "the save names the file" )
        AssertEqStr( saveDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "a save republishes" )

        AssertContains( closeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "0 document(s) still open", "closing released the buffer" )
        AssertEqInt( closeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "with an empty list, so nothing is left on screen" )
        AssertFalse( closeDiag.Root( ).Member( "params" ).Has( "version" ), _
                     "and no version, because the document is gone" )
    end scope

    '' -- 16. the parse error -------------------------------------------------------
    TestGroup( "malformed message" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[15] ), "message 15 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertTrue( r.Member( "id" ).IsNull( ), "an unparseable request is answered with a null id" )
        AssertEqInt( r.Member( "error" ).Member( "code" ).AsLongInt( ), RPC_PARSE_ERROR, _
                     "broken JSON is a ParseError" )
    end scope

    '' -- 17. shutdown ---------------------------------------------------------------
    TestGroup( "shutdown" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[16] ), "message 16 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 3, "answers id 3" )
        AssertTrue( r.Has( "result" ), "shutdown returns a result member" )
        AssertTrue( r.Member( "result" ).IsNull( ), "the shutdown result is null" )
    end scope

    '' -- 18. a request arriving after shutdown --------------------------------------
    TestGroup( "post-shutdown request" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[17] ), "message 17 is JSON" )
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
