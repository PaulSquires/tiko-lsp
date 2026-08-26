# The tree-sitter grammar

`grammar/` holds **tree-sitter-tiko**: a tree-sitter grammar for the language
this server serves. It is a separate artefact from the server — nothing in
`src/` uses it — and it exists so an editor can colour, fold and outline tiko
source **without** a language server running, and so the Zed extension has a
grammar to name.

The full design note is [grammar/README.md](../grammar/README.md). This page
records the decisions and the measurements.

## The two decisions that shape it

**1. Block structure exactly; statement interiors as flat atoms.** Openers,
bodies and closers are real nodes; the inside of a statement is a run of
identifiers, numbers, strings, operators and *balanced* bracket groups. tiko's
expression grammar is ambiguous by design — `Foo(1)` is a call, an index or a
cast depending on what `Foo` is — and resolving it changes nothing about how
the text is coloured.

**2. Only structural words are keywords.** The other ~200 reserved words are
identifiers to the parser and are coloured by a `#match?` predicate in
`queries/highlights.scm`, from the same list as the server's own keyword table
in `src/analysis/lexer.bas`. The language is case-insensitive, so every keyword
is a regex, which switches off tree-sitter's keyword extraction; a 200-word
`keyword` rule then collides with `identifier` at every turn. Moving the list
into the query removes the ambiguity rather than fighting it.

## What real code taught it

Every rule below exists because a corpus file failed, not because the language
reference lists it.

| The line | What went wrong |
| --- | --- |
| `end select` | Read as `end <expression>` with `select` as the value. Closers are now **single tokens** (`end sub`, `end if`), so the lexer settles it by longest match. |
| `dim as long removed` | `REM` matched the prefix of `removed`, `remaining`, `Remove` — the rest of the line vanished into a comment. `REM` now needs a space after it. |
| `open err for output as #fh` | FOR and AS without meaning either: it opened a loop that never closed and the rest of the file was lost. The line is one token. |
| `function = 0` | The FreeBASIC way to set a return value opened a procedure that never closed — **222 files** of PsControls failed on this one shape. |
| `r = type<POINT>( x, y )` | A UDT literal spelled with the block word. |
| `declare sub puts_ cdecl alias "puts" ( ... )` | The parameter list does not come last; it is one signature tail among others. |
| `Call_( a, _  '' note` | A comment may follow the continuation underscore. |
| a file with no trailing newline | Every buffer being typed into. An external scanner contributes one zero-width token: **end of file ends a line**. |
| an unterminated `"` | fbc accepts it, this project's corpus contains one, and an editor sees one on every keystroke while a string is typed. |

## Measured

Corpus-driven means judged by whether it parses real code:

| Tree | Files | With an ERROR |
| --- | ---: | ---: |
| `tiko-lsp/src` | 77 | 0 |
| `tiko-lsp/tests` | 15 | 0 |
| `tiko-lang/src` | 123 | 0 |
| `PsControls` (FreeBASIC) | 572 | 0 |

`tree-sitter test` runs 19 corpus cases covering declarations, statements, the
preprocessor and the lexical corners; all pass.

## Not verified

- **No editor has rendered it.** The queries are checked with
  `tree-sitter query`, which proves they compile and capture the nodes they
  name — not that a colour scheme maps every capture to a colour.
- **Wiring it into the Zed extension is not done.** A Zed extension names a
  grammar by *repository URL and commit*, never by a local path, so the grammar
  has to be published as a repository of its own first.
- **Two files parse with a `MISSING "end namespace"`**: `mir/lowerstr.bas` and
  `parser/parser.bas` open a namespace and leave the closer to a file they
  `#include` at the bottom. Legal, and no file-at-a-time parser can balance it.
- **PsControls is FreeBASIC, not tiko** -- it is in the table because it is
  25 owner-drawn controls of hand-written real code, and it is what found
  `function = 0` and `type<POINT>( ... )`.
