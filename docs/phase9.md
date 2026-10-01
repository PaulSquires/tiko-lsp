# Phase 9 — files changed behind the editor's back

`git checkout`, `git pull`, a build step that writes a header: none of them goes
through the editor, so none of them produces a `didOpen` or a `didChange`. Until
now the index simply went stale — it kept answering with symbols from a file that
no longer existed, and knew nothing about one that had appeared — until the
server was restarted.

## Delivered

| Requirement | Where |
| --- | --- |
| `client/registerCapability` (server → client) | `src/handlers/watched_files.bas` — `RequestFileWatching` |
| `workspace/didChangeWatchedFiles` | `src/handlers/watched_files.bas` |
| a request from the server | `Server.SendRequest`, `RpcBuildRequest` |
| capabilities | **none** — see below |

## The server does not watch anything

Walking a tree for changes costs a thread and a wakeup budget, and every editor
already has a watcher tuned to its platform — ReadDirectoryChangesW, inotify,
FSEvents. LSP's answer is to ask the client to do it, and that is why there is
**no static capability** for this feature: a server that wants file events has to
register for them at run time, and only a client offering
`workspace.didChangeWatchedFiles.dynamicRegistration` will accept the
registration.

So this is the first request this server has ever *sent*:

```json
{"id":"tiko-1","method":"client/registerCapability","params":{"registrations":[
  {"id":"tiko-watched-files","method":"workspace/didChangeWatchedFiles",
   "registerOptions":{"watchers":[{"globPattern":"**/*.{tko,ti,bas,bi,inc}","kind":7}]}}]}}
```

Three details worth naming:

- **The id is a string.** The client numbers its own requests and the server
  numbers its own; they are separate spaces. `"tiko-1"` can never be mistaken for
  the client's `1` — in a log, in a test, or in a client that matches replies
  against its own table.
- **Nothing waits for the answer.** There is nothing to do differently if the
  client accepts late, and nothing at all to do if it never answers. The reply is
  logged and dropped — and the dispatcher had to learn not to answer it, because
  replying to a response with `MethodNotFound` is a protocol violation that
  confuses a client into matching an error against its own request table.
- **A client that cannot register leaves the feature off**, with one line in the
  log saying so. Half-working here would mean an index that is current for some
  events and not others, which is worse than one that is honestly only as current
  as the last scan.

The registration is sent from `initialized`, **before** the workspace scan is
started. A file changed while the scan runs then produces a notification the
server can act on, rather than falling into the gap between "scanned" and
"watched".

## What a notification does

| Event | Action |
| --- | --- |
| Created, Changed | re-index the file from disk |
| Deleted | drop it from the index |
| anything that is not `.tiko`, `.tko`, `.ti`, `.bas`, `.bi`, `.inc` | ignore |
| a path under `.git` and friends | ignore |
| **a file the editor has open** | **ignore** |

The last row is the rule the whole server is built on: the buffer is the truth.
Re-reading the disk copy of an open file would replace what the user can see with
what was last saved — and for the case that motivates this feature, a branch
switch under an open editor, it is the *editor* that decides what to do and tells
us in a `didChange`.

A client may watch more than it was asked to — some send every change under the
workspace root regardless of the glob — so the filter is applied again on this
side rather than trusted.

**While a scan is in flight, changes are dropped.** The worker reads each file as
it reaches it, so whatever the notifications describe is what it will find; and
anything applied to the live index in the meantime would be thrown away when the
fresh one is adopted. That is not a shortcut, it is the only version that cannot
go stale.

## A burst goes to the worker

A `git checkout` across a branch does not report three files; it reports
hundreds or thousands. Applied one at a time on the message loop, at the 1–3 ms
it costs to re-index one file into a large index, that is **a frozen editor for
about a second per thousand files** — which is the very thing phase 8 was about.

So a notification is now planned before it is acted on:

1. **Filter**, as before: only `.tiko`/`.tko`/`.ti`/`.bas`/`.bi`/`.inc`, nothing under `.git`, and
   nothing the editor has open.
2. **Collapse.** One checkout reports the same file more than once — deleted
   then created, changed twice — and only the last word about it matters. Files
   are keyed exactly as the index keys them, so one file counts once however the
   client spelled its URI.
