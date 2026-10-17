# Phase 1 — LSP foundation

What was built, what it does message by message, and what was actually verified.

## Delivered

| Requirement | Where |
| --- | --- |
| project structure | `src/{json,rpc,lsp,handlers,utils}`, `tests/`, `build/`, `docs/` |
| `main.bas` | argument parsing, the message loop, exit codes |
| stdin/stdout transport | `src/rpc/transport.tiko` — `StdioTransport` |
| `Content-Length` parsing | `src/rpc/transport.tiko` — `MessageFramer` |
| JSON-RPC request/notification handling | `src/rpc/jsonrpc.tiko`, `src/lsp/dispatcher.tiko` |
| `initialize` / `initialized` / `shutdown` / `exit` | `src/handlers/lifecycle.tiko` |
| logging to stderr or a file | `src/utils/logging.tiko` |
| build instructions, Windows and Linux | `build/`, and the README |
| a piped-message test | `tests/session_tool.tiko` |

Extras that were cheap and belong to the same state machine: `$/setTrace`,
`$/cancelRequest`, and `window/logMessage` in the outgoing direction.

## Behaviour, message by message

**`initialize`** records `processId`, `clientInfo`, `rootUri`, `trace`,
`workspaceFolders` and the offered `positionEncodings`. A client that sends only
`rootUri` gets it normalised into a one-entry folder list, so phase 6 has a single
shape to walk. The reply is:

```json
{ "capabilities": {}, "serverInfo": { "name": "tiko-lsp", "version": "0.1.0" } }
```

Empty capabilities is the honest answer for a server with no document store — see
the note in `LspBuildCapabilities`.

**`initialized`** is acknowledged with a `window/logMessage` notification, which is
also the cheapest end-to-end proof that the server-to-client direction works.

**`shutdown`** releases the recorded workspace state, moves to `SRV_SHUTDOWN` and
returns `null` — as a present `"result": null`, not an absent member.

**`exit`** ends the loop. Exit code 0 if `shutdown` was received first, 1 otherwise.

Everything else is refused by the rules in
[architecture.md](architecture.md#the-lifecycle-rules).

## Framing

`MessageFramer` is a byte-level state machine, deliberately separate from the
stream so it can be tested without a process:

- headers end at CRLFCRLF, and bare LFLF is accepted as well;
- header names are case-insensitive, values may be padded;
- `Content-Type` and any unknown header are ignored, not fatal;
- a missing, empty or non-numeric `Content-Length` is a hard error — the stream
  cannot be resynchronised, so the server stops rather than guessing;
- `Content-Length` above 64 MB is refused instead of allocated;
- the byte count is authoritative: a payload containing a blank line is never
  re-scanned for headers;
- a partially arrived message keeps its parsed header cached, so a message
  delivered one byte at a time is not re-parsed on every byte;
- the buffer is compacted once the consumed prefix passes 64 KB and is at least
  half the buffer.

On Windows, stdin and stdout are switched to binary mode (`_setmode`) before
anything is read or written. Without it the CRT rewrites CRLF and any UTF-8 byte
that happens to be 0x0A or 0x1A.

## Verification

Run: `build\_run_tests.bat` on Windows 11, fbc-modern 1.20.0 (win64), gas64 backend.

| Suite | Result |
| --- | --- |
| framing (`test_framing.exe`) | 41 assertions, all passed |
| json + jsonrpc (`test_json.exe`) | 110 assertions, all passed |
| piped session (real `tiko-lsp.exe` over a pipe) | 32 assertions, all passed |

The build is warning-free with `-w all`.

Checked by hand as well:

- `printf '' \| tiko-lsp` — stdin closed with no `exit` exits **1**;
- the scripted session exits **0**;
- `--version` and `--help` print to stderr and exit 0; an unknown option exits 2;
- `bin/server.log` after a session contains the full INFO trail and stdout contains
  only protocol bytes.

### Not verified

- **Linux and macOS.** Neither `_compile.sh` nor `_build_yyjson_linux.sh` has been
  run; they are written from the Windows build and the yyjson build script, and the
  only platform-specific code in the server is the `_setmode` pair. Treat the Linux
  path as untested until someone runs it.
- **A real editor.** No Zed, VS Code, Neovim or Helix session has been driven
  against this binary. The transport is verified against a byte-exact scripted
  session, which is not the same as an editor's timing and framing.
- **Very large payloads.** The framer is tested to 5000 small messages and against
  a refused 100 GB `Content-Length`, but no multi-megabyte `didOpen` has been run
  through it — there is nothing to send one to until phase 2.
- **Memory.** No leak checker has been run. Ownership is single-owner throughout
  and the destructors are in place, but that is an argument, not a measurement.

## Next: phase 2

`textDocument/didOpen` / `didChange` / `didSave` / `didClose`, a `TextDocument`
with a line index, and `utils/position.tiko` as the single home for
UTF-16-to-byte-offset conversion. `textDocumentSync` becomes the first entry in
`LspBuildCapabilities` — after the document store works, not before.
