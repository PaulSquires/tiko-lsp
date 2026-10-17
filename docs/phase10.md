# Phase 10 — the include graph

Until now every cross-file answer was *"is this name declared **somewhere** in
the workspace?"*. `Widget` in widgets.bas resolved to shared.bi because
shared.bi happened to be in the folder — it would have resolved the same way if
the two files had nothing to do with each other. Nothing in the server read an
`#include`.

The graph turns *"this name exists somewhere"* into *"this name is visible
here"*.

## Delivered

| | Where |
| --- | --- |
| reading the directives | `src/analysis/includes.tiko` |
| edges, resolution, visibility | `src/workspace/symbol_index.tiko` |
| go to definition **on** an `#include` | `src/handlers/definition.tiko` |
| definition ranked by what a file can see | `SymbolIndex.FindDefinitionFrom` |
| completion through an include, scope and member | `src/handlers/completion.tiko` |
| rename narrowed to what can see the declaration | `src/handlers/rename.tiko` |

No new capability: an include-aware answer is the same request answered better.

## Resolution is lexical, in three steps

No file I/O at all. A candidate path is built, normalised, and looked up among
the files already indexed — twenty thousand includes cost twenty thousand hash
probes rather than twenty thousand `stat` calls, and the question really being
asked is *"is this one of ours?"*.

1. **Relative to the includer**, which is what fbc does and what a reader
   assumes: two directories can each hold a `shared.bi`, and the one next door
   is the one meant.
2. **Against the workspace folders**, which stand in for fbc's `-i` paths. The
   server is never told the real ones — they live in a build script it does not
   read.
3. **By file name, when the workspace holds exactly one file with it.**

That third step is a guess, and it is the guess that makes the graph worth
having on real code:

| Workspace | includes | resolved without step 3 | with it |
| --- | --- | --- | --- |
| tiko-lsp | 255 | 216 | 216 |
| AfxNova | 4,654 | **28** | **4,360** |
| C:\dev\tiko | 6,475 | 1,329 | 5,560 |

AfxNova writes `#include once "AfxNova/DWSTRING.inc"` and relies on an `-i` path
pointing at the compiler's include directory. Without step 3 the graph knew
essentially nothing about it. **The uniqueness condition is what keeps the step
honest**: two files called `common.bi` in different folders resolve to neither,
and the file is then marked as having an unresolved include — which every caller
treats as *visibility unknown*.

tiko-lsp's own 39 unresolved edges are `crt.bi`, `fb/*.bi` and `yyjson.bi`:
compiler headers, correctly outside the graph.

## Unknown visibility is not invisibility

A file with an edge to nowhere might reach anything by a path the server cannot
see. So its visible set is a **lower bound**, and every caller is written to
that:

- **definition** prefers a declaration the file can see and falls back to the
  workspace-wide best — an unresolved include must never turn into "no such
  name";
- **completion** adds what the visible set declares and never removes anything;
- **rename** narrows its edit set to the files that can see the declaration —
  *plus* every file with an unresolved include, because those might see it too.

## What it changed

### Go to definition on an `#include`

Ctrl-clicking `#include once "shared.bi"` opens shared.bi. Nothing else in LSP
expresses "go to this file", and every editor already binds the gesture to this
request. The cheap half of the question — *is the caret on an include path at
all?* — is answered from the open document's own tokens, so an ordinary
go-to-definition never starts by waiting for a workspace scan it does not need.

### Completion reads through the include

This is the change a user notices. A file that includes a header saw **none** of
what the header declares: the one list read on every keystroke stopped at a file
boundary the language does not have. Now the scope list carries what the visible
set declares, in a group of its own — after this file's declarations, before the
keywords — and `w.` offers the fields of a type declared in a header.

**Completion never waits.** It runs on every keystroke, so it uses the index
when the worker has already finished and silently skips it when it has not; a
first completion that blocked for a four-second scan would be worse than a
shorter list.

**And it is capped.** A file at the top of a big header tree can see 49,831
symbols (measured, `C:\dev\tiko`). The list is filtered by what has been typed,
capped at 1,000 included names, and returned as a `CompletionList` with
`isIncomplete: true` — the protocol's way of saying *ask me again when you have
typed more*. Filtered is incomplete too: a client that believed a prefix-filtered
list was the whole truth would narrow it locally, and the names it never saw
would never appear.

