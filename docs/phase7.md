# Phase 7 — the editing features

The phase where the server stops answering questions about the code and starts
changing it.

## Delivered

| Requirement | Where |
| --- | --- |
| `textDocument/prepareRename` | `src/handlers/rename.bas` |
| `textDocument/rename` | `src/handlers/rename.bas` |
| `textDocument/signatureHelp` | `src/handlers/signature_help.bas`, `src/analysis/signature.bas` |
| `textDocument/semanticTokens/full` | `src/handlers/semantic_tokens.bas`, `src/analysis/semantic.bas` |
| `textDocument/inlayHint` | `src/handlers/inlay_hints.bas` |
| `textDocument/formatting` | `src/handlers/formatting.bas`, `src/analysis/format.bas` |
| `textDocument/rangeFormatting` | same |
| `textDocument/codeAction` | `src/handlers/code_action.bas` |
| capabilities | `renameProvider.prepareProvider`, `signatureHelpProvider`, `semanticTokensProvider` (full only), `inlayHintProvider`, `documentFormattingProvider`, `documentRangeFormattingProvider`, `codeActionProvider` (quickfix only) |

## Rename: two modes, and a refusal

Rename is the first request in this server that **rewrites the user's code**,
and that changes what "good enough" means. References may over-report: a wrong
row in a list costs a glance. A rename that over-reaches edits files the user
never opened, and the mistake surfaces later — in a build failure, or not at
all.

So there are two modes and nothing else:

- **A local or a parameter** is renamed inside its own procedure, in its own
  file. That is exact: a local cannot be named from outside the body it is
  declared in, so the edit set is provably complete and provably minimal.
- **Anything else** — a procedure, a type, a field, a file-level variable — is
  renamed across the workspace **by name**, exactly matching what "find all
  references" reports for it.

And the guard that makes the second one defensible: **if any local anywhere in
the workspace shares that name, the rename is refused**, with a message saying
where. Renaming a field called `Label_` by name would otherwise silently
rewrite the parameter `label_` in an unrelated procedure. Nothing in this server
can tell those apart — it has no type system — so it says so instead of
guessing. The piped session asserts exactly this case against the fixture
workspace.

`prepareRename` gives the same verdict **before** the editor asks for a new
name, which is the whole reason that request exists, and returns an **error**
rather than a null result so the client shows the reason and not just "cannot
rename".

Two more refusals: a new name that is not a tiko identifier, or that is a
reserved word, is `InvalidParams`; and a rename touching more than 5000
occurrences is refused outright. **A truncated rename is corruption**, so the
cap must never trim the way the reference cap does.

The edit goes back as `documentChanges` — versioned, so a client can reject an
edit that raced with a keystroke — when the client said it understands that
form in `initialize`, and as plain `changes` when it did not.

### The dot matters

`w.Label_` resolves through `ResolveMember`, which falls back to *any* symbol of
that name when the field itself is declared in another file — and in this file
`label_` is very often a parameter. Taking the local path there would rewrite
the parameter and leave the field alone: exactly backwards. So the local path
requires that the identifier is **not** a member access.

## Signature help

Answered from the signature the parser recorded when the procedure was
declared — `SymbolInfo.Detail_`, rebuilt from the tokens — so there is no second
parse. Splitting it back into parameters is a string operation, and the two
cases that break a naive split are both tested: a default value containing a
comma (`byval sep as string = ","`) and a function-pointer parameter carrying
its own parentheses.

Which call the caret is in is found by walking **backwards** to the innermost
unclosed `(` on the same logical line: at `Sum( a, Max( b, |` the answer is
`Max`, and nesting falls out of a depth counter rather than needing a stack. The
search stops at the start of the logical line, so a stray `(` twenty lines up
cannot swallow the file, while a `_` continuation still resolves — the lexer
emits no end-of-line for one.

Parameter labels go over the wire as `[start, end)` offset pairs, not
substrings: a substring would highlight the first `a` in
`(byval a as any ptr)` when the caret is somewhere else entirely.

**Overloads are counted, not chosen.** Picking between `Add( long )` and
`Add( string )` needs the type of what has been typed so far. The first
declaration is shown, `activeSignature` stays 0, and the log says how many
alternatives there were.

## Semantic tokens

Three rules the protocol imposes, each of which fails **silently** when broken —
the client renders nothing and reports nothing:

1. tokens are sorted, and encoded as deltas from the previous token;
2. **no token may span a line** — a nesting `/' ... '/` comment over four lines
   is four tokens;
3. lengths and characters are UTF-16 code units.

All three are asserted directly, including a test that rebuilds the absolute
positions from the deltas the way a client does.

