# tiko-lsp for Zed

A Zed extension that gives `.tiko`, `.tko` and `.ti` files (and the legacy `.bas`, `.bi` and `.inc`)
a language — **Tiko** — and starts `tiko-lsp` for them.

The extension itself does almost nothing, and that is the point: Zed speaks LSP,
tiko-lsp speaks LSP, and all that was missing between them was a language name
and the path to a binary. Everything a user sees comes from the server.

## Install

1. **Install tiko** ([tiko-lang.net](https://tiko-lang.net/#install)). The server comes
   with it: `tiko-lang\tiko-lsp.exe` on Windows, `tiko-lang/bin/tiko-lsp` on Linux and
   macOS.
2. In Zed: `zed: install dev extension` from the command palette
   (`ctrl-shift-p`), and choose this folder — `editors/zed`.

Zed compiles the extension to WebAssembly itself; it needs `rustup` and the
`wasm32-wasip1` target, which it will offer to install.

## Where it looks for the server

In order:

1. `lsp.tiko-lsp.binary.path` in your Zed settings;
2. the server in the toolchain folder named by
   `lsp.tiko-lsp.initialization_options.toolchainPath` (see below);
3. `tiko-lsp` on your `PATH` — which it is, beside `tiko`, if you put the
   toolchain on your `PATH`;
4. `bin/tiko-lsp.exe` inside the folder you have open — so building the server
   and editing it in the same window just works.

An extension runs in a sandbox that cannot look outside the folder you have open,
so a `toolchainPath` is used as written: if it is wrong, the server fails to start
and Zed shows that error.

The simplest setting names the toolchain once; the server then takes its headers,
packages and compiler from the same folder:

```json
{
  "lsp": {
    "tiko-lsp": {
      "initialization_options": { "toolchainPath": "C:/tiko-lang" }
    }
  }
}
```

If none of those finds it, Zed shows the error the extension raises, which says
what to set. A language server that silently isn't there is the worst outcome,
so the extension never returns a command it could not find.

To point it somewhere explicitly, in `settings.json`:

```json
{
  "lsp": {
    "tiko-lsp": {
      "binary": {
        "path": "C:/dev/tiko-lsp/bin/tiko-lsp.exe",
        "arguments": ["--stdio"]
      }
    }
  }
}
```

Add `"--log-level", "debug", "--log-file", "C:/temp/tiko-lsp.log"` to
`arguments` when you want to see what the server is doing. It never writes to
stdout — that channel belongs to the protocol.

## Toolchain headers (Win32, AfxNova)

For `windows.bi`, AfxNova and the runtime headers to complete, hover and show
signatures, tell the server where the toolchain's `inc` is. Zed passes
`initialization_options` straight through to the server:

```json
{
  "lsp": {
    "tiko-lsp": {
      "initialization_options": {
        "includePaths": ["C:/dev/tiko-editor-tiko/toolchains/tiko-windows/inc"]
      }
    }
  }
}
```

The toolchain's `pkg` -- what `#import "std/strings"` names -- is found beside
that `inc` on its own; `"packagePaths": [...]` names it explicitly if it lives
elsewhere.

Verified in Zed 1.23.2: the `initialize` request carries it and the server
reports `toolchain headers from ...`. The headers are read on the server's
worker thread, so the server starts as fast as before; Win32 names appear a
couple of seconds later.

`"compilerPath": "C:/dev/tiko-editor-tiko/toolchains/tiko-windows/tiko.exe"` lets the
server ask the compiler (`tiko metadata`) where each workspace folder's package
resolves its imports -- `-i` options included -- and answer `tiko/metadata`; see the
top-level README. Never run for diagnostics.

## What works

Verified by running Zed **1.16.1** against this extension with a real
`tiko-lsp.exe`: the extension loads, `widgets.bas` is recognised as Tiko, the
server starts, `initialize` names the client as Zed, `didOpen` arrives, the file
is analysed, the workspace scan starts in the background, and Zed's
`textDocument/codeAction` requests are answered.

The server's own list of what it implements is in
[the README](../../README.md): diagnostics, document symbols, hover, go to
definition, completion, workspace symbols, references, rename, signature help,
semantic tokens, inlay hints, formatting and quick fixes.

## What is not verified

- **Syntax highlighting.** This language has **no tree-sitter grammar** yet — a
  `tiko-tree-sitter` is in progress under [../../grammar](../../grammar) — so
  Zed has nothing to colour with unless it renders the server's semantic tokens,
  which was not observed in the run above. The language and the server work
  without one; the file may simply look plain.
- **Every feature through the UI.** The run above confirms the wiring and the
  requests Zed made in the first seconds. Hover, completion and rename were
  exercised against the server over a pipe by
  [the test suite](../../tests/session_tool.tiko), not through Zed's interface.
- **macOS and Linux.** The extension has no platform-specific code, and the
  server has never been built for either.

## The grammar

Syntax highlighting, folding, the outline and indentation come from
**tiko-tree-sitter**, which lives at `../../grammar` and is declared here as:

```toml
[grammars.tiko]
repository = "file:///C:/dev/tiko-tree-sitter"
rev = "..."
```

A Zed extension names a grammar by REPOSITORY AND REVISION -- never by a path --
and the repository root is where Zed looks for `src/parser.c`. `../../grammar`
is not a repository root, so it is mirrored to one; a `file://` URL keeps that
local until the grammar is published. Zed clones that revision and compiles it
to wasm itself.

After changing the grammar, run:

```bash
bash editors/zed/sync-grammar.sh
```

which regenerates the parser, mirrors it, commits, and rewrites `rev` above.
Then run **`zed: reload extensions`** in Zed (or restart it) -- a dev extension
is a symlink to this directory, so nothing else has to be reinstalled.

The queries Zed uses are `languages/tiko/*.scm` in THIS directory, not the ones
in the grammar: the capture names are mapped onto the set Zed's themes colour,
and a capture a theme does not know is simply not painted.
