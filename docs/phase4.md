# Phase 4 — symbols, outline, hover, go to definition

The first phase an editor user can *see*: an outline pane, a tooltip, and F12.

## Delivered

| Requirement | Where |
| --- | --- |
| symbol model | `src/analysis/symbols.bas` — `SymbolInfo`, `SymbolTable` |
| symbol extraction | `src/analysis/parser.bas` — the same pass that finds block structure |
| cached per-document analysis | `src/document/document.bas` — `Tokens()`, `Symbols()`, `Diagnostics()` |
| `textDocument/documentSymbol` | `src/handlers/document_symbols.bas` |
| `textDocument/hover` | `src/handlers/hover.bas` |
| `textDocument/definition` | `src/handlers/definition.bas` |
| capabilities | `documentSymbolProvider`, `hoverProvider`, `definitionProvider` |

## What is extracted

Every declaration the parser walks past, with a kind, a signature, a
documentation comment, a parent, and two ranges:

| Written | Kind | Detail |
| --- | --- | --- |
| `sub Greet( byval n as long )` | Function | `(byval n as long)` |
| `function Add( ... ) as long` | Function | `(...) as long` |
| `sub Customer.SetName( ... )` | Method | `(...)` |
| `constructor Customer( )` | Constructor | |
| `operator Customer.let( ... )` | Operator | |
| `declare sub SetName( ... )` inside a type | Method, *declared* | |
| `type Customer` / `union U` | Struct | |
| `enum Colour` / `Red` / `Green = 5` | Enum, EnumMember | `= 5` |
| `namespace App` | Namespace | |
| `Name_ as string` inside a type | Field | `as string` |
| `as long Extra1, Extra2` inside a type | Field ×2 | `as long` |
| `dim shared as long counter` | Variable | `as long` |
| `const MAX_ITEMS = 100` | Constant | `= 100` |
| `dim`, `var`, `static` inside a procedure | Variable, *local* | |
| every parameter | Variable, *local* | its own text |

Both FreeBASIC declaration orders are handled — `dim a as long, b as string`
and `dim as long a, b` — and modifiers (`shared`, `private`, `const`, `virtual`)
are skipped rather than mistaken for names.

A generic member keeps its type arguments: `function Optional( of T ).Value( )`
is named `Optional (of T).Value`, not `Optional`. Getting that wrong put the
member name in the signature for every generic in `fb/*.bi`.

**Locals are extracted but never listed in the outline.** They are needed to
resolve a hover over a variable; an outline that lists every `dim` is unusable.

## Two ranges per symbol, and why

| | covers | used for |
| --- | --- | --- |
| `range` | the whole declaration, opener to `end sub` | what the editor highlights when the outline row is selected |
| `selectionRange` / definition target | just the identifier | where the caret lands on F12 |

LSP requires `selectionRange` to be inside `range`. A client whose server gets
that wrong shows an **empty outline** rather than an error, so both come from
the same symbol and are never mixed.

## Resolution

`SymbolTable.Resolve( name, offset )` walks outwards from the innermost scope
containing the offset: the procedure's locals and parameters, then each
enclosing type or namespace, then file level. That is what makes a parameter
named `total` shadow a global named `total` — the classic scope bug, and a
silent one.

At file level a **definition beats a `declare`**, so hovering a call points at
the body rather than at the prototype when a file has both.

`something.Name` is a different question, and is answered by `ResolveMember`,
which matches on name *and* kind. With no type inference yet, a member name that
appears in two types resolves to the first — honest, useful, and replaced when
the type system arrives.

## The analysis cache

A document analyses itself at most once per version. `Tokens()`, `Symbols()` and
`Diagnostics()` each re-analyse first if the text changed, so four features
asking the same question after one edit cost one analysis, and no caller has to
know whether the cache is warm. Any mutation drops it.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean. **627 assertions**, all passing:

| Suite | Assertions |
| --- | --- |
| framing | 41 |
| json + jsonrpc | 110 |
| position | 64 |
| uri + document | 88 |
| analysis (lexer, parser, this project's own source) | 157 |
| **symbols** | **74** |
| piped session (real process) | 93 |

The symbol suite covers every extraction form above, the two ranges, scope
resolution including the shadowing case, member resolution, the token-under-the
cursor rules, the hover markdown, and half-typed code — an unclosed `type` must
still produce an outline, because a blank outline is what makes an editor feel
broken.

The piped session proves the whole path against a **real process**: a document
with a `counter` declared on line 0 and used on line 2 yields an outline of two
symbols with the right kinds and ranges, a hover on the *use* that returns
```` ```freebasic\ncounter as long\n``` ```` marked *variable*, and a definition
that lands on **line 0, character 19** — the name, not the line.

The parser corpora were re-run after every symbol change: 435,000 lines, still
zero diagnostics outside fbc's own `fail-*.bas`. Symbol extraction was also run
over 380 of those files — 87,962 symbols, no crash and no timeout.

### Not verified

- **Linux and macOS**, still.
- **A real editor**, still. The outline, hover and definition are verified
  against the wire format, which is not the same as VS Code drawing them.
- **Cross-file anything.** A name declared in an `#include`d header resolves to
  nothing rather than to the wrong place. `workspace/symbol`, references and
  cross-file definition are phase 6, and need the workspace index.
- **Type inference.** `customer.Name` finds *a* field called `Name`, not the
  field of `customer`'s type.
- **Overloads.** Two procedures with the same name resolve to the first found;
  picking by argument types needs the semantic analyser.
- **Memory.** No leak checker has been run.

## Next: phase 5

Completion — keywords from the same table the lexer uses, the symbols in scope
from this table, and members after a `.` once there is enough type information
to know whose members they are.