| File including | prefix | time | items |
| --- | --- | --- | --- |
| `AfxNova/CWindow.inc` | *(none)* | 9.1 ms | 1,249 |
| `AfxNova/CWindow.inc` | `Afx` | 8.4 ms | 851 |
| `AfxNova/CWindow.inc` | `AfxWin` | 3.7 ms | 258 |

### Rename got narrower

A rename by name reached the whole workspace, and **any** local anywhere that
shared the name made it refuse — so renaming a field called `Count` was
impossible in any project that also had a loop variable called `count`. The edit
set is now the files that can see the declaration (`IncludedBy`), plus the file
the request came from, plus every file whose visibility is unknown. The refusal
applies to the same set.

## What it costs

| Workspace | files | resolve | widest visible set | reverse set |
| --- | --- | --- | --- | --- |
| tiko-lsp | 92 | 0.7 ms | 34 files, 969 symbols | 72 files |
| AfxNova | 2,093 | 26 ms | 46 files, 18,667 symbols | 1,926 files |
| C:\dev\tiko | 4,000 | 54 ms | 297 files, 49,831 symbols | 1,825 files |

Resolution runs on the worker after a scan, and on the message loop after a
buffer changes — one hash probe per edge, which is a fraction of the analysis
that just ran. `VisibleFrom` is about 3 µs; `IncludedBy` walks the whole index
repeatedly until it stops growing, and costs 0.1–0.2 ms.

## The bug this found

Driving completion through AfxNova's headers produced **no response at all**, and
one line in the log: `failed to serialise response for id 3`.

yyjson refuses to serialise a document containing invalid UTF-8 — and refuses
**all** of it. **155 of AfxNova's 179 source files carry a Latin-1 `é` in their
copyright line.** One byte, in one symbol's documentation, and the entire
response was lost: nothing on the wire, and an editor waiting forever for a
request that never completed.

Every string that goes out is now checked as it is built, and a byte that cannot
be part of a well-formed sequence becomes U+FFFD. Valid text — including CJK and
emoji — is passed through untouched and costs one scan. The user sees a
replacement character in a copyright line instead of a feature that does not
work.

The same fault would have hit hover, the outline and diagnostics on those files.
It was invisible until a request happened to draw text from 155 files at once.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean, everything linked `-mt`. **1,035 assertions**, all passing.

The workspace suite gained 29 assertions over the graph, all against synthetic
files — `IndexText` takes the text, and resolution is lexical, so a graph can be
described in the test without writing anything to disk:

- a chain three deep: the visible set is transitive, and directed;
- **a cycle terminates** and lists each file once, which is what `#include once`
  exists for;
- an edge to nowhere leaves the file marked and its visible set at one;
- a forward slash and the wrong case still resolve;
- a search path resolves what the includer's directory cannot;
- two files declare `Thing`, and the one that is **visible** is the one found;
- and the real fixture: widgets.bas → shared.bi, on line 1, one way only.

The piped session gained 15, against a real process: a jump along an
`#include`, a scope completion carrying the included type and constant (in sort
group 4, with the file's own locals still there), and `w.` offering the fields of
a type declared in the other file — with no keywords in a member context.

The JSON suite gained 11 for the UTF-8 fault: a Latin-1 byte, a truncated
sequence, and valid CJK and emoji that must survive untouched.

### Not verified

- **`-i` paths.** The server never learns them. Step 3 covers the common case
  by name; an include that needs a real search path and whose file name is not
  unique stays unresolved.
- **Conditional includes.** A directive inside a `#if` branch is an edge like
  any other: this server does not evaluate conditionals, so a platform header
  counts as visible in every configuration. The honest reading is "visible in
  some build".
- **Macro-built include paths** are not edges at all — `#include SOME_MACRO`
  needs a preprocessor.
- **Rename's narrowing is verified at the index level, not on the wire**: the
  fixture has two files, so the narrowed and unnarrowed sets are the same there.
- **Linux and macOS**, still.
