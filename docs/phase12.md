# Phase 12 — `#cinclude`: C headers, through the compiler

`#cinclude "raylib.h"` (tiko-lang ADR 0016) imports a C header: tiko runs libclang over it
and compiles the FreeBASIC binding it writes. The lexer already saw the line as one
preprocessor token, and the parser skipped it — so a raylib program got no completion,
hover, signature help or definition for a single raylib name.

This server cannot read C. It does not have to: it asks the compiler where the binding is,
and indexes that like any `#include`d header.

## Delivered

| | Where |
| --- | --- |
| reading the directive | `FindCIncludes`, `src/analysis/includes.tiko` |
| `#cinclude` edges in the include graph (`IncludeEdge.IsC_`) | `src/workspace/symbol_index.tiko` |
| asking the compiler, the binding store | `src/workspace/cincludes.tiko` |
| running it on the worker, full build and refresh | `src/workspace/index_builder.tiko` |
| go to definition **on** the header path | `src/handlers/definition.tiko` |
| the compiler's side: `tiko --print-cincludes` | tiko-lang e23b4080 |

No new capability: the binding is a header like any other, so completion, hover, signature
help and definition reach it through the include graph exactly as phase 10 built it.

## The compiler is asked, and only on the worker

The author amended the "no compiler subprocess for analysis" rule for this on 2026-10-13
(it had already been amended for `tiko metadata`). With `initializationOptions.compilerPath`
set, the worker runs

    tiko --print-cincludes [-i <include dir>]... <file>

for each file that itself holds a `#cinclude`, in the package's directory (the working
directory is part of tiko's cache key, so this is what shares a build's cached bindings),
else the file's own. The compiler preprocesses the file, imports each `#cinclude` exactly as
a build does — the same disk cache, the same delta chain, `#cmdline` honoured — and prints

    {"format":1,"cincludes":[{"file","line","header","binding"[,"error"]}...]}

A header that cannot be imported has no binding and an `error`, which is logged; the exit
is then 1, and the rest of the answer is still taken.

A cold import of windows.h is ~19 s and a warm one well under a second, so this never runs
on the message loop. The limit is 120 s, for a compiler that hangs.

**One query per file, not per unit root.** A `.bi` with a `#cinclude` is asked as its own
root, so it gets its WHOLE binding — a build including it after another `#cinclude` would
get a delta. For a server answering "what can this file see", the whole binding is the
better answer.

## Resolution: by lookup, never by path

A `#cinclude` edge is never resolved the way an `#include` is — the C header is not a file
this server can index, and is never read. `ResolveIncludes` looks the pair (includer,
header) up in the store `LoadCIncludes` filled and points the edge at the indexed binding:
a mutex, a map probe and a hash probe, safe on the message loop. Until the worker has asked,
the edge is unresolved, which leaves the file's visible set a lower bound — "maybe
everything", as any unplaceable include.

The worker's order is: every file; the graph (which reads the toolchain headers, so a header
that itself `#cinclude`s is found); the `#cinclude`s; the graph again (which points the new
edges and reads what each binding `#include`s, `crt/long.bi`).

A binding is indexed as an **external** file, like a toolchain header: never renamed into,
never searched for references, kept out of `workspace/symbol`. It is read with its own size
cap (256 MB) — windows.h's binding is several times a source file's 4 MB.

## Not handled

- **`#define` macros in a binding are not offered** — raylib's colours (`LIGHTGRAY`, a
  `#define ... type<Color>(...)`) among them. This server does not index object-like macros
  anywhere; that is a limit of its symbol model, not of `#cinclude`.
- A `#cinclude` typed into an open buffer resolves when the file is saved (the refresh worker
  asks again) or at the next full build, not as it is typed.
- The compiler is asked with the host target and no `-cinclude`/`-cdefine` beyond what the
  file's own `#cmdline` gives; a `tiko.toml` target that adds them is not consulted.

## Verified

- `tests/test_workspace.tiko`, group `#cinclude` (20 assertions): edges with and without a
  compiler, the binding external, definition and parameters through it, a failed header, a
  compiler that cannot run. `tests/fake_tiko` answers `--print-cincludes` from a fixture.
- The `#cinclude` piped session against the real server, and its no-compiler control.
- By hand, the real packaged tiko over raylib: completion after `Draw` and `KEY_`, signature
  help and hover on `DrawText`, definition on `DrawText` and on the header path into the
  cached `binding.bi`.
