# tiko-lsp

A Language Server Protocol server for **fbc-modern**, written in fbc-modern.

It speaks LSP 3.17 over stdin/stdout and is a plain standalone executable, so any
LSP-capable editor — Zed, VS Code, Neovim, Helix, Sublime Text — can launch it.

The server is designed to end up sharing the compiler's own lexer, parser, AST,
symbol table and semantic analyser rather than shelling out to `fbc.exe`. Nothing
here launches a compiler process, and nothing ever will.

```
        LSP client (Zed / VS Code / Neovim / Helix / ...)
                          |
                          |  JSON-RPC 2.0 over stdin/stdout
                          v
        +-----------------------------------------+
        |  tiko-lsp                               |
        |    transport   Content-Length framing   |
        |    jsonrpc     message model            |
        |    dispatcher  lifecycle state machine  |
        |    handlers    one per LSP method       |
        +-----------------------------------------+
                          |
                          v          (phases 3-7)
        +-----------------------------------------+
        |  compiler frontend API                  |
        |    lexer / parser / AST / symbols /     |
        |    type system / semantic analyser      |
        +-----------------------------------------+
```

## Status: phases 1-10 complete

| Phase | Contents | State |
| --- | --- | --- |
| 1 | transport, JSON-RPC, dispatcher, `initialize` / `initialized` / `shutdown` / `exit`, logging | **done** |
| 2 | documents, `didOpen` / `didChange` / `didSave` / `didClose`, line index, UTF-16 positions | **done** |
| 3 | lexer, parser with error recovery, diagnostics | **done** |
| 4 | symbols, document symbols, hover, go to definition | **done** |
| 5 | completion | **done** |
| 6 | workspace index, workspace symbols, references | **done** |
| 7 | rename, signature help, semantic tokens, inlay hints, code actions, formatting | **done** |
| 8 | the workspace scan off the message loop | **done** |
| 9 | watched files: an index that notices `git checkout`, bursts included | **done** |
| 10 | the include graph: what a file can actually see | **done** |

The `initialize` response advertises exactly what works: `textDocumentSync`
(incremental), `positionEncoding`, `documentSymbolProvider`, `hoverProvider`,
`definitionProvider`, `completionProvider`, `workspaceSymbolProvider`,
`referencesProvider`, multi-root `workspace.workspaceFolders`,
`renameProvider` **with** `prepareProvider`, `signatureHelpProvider`,
`semanticTokensProvider` (`full` only — no delta, because returning a full set
while claiming deltas is what makes a client show stale colours),
`inlayHintProvider`, `documentFormattingProvider`,
`documentRangeFormattingProvider` and `codeActionProvider` (`quickfix` only).
Nothing else — `typeDefinitionProvider` would need the type system this server
does not have, so it is not claimed. See `LspBuildCapabilities` in
[src/lsp/protocol.bas](src/lsp/protocol.bas). Diagnostics need no capability: they
are pushed, and the server publishes them on open, change and save.

The parser was developed against **435,000 lines of real FreeBASIC** — fbc's own
compiler, the fbc-modern standard library, AfxNova and the fbc test suite — and
produces zero diagnostics on all of it except the files fbc itself expects to
reject. False positives are the failure mode that matters for a language server;
see [docs/phase3.md](docs/phase3.md) for the fourteen that were found and fixed.

Positions are UTF-16 code units, handled in one place
([src/utils/position.bas](src/utils/position.bas)): `中` is one column and three
bytes, `😀` is two columns and four bytes.

## Layout

