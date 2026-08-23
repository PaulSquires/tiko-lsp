'' ############################################################################
''  tests/session_tool.bas -- the end-to-end piped-session test
''
''  This is the "manually piped LSP messages" check, in two halves so it works
''  identically on Windows and Linux without a shell that can emit exact CRLF:
''
''      session_tool --write session.bin <workspace-root>
''      tiko-lsp < session.bin > captured.bin
''      session_tool --check captured.bin
''
''  <workspace-root> is tests/fixtures/workspace, whose two files are what the
''  cross-file assertions are made against. The scripted didOpen carries the
''  REAL CONTENT of widgets.bas, read at --write time, so the buffer and the
''  file on disk cannot drift apart.
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
#include once "../src/utils/uri.bi"

const CR = chr(13)
const LF = chr(10)

'' A doubled quote is how a FreeBASIC literal spells one quote, and a JSON
'' payload is nothing but quotes. Q is one quote, so the messages below read
'' as JSON rather than as a hedge maze.
const Q = chr(34)

private function Frame( byref payload as string ) as string
    return "Content-Length: " & len(payload) & CR & LF & CR & LF & payload
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
''  The scripted client session
'' ----------------------------------------------------------------------------
private function SessionBytes( byref workspaceRoot as string ) as string
    dim as string s
    dim as string wsUri = PathToUri( workspaceRoot )

    '' 1. initialize, with the fixture workspace as its only folder.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "id" & Q & ":1," & Q & "method" & Q & ":" & Q & "initialize" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "processId" & Q & ":4242," & _
                Q & "clientInfo" & Q & ":{" & Q & "name" & Q & ":" & Q & "session_tool" & Q & "," & _
                Q & "version" & Q & ":" & Q & "1.0" & Q & "}," & _
                Q & "rootUri" & Q & ":" & Q & wsUri & Q & "," & _
                Q & "trace" & Q & ":" & Q & "messages" & Q & "," & _
                Q & "capabilities" & Q & ":{" & Q & "general" & Q & ":{" & _
                Q & "positionEncodings" & Q & ":[" & Q & "utf-16" & Q & "," & Q & "utf-8" & Q & "]}}," & _
                Q & "workspaceFolders" & Q & ":[{" & Q & "uri" & Q & ":" & Q & wsUri & Q & "," & _
                Q & "name" & Q & ":" & Q & "fixture" & Q & "}]}}" )

    '' 2. the client confirms. The server answers with its ready message AND,
    ''    because this is where the workspace scan happens, a second one saying
    ''    what it indexed.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "initialized" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 3. a request for something not implemented -> MethodNotFound.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":2," & _
                Q & "method" & Q & ":" & Q & "textDocument/rename" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & Q & "uri" & Q & ":" & _
                Q & "file:///x.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":0," & Q & "character" & Q & ":0}," & _
                Q & "newName" & Q & ":" & Q & "Other" & Q & "}}" )

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
    ''    `end sub`. It is deliberately NOT in the workspace folder.
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
    ''    publishDiagnostics that follows must be EMPTY.
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

    '' 8. a change for a document that was never opened -- dropped in silence.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didChange" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/never-opened.bas" & Q & "," & _
                Q & "version" & Q & ":5}," & _
                Q & "contentChanges" & Q & ":[{" & Q & "text" & Q & ":" & Q & "whatever" & Q & "}]}}" )

    '' 9. the single-file features, against the document as the edits left it.
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

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":8," & _
                Q & "method" & Q & ":" & Q & "textDocument/completion" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":2," & Q & "character" & Q & ":3}}}" )

    '' 10. now a file that IS in the workspace, with the content it has on
    ''     disk. Its `Widget` on line 4 is declared in the OTHER file, which is
    ''     what the next three requests are about.
    dim as string widgetsPath = workspaceRoot & "\widgets.bas"
    dim as string widgetsText
    if( ReadWholeFile( widgetsPath, widgetsText ) = false ) then
        print "session_tool: cannot read " & widgetsPath
        end 1
    end if

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didOpen" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "," & _
                Q & "languageId" & Q & ":" & Q & "freebasic" & Q & "," & Q & "version" & Q & ":1," & _
                Q & "text" & Q & ":" & JsonQuote( widgetsText ) & "}}}" )

    '' 11. cross-file definition: `Widget` at line 4, character 11 is declared
    ''     in shared.bi, which this file only #includes -- and the server does
    ''     not follow includes. The workspace index is the whole reason this
    ''     can be answered.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":9," & _
                Q & "method" & Q & ":" & Q & "textDocument/definition" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":4," & Q & "character" & Q & ":11}}}" )

    '' 12. references to the same name, across both files.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":10," & _
                Q & "method" & Q & ":" & Q & "textDocument/references" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":4," & Q & "character" & Q & ":11}," & _
                Q & "context" & Q & ":{" & Q & "includeDeclaration" & Q & ":true}}}" )

    '' 13. the workspace picker.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":11," & _
                Q & "method" & Q & ":" & Q & "workspace/symbol" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "query" & Q & ":" & Q & "widget" & Q & "}}" )

    '' 14. save and close the first document. widgets.bas stays open, so the
    ''     close trace must say ONE document is still open.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didSave" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}}}" )
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didClose" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}}}" )

    '' 15. broken JSON -> ParseError against a null id, and the session must
    ''     CONTINUE afterwards.
    s &= Frame( "{ this is not json" )

    '' 16. shutdown -> null result.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":3," & _
                Q & "method" & Q & ":" & Q & "shutdown" & Q & "}" )

    '' 17. a request after shutdown -> InvalidRequest.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":4," & _
                Q & "method" & Q & ":" & Q & "textDocument/hover" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 18. exit -> the process ends with code 0, because shutdown came first.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "exit" & Q & "}" )

    return s
