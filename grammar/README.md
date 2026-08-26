# tree-sitter-tiko

A tree-sitter grammar for **tiko** — the FreeBASIC-compatible language of
`tiko-lang` — written for **editors**: highlighting, folding, an outline,
bracket matching and indentation.

It is deliberately **not** a compiler front end, and the difference is the
whole design.

## What it parses exactly, and what it does not

**Exactly: block structure.** Procedures, types, unions, enums, namespaces,
`extern`, `scope`, `with`, `asm`, `if`/`elseif`/`else`, `select case`, all
three loops, labels, and the preprocessor. Every one of those has its opener,
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

`src/scanner.c` contributes exactly one zero-width token: **end of file ends a
line**. An editor buffer spends most of its life without a trailing newline —
the caret is on the last line, still typing it — and a grammar that insists on
one reports the last statement as broken exactly while it is being written.

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
| `tiko-lsp/src` | 77 | 0 |
| `tiko-lsp/tests` | 15 | 0 |
| `tiko-lang/src` | 123 | 0 |
| `PsControls` (FreeBASIC) | 572 | 0 |

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

The grammar is a plain tree-sitter grammar and works anywhere one does. For
Zed, the extension in [`../editors/zed`](../editors/zed) declares the language
and the language server; wiring the grammar into it needs the grammar published
as a git repository of its own, because a Zed extension names a grammar by
repository URL and commit, never by a local path.
