# Phase 8 — off the message loop

The phase that fixes the one structural problem the first seven left behind,
and — by finally driving the server the way an editor does — the one bug that
mattered more than all of them.

## What was wrong

Phase 6 built the workspace index inside the `initialized` notification. On a
4,000-file tree that is **five seconds during which the server reads nothing**:
the editor's first keystrokes, its first hover, its first completion request all
sit in the pipe behind a scan that none of them needed. A language server that
does that looks broken, and the user cannot tell the difference between slow and
hung.

## What changed

A worker thread scans and indexes into an index **of its own**, and the message
loop keeps reading. Nothing is shared while the work happens: the worker never
touches the open documents, never writes to the protocol stream, and never looks
at the live index. The only state crossing threads is a cancellation flag and,
at the end, one pointer.

| | Before | After |
| --- | --- | --- |
| workspace scan | inside `initialized` | worker thread, started there |
| who waits | every message behind it | only requests that need cross-file knowledge |
| result handover | — | one pointer, adopted whole |

**A pointer, not a copy.** `Server.Index` became a `SymbolIndex ptr` so the
worker's index can be adopted wholesale. Copying it would duplicate a quarter of
a million symbols on the message loop — trading a five-second stall for a
hundred-millisecond one, which is the same bug with a smaller number.

### Who waits, and who does not

| Request | Waits for the scan? |
| --- | --- |
| `didOpen` / `didChange` / `didSave` / `didClose`, diagnostics | no |
| hover, completion, document symbols, signature help, semantic tokens, inlay hints, formatting, code actions | no |
| definition **answered from the open file** | no |
| definition that has to fall back to the workspace | yes |
| `workspace/symbol`, references, rename | yes |

Everything in the first two rows is what a user does in the first seconds after
opening an editor. Everything that waits, waits because there is no honest
answer before the scan is finished — a rename that silently skipped half the
workspace because it was asked early would be the worst bug this server could
have.

The scan is delivered at the first request that needs it, which is also when its
`window/logMessage` summary appears. That makes the ordering deterministic —
the piped session asserts the summary arrives immediately before the first
cross-file answer, thirteen messages after the scan was started — and it means a
client is never told about work it did not ask for.

**The open buffers go on top.** The worker indexed what is on disk, because it
must not touch documents the message loop owns; when the loop adopts the result
it re-indexes every open document over it. A buffer edited during the scan
therefore wins, which is the rule everywhere else in this server.

## The bug that mattered more

While measuring this, the server was driven over a **live pipe** for the first
time — a real process, messages written one at a time, the pipe kept open, as an
editor does it. It hung on `initialize`.

```freebasic
fread( @chunk(0), 1, READ_CHUNK_BYTES, stdin )
```

`fread` does not return until it has the full count **or the stream ends**. Every
test in this repository feeds the server a FILE, where the end arrives at once,
so every test passed — 934 assertions, including a piped-session suite that
drives the real executable. An editor is not a file: it sends `initialize`, keeps
the pipe open, and waits. The server sat inside `fread` waiting for 65,000 bytes
that were never coming.

The fix is `read()` on the file descriptor, which returns as soon as any bytes
are available — which is what the framing state machine was written to expect all
along. The framing was never the problem; the call that fed it was.

There is now a test that reads from a pipe **with the writing end still open**,
on a worker thread with a two-second deadline, because the failure mode is a hang
and a suite that hangs tells you less than one that fails. It fails against the
old transport and passes against the new one.

**The lesson, in one line: a test that feeds a file cannot tell you the server
works with an editor.**

## The other race

The first async build indexed the fixture workspace to **two files and zero
symbols**. No crash, no diagnostic, nothing in the log.

The lexer's keyword table was built on first use:

```freebasic
if( g_KeywordsReady ) then exit sub
g_KeywordsReady = true
```

Correct for exactly as long as this server was single-threaded. Two threads
lexing at once both reach the guard; one sets the flag and starts filling the
map, the other sees the flag and reads an **empty** table — so no word in the
language is a keyword, no statement opens a block, and every file indexes to
nothing.

Both that table and the two mutexes the server now owns are built in **module
constructors**, which run while the program is still single-threaded. That
removes the race rather than locking against it: a lock in `KeywordOf` would sit
on the hottest path in the lexer, one acquisition per token.

`ReadSourceFile` did need a lock. `freefile` returns a number that is free *right
now*, and between that and the `open` that claims it the other thread can be
handed the same one — so the two calls are made under a mutex. The read itself is
not serialised.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean, everything linked `-mt`. **953 assertions**, all passing:

| Suite | Assertions |
| --- | --- |
| **framing** | **43** |
| json + jsonrpc | 110 |
| position | 64 |
| uri + document | 88 |
| analysis | 157 |
| symbols | 74 |
| completion | 63 |
| **workspace** | **78** |
| signature | 53 |
| semantic tokens | 32 |
| formatting | 33 |
| piped session (real process) | 158 |

New: the live-pipe read (framing), and fourteen assertions over the background
build — that its result matches a synchronous scan file for file and symbol for
symbol, that a cancelled build hands back nothing, that taking with nothing
pending is a no-op, and that **200 analyses on the main thread while the worker
runs all produce the right symbols**. That last one can only ever be evidence
rather than proof — a race that has been fixed cannot be observed — but it is
the exact shape of the failure that was shipped and caught.

### Performance

Time from process start until the answer reaches the client, both builds linked
`-mt` so the comparison is the design and not the runtime. Warm file cache.

| Workspace | Files | hover — phase 7 | hover — now | `workspace/symbol` — phase 7 | now |
| --- | --- | --- | --- | --- | --- |
| tiko-lsp | 65 | 84 ms | **12 ms** | 86 ms | 85 ms |
| AfxNova | 179 | 2,761 ms | **11 ms** | 2,837 ms | 2,694 ms |
| C:\dev\tiko | 4,000 (capped) | 5,001 ms | **11 ms** | 5,115 ms | ~4,700 ms |

The first answer now costs the same on a 4,000-file workspace as on a 65-file
one. The request that genuinely needs the scan still pays for it, and always
will.

One honest cost: the multithreaded runtime is not free. The same phase-7 code
rebuilt with `-mt` indexes `C:\dev\tiko` in 5.0 s against 3.9 s without it —
about 25% slower, in thread-safe allocation, on the most allocation-heavy work
this server does. That is the price of the row above, and it is paid where a
user is not watching.

### Not verified

- **Linux and macOS**, still — and the read path is now platform-split
  (`_read` / `read`), so there is one more thing there that has never been run.
- **A real editor**, still. The live-pipe driver used for the measurements above
  is not an editor; it is a Python script that behaves like one.
- **Cancellation mid-walk.** A build is cancelled between files and between
  folders, so one enormous directory walk still has to finish — about a second on
  a 4,000-file tree, paid at shutdown.
- **Per-document analysis is still on the message loop**, deliberately: it is
  1 ms for 900 lines and 10 ms for 8,600, and the answer to the request in hand
  depends on it. Moving it would buy a millisecond and cost a debounce, a
  cancellation protocol and a class of stale-answer bugs.
- **Nothing is cancellable.** `$/cancelRequest` is still ignored; a rename over a
  large workspace runs to completion whatever the client does.