Comments, strings, numbers and keywords **are** emitted, even though a TextMate
grammar could colour them, because for tiko most editors have no grammar at
all — the server is the only source of colour there. Punctuation is **not**:
every parenthesis and comma in a file would double the payload to say what is
already obvious. An identifier that resolves to nothing is left alone as well;
an unknown name is better uncoloured than coloured on a guess.

Colouring is **by name, not by resolution**. Clients that do not implement
deltas re-request the whole file on every keystroke, so this has to cost a
millisecond rather than a scope walk per identifier. Two symbols sharing a name
therefore share a colour — which they would anyway, except in the rare case
where a field and a procedure are called the same thing.

`full` only. No range variant and no delta: a delta needs the previous result
kept per document and a result id to match it against, and claiming it while
returning a full set every time is what makes a client show stale colours.

## Inlay hints

One kind: **the parameter name at a call site**, so `Move( 10, 3 )` reads as
`Move( x: 10, y: 3 )` without the file saying so.

The other classic hint — the inferred type of a `var` — is not produced, because
inferring it needs a type system this server does not have, and a wrong type
rendered inside the user's code as though it were fact is worse than no hint.

Hints are suppressed wherever they say nothing: when the argument is already the
parameter's name, when the callee does not resolve, and when the name is
**overloaded**, because the parameter names may differ between overloads and
annotating from the first would put the wrong word in the user's line.

The case the corpus caught immediately: `sub Move_( byval x as long )` has
exactly the shape of a call, so a procedure's own header was getting its
parameters annotated with their own names. A declaration's name is now
recognised and skipped.

## Formatting

**What it changes: leading whitespace, trailing whitespace, and the final
newline.** That is the whole list. Everything else a formatter could do to
tiko — keyword case, spacing inside parentheses, alignment of consecutive
assignments — is taste that the language does not settle, and a formatter that
rewrites a file to its own taste on every save is one the user turns off.
Indentation has a right answer, because it is the block structure.

**It refuses on broken code.** If the parser reported an error — an unclosed
`sub`, an `end if` with no `if` — the structure is unknown and re-indenting from
a wrong structure moves a screenful of lines to the wrong column. The refusal is
an **empty edit list**, not an error: format-on-save must not raise a dialog.

The block depth comes from the parser's own block stack rather than from a
second scanner in the formatter. That was the whole point of the `IndentTrace`
added to `ParseTokens` in this phase: two answers to "does this line open a
block" would drift apart, and the first symptom would be a single-line `if`
indenting the rest of the file.

### What the corpus taught

Every rule below came out of running the formatter over this project's own
source and AfxNova's, not out of thinking about it first. Each is now a test.

- **A continuation line is left where it is.** Indenting it one level past its
  statement is defensible in the abstract and wrong in practice: real
  tiko aligns a wrapped parameter list under the opening parenthesis, and
  the server cannot know which column that is. The first version produced a
  thousand edits on this project alone, every one destroying an alignment
  somebody chose.
- **`_` followed by a comment still continues the line.** Reading the text for a
  trailing underscore misses `& _   '' note`, which appears on four consecutive
  lines of this project's own test suite. Continuations are now taken from the
  lexer: it emits an end-of-line token at the end of every *logical* line and
  nowhere else, so a line with content and no end-of-line token is a line that
  continues.
- **`CASE` arms and access specifiers add a level the block stack does not
  have.** Neither opens a frame, so an `if` inside a `case` arm — or a member
  after `public:` — was marked one level too shallow. Both now set a *bias* on
  the enclosing frame. `public:` had never needed to be noticed by the parser
  before; it declares nothing.
- **A divider comment belongs to the clause below it.** A comment written
  between two `case` arms introduces the next one. The rule is narrow on
  purpose: only a comment block that follows ordinary code *and* precedes a
  clause moves. A comment that is the whole body of an arm follows a clause
  rather than code, and stays where it was written.
- **A preprocessor conditional does not indent.** An include guard wraps a whole
  file; indenting inside one would move every line in it.
- **The inside of a multi-line comment, and a `#macro` body, are never
  touched.** Comment art is not indentation, and a macro body is text — fbc's
  own test suite opens a block in one macro and closes it in another.

### Formatting cannot corrupt code

A harness formats every file in a tree, re-lexes the result, and requires that
the **token stream is identical** — same kinds, same texts — and that formatting
again changes nothing. Across 265 files (this project, AfxNova, `fb/*.bi`):
**zero token changes and zero non-idempotent files.**

