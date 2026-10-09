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
                Q & "documentChanges" & Q & ":true}," & _
                Q & "didChangeWatchedFiles" & Q & ":{" & _
                Q & "dynamicRegistration" & Q & ":true}}}," & _
                Q & "workspaceFolders" & Q & ":[{" & Q & "uri" & Q & ":" & Q & wsUri & Q & "," & _
                Q & "name" & Q & ":" & Q & "fixture" & Q & "}]}}" )

    '' 2. the client confirms. The server answers with its ready message AND,
    ''    because this is where the workspace scan happens, a second one saying
    ''    what it indexed.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "initialized" & Q & "," & Q & "params" & Q & ":{}}" )

    '' 3. the answer to the server's own request. It asked the client to watch
    ''    the workspace the moment `initialized` arrived, and a client that
    ''    never answers is a client that never registered.
    ''
    ''    The id is the server's, and it is a STRING -- "tiko-1" -- so it can
    ''    never be confused with one of the numbered ids below.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "id" & Q & ":" & Q & "tiko-1" & Q & "," & Q & "result" & Q & ":null}" )

    '' 4. a request for something not implemented -> MethodNotFound. It used
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
                Q & "languageId" & Q & ":" & Q & "tiko" & Q & "," & Q & "version" & Q & ":1," & _
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
                Q & "languageId" & Q & ":" & Q & "tiko" & Q & "," & Q & "version" & Q & ":1," & _
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
                Q & "languageId" & Q & ":" & Q & "tiko" & Q & "," & Q & "version" & Q & ":1," & _
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

    '' 24. A FILE CHANGES BEHIND THE EDITOR'S BACK. shared.bi is reported
    ''     deleted -- a branch switch, say -- and the workspace picker must
    ''     stop offering what was in it.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "workspace/didChangeWatchedFiles" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "changes" & Q & ":[{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( workspaceRoot & "\shared.bi" ) & Q & "," & _
                Q & "type" & Q & ":3}]}}" )

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":22," & _
                Q & "method" & Q & ":" & Q & "workspace/symbol" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "query" & Q & ":" & Q & "widget" & Q & "}}" )

    '' 25. and back again: the same file reported created.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                Q & "method" & Q & ":" & Q & "workspace/didChangeWatchedFiles" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "changes" & Q & ":[{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( workspaceRoot & "\shared.bi" ) & Q & "," & _
                Q & "type" & Q & ":1}," & _
                "{" & Q & "uri" & Q & ":" & Q & PathToUri( workspaceRoot & "\notes.txt" ) & Q & "," & _
                Q & "type" & Q & ":1}," & _
                "{" & Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "," & _
                Q & "type" & Q & ":2}]}}" )

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":23," & _
                Q & "method" & Q & ":" & Q & "workspace/symbol" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "query" & Q & ":" & Q & "widget" & Q & "}}" )

    '' 26. A BURST. A hundred and twenty distinct files reported at once, which
    ''     is what a branch switch looks like from a watcher. Applying those
    ''     one at a time would be a fifth of a second of a frozen editor, so
    ''     the server re-scans the workspace on the worker instead -- and the
    ''     next request that needs the index waits for that scan, exactly as it
    ''     does at start-up.
    scope
        dim as string changes_
        for i as long = 1 to 120
            if( i > 1 ) then changes_ &= ","
            changes_ &= "{" & Q & "uri" & Q & ":" & Q & _
                        PathToUri( workspaceRoot & "\burst" & i & ".bas" ) & Q & "," & _
                        Q & "type" & Q & ":1}"
        next

        '' Two REAL files among the fiction: shared.bi, which is on disk and
        '' not open, and widgets.bas, which the editor HAS open and which must
        '' be left alone even here.
        changes_ &= ",{" & Q & "uri" & Q & ":" & Q & _
                    PathToUri( workspaceRoot & "\shared.bi" ) & Q & "," & _
                    Q & "type" & Q & ":2}"
        changes_ &= ",{" & Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "," & _
                    Q & "type" & Q & ":2}"

        s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                    Q & "method" & Q & ":" & Q & "workspace/didChangeWatchedFiles" & Q & "," & _
                    Q & "params" & Q & ":{" & Q & "changes" & Q & ":[" & changes_ & "]}}" )
    end scope

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":24," & _
                Q & "method" & Q & ":" & Q & "workspace/symbol" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "query" & Q & ":" & Q & "widget" & Q & "}}" )

    '' 27. THE INCLUDE GRAPH. widgets.bas line 1 is `#include once "shared.bi"`,
    ''     and character 20 is inside the quoted path.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":25," & _
                Q & "method" & Q & ":" & Q & "textDocument/definition" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":1," & Q & "character" & Q & ":20}}}" )

    '' 28. completion inside the function body: line 6 is `    return w`, and
    ''     character 4 is the start of it -- an ordinary scope position. What
    ''     it must now contain is everything shared.bi declares.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":26," & _
                Q & "method" & Q & ":" & Q & "textDocument/completion" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":6," & Q & "character" & Q & ":4}}}" )

    '' 29. and member completion: line 5 is `    w.Label_ = label_`, character 6
    ''     is immediately after the dot. `w` is a Widget, Widget is declared in
    ''     the OTHER file, and its fields have to come from there.
    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":27," & _
                Q & "method" & Q & ":" & Q & "textDocument/completion" & Q & "," & _
                Q & "params" & Q & ":{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & PathToUri( widgetsPath ) & Q & "}," & _
                Q & "position" & Q & ":{" & Q & "line" & Q & ":5," & Q & "character" & Q & ":6}}}" )

    '' 30. save and close the first document. widgets.bas stays open, so the
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

    '' Forty-two, and exactly forty-two:
    ''    1 request FROM the server -- client/registerCapability, asking the
    ''      client to watch the workspace for source files
    ''   28 answers to requests -- initialize, typeDefinition, second
    ''      initialize, documentSymbol, hover, definition, completion,
    ''      cross-file definition, references, workspace/symbol, two signature
    ''      helps, inlay hints, semantic tokens, code actions, prepareRename,
    ''      rename, a refused prepareRename, a refused rename, formatting,
    ''      three more workspace/symbol queries around watched-file changes,
    ''      a jump along an #include and two completions that read through one,
    ''      shutdown, post-shutdown
    ''    1 parse error
    ''    3 window/logMessage -- "ready", and what each background scan found:
    ''                           the one started at `initialized` and the one a
    ''                           burst of watched-file changes triggers. WHERE
    ''                           those two land in the stream is a matter of
    ''                           thread scheduling, so they are checked by
    ''                           content and taken out before anything else is
    ''                           checked by position
    ''    9 $/logTrace          -- didOpen x3, didChange, didSave, didClose,
    ''                            and three didChangeWatchedFiles
    ''    6 publishDiagnostics, one after each of the document ones
    '' and NOTHING for the two $/ notifications the server must swallow, for
    '' the didChange against a document that was never opened, or for the
    '' client's answer to the registration request.
    AssertEqInt( f.Pending( ), 0, "the server's output ends on a message boundary" )
    AssertEqInt( messages.Count( ), 48, "the session produced exactly forty-eight messages" )
    if( messages.Count( ) <> 48 ) then
        for i as long = 0 to messages.Count( ) - 1
            print "      [" & i & "] " & left( messages[i], 150 )
        next
        return TestSummary( "piped session" )
    end if

    '' -- the two scan reports, which arrive WHEN A THREAD FINISHES --------------
    ''
    '' Everything else in this stream is ordered by the protocol: an answer
    '' follows its request. These two do not belong to any request -- they are
    '' the workspace scan and the watched-file refresh saying what they found,
    '' at whichever message first collected them. That is a matter of thread
    '' scheduling, so they are checked by CONTENT and then taken out of the
    '' stream; the positional assertions below read what is left.
    TestGroup( "the background scans report in" )

    dim ordered as FB.Array( of string )
    dim reports as FB.Array( of string )
    dim as long firstReportAt = -1

    scope
        for i as long = 0 to messages.Count( ) - 1
            dim as JsonDoc doc
            dim as boolean isReport = false

            if( doc.Parse( messages[i] ) ) then
                if( doc.Root( ).Member( "method" ).AsString( ) = LSP_WINDOW_LOG_MESSAGE ) then
                    dim as string text_ = doc.Root( ).Member( "params" ).Member( "message" ).AsString( )
                    if( instr( text_, "indexed " ) > 0 orelse instr( text_, "re-indexed " ) > 0 ) then
                        isReport = true
                        if( firstReportAt < 0 ) then firstReportAt = i
                    end if
                end if
            end if

            if( isReport ) then reports.Push( messages[i] ) else ordered.Push( messages[i] )
        next

        AssertEqInt( reports.Count( ), 2, "two scans reported in: the start-up one and the refresh" )
        if( reports.Count( ) = 2 ) then
            dim as JsonDoc first_, second_
            AssertTrue( first_.Parse ( reports[0] ), "the first report is JSON" )
            AssertTrue( second_.Parse( reports[1] ), "the second report is JSON" )

            dim as string a = first_.Root( ).Member( "params" ).Member( "message" ).AsString( )
            AssertContains( a, "indexed 2 file(s)", "the start-up scan found both fixture files" )
            AssertContains( a, "symbol(s)", "and counted their symbols" )
            AssertFalse( instr( a, "0 symbol(s)" ) > 0, _
                         "with symbols in them -- a keyword table raced into by two " & _
                         "threads indexes every file to nothing, silently" )

            dim as string b = second_.Root( ).Member( "params" ).Member( "message" ).AsString( )
            AssertContains( b, "re-indexed 1 of 121 file(s)", _
                            "the burst's refresh re-read one real file, and only one" )
            AssertContains( b, "120 unreadable", "the invented ones simply failed" )
        end if

        '' It cannot arrive before there is anything to report on, and it must
        '' arrive before the first answer that depends on it.
        AssertTrue( firstReportAt > 2, "no scan reports before the client is even registered" )
    end scope

    '' -- 1. the initialize response --------------------------------------------
    TestGroup( "initialize response" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( ordered[0] ), "message 0 is JSON" )
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
        AssertTrue( ready_.Parse( ordered[1] ), "message 1 is JSON" )

        AssertEqStr( ready_.Root( ).Member( "method" ).AsString( ), LSP_WINDOW_LOG_MESSAGE, _
                     "the server says it is ready" )
        AssertContains( ready_.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        LSP_SERVER_NAME, "naming itself" )

        '' Then it asks the client for something: to watch the workspace. This
        '' is the only request this server ever sends, and it is a REQUEST --
        '' there is no capability for file watching, so registering at run time
        '' is the only way to have it.
        dim as JsonDoc reg_
        AssertTrue( reg_.Parse( ordered[2] ), "message 2 is JSON" )
        AssertEqStr( reg_.Root( ).Member( "method" ).AsString( ), LSP_REGISTER_CAPABILITY, _
                     "the server registers for file watching" )
        AssertTrue( reg_.Root( ).Member( "id" ).IsString( ), _
                    "with an id of its own, in its own namespace" )

        dim as JsonValue registration = reg_.Root( ).Member( "params" ) _
                                            .Member( "registrations" ).Item( 0 )
        AssertEqStr( registration.Member( "method" ).AsString( ), LSP_DID_CHANGE_WATCHED, _
                     "for didChangeWatchedFiles" )

        dim as JsonValue watcher = registration.Member( "registerOptions" ) _
                                               .Member( "watchers" ).Item( 0 )
        AssertEqStr( watcher.Member( "globPattern" ).AsString( ), LSP_WATCH_GLOB, _
                     "watching tiko source and nothing else" )
        AssertEqInt( watcher.Member( "kind" ).AsLongInt( ), LSP_WATCH_KIND, _
                     "for creation, change and deletion alike" )

        '' And then it says nothing more until it is asked something: the scan
        '' it started reports in later, when its result is taken.
        dim as JsonDoc next_
        AssertTrue( next_.Parse( ordered[3] ), "message 3 is JSON" )
        AssertFalse( next_.Root( ).Member( "method" ).AsString( ) = LSP_WINDOW_LOG_MESSAGE, _
                     "and nothing else before the next answer" )
    end scope

    '' -- 3. MethodNotFound ------------------------------------------------------
    TestGroup( "unimplemented method" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( ordered[3] ), "message 3 is JSON" )
        AssertEqInt( doc.Root( ).Member( "id" ).AsLongInt( ), 2, "answers id 2" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_METHOD_NOT_FOUND, _
                     "textDocument/typeDefinition is MethodNotFound" )
    end scope

    '' -- 4. a second initialize -------------------------------------------------
    TestGroup( "second initialize" )
    scope
        dim as JsonDoc doc
        AssertTrue( doc.Parse( ordered[4] ), "message 4 is JSON" )
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
        AssertTrue( openTrace.Parse  ( ordered[5] ), "message 5 is JSON" )
        AssertTrue( openDiag.Parse   ( ordered[6] ), "message 6 is JSON" )
        AssertTrue( changeTrace.Parse( ordered[7] ), "message 7 is JSON" )
        AssertTrue( changeDiag.Parse ( ordered[8] ), "message 8 is JSON" )

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
        AssertTrue( outline_.Parse( ordered[9]  ), "message 9 is JSON" )
        AssertTrue( hover_.Parse  ( ordered[10]  ), "message 10 is JSON" )
        AssertTrue( defn_.Parse   ( ordered[11] ), "message 11 is JSON" )
        AssertTrue( cmp_.Parse    ( ordered[12] ), "message 12 is JSON" )

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

        '' A CompletionList, not a bare array: the server has to be able to say
        '' `isIncomplete`, and it does whenever it filtered by the typed prefix.
        dim as JsonValue cmpResult = cmp_.Root( ).Member( "result" )
        AssertTrue( cmpResult.Member( "items" ).Count( ) > 200, _
                    "completion carries the language as well as the file" )
        AssertFalse( cmpResult.Member( "isIncomplete" ).AsBoolean( true ), _
                     "and with nothing typed yet it is the whole list" )
    end scope

    '' -- 13..14. the workspace file opens ---------------------------------------
    TestGroup( "a workspace file opens" )
    scope
        dim as JsonDoc trace_, diag_
        AssertTrue( trace_.Parse( ordered[13] ), "message 13 is JSON" )
        AssertTrue( diag_.Parse ( ordered[14] ), "message 14 is JSON" )

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
        AssertTrue( defn_.Parse( ordered[15] ), "message 15 is JSON" )
        AssertTrue( refs_.Parse( ordered[16] ), "message 16 is JSON" )
        AssertTrue( syms_.Parse( ordered[17] ), "message 17 is JSON" )

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
        AssertTrue( yTrace.Parse  ( ordered[18] ), "message 18 is JSON" )
        AssertTrue( yDiag.Parse   ( ordered[19] ), "message 19 is JSON" )
        AssertTrue( sig1.Parse    ( ordered[20] ), "message 20 is JSON" )
        AssertTrue( sig2.Parse    ( ordered[21] ), "message 21 is JSON" )
        AssertTrue( hints_.Parse  ( ordered[22] ), "message 22 is JSON" )
        AssertTrue( sem_.Parse    ( ordered[23] ), "message 23 is JSON" )
        AssertTrue( actions_.Parse( ordered[24] ), "message 24 is JSON" )

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
        AssertTrue( prep_.Parse   ( ordered[25] ), "message 25 is JSON" )
        AssertTrue( ren_.Parse    ( ordered[26] ), "message 26 is JSON" )
        AssertTrue( refused_.Parse( ordered[27] ), "message 27 is JSON" )
        AssertTrue( badName_.Parse( ordered[28] ), "message 28 is JSON" )
        AssertTrue( fmt_.Parse    ( ordered[29] ), "message 29 is JSON" )

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

    '' -- 31..34. A FILE CHANGES BEHIND THE EDITOR'S BACK -------------------------
    ''
    '' shared.bi is reported deleted and then created again. Nothing on disk
    '' actually moves: what is under test is that the server believes the
    '' client, because the client is the only one watching.
    TestGroup( "watched files" )
    scope
        dim as JsonDoc goneTrace, goneSyms, backTrace, backSyms
        AssertTrue( goneTrace.Parse( ordered[30] ), "message 30 is JSON" )
        AssertTrue( goneSyms.Parse ( ordered[31] ), "message 31 is JSON" )
        AssertTrue( backTrace.Parse( ordered[32] ), "message 32 is JSON" )
        AssertTrue( backSyms.Parse ( ordered[33] ), "message 33 is JSON" )

        '' -- deleted -------------------------------------------------------------
        AssertContains( goneTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "didChangeWatchedFiles", "the notification is acted on" )
        AssertContains( goneTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "1 removed", "one file leaves the index" )

        dim as JsonValue after_ = goneSyms.Root( ).Member( "result" )
        dim as boolean sawShared = false
        for i as long = 0 to after_.Count( ) - 1
            if( instr( lcase( after_.Item( i ).Member( "location" ).Member( "uri" ).AsString( ) ), _
                       "shared.bi" ) > 0 ) then sawShared = true
        next
        AssertFalse( sawShared, "and the picker stops offering what was in it" )

        '' -- created again --------------------------------------------------------
        ''
        '' The same batch reports two more changes that must be IGNORED: a
        '' .txt file, because a client may watch more than it was asked to,
        '' and widgets.bas, which the editor has OPEN -- re-reading the disk
        '' copy of that would replace what the user can see with what was last
        '' saved.
        AssertContains( backTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "1 re-indexed", "the file comes back" )
        AssertContains( backTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "2 ignored", "a non-source file and an OPEN document are both ignored" )

        dim as JsonValue back_ = backSyms.Root( ).Member( "result" )
        sawShared = false
        for i as long = 0 to back_.Count( ) - 1
            if( instr( lcase( back_.Item( i ).Member( "location" ).Member( "uri" ).AsString( ) ), _
                       "shared.bi" ) > 0 ) then sawShared = true
        next
        AssertTrue( sawShared, "and its symbols are findable again" )
    end scope

    '' -- 35..37. A BURST GOES TO THE WORKER ---------------------------------------
    TestGroup( "a watched-file burst" )
    scope
        dim as JsonDoc burstTrace, syms_
        AssertTrue( burstTrace.Parse( ordered[34] ), "message 34 is JSON" )
        AssertTrue( syms_.Parse     ( ordered[35] ), "message 35 is JSON" )

        '' A hundred and twenty invented files plus shared.bi -- and NOT
        '' widgets.bas, which the editor has open. The open file is filtered
        '' out before the count is taken, exactly as in a small batch.
        AssertContains( burstTrace.Root( ).Member( "params" ).Member( "message" ).AsString( ), _
                        "121 change(s)", "the open file is excluded from the batch" )
        AssertContains( burstTrace.Root( ).Member( "params" ).Member( "verbose" ).AsString( ), _
                        "121 re-indexed in the background", _
                        "and none of them is read on the message loop" )

        '' What the refresh actually did is checked with the other scan report,
        '' at the top: it arrives when a thread finishes, not when a message is
        '' answered.
        ''
        '' And the index is intact. A file that could not be read keeps
        '' whatever the index already knew about it -- merging an empty entry
        '' for it would delete a file's symbols because a watcher was wrong.
        dim as JsonValue found = syms_.Root( ).Member( "result" )
        AssertEqInt( syms_.Root( ).Member( "id" ).AsLongInt( ), 24, "answers id 24" )

        dim as boolean sawShared = false
        for i as long = 0 to found.Count( ) - 1
            if( instr( lcase( found.Item( i ).Member( "location" ).Member( "uri" ).AsString( ) ), _
                       "shared.bi" ) > 0 ) then sawShared = true
        next
        AssertTrue( sawShared, "and the workspace is whole afterwards" )
    end scope

    '' -- 36..38. THE INCLUDE GRAPH -----------------------------------------------
    TestGroup( "the include graph" )
    scope
        dim as JsonDoc jump_, scope_, member_
        AssertTrue( jump_.Parse  ( ordered[36] ), "message 36 is JSON" )
        AssertTrue( scope_.Parse ( ordered[37] ), "message 37 is JSON" )
        AssertTrue( member_.Parse( ordered[38] ), "message 38 is JSON" )

        '' -- go to definition ON an #include line --------------------------------
        dim as JsonValue where_ = jump_.Root( ).Member( "result" )
        AssertEqInt( jump_.Root( ).Member( "id" ).AsLongInt( ), 25, "answers id 25" )
        AssertContains( lcase( where_.Member( "uri" ).AsString( ) ), "shared.bi", _
                        "a click on an include path opens that file" )
        AssertEqInt( where_.Member( "range" ).Member( "start" ).Member( "line" ).AsLongInt( ), 0, _
                     "at its first line" )
        AssertEqInt( where_.Member( "range" ).Member( "start" ).Member( "character" ).AsLongInt( ), 0, _
                     "and its first character -- there is no name to land on" )

        '' -- completion reads through the include --------------------------------
        ''
        '' Before the graph this list stopped at the file boundary, which the
        '' language does not have: shared.bi's type, constant and prototype
        '' were all in scope and none of them was offered.
        dim as JsonValue items = scope_.Root( ).Member( "result" ).Member( "items" )
        AssertTrue( items.Count( ) > 200, "the scope list still carries the language" )

        dim as boolean sawType = false, sawConst = false, sawLocal = false
        dim as string typeSort

        for i as long = 0 to items.Count( ) - 1
            dim as string label = items.Item( i ).Member( "label" ).AsString( )
            if( label = "Widget" ) then
                sawType  = true
                typeSort = items.Item( i ).Member( "sortText" ).AsString( )
            end if
            if( label = "WIDGET_LIMIT" ) then sawConst = true
            if( label = "w" ) then sawLocal = true
        next

        AssertTrue( sawType,  "the type declared in the included file is offered" )
        AssertTrue( sawConst, "and its constant" )
        AssertTrue( sawLocal, "without losing this file's own locals" )

        '' Group 4: after this file's own declarations, before the keywords.
        '' An included name is in scope, and it is still one step further away
        '' than something declared here.
        AssertEqStr( left( typeSort, 1 ), "4", "included names sort after local ones" )

        '' -- member completion through the include -------------------------------
        dim as JsonValue members = member_.Root( ).Member( "result" ).Member( "items" )
        AssertEqInt( member_.Root( ).Member( "id" ).AsLongInt( ), 27, "answers id 27" )

        dim as boolean sawField = false, sawKeyword = false
        for i as long = 0 to members.Count( ) - 1
            dim as string label = members.Item( i ).Member( "label" ).AsString( )
            if( label = "Label_" orelse label = "Size_" ) then sawField = true
            if( lcase( label ) = "sub" ) then sawKeyword = true
        next

        AssertTrue ( sawField, "`w.` offers the fields of a type declared in a header" )
        AssertFalse( sawKeyword, "and a member context still contains no keywords" )
    end scope

    '' -- 39..42. save and close --------------------------------------------------
    TestGroup( "save and close" )
    scope
        dim as JsonDoc saveTrace, saveDiag, closeTrace, closeDiag
        AssertTrue( saveTrace.Parse ( ordered[39] ), "message 39 is JSON" )
        AssertTrue( saveDiag.Parse  ( ordered[40] ), "message 40 is JSON" )
        AssertTrue( closeTrace.Parse( ordered[41] ), "message 41 is JSON" )
        AssertTrue( closeDiag.Parse ( ordered[42] ), "message 42 is JSON" )

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
        AssertTrue( doc.Parse( ordered[43] ), "message 43 is JSON" )
        AssertTrue( doc.Root( ).Member( "id" ).IsNull( ), "an unparseable request is answered with a null id" )
        AssertEqInt( doc.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_PARSE_ERROR, _
                     "broken JSON is a ParseError" )
    end scope

    '' -- 36..37. shutdown and after -----------------------------------------------
    TestGroup( "shutdown" )
    scope
        dim as JsonDoc doc, after_
        AssertTrue( doc.Parse   ( ordered[44] ), "message 44 is JSON" )
        AssertTrue( after_.Parse( ordered[45] ), "message 45 is JSON" )

        AssertEqInt( doc.Root( ).Member( "id" ).AsLongInt( ), 3, "answers id 3" )
        AssertTrue ( doc.Root( ).Member( "result" ).IsNull( ), "the shutdown result is null" )

        AssertEqInt( after_.Root( ).Member( "error" ).Member( "code" ).AsLongInt( ), RPC_INVALID_REQUEST, _
                     "a request after shutdown is InvalidRequest" )
    end scope

    return TestSummary( "piped session" )