end function

private function WriteSession( byref path as string, byref workspaceRoot as string ) as long
    dim as long f = freefile( )
    if( open( path for binary access write as #f ) <> 0 ) then
        print "session_tool: cannot write " & path
        return 1
    end if

    dim as string bytes_ = SessionBytes( workspaceRoot )
    put #f, , bytes_
    close #f

    print "wrote " & len(bytes_) & " bytes to " & path
    return 0
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

    '' Twenty-five, and exactly twenty-five:
    ''   12 answers to requests -- initialize, rename, second initialize,
    ''      documentSymbol, hover, definition, completion, cross-file
    ''      definition, references, workspace/symbol, shutdown, post-shutdown
    ''    1 parse error
    ''    2 window/logMessage -- "ready", and what the workspace scan found
    ''    5 $/logTrace          -- didOpen x2, didChange, didSave, didClose
    ''    5 publishDiagnostics, one after each of those
    '' and NOTHING for the two $/ notifications the server must swallow, nor
    '' for the didChange against a document that was never opened.
    AssertEqInt( f.Pending( ), 0, "the server's output ends on a message boundary" )
    AssertEqInt( messages.Count( ), 25, "the session produced exactly twenty-five messages" )
    if( messages.Count( ) <> 25 ) then
        for i as long = 0 to messages.Count( ) - 1
            print "      [" & i & "] " & left( messages[i], 150 )
        next
        return TestSummary( "piped session" )
    end if

    '' -- 1. the initialize response --------------------------------------------
    TestGroup( "initialize response" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[0] ), "message 0 is JSON" )
        dim as JsonValue r = doc.Root( )
        AssertEqInt( r.Member( "id" ).AsLongInt( ), 1, "answers id 1" )
        AssertEqStr( r.Member( "result" ).Member( "serverInfo" ).Member( "name" ).AsString( ), _
                     LSP_SERVER_NAME, "serverInfo names the server" )

        dim as JsonValue caps = r.Member( "result" ).Member( "capabilities" )
        AssertEqStr( caps.Member( "positionEncoding" ).AsString( ), LSP_ENCODING_UTF16, _
                     "the negotiated position encoding is stated" )
        AssertEqInt( caps.Member( "textDocumentSync" ).Member( "change" ).AsLongInt( ), _
                     clngint( LSPSYNC_INCREMENTAL ), "incremental sync is advertised" )
        AssertTrue ( caps.Member( "documentSymbolProvider" ).AsBoolean( ), "documentSymbol is claimed" )
        AssertTrue ( caps.Member( "hoverProvider" ).AsBoolean( ), "hover is claimed" )
        AssertTrue ( caps.Member( "definitionProvider" ).AsBoolean( ), "definition is claimed" )
        AssertTrue ( caps.Member( "completionProvider" ).IsObject( ), "completion is claimed" )

        '' Phase 6's three.
        AssertTrue ( caps.Member( "workspaceSymbolProvider" ).AsBoolean( ), "workspace/symbol is claimed" )
        AssertTrue ( caps.Member( "referencesProvider" ).AsBoolean( ), "references is claimed" )
        AssertTrue ( caps.Member( "workspace" ).Member( "workspaceFolders" ).Member( "supported" ).AsBoolean( ), _
                     "multi-root workspaces are supported" )
        AssertTrue ( caps.Member( "workspace" ).Member( "workspaceFolders" ) _
                         .Member( "changeNotifications" ).AsBoolean( ), _
                     "and the server asks to be told when they change" )

        '' Still nothing that is not implemented.
        AssertFalse( caps.Has( "renameProvider" ), "rename is NOT claimed" )
        AssertFalse( caps.Has( "signatureHelpProvider" ), "signature help is NOT claimed" )
    end scope

    '' -- 2..3. initialized, and the workspace scan ------------------------------
    TestGroup( "the workspace index is built on `initialized`" )
    scope
        dim as JsonDoc ready_, indexed_
        AssertTrue( ready_.Parse  ( messages[1] ), "message 1 is JSON" )
        AssertTrue( indexed_.Parse( messages[2] ), "message 2 is JSON" )

        AssertEqStr( ready_.Root( ).Member( "method" ).AsString( ), LSP_WINDOW_LOG_MESSAGE, _
                     "the server says it is ready" )
        AssertContains( ready_.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        LSP_SERVER_NAME, "naming itself" )

        AssertEqStr( indexed_.Root( ).Member( "method" ).AsString( ), LSP_WINDOW_LOG_MESSAGE, _
                     "and then what it indexed" )

        dim as string what = indexed_.Root( ).Member( "params" ).Member( "message" ).AsString( )
        AssertContains( what, "indexed 2 file(s)", "both fixture files were found" )
        AssertContains( what, "symbol(s)", "and their symbols counted" )
    end scope

    '' -- 4. MethodNotFound ------------------------------------------------------
    TestGroup( "unimplemented method" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[3] ), "message 3 is JSON" )
        AssertEqInt( doc.Root( ).Member( "id" ).AsLongInt( ), 2, "answers id 2" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_METHOD_NOT_FOUND, _
                     "textDocument/rename is MethodNotFound" )
    end scope

    '' -- 5. a second initialize -------------------------------------------------
    TestGroup( "second initialize" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[4] ), "message 4 is JSON" )
        AssertTrue( doc.Root( ).Member( "id" ).IsString( ), "a string id is echoed AS A STRING" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_REQUEST, _
                     "a second initialize is InvalidRequest" )
    end scope

    '' -- 6..9. document synchronisation and diagnostics -------------------------
    TestGroup( "document synchronisation and diagnostics" )
    scope
        dim as JsonDoc openTrace, openDiag, changeTrace, changeDiag
        AssertTrue( openTrace.Parse  ( messages[5] ), "message 5 is JSON" )
        AssertTrue( openDiag.Parse   ( messages[6] ), "message 6 is JSON" )
        AssertTrue( changeTrace.Parse( messages[7] ), "message 7 is JSON" )
        AssertTrue( changeDiag.Parse ( messages[8] ), "message 8 is JSON" )

        AssertContains( openTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "v1, 3 line(s), 50 byte(s)", "the opened buffer is measured correctly" )

        dim as JsonValue d = openDiag.Root( )
        AssertEqStr( d.Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, "diagnostics published" )
        AssertEqInt( d.Member( "params" ).Member( "diagnostics" ).Count( ), 1, _
                     "one diagnostic for the unclosed sub" )

        dim as JsonValue item = d.Member( "params" ).Member( "diagnostics" ).Item( 0 )
        AssertEqStr( item.Member( "code" ).AsString( ), "unclosed-block", "with a stable code" )
        AssertEqStr( item.Member( "source" ).AsString( ), "tiko-lsp", "attributed to this server" )
        AssertContains( item.Member( "message" ).AsString( ), "'sub Test'", "naming the procedure" )
        AssertEqInt( item.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 1, _
                     "the range points at the SUB, on line 1" )

        AssertContains( changeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "v2, 4 line(s), 58 byte(s)", "the edits applied in order, against the evolving text" )
        AssertEqInt( changeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "and fixing the error publishes an EMPTY list" )
    end scope

    '' -- 10..13. the single-file features ---------------------------------------
    TestGroup( "outline, hover, definition, completion" )
    scope
        dim as JsonDoc outline_, hover_, defn_, cmp_
        AssertTrue( outline_.Parse( messages[9]  ), "message 9 is JSON" )
        AssertTrue( hover_.Parse  ( messages[10] ), "message 10 is JSON" )
        AssertTrue( defn_.Parse   ( messages[11] ), "message 11 is JSON" )
        AssertTrue( cmp_.Parse    ( messages[12] ), "message 12 is JSON" )

        dim as JsonValue syms = outline_.Root( ).Member( "result" )
        AssertEqInt( syms.Count( ), 2, "the outline has two top-level symbols" )
        AssertEqStr( syms.Item( 0 ).Member( "name" ).AsString( ), "counter", "the variable is listed" )
        AssertEqInt( syms.Item( 0 ).Member( "kind" ).AsLongInt( ), 13, "as a Variable" )
        AssertEqStr( syms.Item( 1 ).Member( "name" ).AsString( ), "Test", "the procedure is listed" )

        dim as string markdown = hover_.Root( ).Member( "result" ).Member( "contents" ) _
                                       .Member( "value" ).AsString( )
        AssertContains( markdown, "counter as long", "hover shows the declaration" )

        dim as JsonValue where_ = defn_.Root( ).Member( "result" )
        AssertEqInt( where_.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 0, _
                     "a use on line 2 resolves to the declaration on line 0" )
        AssertEqInt( where_.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 19, _
                     "at the character the NAME starts" )

        dim as JsonValue items = cmp_.Root( ).Member( "result" )
        AssertTrue( items.Count( ) > 200, "completion carries the language as well as the file" )
    end scope

    '' -- 14..15. the workspace file opens ---------------------------------------
    TestGroup( "a workspace file opens" )
    scope
        dim as JsonDoc trace_, diag_
        AssertTrue( trace_.Parse( messages[13] ), "message 13 is JSON" )
        AssertTrue( diag_.Parse ( messages[14] ), "message 14 is JSON" )

        AssertContains( trace_.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didOpen widgets.bas", "the fixture file is opened" )
        AssertEqInt( diag_.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "and it analyses clean" )
    end scope

    '' -- 16..18. THE CROSS-FILE FEATURES ----------------------------------------
    ''
    '' widgets.bas uses `Widget` on line 4. It is declared in shared.bi, which
    '' widgets.bas only #includes -- and this server does not follow includes.
    '' Everything below is answered from the workspace index or not at all.
    TestGroup( "cross-file definition, references, workspace symbols" )
    scope
        dim as JsonDoc defn_, refs_, syms_
        AssertTrue( defn_.Parse( messages[15] ), "message 15 is JSON" )
        AssertTrue( refs_.Parse( messages[16] ), "message 16 is JSON" )
        AssertTrue( syms_.Parse( messages[17] ), "message 17 is JSON" )

        '' -- definition, into another file --------------------------------------
        dim as JsonValue where_ = defn_.Root( ).Member( "result" )
        AssertEqInt( defn_.Root( ).Member( "id" ).AsLongInt( ), 9, "answers id 9" )
        AssertContains( lcase( where_.Member( "uri" ).AsString( ) ), "shared.bi", _
                        "a use in one file resolves to the declaration in ANOTHER" )
        AssertEqInt( where_.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 1, _
                     "landing on the line `type Widget` is on" )
        AssertEqInt( where_.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 5, _
                     "at the character the name starts" )
        AssertEqInt( where_.Member( "range" ).Member( "end" ).Member( "character" ).AsLongInt( ), 11, _
                     "and ending after it" )

        '' -- references, across both files --------------------------------------
        dim as JsonValue refs = refs_.Root( ).Member( "result" )
        AssertEqInt( refs_.Root( ).Member( "id" ).AsLongInt( ), 10, "answers id 10" )
        AssertEqInt( refs.Count( ), 4, "Widget is used four times in the workspace" )

        dim as boolean inShared = false, inWidgets = false
        for i as long = 0 to refs.Count( ) - 1
            dim as string u = lcase( refs.Item( i ).Member( "uri" ).AsString( ) )
            if( instr( u, "shared.bi" ) > 0 ) then inShared = true
            if( instr( u, "widgets.bas" ) > 0 ) then inWidgets = true
        next
        AssertTrue( inShared andalso inWidgets, "and the hits span both files" )

        '' -- the workspace picker ------------------------------------------------
        dim as JsonValue found = syms_.Root( ).Member( "result" )
        AssertEqInt( syms_.Root( ).Member( "id" ).AsLongInt( ), 11, "answers id 11" )
        AssertTrue ( found.Count( ) >= 4, "the query finds the type, the constant and the procedure" )

        dim as JsonValue first_ = found.Item( 0 )
        AssertEqStr( first_.Member( "name" ).AsString( ), "Widget", "the exact match is first" )
        AssertEqInt( first_.Member( "kind" ).AsLongInt( ), 23, "as a Struct" )
        AssertEqStr( first_.Member( "containerName" ).AsString( ), "shared.bi", _
                     "and says which file it is in" )
        AssertContains( lcase( first_.Member( "location" ).Member( "uri" ).AsString( ) ), "shared.bi", _
                        "with a location a client can open" )
        AssertEqInt( first_.Member( "location" ).Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), _
                     1, "at the right line" )
    end scope

    '' -- 19..22. save and close --------------------------------------------------
    TestGroup( "save and close" )
    scope
        dim as JsonDoc saveTrace, saveDiag, closeTrace, closeDiag
        AssertTrue( saveTrace.Parse ( messages[18] ), "message 18 is JSON" )
        AssertTrue( saveDiag.Parse  ( messages[19] ), "message 19 is JSON" )
        AssertTrue( closeTrace.Parse( messages[20] ), "message 20 is JSON" )
        AssertTrue( closeDiag.Parse ( messages[21] ), "message 21 is JSON" )

        AssertContains( saveTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didSave x.bas", "the save names the file" )
        AssertEqStr( saveDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "a save republishes" )

        '' widgets.bas is still open, which is what makes this ONE and not zero.
        AssertContains( closeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "1 document(s) still open", "closing one buffer leaves the other" )
        AssertEqInt( closeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "and clears the closed file's diagnostics" )
    end scope

    '' -- 23. the parse error ------------------------------------------------------
    TestGroup( "malformed message" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[22] ), "message 22 is JSON" )
        AssertTrue( doc.Root( ).Member( "id" ).IsNull( ), "an unparseable request is answered with a null id" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_PARSE_ERROR, _
                     "broken JSON is a ParseError" )
    end scope

    '' -- 24..25. shutdown and after -----------------------------------------------
    TestGroup( "shutdown" )
    scope
        dim as JsonDoc doc, after_
        AssertTrue( doc.Parse   ( messages[23] ), "message 23 is JSON" )
        AssertTrue( after_.Parse( messages[24] ), "message 24 is JSON" )

        AssertEqInt( doc.Root( ).Member( "id" ).AsLongInt( ), 3, "answers id 3" )
        AssertTrue ( doc.Root( ).Member( "result" ).IsNull( ), "the shutdown result is null" )

        AssertEqInt( after_.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_REQUEST, _
                     "a request after shutdown is InvalidRequest" )
    end scope

    return TestSummary( "piped session" )
end function

'' ----------------------------------------------------------------------------
''  Entry point
'' ----------------------------------------------------------------------------
dim as string mode_ = command( 1 )
dim as string path_ = command( 2 )
dim as string root_ = command( 3 )

if( len(path_) = 0 ) then
    print "usage: session_tool --write <file> <workspace-root> | --check <file>"
    end 2
end if

select case lcase( mode_ )
    case "--write"
        if( len(root_) = 0 ) then
            print "session_tool --write needs the workspace root"
            end 2
        end if
        end WriteSession( path_, root_ )

    case "--check"
        end CheckSession( path_ )

    case else
        print "usage: session_tool --write <file> <workspace-root> | --check <file>"
        end 2
end select
