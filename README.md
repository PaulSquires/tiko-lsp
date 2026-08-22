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

## Status: phases 1-3 complete

| Phase | Contents | State |
| --- | --- | --- |
| 1 | transport, JSON-RPC, dispatcher, `initialize` / `initialized` / `shutdown` / `exit`, logging | **done** |
| 2 | documents, `didOpen` / `didChange` / `didSave` / `didClose`, line index, UTF-16 positions | **done** |
| 3 | lexer, parser with error recovery, diagnostics | **done** |
| 4 | symbols, document symbols, hover, go to definition | |
| 5 | completion | |
| 6 | workspace index, workspace symbols, references | |
| 7 | rename, signature help, semantic tokens, inlay hints, code actions, formatting | |

The `initialize` response advertises exactly what works: `textDocumentSync`
(incremental) and `positionEncoding`, and nothing else. Promising `hoverProvider`
before phase 4 would make every hover time out, so each capability is added in the
phase that implements it — see `LspBuildCapabilities` in
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
                parser.bi/.bas        block structure, with error recovery
                diagnostics.bi/.bas   the problem model, in byte offsets
    handlers/   lifecycle.bi/.bas     initialize / initialized / shutdown / exit
                text_document.bi/.bas didOpen / didChange / didSave / didClose
    utils/      logging.bi/.bas       stderr and optional log file, never stdout
                position.bi/.bas      line index, UTF-16 <-> byte offsets
                uri.bi/.bas           file: URI <-> filesystem path
  tests/        assert.bi, test_framing.bas, test_json.bas, test_position.bas,
                test_document.bas, test_analysis.bas, session_tool.bas
  build/        _compile.bat/.sh, _run_tests.bat/.sh, _build_yyjson_linux.sh
  docs/         architecture.md, phase1.md, phase2.md, phase3.md
```

`src/workspace/` arrives with the phase that fills it; empty placeholder files
would only be noise.

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

(or `sh build/_run_tests.sh`). Six suites:

- **framing** — 41 assertions over `MessageFramer`: torn messages fed one byte at a
  time, several messages per read, CRLF and bare LF, unknown headers, UTF-8 byte
  counts, a payload containing a blank line, every malformed-header case, and 5000
  messages through one framer to prove the buffer is compacted.
- **json + jsonrpc** — 110 assertions over the JSON facade and the message model,
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
- **piped session** — 72 assertions against a **real `tiko-lsp` process** driven
  over a pipe: `session_tool --write` emits a byte-exact scripted session, the
  server runs it, and `session_tool --check` reframes and validates the reply
  stream — including that two edits in one `didChange` applied in order against
  the evolving text, that a syntax error becomes a `publishDiagnostics` with the
  right range and code, that fixing it publishes an **empty** list, that the
  notifications which must be swallowed produced no output, and that the process
  exited 0.

## Licence

MIT, (c) 2026 Paul Squires -- see [LICENSE](LICENSE).

The server links [yyjson](https://github.com/ibireme/yyjson), which is MIT,
(c) YaoYuan (ibireme). It is not vendored here; a build needs the FreeBASIC
bindings at `C:\dev\yyjson`, and a distributed binary ships `yyjson64.dll`
beside it, so carry yyjson's licence with any release.