3. **Count.** Up to **100 distinct files**, apply them here: that is a hiccup of
   100–200 ms at worst, measured. Beyond that, the reading goes to the worker
   and the deletions — which read nothing — are applied immediately.

The worker re-indexes **only the named files** into a small index of its own,
and the result is **merged** into the live one (`SymbolIndex.Absorb`) when the
next request that needs the index takes delivery. That is the difference from a
whole-workspace scan, and it is the difference between 0.7 s and 2.9 s for the
next cross-file answer on a 2,000-file workspace — re-reading 1,800 files that
nothing said anything about is work for its own sake.

**A file that could not be read keeps what the index already knew.** A watcher
that reports a file which is gone by the time the worker gets there must not
delete that file's symbols; the refresh simply has no entry for it, and merging
cannot remove one.

Two rules follow from having two kinds of background job:

- a **full scan** in flight still means the batch is dropped, because the scan
  reads every file anyway;
- a **refresh** in flight does not, because it covers only the files it was
  given. The second burst waits for the first refresh to land before planning
  its own — measured at about 200 ms for a 200-file refresh, and the only case
  in which a burst blocks the loop at all.

### Measured

Time until a `hover` — which needs nothing but the open buffer — is answered
after a burst arrives, over a live pipe. AfxNova, 2,093 indexed files.

| Burst | hover before | hover now | next `workspace/symbol` before | now |
| --- | --- | --- | --- | --- |
| 200 files | 112 ms | **5 ms** | 191 ms | 209 ms |
| 1,000 files | 724 ms | **26 ms** | 812 ms | 688 ms |

On `C:\dev\tiko` (4,000 files), a 1,000-file burst answers a hover in 34 ms and
the following `workspace/symbol` in 711 ms. Two 200-file bursts sent back to
back answer in 218 ms, which is the second one waiting for the first.

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean, everything linked `-mt`. **979 assertions**, all passing — twelve suites,
of which the piped session grew to **184**.

The session now runs the whole round trip against a real process:

- the server sends `client/registerCapability` immediately after `initialized`,
  with the right glob and `kind` 7, and a string id;
- the scripted client answers it, and that answer produces **no output** —
  responses are not answered;
- `shared.bi` is reported **deleted**, and `workspace/symbol "widget"` stops
  offering anything from it;
- a second batch reports `shared.bi` created, a `.txt` file created, and
  `widgets.bas` — which is **open** — changed. The trace says `1 re-indexed,
  2 ignored`, and the picker offers `shared.bi` again.

And then a **burst**: 120 invented files, plus `shared.bi`, plus the open
`widgets.bas`. The trace says `121 change(s)` — the open file was filtered out
before counting — and `121 re-indexed in the background`; the refresh reports
`re-indexed 1 of 121 file(s) (120 unreadable)`; and `shared.bi` is still in the
workspace picker afterwards, because a file that could not be read keeps what
the index knew.

Forty-five messages, and exactly forty-five: the count is asserted, so a stray
notification or a reply to the client's response would fail the suite rather than
pass unnoticed.

### Not verified

- **A real editor's watcher.** Whether VS Code, Zed or Neovim actually honours
  `**/*.{tko,ti,bas,bi,inc}` and sends what this expects is untested here; the session
  drives the protocol, not an editor.
- **Linux and macOS**, still.
- **Rename and move events.** LSP has no rename event: a client reports a move as
  a delete plus a create, and this server treats it as exactly that. There is
  also `workspace/willRenameFiles`, which is a different feature and is not
  claimed.
- **`unregisterCapability`.** The registration is made once and never withdrawn.
  Its id is fixed (`tiko-watched-files`) so it *could* be, but nothing does.
- **A queue for overlapping bursts.** A burst arriving while a refresh is still
  running waits for it on the message loop — 200 ms for a 200-file refresh, the
  one case where a burst blocks anything. Queuing the second batch instead is
  the obvious next step and is not done.
- **The merge cost is not separately measured.** `Absorb` copies one entry per
  refreshed file into the live index, on the request that takes delivery; at
  1,000 files it is inside the 688 ms above, but it has not been isolated.
- **No debounce.** Ten notifications of ten files each are ten small batches,
  not one of a hundred: nothing waits to see whether more is coming.

## Next

What a file can actually see -- [phase10.md](phase10.md).
