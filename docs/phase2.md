# Phase 2 — documents and positions

The editor's buffers, and the coordinate system every later phase will use.

## Delivered

| Requirement | Where |
| --- | --- |
| in-memory document model | `src/document/document.bas` — `TextDocument` |
| document store | `src/document/document_manager.bas` — `DocumentManager` |
| `didOpen` / `didChange` / `didSave` / `didClose` | `src/handlers/text_document.bas` |
| incremental text synchronisation | `TextDocument.ApplyRange` |
| line index | `src/utils/position.bas` — `LineIndex` |
| LSP position ↔ byte offset, UTF-16 aware | `src/utils/position.bas` |
| URI ↔ path | `src/utils/uri.bas` |
| capability advertised | `textDocumentSync { openClose, change: 2, save }`, `positionEncoding` |

`$/logTrace` was added at the same time (`Server.SendTrace`): document
notifications have no responses, so without it there is nothing on the wire to
test against.

## The buffer is the truth

From `didOpen` to `didClose`, `TextDocument.Text()` is authoritative and nothing
in the server reads the file from disk. This is the rule the whole phase exists to
enforce — a server that re-reads the file lags one save behind the user and gets
every position subtly wrong.

`didSave` therefore asks for **no text** (`includeText: false`): the buffer already
matches what was written. It is honoured when a client sends it anyway.

## Coordinates

Three systems, and the module keeps them apart:

| | counts | used by |
| --- | --- | --- |
| LSP position | line + **UTF-16 code units** | the protocol |
| byte offset | bytes into UTF-8 text | lexer, parser, `MID` |
| `SourcePosition` | both | everything internal |

`中` is 3 bytes and **1** unit. `😀` is 4 bytes and **2** units — a surrogate pair.
Treating `character` as a byte index works perfectly until the first accented
letter, then silently points into the middle of a character.

Rules implemented, all of them tested:

- LF, CRLF and a lone CR each terminate a line; a CRLF is one terminator and a
  position can never land between its two bytes;
- a column past the end of a line clamps to the end of the line, and a line past
  the end of the document clamps to the end of the document — the specification
  requires clamping, not an error;
- a column landing between the halves of a surrogate pair rounds **down** to the
  start of the character, because there is no byte offset in the middle of one;
- invalid UTF-8 counts one unit per byte rather than failing, because a language
  server sees half-typed text constantly;
- `LineIndex` is rebuilt in full on every edit. Patching it in place would have to
  handle a terminator split across the edit boundary; one linear pass over a
  document is not what makes a language server slow.

## Incremental changes

`contentChanges` is an ordered list, and **each entry applies to the document as
the previous one left it**. The end-to-end test pins this down: two edits in one
`didChange`, and the resulting document must be 30 bytes. Computing both ranges
against the original text yields 26, so the wrong implementation cannot pass.

An entry with no `range` replaces the whole document — legal even under
incremental sync, and what clients send after an external change such as a branch
switch. `rangeLength` is ignored: deprecated, in UTF-16 units, and redundant.

Hostile input is normalised rather than dropped, because dropping an edit
desynchronises the buffer from the editor permanently: a reversed range is
swapped, out-of-range coordinates clamp, and a change for a document that was
never opened is logged and discarded (there is no base text to apply it to).

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean.

| Suite | Result |
| --- | --- |
| framing | 41 assertions, all passed |
| json + jsonrpc | 110 assertions, all passed |
| **position** | **64 assertions, all passed** |
| **uri + document** | **88 assertions, all passed** |
| piped session (real process) | 53 assertions, all passed |

The position suite covers every terminator form, the CJK and astral cases, the
mid-surrogate rounding rule, clamping in both directions, malformed UTF-8, and a
round trip over every character boundary in a mixed-script document. The document
suite covers thirteen single-character insertions (what typing actually looks
like), edits that join and split lines, edits placed by UTF-16 column over
multi-byte text, reversed and out-of-range ranges, and a hundred documents opened
and half closed through the manager.

### Not verified

- **Linux and macOS**, still. The scripts are updated for the new sources but have
  never been run.
- **A real editor**, still.
- **Large-file performance.** `ApplyRange` copies the whole text and rebuilds the
  whole index per edit: O(n) per keystroke. For files up to a few hundred KB that
  is microseconds and correct; a 10 MB file being typed into would want a rope or
  a patched index. No measurement has been taken, so this is an expectation, not a
  result.
- **Memory.** Single-owner throughout, `DocumentManager` frees every document in
  `Close`/`CloseAll`/destructor, and the hundred-document test exercises that path
   — but no leak checker has been run.

## A toolchain bug this phase found, and its fix

Phase 2 needed a second hash map — one for open documents, on top of the
dispatcher's method registry — and the program stopped linking: ~18 "multiple
definition of `FB::HASHOF(...)`" errors, naming a standard-library function and
neither of the two files responsible.

`fb/hash.bi` defined its eighteen `HashOf` overloads **without `private`**, while
`HashBytes` and `HashInt` in the same header had it. A header-only module emits
every public definition into each module that includes it, so `fb/map.bi` — and
`fb/set.bi`, which also includes it — could be used from only ONE compilation
unit per program.

Fixed upstream in fbc-modern on 2026-08-22: the overloads are `private`, so each
module gets its own copy, and the header now says why so it does not regress. The
containers' own test suite (`container-map`, `container-set`, the two ordered
variants, `container-iterators`, `hash-ustring`) still passes, including the
user-defined `HashOf` case, and both negative tests still fail with the same
`error 99 ... HASHOF()` at the instantiation site.

tiko-lsp carried two workarounds in the meantime — an `any ptr` around the
document map and a flat-array method registry. Both are gone; `document_manager.bas`
and `dispatcher.bas` each hold a plain `FB.Map`, which is also the standing proof
that the fix works in a real multi-module program.

## Next: phase 3

A lexer and an error-recovering parser for fbc-modern, and
`textDocument/publishDiagnostics`. The document model already gives the parser
what it needs: authoritative text, a line index, and a position layer that turns
a byte offset back into the range an editor can draw.
