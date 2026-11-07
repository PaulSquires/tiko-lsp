# tiko-tree-sitter

A tree-sitter grammar for **tiko** — the FreeBASIC-compatible language of
`tiko-lang` — written for **editors**: highlighting, folding, an outline,
bracket matching and indentation.

It is deliberately **not** a compiler front end, and the difference is the
whole design.

## What it parses exactly, and what it does not

**Exactly: block structure.** Procedures, types, unions, enums, namespaces,
`extern`, `scope`, `with`, `asm`, `if`/`elseif`/`else`, `select case`, all
three loops, labels, and the preprocessor -- tiko's `#module`, `#import` and
`#export` included. Every one of those has its opener,
its body and its closer in the tree, which is what folding, indentation and the
outline are built from.

**Not: expressions.** The inside of a statement is a flat run of *atoms* —
identifiers, numbers, strings, operators and balanced bracket groups. tiko's
expression grammar is large and ambiguous by design (`Foo(1)` is a call, an
array index or a cast depending on what `Foo` is), none of that changes how the
text is coloured, and a grammar that ERRORs on real code highlights nothing at
all.

**Only structural words are keywords.** `sub`, `end`, `if`, `for` and their
kind are in the grammar because they delimit blocks. The other two hundred
reserved words — `print`, `mod`, `andalso`, `sizeof` — are ordinary identifiers
to the parser and are coloured by a `#match?` predicate in
[queries/highlights.scm](queries/highlights.scm). That is not a shortcut, it is
the fix: tiko is case-insensitive, so every keyword is a regex rather than a
string, which switches off tree-sitter's keyword extraction, and a two-hundred
word `keyword` rule then collides with `identifier` at every turn.

## Three facts about the language that shape everything

* **Keywords are case-insensitive** — `Sub`, `sub` and `SUB` are one word.
* **A statement ends at a newline or a colon**, so a newline is a real token
  and cannot live in `extras`.
* **A line continues with `_`**, which *is* in extras — a wrapped statement is
  identical to an unwrapped one everywhere else. A comment may follow the
  underscore.

## The external scanner

`src/scanner.c` contributes three tokens. The first is zero-width: **end of file ends a
line**. An editor buffer spends most of its life without a trailing newline —
the caret is on the last line, still typing it — and a grammar that insists on
one reports the last statement as broken exactly while it is being written.

The other two are tiko's **contextual words `interface` and `inherits`**. Neither
is reserved, and as keyword tokens they would lex as keywords wherever a name is
valid too (`print interface`). The scanner emits one only where the parser can
take it and a name — not `as`, not `=` — follows: `interface IAnimal`,
`inherits Animal`.

## Building and testing

```bash
npm install
npx tree-sitter generate
npx tree-sitter test
```

`src/parser.c`, `src/grammar.json` and `src/node-types.json` are generated and
**committed**, so a consumer needs no tree-sitter CLI.

## What it is measured against

The grammar is corpus-driven: it is judged by whether it parses real code, not
by whether it is elegant.

| Tree | Files | With an ERROR |
| --- | ---: | ---: |
| `tiko-lsp/src` | 89 | 0 |
| `tiko-lsp/tests` | 14 | 0 |
| `tiko-lang/src` | 438 | 3 |
| `tiko-lang/tests` (not `vendor/`) | 2446 | 92 |
| `tiko-lang/pkg` | 385 | 2 |
| `tiko-lang/examples` | 845 | 0 |
| `tiko-lang/by-example/examples` | 309 | 0 |
| `tiko-lang/tkedit` | 58 | 0 |
| `AfxNova/src` (FreeBASIC) | 179 | 1 |

Re-measured 2026-11-04. The two `pkg` files are `std/tasks/scheduler.tiko`, which
opens `extern` in three `#if` branches and closes it once, and `CDialog.tiko`'s
`IF x DoIt( )` with no THEN; the three in `src` are namespaces closed in an
`#include`d file (below).

`tiko-lang/tests` is the compiler's own corner-case corpus, and several of the
92 are deliberately invalid programs that a grammar is *supposed* to reject.

Two files in `tiko-lang/src` (`mir/lowerstr.bas`, `parser/parser.bas`) open a
`namespace` and leave the `end namespace` to a file they `#include` at the
bottom. That is legal, and no file-at-a-time parser can balance it: the tree is
correct apart from one `MISSING "end namespace"` at EOF.

## Queries

| File | Used for |
| --- | --- |
| `queries/highlights.scm` | colour |
| `queries/brackets.scm` | matching `sub`/`end sub` as well as `(`/`)` |
| `queries/indents.scm` | indent on an opener, outdent on a closer |
| `queries/outline.scm` | the symbol list: procedures, types, namespaces, macros |

## Using it from an editor

The grammar is a plain tree-sitter grammar and works anywhere one does. The Zed
extension is in [`../editors/zed`](../editors/zed), and it names this grammar by
REPOSITORY AND REVISION -- never by a path, and the repository root is where it
looks for `src/parser.c`. This directory is not a repository root, so it is
mirrored to one (`C:\dev\tiko-tree-sitter` by default) and loaded through a
`file://` URL. Run [`../editors/zed/sync-grammar.sh`](../editors/zed/sync-grammar.sh)
after changing the grammar: it regenerates, mirrors, commits and re-pins the
revision in `extension.toml`.