end function

'' ############################################################################
''  The TOOLCHAIN-HEADER session -- --write-inc / --check-inc
''
''      session_tool --write-inc session-inc.bin <incws-root> <toolinc-dir>
''      tiko-lsp < session-inc.bin > captured-inc.bin
''      session_tool --check-inc captured-inc.bin
''
''  A second, smaller session against tests/fixtures/incws, with
''  `initializationOptions.includePaths` naming tests/fixtures/toolinc -- the
''  stand-in for a toolchain's inc. app.bas includes fakewin.bi (only in the
''  toolchain) and helper.bi (in the workspace), and calls one sub from each:
''
''      line 4:    MessageBoxW( 0, "hi", "app", 0 )
''      line 5:    Helper( 1, "x" )
''
''  Checked BY ID, not by position: the scan's log message lands wherever a
''  thread finishes, and nothing here depends on the order of anything else.
'' ############################################################################

'' One request, framed.
private function Req_( byval id as long, byref method_ as string, byref params as string ) as string
    return Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":" & id & "," & _
                  Q & "method" & Q & ":" & Q & method_ & Q & "," & Q & "params" & Q & ":" & params & "}" )
end function

'' One notification, framed.
private function Note_( byref method_ as string, byref params as string ) as string
    return Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & _
                  Q & "method" & Q & ":" & Q & method_ & Q & "," & Q & "params" & Q & ":" & params & "}" )