| Tree | Files | Refused | Would change |
| --- | --- | --- | --- |
| tiko-lsp `src/` | 71 | 0 | 5 files, 15 edits |
| tiko-lsp `tests/` | 15 | 0 | 1 file, 8 edits |
| `fb/*.bi` | 67 | 0 | 65 files, 24,314 edits |
| AfxNova `src/` | 179 | 0 | 175 files, 124,159 edits |

The last two rows are not a bug and not a boast: those codebases do not indent
namespace bodies, and this formatter does. That is what a formatter is, which is
why it only ever runs when asked. The fifteen remaining edits in this project's
own source are the `#if` rule (two lines this repository indents and the
formatter does not) and two comment blocks aligned by hand.

## Code actions

Three quick fixes, and the list is short on purpose. A quick fix is applied with
one keystroke and usually without reading it, so the only defensible ones are
those with a **single unambiguous edit**:

| Diagnostic | Fix |
| --- | --- |
| `unterminated-string` | insert the closing quote at the end of the line |
| `unterminated-comment` | close the block comment at the end of the file |
| `unexpected-character` | delete the byte that begins nothing |

Deliberately **not** offered:

- `unclosed-block` — `end sub` has to go *somewhere*, and the server cannot know
  where the body was meant to stop. Putting it at the end of the file would
  swallow every procedure written after the broken one.
- `mismatched-end` — the same problem from the other side: either the opener or
  the closer is wrong, and choosing costs the user whichever half was right.
- `unbalanced-parenthesis` — a `)` can belong to any of several open calls.

A server that offers fixes for those looks more capable and is wrong often
enough to be worse than silence.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean. **934 assertions**, all passing:

| Suite | Assertions |
| --- | --- |
| framing | 41 |
| json + jsonrpc | 110 |
| position | 64 |
| uri + document | 88 |
| analysis | 157 |
| symbols | 74 |
| completion | 63 |
| workspace | 64 |
| **signature** | **53** |
| **semantic tokens** | **32** |
| **formatting** | **33** |
| piped session (real process) | 155 |

The piped session drives a **real `tiko-lsp.exe`** through thirty-seven
messages and asserts the phase-7 path end to end: the signature of `Move_`
with the right active parameter before and after the comma, two inlay hints
carrying the parameter names, a semantic-token array whose first token is a
keyword at line 0, a quick fix that inserts one quote at the end of the
unterminated line, `prepareRename` over exactly the identifier, a local rename
producing three edits in one file, the refusal for a name a local shares, an
`InvalidParams` for a rename to `end`, and one formatting edit for the one
unindented line.

### Performance

Measured on win64/gas64, per request, averaged over ten runs.

| File | Lines | Semantic tokens | Formatting | Signature help | Inlay hints (60 lines) |
| --- | --- | --- | --- | --- | --- |
| `parser.bas` | 1,736 | 2.2 ms | 3.9 ms | 0.01 ms | 0.04 ms |
| `AfxWebView2.bi` | 6,255 | 9.6 ms | 14.8 ms | 0.03 ms | 0.08 ms |

Signature help and inlay hints are typed against and cost nothing. Semantic
tokens and formatting are the expensive pair — formatting re-analyses the
document because it needs the indent trace, which the cached analysis does not
carry.

### Not verified

- **Linux and macOS**, still. The scripts exist and have never been run.
- **A real editor**, still. Every assertion here is made against the bytes on
  the wire, not against what VS Code or Zed does with them.
- **Semantic token deltas** are not implemented, so a client that re-requests
  the full set on every keystroke pays 10 ms on a 6,000-line file.
- **Rename across an `#include` graph.** It matches by name across the whole
  workspace, which is broader than one file's include set and narrower than
  correct.
- **Formatting a file that fbc accepts but this parser does not.** The parser is
  clean across 435,000 lines of real source, so this should be rare, but the
  consequence here is a refusal rather than a diagnostic — and a refusal is
  silent apart from the log.
- **The startup stall** from phase 6 is unchanged: the index build still blocks
  the message loop.

## Next

The seven phases the plan named are done. What is worth doing next, in order of
how much it would change the experience:

1. **Move analysis off the message loop.** It is the one structural problem
   left: a large workspace's index build, and every re-analysis, happens where
   the client is waiting. *Done, for the workspace scan -- see
   [phase8.md](phase8.md), which also records the bug that found: the server
   could not talk to a live editor at all.*
2. **`workspace/didChangeWatchedFiles`**, so a branch switch does not leave the
   index describing a file that no longer exists.
3. **An include graph**, which would turn "somewhere in the workspace" into
   "visible from here" and make both definition and rename precise.
4. **Semantic token deltas**, once there is a reason to care about the 10 ms.
5. **Type inference**, which is what overload resolution, `var` type hints and
   symbol identity all wait on.