```
tiko-lsp/
  src/
    main.bas                  argument parsing and the message loop
    json/       json.bi/.bas          JsonDoc / JsonValue / JsonBuilder over yyjson
    rpc/        transport.bi/.bas     MessageFramer + StdioTransport
                jsonrpc.bi/.bas       RpcMessage / RpcId / RpcError + serialisers
    lsp/        protocol.bi/.bas      method names, capabilities, LSP constants
                dispatcher.bi/.bas    Server, lifecycle rules, handler registry
                publish.bi/.bas       diagnostics -> publishDiagnostics
    document/   document.bi/.bas      TextDocument: text, line index, edits
                document_manager.bi/.bas   every open buffer, keyed by URI
    analysis/   lexer.bi/.bas         FreeBASIC tokens, 247 reserved words
                parser.bi/.bas        block structure and symbols, with recovery
                symbols.bi/.bas       the symbol table, scope resolution, hover text
                completion.bi/.bas    what could be typed here
                includes.bi/.bas      the #include directives in a file
                diagnostics.bi/.bas   the problem model, in byte offsets
                signature.bi/.bas     calls, and the parameters being filled in
                semantic.bi/.bas      semantic tokens and their encoding
                format.bi/.bas        re-indentation, and what it refuses
    workspace/  workspace.bi/.bas     finding the source files
                symbol_index.bi/.bas  every symbol in the workspace
                index_builder.bi/.bas the scan, on a worker thread
    handlers/   lifecycle.bi/.bas     initialize / initialized / shutdown / exit
                text_document.bi/.bas didOpen / didChange / didSave / didClose
                document_symbols.bi/.bas   the outline
                hover.bi/.bas         hover, and the shared resolution step
                definition.bi/.bas    go to definition
                completion.bi/.bas    completion
                workspace_symbols.bi/.bas  workspace/symbol, and the index build
                references.bi/.bas    find all references
                watched_files.bi/.bas files changed outside the editor
                rename.bi/.bas        prepareRename and rename
                signature_help.bi/.bas     the signature popup
                semantic_tokens.bi/.bas    semanticTokens/full
                inlay_hints.bi/.bas   parameter names at call sites
                formatting.bi/.bas    formatting and rangeFormatting
                code_action.bi/.bas   the three quick fixes
    utils/      logging.bi/.bas       stderr and optional log file, never stdout
                position.bi/.bas      line index, UTF-16 <-> byte offsets
                uri.bi/.bas           file: URI <-> filesystem path
  tests/        assert.bi, test_framing.bas, test_json.bas, test_position.bas,
                test_document.bas, test_analysis.bas, test_symbols.bas,
                test_completion.bas, test_workspace.bas, session_tool.bas,
                fixtures/workspace/   a two-file workspace the cross-file
                                      assertions are made against
  build/        _compile.bat/.sh, _run_tests.bat/.sh, _build_yyjson_linux.sh
  docs/         architecture.md, phase1.md .. phase10.md
```

Every directory in the sketch now has something real in it.

## Building

### Windows

Needs the fbc-modern toolchain and a built `yyjson64.dll`:

```bash
build\_compile.bat
```

Override the defaults with `TIKO_LSP_FBC` and `TIKO_LSP_YYJSON` if your checkouts
live elsewhere. The build copies `yyjson64.dll` next to the executable, which is
where the server loads it from.

### Linux

yyjson ships a Windows DLL only, so build its static library once:

```bash
sh build/_build_yyjson_linux.sh
```

then:

```bash
sh build/_compile.sh
```

There is no Windows-only code outside a single `#ifdef __FB_WIN32__` in
[src/rpc/transport.bas](src/rpc/transport.bas), where stdin and stdout are put into
binary mode. macOS needs the same yyjson step and nothing else.

## Running

The server is normally started by the editor, not by hand:

```bash
tiko-lsp --stdio
```

| Option | Meaning |
| --- | --- |
| `--stdio` | accepted and ignored; stdio is the only transport |
| `--log-level <level>` | `off`, `error` (default), `warn`, `info`, `debug`, `trace` |
| `--log-file <path>` | append diagnostics to a file as well as stderr |
| `--version`, `--help` | printed to **stderr**, then exit |

`TIKO_LSP_LOG_LEVEL` and `TIKO_LSP_LOG_FILE` do the same and are overridden by the
flags. At `trace` every message is logged in both directions.

**Diagnostics never go to stdout.** stdout carries the protocol, and one stray byte
desynchronises the framing.

### Editor configuration

Zed (`~/.config/zed/settings.json` — via a language-server extension entry):

```json
{
  "lsp": {
    "tiko-lsp": {
      "binary": { "path": "C:/dev/tiko-lsp/bin/tiko-lsp.exe", "arguments": ["--stdio"] }
    }
  }
}
```

Neovim:

```lua
vim.lsp.config.tiko_lsp = {
  cmd = { 'C:/dev/tiko-lsp/bin/tiko-lsp.exe', '--stdio' },
  filetypes = { 'freebasic' },
  root_markers = { '.git' },
}
vim.lsp.enable('tiko_lsp')
```

Helix (`languages.toml`):

```toml
[language-server.tiko-lsp]
command = "C:/dev/tiko-lsp/bin/tiko-lsp.exe"
args = ["--stdio"]
```

Nothing in the server depends on its own path, so any location works.

## Tests

```bash
build\_run_tests.bat
```

(or `sh build/_run_tests.sh`). Twelve suites, 1,035 assertions:

- **framing** — 43 assertions over `MessageFramer`: torn messages fed one byte at a
  time, several messages per read, CRLF and bare LF, unknown headers, UTF-8 byte
  counts, a payload containing a blank line, every malformed-header case, and 5000
  messages through one framer to prove the buffer is compacted.
