# The tree-sitter grammar

`grammar/` holds **tiko-tree-sitter**: a tree-sitter grammar for the language
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
in `src/analysis/lexer.tiko`. The language is case-insensitive, so every keyword
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
| `operator = ( ... )`, `operator C.@ ( )` | An operator is named by a **symbol**, and a member operator carries its type in front of it. AfxNova defines dozens; each lost its file from the first one on. |
| `as const IID const ptr` | `const` is part of a type, and appears twice in one — every COM parameter in AfxNova. |
| `function Some( of T )( byref v as T )` | A generic procedure names its type parameters between the name and the value parameters. |
| `#macro M( args... )` | The variadic macro parameter is named. |
| `a : 3 as ulong` | A bitfield member — the colon ends a statement everywhere else. |
| `rtp.type = nType` | A structural word after a dot is a member name. |
| `operator = ( ... )` vs `operator = *cast( ... )` | The same two tokens open a definition and assign a result. Both readings go to the GLR parser, and whichever goes on to parse wins. |
| `( of T )` | One token, `( of`. `Foo( of T )` and `Foo( x )` differ only *after* the parenthesis, so as two tokens the parser has to pick a generic list or a parameter list before it can see which it is. |
| `extern import x alias "y" as T` | A statement, not a block — same first word as `extern "C"`, and a dynamic precedence keeps it from swallowing a later block's `end extern`. |
| `= function( byval v as T ) as T ... end function` | A lambda: a procedure with no name. |
| `p->lpvtbl->Select( p )` | A structural word after `.` or `->` is a member name. |
| `if p = 0 then function = "" : exit function` | Assigning the result inline. |
| `type as integer rev1, rev2` | The reversed type-alias list. |
| a file with no trailing newline | Every buffer being typed into. An external scanner contributes one zero-width token: **end of file ends a line**. |
| an unterminated `"` | fbc accepts it, this project's corpus contains one, and an editor sees one on every keystroke while a string is typed. |
| `interface IAnimal` ... `end interface`, `class Dog` ... `end class` | tiko's interfaces. An interface's members are bare headers -- `sub Speak( )` with no body and no END -- so they are their own rule (`interface_method`), not a procedure that never closes; `inherits` and `implements` lines are clauses of a class, type or interface body, and `implements IAnimal.Name` may end a DECLARE. |
| `print interface`, `dim as long inherits = 2` | Neither word is reserved (tiko-lang's `interface-as-name` test keeps every such name), and a keyword token lexes as the keyword wherever a name is valid too. The external scanner emits them, only where the parser can take one AND a name -- not `as`, not `=` -- follows. `class` and `implements` are fbc-reserved, so they are ordinary keywords. |
| `type X extends Object implements I` | fbc's spelling: `implements` on the header line. |
| a property's `set` ... `end set` (and `get` ... `end get`) | **Coloured by the queries, not parsed.** `set` alone on its line is already a bare identifier straight under the property, and `end set` is `end <value>`, so two `#match?` patterns colour exactly those (not `Set( of long )`, `x = set`). Every grammar form measured cost more: a section block +2.5 MB of `parser.c` (1530 -> 1920 large states, its closers reach every nested body), the opener alone as a scanner token +1.4 MB. |
| `type Lexer as view` … `end type` | tiko's view-kind type (string slices): a TYPE block whose line has an AS. `as view` is one token from the external scanner, which ends it at a word boundary -- `type V as viewport` stays an alias. `s[lo to hi]` needed nothing: the brackets hold atoms. |
| `s = """` … `"""` | tiko's block string: `"""` that ends its line opens one, the first line starting (after blanks) with `"""` closes it. One `string` token, a regular expression with no scanner. `"""abc"""` never matches the opener, so it stays fbc's 5-character string. An unterminated block matches nothing and lexes as before, so the lines under a half-typed block stay code until its closer is written. |

## Measured

Corpus-driven means judged by whether it parses real code:

| Tree | Files | With an ERROR |
| --- | ---: | ---: |
| `tiko-lsp/src` | 89 | 0 |
| `tiko-lsp/tests` | 53 | 0 |
| `tiko-lang/src` | 447 | 3 |
| `tiko-lang/tests` (not `vendor/`) | 2481 | 94 |
| `tiko-lang/pkg` | 385 | 2 |
| `tiko-lang/examples` | 844 | 0 |
| `tiko-lang/by-example/examples` | 309 | 0 |
| `tiko-lang/tkedit` | 58 | 0 |
| `AfxNova/src` (FreeBASIC) | 179 | 1 |

Re-measured 2026-11-06 (`.tiko`, `.ti`, `.bas`, `.bi`; AfxNova's `.inc` too), after
interfaces and classes: old vs new parser over the same 4,694 files, 116 -> 99 with an
ERROR and no file newly failing -- the 17 fixed are tiko-lang's interface tests.
`tiko-lang/tests` still counts `interface-parse-errors.bas`, deliberately invalid. The two `pkg` files are `std/tasks/scheduler.tiko`, which
opens `extern` in three `#if` branches and closes it once, and `CDialog.tiko`'s
`IF x DoIt( )` with no THEN; the three in `src` are namespaces closed in an
`#include`d file (below).

`tree-sitter test` runs 29 corpus cases covering declarations, statements, the
preprocessor and the lexical corners; all pass.

tiko's module directives (tiko-lang ADR 0017) are structural nodes of their own:
`preproc_module` (`#module "name"`), `preproc_import` (`#import "path"`, its
`as` alias and `public`) and `preproc_export` (`#export A, B`), coloured and
listed in the outline in both query sets. Measured over the 96 `.bas` files of
tiko-lang's module tests, fixtures and `pkg/std`: 3 with an ERROR -- one a
deliberately malformed `#import` from its diagnostics tests, and two the grammar
already missed (`sub f( ) constructor 101`, `public union`), which the module
rules did not change.

## Not verified

- **Zed is wired up, but nothing has rendered it yet.** A Zed extension names a
  grammar by *repository and revision*, never by a path -- and the repository
  root is where it looks for `src/parser.c`. A `file://` URL is allowed, so the
  grammar is mirrored to a local repository at `C:\dev\tiko-tree-sitter` and
  `editors/zed/extension.toml` pins that revision. `editors/zed/sync-grammar.sh`
  re-mirrors and re-pins after a grammar change. What has NOT happened is a
  reload inside Zed VERIFIED THE LANGUAGE SERVER, not the colours: with the
  queries in place Zed logs `start/finish loading grammar "tiko"` and starts
  `tiko-lsp.exe`. Nobody has looked at a rendered buffer yet.

- **ONE PATTERN SHAPE ZED REFUSES**, found the hard way: anything that names a
  FIELD or a KEYWORD inside `enum_definition` --
  `(enum_definition name: (identifier) @type)`,
  `(enum_definition "enum" @open "end enum" @close)`. Zed says NOTHING: the
  language never attaches, so the file loses its highlighting *and* its
  language server, and the log is silent at every trace level. `tree-sitter
  query` accepts both, so the grammar's own queries are not a check on Zed's.
  A named child -- `(enum_definition (identifier) @type)` -- is fine, and that
  is what the Zed queries use.
- **Two files parse with a `MISSING "end namespace"`**: `mir/lowerstr.bas` and
  `parser/parser.bas` open a namespace and leave the closer to a file they
  `#include` at the bottom. Legal, and no file-at-a-time parser can balance it.
- **What still fails is listed, not rounded away.** In `tiko-lang/tests`
  (2446 files, the compiler's own corner-case corpus) 92 files carry an
  ERROR — and some of them **should**: `bad-decl.bas`, `bad-expr.bas`,
  `broken.bas`, `missing-end.bas` and `unclosed-paren.bas` are deliberately
  invalid programs, and `field-keyword-name.bas` exists to prove a field may be
  named after almost any keyword. The rest are `#macro` bodies, `#print`, and
  declarations spelled in ways this grammar reads as one statement rather than
  several.
- **A member named with a structural word and no dot in front of it** —
  `as UINT Type` — still fails; it is 4 of AfxNova's 7.
- **PsControls is FreeBASIC, not tiko** -- it is in the table because it is
  25 owner-drawn controls of hand-written real code, and it is what found
  `function = 0` and `type<POINT>( ... )`.
