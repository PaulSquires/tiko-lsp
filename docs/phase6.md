# Phase 6 — the workspace

The phase where the server stops being one file at a time.

## Delivered

| Requirement | Where |
| --- | --- |
| workspace folders | `initialize`, plus `workspace/didChangeWorkspaceFolders` |
| source discovery | `src/workspace/workspace.bas` — `ScanFolder` |
| workspace symbol index | `src/workspace/symbol_index.bas` |
| `workspace/symbol` | `src/handlers/workspace_symbols.bas` |
| cross-file definition | `src/handlers/definition.bas` — falls back to the index |
| `textDocument/references` | `src/handlers/references.bas` |
| capabilities | `workspaceSymbolProvider`, `referencesProvider`, `workspace.workspaceFolders` |

## Discovery

`WalkDir` from `fb/filesystem.bi` does the walking: reentrant, and it does not
follow directory symlinks, so the traversal is a tree by construction — no
visited set, no cycles. FreeBASIC's own `DIR`/`DIRNEXT` -- the server is
written in it -- is a per-thread global
and cannot be nested at all, which is why this could not be hand-rolled.

- `.bas`, `.bi`, `.inc`, case-insensitively. Nothing else is tiko source.
- `.git`, `.svn`, `.hg`, `.vs`, `.vscode`, `.idea`, `node_modules` and
  `__pycache__` are skipped anywhere in the path. **`bin` and `obj` are not** —
  the extension filter already excludes build output, and a project that keeps
  sources in `bin\` should still find them.
- Caps: 4000 files, 4 MB per file. A scan of the wrong folder is then slow
  rather than fatal, and the log says the limit was hit rather than pretending
  the workspace is small.

## One file, one entry

The index is keyed on the **resolved absolute path**, lower-cased — not on the
URI. The scan builds one spelling and the client sends another, and
`file:///c%3A/p/build/../x.bas` names the same file as `file:///c%3A/p/x.bas`.

This is not hypothetical: the piped session caught it. The fixture file was
indexed once by the scan and once by `didOpen` under a different spelling, and
`Widget` came back with **six** references instead of four. Keying on the
resolved path fixed it, and a test now indexes one file under two spellings and
requires one entry.

The URI is still stored, and the last indexer's spelling wins — which is the
client's whenever the file is open, so answers come back in the words the client
used.

## The open buffer wins

The same rule as everywhere else in this server. A file the editor has open is
indexed from the **buffer**, on `didOpen` and on every `didChange`, so a symbol
that has been typed but not saved is already findable from another file. On
`didClose` the index goes back to the file on disk, or drops the entry if there
is no file there.

`FindDefinition` ranks accordingly: a body beats a `declare`, and a
buffer-indexed file beats one read from disk.

## References are re-lexed, not stored

A workspace's identifiers are tens of megabytes to hold and to keep current. A
"find all references" is a deliberate action a user waits a moment for — unlike
completion, which runs on every keystroke — so it is answered by scanning:

1. a whole-text case-insensitive substring test, which most files fail, and
   which skips the lexer for them entirely;
2. then the real lexer, because a substring is not an identifier: `count` occurs
   inside `counter`, inside `"a count of"` and inside `' count them`, and none
   of those is a reference. The test asserts exactly that.

Matching is **by name**, not by symbol identity. Every `Count` in the workspace
matches, whichever type it belongs to. That is what a name-based index can
honestly do; telling two members called `Count` apart needs the type system.

## When the index is built

On the `initialized` notification, not during `initialize`. The client is
blocked waiting for the `initialize` response, and a scan of a large tree there
shows up as a slow start; by the time `initialized` arrives the editor is
running and merely gets its cross-file answers a moment later.

A folder added or removed rebuilds the index rather than patching it. A folder
change is rare, and keeping an incremental version correct across overlapping
folders is not worth the bugs.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean. **754 assertions**, all passing:

| Suite | Assertions |
| --- | --- |
| framing | 41 |
| json + jsonrpc | 110 |
| position | 64 |
| uri + document | 88 |
| analysis | 157 |
| symbols | 74 |
| completion | 63 |
| **workspace** | **64** |
| piped session (real process) | 93 |

The workspace suite covers discovery rules, scanning the fixture, indexing and
re-indexing, the one-file-one-entry rule, buffer-beats-disk, `FindDefinition`'s
ranking, query scoring and its cap, and identifier scanning including the
strings and comments it must not match.

The piped session now runs against a **real two-file workspace**
(`tests/fixtures/workspace`) and asserts the whole cross-file path end to end:

- the server reports `indexed 2 file(s)` after `initialized`;
- `Widget`, used in `widgets.bas` and declared in `shared.bi` — a file that
  `widgets.bas` only `#include`s, and this server does not follow includes —
  resolves to **shared.bi line 1, character 5**;
- references for it return **4 locations spanning both files**;
- `workspace/symbol "widget"` returns the exact match first, as a Struct, with
  `containerName: "shared.bi"` and a location a client can open.

### Performance

Measured on win64/gas64: scan, then index, then twenty queries.

| Workspace | Files | Symbols | Scan | Index | Query |
| --- | --- | --- | --- | --- | --- |
| tiko-lsp | 65 | 2,725 | 5 ms | 33 ms | 0.7 ms |
| fbc's compiler | 199 | 24,685 | 4 ms | 564 ms | 6 ms |
| AfxNova | 179 | 86,743 | 2 ms | 927 ms | 27 ms |
| C:\dev\tiko | 4,000 (capped) | 209,868 | 1.0 s | 4.3 s | 84 ms |

### Not verified

- **Linux and macOS**, still.
- **A real editor**, still.
- **The startup stall.** The index build blocks the message loop, so on a large
  workspace the editor's first few seconds of typing are queued behind it —
  4.3 s in the worst case measured. Moving analysis onto a worker is the obvious
  next structural change, and the dispatcher's only shared state is the `Server`
  object, but it is not done.
- **Live file watching.** A file changed on disk by another program — a branch
  switch, a build step — is not noticed. `workspace/didChangeWatchedFiles` is
  not handled. *Handled since [phase9.md](phase9.md).*
- **Include graphs.** Nothing follows `#include`; a name resolves because it is
  somewhere in the workspace, not because this file can actually see it.
- **Symbol identity.** References and cross-file definitions match by name, so
  two unrelated members with one name are one answer.
- **Memory.** The index holds a symbol table and one range per symbol for every
  file — about 210,000 symbols for the largest workspace measured — and no leak
  checker has been run.

## Next: phase 7

Rename — which is references plus a `WorkspaceEdit`, and which needs
`prepareRename` to refuse the places a rename would be wrong. Then signature
help, semantic tokens, inlay hints, code actions and formatting. All of it
landed: see [phase7.md](phase7.md).
