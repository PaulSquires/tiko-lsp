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
   "registerOptions":{"watchers":[{"globPattern":"**/*.{bas,bi,inc}","kind":7}]}}]}}
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
| anything that is not `.bas`, `.bi`, `.inc` | ignore |
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

## Verification

`build\_run_tests.bat`, Windows 11, fbc-modern 1.20.0 (win64), gas64, `-w all`
clean, everything linked `-mt`. **969 assertions**, all passing — twelve suites,
of which the piped session grew to **174**.

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

Forty-two messages, and exactly forty-two: the count is asserted, so a stray
notification or a reply to the client's response would fail the suite rather than
pass unnoticed.

### Not verified

- **A real editor's watcher.** Whether VS Code, Zed or Neovim actually honours
  `**/*.{bas,bi,inc}` and sends what this expects is untested here; the session
  drives the protocol, not an editor.
- **Linux and macOS**, still.
- **Rename and move events.** LSP has no rename event: a client reports a move as
  a delete plus a create, and this server treats it as exactly that. There is
  also `workspace/willRenameFiles`, which is a different feature and is not
  claimed.
- **`unregisterCapability`.** The registration is made once and never withdrawn.
  Its id is fixed (`tiko-watched-files`) so it *could* be, but nothing does.
- **Bursts.** A `git checkout` across a large branch can produce thousands of
  events in one notification; each is re-indexed immediately, on the message
  loop, at roughly a millisecond per file. A debounce, or handing the batch to
  the worker, is the obvious next step and is not done.