- **json + jsonrpc** — 121 assertions over the JSON facade and the message model,
  including deep-copy ownership and every rejection path. Serialiser output is
  checked by parsing it back, never by string comparison.
- **position** — 64 assertions over the line index and UTF-16 conversion: every
  terminator form, CJK and astral characters, mid-surrogate rounding, clamping in
  both directions, malformed UTF-8, and an offset round trip over every character
  boundary in a mixed-script document.
- **uri + document** — 88 assertions over URI/path conversion, incremental edits
  (including thirteen single-character insertions, edits that join and split
  lines, and edits placed by UTF-16 column over multi-byte text), reversed and
  out-of-range ranges, and the document manager.
- **analysis** — 157 assertions over the lexer and the parser: comments that
  nest, all three string spellings, malformed numbers, every block form, the
  recovery rule (one missing `end if` is one diagnostic, pointing at the `if`),
  half-typed text, and every false positive found in the corpora. The suite also
  analyses **this project's own source** and requires zero diagnostics from it.
- **symbols** — 74 assertions over symbol extraction, the two ranges every
  symbol carries, scope resolution (a parameter shadows a global of the same
  name), member resolution, the token-under-the-cursor rules, hover markdown,
  and half-typed code — an unclosed `type` must still produce an outline.
- **completion** — 63 assertions over context detection (including inside a
  string and inside a comment, where the answer is nothing), member completion
  through a declared type, a pointer, `this.`, an enum and a namespace, the
  scope list with its group ordering, and case-insensitive de-duplication.
- **workspace** — 107 assertions over discovery rules, the include graph
  (a chain, a cycle, an edge to nowhere, a wrong-case forward-slash path, and
  two files declaring one name where only one is visible), indexing and
  re-indexing, the one-file-one-entry rule (a path through `build/..` is the
  same file), buffer-beats-disk, query scoring, and identifier scanning —
  including the strings and comments a reference search must NOT match.
- **signature** — 53 assertions over splitting a recorded signature (a comma
  inside a default value does not split it; a function-pointer parameter counts
  as one), finding which call the caret is in (the INNER one, when they nest),
  and the argument sites inlay hints are built from.
- **semantic tokens** — 32 assertions, mostly about the encoding, because that
  is what fails silently: a four-line block comment must be four tokens, the
  deltas must rebuild the absolute positions, and lengths are UTF-16 units.
- **formatting** — 33 assertions written as "this text formats to that text",
  including everything it must leave alone: an already-tidy file (zero edits),
  broken structure (zero edits, and a reason), comment art inside a block
  comment, a `#macro` body, a `#if` body, and a wrapped line's alignment.
- **piped session** — 200 assertions against a **real `tiko-lsp` process** driven
  over a pipe: `session_tool --write` emits a byte-exact scripted session, the
  server runs it, and `session_tool --check` reframes and validates the reply
  stream — including that two edits in one `didChange` applied in order against
  the evolving text, that a syntax error becomes a `publishDiagnostics` with the
  right range and code, that fixing it publishes an **empty** list, that an
  outline, a hover, a go-to-definition and a completion list come back with the
  right kinds — the definition landing on the declaration's name, the completion
  sorting a declaration above a keyword — that the notifications which must be
  swallowed produced no output, and that the process exited 0. It also runs
  against a **real two-file workspace**: a type used in one file and declared in
  another resolves across files, references span both, and the workspace picker
  returns the exact match first. The phase-7 half drives the whole editing path:
  a signature with the right active parameter before and after the comma, two
  inlay hints, a semantic-token array, a quick fix that inserts one quote, a
  local rename producing three edits in one file, and the refusal for a name a
  local elsewhere shares. It also drives the one request the server SENDS --
  `client/registerCapability`, asking the client to watch the workspace — and
  the file events that come back: a deleted file leaves the workspace picker,
  a created one returns to it, and a change reported for a file the editor has
  open is ignored, because the buffer is the truth. A **burst** of 121 changes
  goes to the worker instead of the message loop, and the files it could not
  read keep the symbols the index already had. And the **include graph**: a
  click on an `#include` path opens that file, the completion list carries what
  the included header declares, and `w.` offers the fields of a type declared in
  another file.

## Licence

MIT, (c) 2026 Paul Squires -- see [LICENSE](LICENSE).

The server links [yyjson](https://github.com/ibireme/yyjson), which is MIT,
(c) YaoYuan (ibireme). It is not vendored here; a build needs the FreeBASIC
bindings at `C:\dev\yyjson`, and a distributed binary ships `yyjson64.dll`
beside it, so carry yyjson's licence with any release.