end function

'' `{"textDocument":{"uri":...},"position":{"line":l,"character":c}}`
private function At_( byref uri as string, byval l as long, byval c as long ) as string
    return "{" & Q & "textDocument" & Q & ":{" & Q & "uri" & Q & ":" & Q & uri & Q & "}," & _
           Q & "position" & Q & ":{" & Q & "line" & Q & ":" & l & "," & Q & "character" & Q & ":" & c & "}}"
end function

private function IncSessionBytes( byref wsRoot as string, byref incDir as string ) as string
    dim as string s
    dim as string wsUri  = PathToUri( wsRoot )
    dim as string appPath = wsRoot & "\app.bas"
    dim as string appUri = PathToUri( appPath )

    dim as string appText
    if( ReadWholeFile( appPath, appText ) = false ) then
        print "session_tool: cannot read " & appPath
        end 1
    end if

    '' 1. initialize, naming the toolchain's include directory.
    s &= Req_( 1, "initialize", "{" & Q & "processId" & Q & ":4242," & _
               Q & "rootUri" & Q & ":" & Q & wsUri & Q & "," & _
               Q & "capabilities" & Q & ":{}," & _
               Q & "initializationOptions" & Q & ":{" & Q & "includePaths" & Q & ":[" & JsonQuote( incDir ) & "]}," & _
               Q & "workspaceFolders" & Q & ":[{" & Q & "uri" & Q & ":" & Q & wsUri & Q & "," & _
               Q & "name" & Q & ":" & Q & "incws" & Q & "}]}" )
    s &= Note_( "initialized", "{}" )

    '' 2. workspace/symbol WAITS for the scan (EnsureWorkspaceIndex), so every
    ''    request after it sees the headers the full build read in.
    s &= Req_( 2, "workspace/symbol", "{" & Q & "query" & Q & ":" & Q & "helper" & Q & "}" )

    s &= Note_( "textDocument/didOpen", "{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & appUri & Q & "," & _
                Q & "languageId" & Q & ":" & Q & "tiko" & Q & "," & Q & "version" & Q & ":1," & _
                Q & "text" & Q & ":" & JsonQuote( appText ) & "}}" )

    '' 3. signature help after `MessageBoxW( 0, ` -- a toolchain header's -- and
    '' 4. after `Helper( ` -- another workspace file's.
    s &= Req_( 3, "textDocument/signatureHelp", At_( appUri, 4, 20 ) )
    s &= Req_( 4, "textDocument/signatureHelp", At_( appUri, 5, 12 ) )

    '' 5, 6. hover on each name.
    s &= Req_( 5, "textDocument/hover", At_( appUri, 4, 6 ) )
    s &= Req_( 6, "textDocument/hover", At_( appUri, 5, 6 ) )

    '' 7. completion after typing `Messa` on a new line inside Main.
    dim as string typed = appText
    dim as long endAt = instr( typed, "end sub" )
    typed = left( typed, endAt - 1 ) & "    Messa" & LF & mid( typed, endAt )
    s &= Note_( "textDocument/didChange", "{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & appUri & Q & "," & Q & "version" & Q & ":2}," & _
                Q & "contentChanges" & Q & ":[{" & Q & "text" & Q & ":" & JsonQuote( typed ) & "}]}" )
    s &= Req_( 7, "textDocument/completion", At_( appUri, 6, 9 ) )

    '' 8. rename MessageBoxW -- refused: the edit would land in the toolchain.
    s &= Req_( 8, "textDocument/rename", "{" & Q & "textDocument" & Q & ":{" & Q & "uri" & Q & ":" & _
               Q & appUri & Q & "}," & Q & "position" & Q & ":{" & Q & "line" & Q & ":4," & _
               Q & "character" & Q & ":6}," & Q & "newName" & Q & ":" & Q & "Foo" & Q & "}" )

    '' 9. workspace/symbol does not offer a toolchain header's names.
    s &= Req_( 9, "workspace/symbol", "{" & Q & "query" & Q & ":" & Q & "onlyinthetoolchain" & Q & "}" )

    '' 11. member completion through a workspace ALIAS of a toolchain GENERIC:
    ''     `dim as IntBox b` / `b.`, where helper.bi says
    ''     `type IntBox as FB.Box( of long )` and Box is in win/fakeuser.bi.
    dim as string typed2 = appText
    dim as long endAt2 = instr( typed2, "end sub" )
    typed2 = left( typed2, endAt2 - 1 ) & "    dim as IntBox b" & LF & "    b." & LF & mid( typed2, endAt2 )
    s &= Note_( "textDocument/didChange", "{" & Q & "textDocument" & Q & ":{" & _
                Q & "uri" & Q & ":" & Q & appUri & Q & "," & Q & "version" & Q & ":3}," & _
                Q & "contentChanges" & Q & ":[{" & Q & "text" & Q & ":" & JsonQuote( typed2 ) & "}]}" )
    s &= Req_( 11, "textDocument/completion", At_( appUri, 7, 6 ) )

    s &= Frame( "{" & Q & "jsonrpc" & Q & ":" & Q & "2.0" & Q & "," & Q & "id" & Q & ":10," & _
                Q & "method" & Q & ":" & Q & "shutdown" & Q & "}" )
    s &= Note_( "exit", "null" )
    return s
