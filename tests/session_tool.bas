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

'' And a backslash, for a JSON string escape written inside one.
const BS = chr(92)

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
                Q & "positionEncodings" & Q & ":[" & Q & "utf-16" & Q & "," & Q & "utf-8" & Q & "]}," & _
                Q & "workspace" & Q & ":{" & Q & "workspaceEdit" & Q & ":{" & _
                Q & "documentChanges" & Q & ":true}}}," & _
                Q & "workspaceFolders" & Q & ":[{" & Q & "uri" & Q & ":" & Q & wsUri & Q & "," & _
                Q & "name" & Q & ":" & Q & "fixture" & Q & "}]}}" )

    '' 2. the client confirms. The server answers with its ready message AND,
    ''    because this is where the workspace scan happens, a second one saying
    ''    what it indexed.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "initialized" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 3. a request for something not implemented -> MethodNotFound. It used
    ''    to be textDocument/rename, which phase 7 implements; typeDefinition
    ''    needs the type system this server does not have, so it is the honest
    ''    stand-in.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":2," & _
                Q & "method" & Q & ":" & Q & "textDocument/typeDefinition" & Q & "," & _
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

    '' 14. a third document, for the editing features. Lines, 0-based:
    ''
    ''        0  sub Move_( byval x as long, byval y as long )
    ''        1  end sub
    ''        2  sub Go_( )
    ''        3  Move_( 10, 3 )
    ''        4  print "oops              <- deliberately unterminated
    ''        5  end sub
    ''
    ''    Line 3 is a call whose signature is known; line 4 is the one lexical
    ''    error there is an unambiguous quick fix_ for.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "textDocument/didOpen" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/y.bas" & Q & "," & _
                Q & "languageId" & Q & ":" & Q & "freebasic" & Q & "," & Q & "version" & Q & ":1," & _
                Q & "text" & Q & ":" & Q & "sub Move_( byval x as long, byval y as long )\n" & _
                "end sub\nsub Go_( )\nMove_( 10, 3 )\nprint " & BS & Q & "oops\nend sub" & Q & "}}}" )

    '' 15. signature help, twice: on the first argument and on the second.
    ''     Line 3 is `Move_( 10, 3 )` -- character 7 is inside `10`, and
    ''     character 11 is inside `3`.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":12," & _
                Q & "method" & Q & ":" & Q & "textDocument/signatureHelp" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/y.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":3," & Q & "character" & Q & ":7}}}" )

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":13," & _
                Q & "method" & Q & ":" & Q & "textDocument/signatureHelp" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/y.bas" & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":3," & Q & "character" & Q & ":11}}}" )

    '' 16. inlay hints over the whole file.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":14," & _
                Q & "method" & Q & ":" & Q & "textDocument/inlayHint" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/y.bas" & Q & "}," & _
                Q & "range" & Q & ":{" & Q & "start" & Q & ":{" & Q & "line" & Q & ":0," & _
                Q & "character" & Q & ":0}," & Q & "end" & Q & ":{" & Q & "line" & Q & ":5," & _
                Q & "character" & Q & ":0}}}}" )

    '' 17. semantic tokens for the same file.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":15," & _
                Q & "method" & Q & ":" & Q & "textDocument/semanticTokens/full" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/y.bas" & Q & "}}}" )

    '' 18. a code action where the caret sits in the unterminated string.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":16," & _
                Q & "method" & Q & ":" & Q & "textDocument/codeAction" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/y.bas" & Q & "}," & _
                Q & "range" & Q & ":{" & Q & "start" & Q & ":{" & Q & "line" & Q & ":4," & _
                Q & "character" & Q & ":8}," & Q & "end" & Q & ":{" & Q & "line" & Q & ":4," & _
                Q & "character" & Q & ":8}}," & _
                Q & "context" & Q & ":{" & Q & "diagnostics" & Q & ":[]}}}" )

    '' 19. prepareRename on the local `w` of widgets.bas -- line 4 is
    ''     `    dim as Widget w`, and character 18 is the `w`.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":17," & _
                Q & "method" & Q & ":" & Q & "textDocument/prepareRename" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":4," & Q & "character" & Q & ":18}}}" )

    '' 20. and the rename itself: a local, so this file and this procedure.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":18," & _
                Q & "method" & Q & ":" & Q & "textDocument/rename" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":4," & Q & "character" & Q & ":18}," & _
                Q & "newName" & Q & ":" & Q & "widget_" & Q & "}}" )

    '' 21. the refusal that matters: `Label_` on line 5 is a FIELD, but
    ''     `label_` is also the parameter of this very function. A name-based
    ''     rename would rewrite both.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":19," & _
                Q & "method" & Q & ":" & Q & "textDocument/prepareRename" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":5," & Q & "character" & Q & ":7}}}" )

    '' 22. a rename to a reserved word -> InvalidParams.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":20," & _
                Q & "method" & Q & ":" & Q & "textDocument/rename" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":4," & Q & "character" & Q & ":18}," & _
                Q & "newName" & Q & ":" & Q & "end" & Q & "}}" )

    '' 23. formatting x.bas, whose body has never been indented.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":21," & _
                Q & "method" & Q & ":" & Q & "textDocument/formatting" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & "file:///c%3A/dev/x.bas" & Q & "}," & _
                Q & "options" & Q & ":{" & Q & "tabSize" & Q & ":4," & _
                Q & "insertSpaces" & Q & ":true}}}" )

    '' 24. save and close the first document. widgets.bas stays open, so the
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

    '' Thirty-seven, and exactly thirty-seven:
    ''   22 answers to requests -- initialize, typeDefinition, second
    ''      initialize, documentSymbol, hover, definition, completion,
    ''      cross-file definition, references, workspace/symbol, two signature
    ''      helps, inlay hints, semantic tokens, code actions, prepareRename,
    ''      rename, a refused prepareRename, a refused rename, formatting,
    ''      shutdown, post-shutdown
    ''    1 parse error
    ''    2 window/logMessage -- "ready", and what the workspace scan found
    ''                            WHEN IT IS TAKEN DELIVERY OF, which is not
    ''                            when it was started: the scan runs on its own
    ''                            thread and the first request that needs it is
    ''                            what waits for it
    ''    6 $/logTrace          -- didOpen x3, didChange, didSave, didClose
    ''    6 publishDiagnostics, one after each of those
    '' and NOTHING for the two $/ notifications the server must swallow, nor
    '' for the didChange against a document that was never opened.
    AssertEqInt( f.Pending( ), 0, "the server's output ends on a message boundary" )
    AssertEqInt( messages.Count( ), 37, "the session produced exactly thirty-seven messages" )
    if( messages.Count( ) <> 37 ) then
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

        '' Phase 7's seven.
        AssertTrue ( caps.Member( "renameProvider" ).Member( "prepareProvider" ).AsBoolean( ), _
                     "rename is claimed, WITH prepare" )
        AssertTrue ( caps.Member( "signatureHelpProvider" ).IsObject( ), "signature help is claimed" )
        AssertTrue ( caps.Member( "semanticTokensProvider" ).Member( "full" ).AsBoolean( ), _
                     "semantic tokens are claimed, full only" )
        AssertFalse( caps.Member( "semanticTokensProvider" ).Has( "range" ), _
                     "and NOT the range variant, which is not implemented" )
        AssertEqInt( caps.Member( "semanticTokensProvider" ).Member( "legend" ) _
                         .Member( "tokenTypes" ).Count( ), SEMTYPE_COUNT, _
                     "the legend is sent in full" )
        AssertTrue ( caps.Member( "inlayHintProvider" ).AsBoolean( ), "inlay hints are claimed" )
        AssertTrue ( caps.Member( "documentFormattingProvider" ).AsBoolean( ), "formatting is claimed" )
        AssertTrue ( caps.Member( "documentRangeFormattingProvider" ).AsBoolean( ), _
                     "and range formatting" )
        AssertEqStr( caps.Member( "codeActionProvider" ).Member( "codeActionKinds" ) _
                         .Item( 0 ).AsString( ), "quickfix", "code actions, quickfix only" )

        '' Still nothing that is not implemented.
        AssertFalse( caps.Has( "typeDefinitionProvider" ), "typeDefinition is NOT claimed" )
        AssertFalse( caps.Has( "documentHighlightProvider" ), "documentHighlight is NOT claimed" )
    end scope

    '' -- 2. initialized ---------------------------------------------------------
    ''
    '' ONE message, not two. The workspace scan is started here and finishes on
    '' its own thread, so what it found is not reported until something asks
    '' for it -- see the cross-file group below, where it arrives.
    TestGroup( "the workspace scan starts on `initialized`" )
    scope
        dim as JsonDoc ready_
        AssertTrue( ready_.Parse( messages[1] ), "message 1 is JSON" )

        AssertEqStr( ready_.Root( ).Member( "method" ).AsString( ), LSP_WINDOW_LOG_MESSAGE, _
                     "the server says it is ready" )
        AssertContains( ready_.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        LSP_SERVER_NAME, "naming itself" )

        '' The next thing the client hears is the answer to its next request,
        '' NOT a scan report. This is the whole change: nothing waited.
        dim as JsonDoc next_
        AssertTrue( next_.Parse( messages[2] ), "message 2 is JSON" )
        AssertFalse( next_.Root( ).Member( "method" ).AsString( ) = LSP_WINDOW_LOG_MESSAGE, _
                     "and then says nothing more until it is asked something" )
    end scope

    '' -- 3. MethodNotFound ------------------------------------------------------
    TestGroup( "unimplemented method" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[2] ), "message 2 is JSON" )
        AssertEqInt( doc.Root( ).Member( "id" ).AsLongInt( ), 2, "answers id 2" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_METHOD_NOT_FOUND, _
                     "textDocument/typeDefinition is MethodNotFound" )
    end scope

    '' -- 4. a second initialize -------------------------------------------------
    TestGroup( "second initialize" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[3] ), "message 3 is JSON" )
        AssertTrue( doc.Root( ).Member( "id" ).IsString( ), "a string id is echoed AS A STRING" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_REQUEST, _
                     "a second initialize is InvalidRequest" )
    end scope

    '' -- 5..8. document synchronisation and diagnostics -------------------------
    ''
    '' All four of these are answered WHILE THE SCAN IS RUNNING, which is the
    '' point of phase 8: typing and diagnostics never wait for the workspace.
    TestGroup( "document synchronisation and diagnostics" )
    scope
        dim as JsonDoc openTrace, openDiag, changeTrace, changeDiag
        AssertTrue( openTrace.Parse  ( messages[4] ), "message 4 is JSON" )
        AssertTrue( openDiag.Parse   ( messages[5] ), "message 5 is JSON" )
        AssertTrue( changeTrace.Parse( messages[6] ), "message 6 is JSON" )
        AssertTrue( changeDiag.Parse ( messages[7] ), "message 7 is JSON" )

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

    '' -- 9..12. the single-file features -----------------------------------------
    TestGroup( "outline, hover, definition, completion" )
    scope
        dim as JsonDoc outline_, hover_, defn_, cmp_
        AssertTrue( outline_.Parse( messages[8]  ), "message 8 is JSON" )
        AssertTrue( hover_.Parse  ( messages[9]  ), "message 9 is JSON" )
        AssertTrue( defn_.Parse   ( messages[10] ), "message 10 is JSON" )
        AssertTrue( cmp_.Parse    ( messages[11] ), "message 11 is JSON" )

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

    '' -- 13..14. the workspace file opens ---------------------------------------
    TestGroup( "a workspace file opens" )
    scope
        dim as JsonDoc trace_, diag_
        AssertTrue( trace_.Parse( messages[12] ), "message 12 is JSON" )
        AssertTrue( diag_.Parse ( messages[13] ), "message 13 is JSON" )

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
        dim as JsonDoc indexed_, defn_, refs_, syms_
        AssertTrue( indexed_.Parse( messages[14] ), "message 14 is JSON" )
        AssertTrue( defn_.Parse   ( messages[15] ), "message 15 is JSON" )
        AssertTrue( refs_.Parse   ( messages[16] ), "message 16 is JSON" )
        AssertTrue( syms_.Parse   ( messages[17] ), "message 17 is JSON" )

        '' -- the scan is delivered HERE ------------------------------------------
        ''
        '' Thirteen messages after it was started, and immediately before the
        '' first request that could not be answered without it. Everything in
        '' between -- three documents opened, an edit, an outline, a hover, a
        '' definition, a completion list -- was answered while it ran.
        AssertEqStr( indexed_.Root( ).Member( "method" ).AsString( ), LSP_WINDOW_LOG_MESSAGE, _
                     "the scan reports in when its result is taken" )

        dim as string what = indexed_.Root( ).Member( "params" ).Member( "message" ).AsString( )
        AssertContains( what, "indexed 2 file(s)", "both fixture files were found" )
        AssertContains( what, "symbol(s)", "and their symbols counted" )
        AssertFalse( instr( what, "0 symbol(s)" ) > 0, _
                     "with symbols in them -- a keyword table raced into by two " & _
                     "threads indexes every file to nothing, silently" )

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

    '' -- 19..30. THE EDITING FEATURES ------------------------------------------
    TestGroup( "signature help, inlay hints, semantic tokens, code actions" )
    scope
        dim as JsonDoc yTrace, yDiag, sig1, sig2, hints_, sem_, actions_
        AssertTrue( yTrace.Parse  ( messages[18] ), "message 18 is JSON" )
        AssertTrue( yDiag.Parse   ( messages[19] ), "message 19 is JSON" )
        AssertTrue( sig1.Parse    ( messages[20] ), "message 20 is JSON" )
        AssertTrue( sig2.Parse    ( messages[21] ), "message 21 is JSON" )
        AssertTrue( hints_.Parse  ( messages[22] ), "message 22 is JSON" )
        AssertTrue( sem_.Parse    ( messages[23] ), "message 23 is JSON" )
        AssertTrue( actions_.Parse( messages[24] ), "message 24 is JSON" )

        AssertContains( yTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didOpen y.bas", "the third document opens" )
        AssertEqInt( yDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 1, _
                     "with the one lexical error it was written to have" )

        '' -- signature help ----------------------------------------------------
        dim as JsonValue sig = sig1.Root( ).Member( "result" ).Member( "signatures" ).Item( 0 )
        AssertEqStr( sig.Member( "label" ).AsString( ), _
                     "Move_(byval x as long, byval y as long)", _
                     "the signature is shown as declared" )
        AssertEqInt( sig.Member( "parameters" ).Count( ), 2, "with two parameters" )
        AssertEqInt( sig1.Root( ).Member( "result" ).Member( "activeParameter" ).AsLongInt( ), 0, _
                     "the caret in the first argument highlights the first parameter" )

        '' The [start, end) span, which is what the client highlights.
        dim as JsonValue span = sig.Member( "parameters" ).Item( 1 ).Member( "label" )
        AssertTrue( span.IsArray( ), "a parameter's label is an offset pair, not a substring" )
        AssertEqInt( span.Item( 0 ).AsLongInt( ), 23, "starting where `byval y` starts" )

        AssertEqInt( sig2.Root( ).Member( "result" ).Member( "activeParameter" ).AsLongInt( ), 1, _
                     "and after the comma, the second" )

        '' -- inlay hints -------------------------------------------------------
        dim as JsonValue hints = hints_.Root( ).Member( "result" )
        AssertEqInt( hints.Count( ), 2, "both literal arguments are annotated" )
        AssertEqStr( hints.Item( 0 ).Member( "label" ).AsString( ), "x:", "with the parameter's name" )
        AssertEqInt( hints.Item( 0 ).Member( "kind" ).AsLongInt( ), 2, "as a Parameter hint" )
        AssertEqInt( hints.Item( 0 ).Member( "position" ).Member( "line" ).AsLongInt( ), 3, _
                     "on the line the call is on" )
        AssertEqInt( hints.Item( 0 ).Member( "position" ).Member( "character" ).AsLongInt( ), 7, _
                     "immediately before the argument" )
        AssertEqStr( hints.Item( 1 ).Member( "label" ).AsString( ), "y:", "and the second is the second" )

        '' -- semantic tokens ---------------------------------------------------
        dim as JsonValue data_ = sem_.Root( ).Member( "result" ).Member( "data" )
        AssertTrue ( data_.Count( ) > 20, "the file produces semantic tokens" )
        AssertEqInt( data_.Count( ) mod 5, 0, "five integers per token" )
        AssertEqInt( data_.Item( 0 ).AsLongInt( ), 0, "the first token is on line 0" )
        AssertEqInt( data_.Item( 1 ).AsLongInt( ), 0, "at character 0" )
        AssertEqInt( data_.Item( 3 ).AsLongInt( ), 13, "and is a keyword -- legend index 13" )

        '' -- code actions ------------------------------------------------------
        dim as JsonValue actions = actions_.Root( ).Member( "result" )
        AssertEqInt( actions.Count( ), 1, "one quick fix_ for the unterminated string" )

        dim as JsonValue fix_ = actions.Item( 0 )
        AssertEqStr( fix_.Member( "title" ).AsString( ), "Insert the closing quote", "titled plainly" )
        AssertEqStr( fix_.Member( "kind"  ).AsString( ), "quickfix", "as a quickfix" )
        AssertEqStr( fix_.Member( "diagnostics" ).Item( 0 ).Member( "code" ).AsString( ), _
                     "unterminated-string", "carrying the diagnostic it fixes" )

        '' The client said it understands documentChanges, so the edit is the
        '' VERSIONED form.
        dim as JsonValue entry = fix_.Member( "edit" ).Member( "documentChanges" ).Item( 0 )
        AssertEqInt( entry.Member( "textDocument" ).Member( "version" ).AsLongInt( ), 1, _
                     "against the version it was computed from" )
        AssertEqStr( entry.Member( "edits" ).Item( 0 ).Member( "newText" ).AsString( ), Q, _
                     "and the edit inserts one quote" )
        AssertEqInt( entry.Member( "edits" ).Item( 0 ).Member( "range" ).Member( "start" ) _
                          .Member( "character" ).AsLongInt( ), 11, _
                     "at the end of the line, where the quote belongs" )
    end scope

    TestGroup( "rename" )
    scope
        dim as JsonDoc prep_, ren_, refused_, badName_, fmt_
        AssertTrue( prep_.Parse   ( messages[25] ), "message 25 is JSON" )
        AssertTrue( ren_.Parse    ( messages[26] ), "message 26 is JSON" )
        AssertTrue( refused_.Parse( messages[27] ), "message 27 is JSON" )
        AssertTrue( badName_.Parse( messages[28] ), "message 28 is JSON" )
        AssertTrue( fmt_.Parse    ( messages[29] ), "message 29 is JSON" )

        '' -- prepareRename ------------------------------------------------------
        dim as JsonValue prep = prep_.Root( ).Member( "result" )
        AssertEqStr( prep.Member( "placeholder" ).AsString( ), "w", _
                     "prepareRename offers the name as written" )
        AssertEqInt( prep.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 18, _
                     "over exactly the identifier" )
        AssertEqInt( prep.Member( "range" ).Member( "end" ).Member( "character" ).AsLongInt( ), 19, _
                     "and no further" )

        '' -- the rename ---------------------------------------------------------
        ''
        '' `w` is a LOCAL, so the edit is confined to its own procedure in its
        '' own file: three occurrences, and nothing in shared.bi.
        dim as JsonValue changes = ren_.Root( ).Member( "result" ).Member( "documentChanges" )
        AssertEqInt( changes.Count( ), 1, "a local rename touches ONE file" )
        AssertContains( lcase( changes.Item( 0 ).Member( "textDocument" ).Member( "uri" ).AsString( ) ), _
                        "widgets.bas", "the file the local is in" )
        AssertEqInt( changes.Item( 0 ).Member( "textDocument" ).Member( "version" ).AsLongInt( ), 1, _
                     "at the version it was computed against" )
        AssertEqInt( changes.Item( 0 ).Member( "edits" ).Count( ), 3, _
                     "and rewrites its three occurrences" )
        AssertEqStr( changes.Item( 0 ).Member( "edits" ).Item( 0 ).Member( "newText" ).AsString( ), _
                     "widget_", "with the new name" )

        '' -- the refusal ---------------------------------------------------------
        AssertTrue( refused_.Root( ).Has( "error" ), "renaming a name a local shares is REFUSED" )
        AssertContains( refused_.Root( ).Member( "error" ).Member( "message" ).AsString( ), _
                        "is also a local", "and the message says why" )

        AssertTrue( badName_.Root( ).Has( "error" ), "renaming to a reserved word is refused" )
        AssertEqInt( badName_.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_PARAMS, _
                     "as InvalidParams" )

        '' -- formatting -----------------------------------------------------------
        ''
        '' x.bas is `dim shared as long counter / sub Test( ) / counter = 2 /
        '' end sub`, so exactly one line is in the wrong column.
        dim as JsonValue edits = fmt_.Root( ).Member( "result" )
        AssertEqInt( edits.Count( ), 1, "formatting the file produces one edit" )
        AssertEqInt( edits.Item( 0 ).Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 2, _
                     "on the body line" )
        AssertEqStr( edits.Item( 0 ).Member( "newText" ).AsString( ), "    ", _
                     "inserting one level of indentation" )
    end scope

    '' -- 31..34. save and close --------------------------------------------------
    TestGroup( "save and close" )
    scope
        dim as JsonDoc saveTrace, saveDiag, closeTrace, closeDiag
        AssertTrue( saveTrace.Parse ( messages[30] ), "message 30 is JSON" )
        AssertTrue( saveDiag.Parse  ( messages[31] ), "message 31 is JSON" )
        AssertTrue( closeTrace.Parse( messages[32] ), "message 32 is JSON" )
        AssertTrue( closeDiag.Parse ( messages[33] ), "message 33 is JSON" )

        AssertContains( saveTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didSave x.bas", "the save names the file" )
        AssertEqStr( saveDiag.Root( ).Member( "method" ).AsString( ), LSP_PUBLISH_DIAGNOSTICS, _
                     "a save republishes" )

        '' widgets.bas and y.bas are still open, which is what makes this TWO.
        AssertContains( closeTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "2 document(s) still open", "closing one buffer leaves the others" )
        AssertEqInt( closeDiag.Root( ).Member( "params" ).Member( "diagnostics" ).Count( ), 0, _
                     "and clears the closed file's diagnostics" )
    end scope

    '' -- 35. the parse error ------------------------------------------------------
    TestGroup( "malformed message" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( messages[34] ), "message 34 is JSON" )
        AssertTrue( doc.Root( ).Member( "id" ).IsNull( ), "an unparseable request is answered with a null id" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_PARSE_ERROR, _
                     "broken JSON is a ParseError" )
    end scope

    '' -- 36..37. shutdown and after -----------------------------------------------
    TestGroup( "shutdown" )
    scope
        dim as JsonDoc doc, after_
        AssertTrue( doc.Parse   ( messages[35] ), "message 35 is JSON" )
        AssertTrue( after_.Parse( messages[36] ), "message 36 is JSON" )

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
