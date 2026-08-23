# Phase 3 — lexer, parser, diagnostics

The first phase that reads tiko rather than just moving it around.

## Delivered

| Requirement | Where |
| --- | --- |
| lexer | `src/analysis/lexer.bas` — `LexSource`, 247 reserved words |
| parser with error recovery | `src/analysis/parser.bas` — `ParseTokens` |
| diagnostic model | `src/analysis/diagnostics.bas` — offsets, severity, stable codes |
| `textDocument/publishDiagnostics` | `src/lsp/publish.bas` |
| published on open, change, save; cleared on close | `src/handlers/text_document.bas` |

No capability was added: diagnostics are **pushed**, and the specification has
nothing to advertise for that. The pull-based `textDocument/diagnostic` of 3.17
is a separate feature, and is not claimed.

## What is checked

From the lexer:

- unterminated string literals (a string never spans a line in tiko);
- unterminated block comments — which **nest**, so `/' a /' b '/ c '/` is one;
- malformed numbers: `1.2.3`, `&hzz`, `12abc`;
- bytes that cannot begin a token.

From the parser, statement by statement:

- every block opener has its closer, and they nest — `sub`/`end sub`,
  `type`/`end type`, `if`/`end if`/`endif`, `while`/`wend`, `do`/`loop`,
  `for`/`next` (including `next j, i`, which closes two), `select`/`end select`,
  `with`, `scope`, `namespace`, `union`, `enum`, `extern "C"`, `asm`;
- `else`, `elseif` and `case` appear inside the right block;
- parentheses and brackets balance within a statement;
- `#if`/`#endif` and `#macro`/`#endmacro` match.

## Recovery

The rule is **one mistake, one diagnostic**. A parser that reports forty errors
for a missing `end if` is worse than one that reports none, because the real
problem is off screen.

So a closer that does not match the top of the stack searches downwards for one
that does. Everything it passes is reported **at its own opener** — where the
user has to go to fix it — then popped, so the rest of the file still analyses
cleanly. The test for this asserts that a missing `end if` inside a sub produces
exactly one diagnostic, and that its range points at the `if`.

Nothing stops at the first error, and no input crashes the analyser: `sub `,
`dim x as `, `if ( `, a lone `#`, a lone quote and an empty document are all
tested directly.

## False positives are the failure mode that matters

A language server that squiggles valid code is worse than one that reports
nothing, so the parser was developed against real source rather than against
hand-written samples. Final state:

| Corpus | Files | Lines | Diagnostics |
| --- | --- | --- | --- |
| fbc's own compiler (`src/src/compiler/*.bas`) | 162 | 152,579 | 0 |
| fbc-modern standard library (`inc/fb/*.bi`) | 67 | 35,061 | 0 |
| AfxNova (`src/*.inc`, `src/*.bi`) | 179 | 199,762 | 0 |
| fbc test suite (string, structs, examples) | 376 | 32,314 | 0 |
| fbc generics tests | 72 | 11,422 | 3 — all in `fail-*.bas`, which are deliberately unbalanced |
| this project | 27 | ~4,000 | 0 |

**Roughly 435,000 lines of real FreeBASIC-compatible source -- tiko reads the
same syntax -- and the only diagnostics are on files
fbc itself expects to reject.**

Fourteen distinct false positives were found and fixed that way. Each is now a
named test in `tests/test_analysis.bas`, because the corpora are not in this
repository:

| What broke | Where it came from |
| --- | --- |
| `{` and `}` were "unexpected characters" | array initialisers, everywhere |
| `_` before `(` ate the rest of the line | `V3##_( x, y, z )` in `fb/vector.bi` — a macro paste, not a continuation |
| a block comment after `_` ended the continuation | nine lines of one initialiser in `ir-gas64.bas` |
| `operator = expr` read as an operator definition | `fb/vector.bi`, which uses both spellings |
| `constructor( 5 )` read as a definition | constructor chaining, `tests/structs` |
| `private const function` / `private virtual destructor` not seen as bodies | `fb/fsdir.bi`, `fb/logrender.bi` |
| an anonymous nested `type` never opened | `union ustab` in `ir-gas64.bas` |
| `type NAME` where NAME lexes as a keyword | `#macro DEFINE_SEGMENT_COMMAND(NAME, ...)` in `objinfo.bas` |
| a field named `Select` opened a SELECT block | COM vtables in AfxNova's `AfxTOM.bi` |
| `extern` opened in a `#if` branch, closed after `#endif` | `fb/scheduler.bi` |
| a macro expanding to a block opener | `#define FBFSLINK_EXTERN extern "C"` |
| a macro body's colons split its statements | `#define COM_IID(...)` in `fb/comptr.bi` |
| a macro opening a block another macro closes | `tests/structs/temp-var-dtors.bas` |
| lambdas — five separate shapes | `tests/generics` |

The lambda work is the largest single piece: an anonymous `function`/`sub` opens
a block from inside an **expression**, which is the one place a block does not
begin a statement. All five forms are handled — plain, capture list
(`sub[ byref total ]( ... )`), calling convention (`function cdecl( ... )`),
`byref` return, and a function type as the return type — while
`cast( function( ) as long, p )` is correctly left alone, because its tail has a
top-level comma.

## Preprocessor handling

Directives are tracked on their **own stack**, not the block stack, because a
directive does not nest with a block. `#else` drops what the previous branch
opened; `#endif` keeps what the surviving branch opened, which is what makes the
`extern`-inside-`#if` idiom work; `#endmacro` drops everything, because a macro
body is text and is not required to balance. Block-structure complaints are
suppressed entirely inside a macro body.

A `#define` whose replacement begins with a block keyword is remembered as an
"opener macro". That is the whole of the macro handling: no expansion, no
arguments.

## Encoding

A UTF-8 BOM is skipped. A **UTF-16** source — which fbc accepts, and which
`tests/string/asc-utf16le.bas` is — produces no diagnostics at all rather than
two thousand: a byte-oriented lexer cannot read it, and saying nothing is the
honest answer.

## Performance

Measured on win64/gas64, one full analysis (lex + parse) of a document:

| File | Size | Time |
| --- | --- | --- |
| `src/analysis/parser.bas` (893 lines) | 37 KB | 1.0 ms |
| `AfxNova/src/AfxCtl.inc` (5,334 lines) | 355 KB | 9.1 ms |
| `fbc/ir-gas64.bas` (8,645 lines) | 280 KB | 10.4 ms |

600,000–2,000,000 lines/second. Analysis runs synchronously on every
`didChange`, which is comfortably inside a keystroke for anything normal; that
is why there is no debouncing yet, and why moving it off the message loop is a
phase 6 concern rather than an urgent one.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean.

| Suite | Result |
| --- | --- |
| framing | 41 assertions |
| json + jsonrpc | 110 assertions |
| position | 64 assertions |
| uri + document | 88 assertions |
| **analysis** | **157 assertions**, including this project's own source |
| piped session (real process) | 72 assertions |

The piped session now proves the whole path: a `didOpen` of a file with a
missing `end sub` produces a `publishDiagnostics` naming `'sub Test'`, at
severity Error, with `source: "tiko-lsp"` and a range covering the `sub` keyword
on line 0; the `didChange` that adds the `end sub` produces an **empty** list,
which is what actually clears an editor's squiggle; and `didClose` publishes an
empty list with no version.

### Not verified

- **Linux and macOS**, still — the scripts are updated but have never been run.
- **A real editor**, still.
- **Semantic errors.** Nothing here type-checks, resolves a name, or notices an
  undeclared variable. `dim x as NoSuchType` is structurally perfect and passes
  silently. Real diagnostics arrive with the semantic analyser.
- **Preprocessor-conditional block structure** beyond the rules above. Code that
  opens a block in one `#if` branch and a *different* one in another can still
  be misread; no example was found in 435,000 lines, but the shape exists.
- **Memory.** No leak checker has been run.

## Next: phase 4

Symbols. The block stack already carries a kind, a name and a range for every
`sub`, `function`, `type`, `enum` and `namespace` — which is `documentSymbol`
almost directly, and the foundation for hover and go-to-definition.