end function

private function WriteIncSession( byref path as string, byref wsRoot as string, _
                                  byref incDir as string ) as long
    dim as long f = freefile( )
    if( open( path for binary access write as #f ) <> 0 ) then
        print "session_tool: cannot write " & path
        return 1
    end if
    dim as string bytes_ = IncSessionBytes( wsRoot, incDir )
    put #f, , bytes_
    close #f
    print "wrote " & len(bytes_) & " bytes to " & path
    return 0
end function

'' The answer to request `id`, or "" when the server sent none.
private function ResponseFor_( byref messages as FB.Array( of string ), byval id as long ) as string
    for i as long = 0 to messages.Count( ) - 1
        dim as JsonDoc d
        if( d.Parse( messages[i] ) = false ) then continue for
        dim as JsonValue r = d.Root( )
        if( r.Has( "method" ) ) then continue for
        if( r.Member( "id" ).IsNumber( ) = false ) then continue for
        if( r.Member( "id" ).AsLongInt( ) = id ) then return messages[i]
    next
    return ""
end function

private function CheckIncSession( byref path as string ) as long
    dim as string captured
    if( ReadWholeFile( path, captured ) = false ) then
        print "session_tool: cannot read " & path
        return 1
    end if

    TestGroup( "toolchain headers, over the wire" )

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
    AssertEqInt( f.Pending( ), 0, "the output ends on a message boundary" )

    for id as long = 1 to 11
        if( len( ResponseFor_( messages, id ) ) = 0 ) then TestFail( "request " & id & " is answered", "no response" )
    next

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 2 ) )
        AssertEqInt( d.Root( ).Member( "result" ).Count( ), 1, "workspace/symbol 'helper': the workspace's one" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 3 ) )
        dim as JsonValue r = d.Root( ).Member( "result" )
        AssertTrue ( r.IsObject( ), "signature help for a toolchain header's MessageBoxW" )
        AssertContains( r.Member( "signatures" ).Item( 0 ).Member( "label" ).AsString( ), _
                        "byval lpText as const wstring ptr", "with the header's parameter list" )
        AssertEqInt( r.Member( "activeParameter" ).AsLongInt( -1 ), 1, "and the second parameter active" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 4 ) )
        dim as JsonValue r = d.Root( ).Member( "result" )
        AssertTrue ( r.IsObject( ), "signature help for Helper, declared in ANOTHER workspace file" )
        AssertContains( r.Member( "signatures" ).Item( 0 ).Member( "label" ).AsString( ), _
                        "byref label as string", "with helper.bi's parameter list" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 5 ) )
        AssertContains( d.Root( ).Member( "result" ).Member( "contents" ).Member( "value" ).AsString( ), _
                        "Shows a message box.", "hover on MessageBoxW: the header's declare and doc comment" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 6 ) )
        AssertContains( d.Root( ).Member( "result" ).Member( "contents" ).Member( "value" ).AsString( ), _
                        "byval count as long", "hover on Helper: another workspace file's declare" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 7 ) )
        dim as boolean found = false
        for each it in ArrayOf( d.Root( ).Member( "result" ).Member( "items" ) )
            if( it.Member( "label" ).AsString( ) = "MessageBoxW" ) then found = true
        next
        AssertTrue( found, "completion after 'Messa' offers MessageBoxW" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 8 ) )
        AssertTrue    ( d.Root( ).Has( "error" ), "rename of MessageBoxW is refused" )
        AssertContains( d.Root( ).Member( "error" ).Member( "message" ).AsString( ), _
                        "toolchain header", "because the toolchain declares it" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 9 ) )
        AssertEqInt( d.Root( ).Member( "result" ).Count( ), 0, "workspace/symbol skips toolchain headers" )
    end scope

    scope
        dim as JsonDoc d
        d.Parse( ResponseFor_( messages, 11 ) )
        dim as string labels = ""
        for each it in ArrayOf( d.Root( ).Member( "result" ).Member( "items" ) )
            labels &= " " & it.Member( "label" ).AsString( )
        next
        AssertContains( labels, " Get", "b. where b is an alias of FB.Box( of long ): Box's Get" )
        AssertContains( labels, " IsEmpty", "and IsEmpty" )
    end scope

    return TestSummary( "toolchain-header session" )
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

    case "--write-inc"
        if( len(root_) = 0 orelse len( command( 4 ) ) = 0 ) then
            print "session_tool --write-inc needs the workspace root and the include directory"
            end 2
        end if
        end WriteIncSession( path_, root_, command( 4 ) )

    case "--check-inc"
        end CheckIncSession( path_ )

    case else
        print "usage: session_tool --write <file> <workspace-root> | --check <file>"
        end 2
end select
