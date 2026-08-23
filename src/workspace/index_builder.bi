'' ############################################################################
''  workspace/index_builder.bi -- the workspace scan, off the message loop
''
''  THE PROBLEM THIS SOLVES. Phase 6 built the index inside the `initialized`
''  notification: 4.3 seconds on a 4,000-file tree, during which the server
''  read nothing from its input. The editor's first keystrokes, its first
''  hover, its first completion -- all queued behind a scan that none of them
''  needed. The user sees a language server that is dead on arrival.
''
''  THE SHAPE OF THE FIX. A worker thread scans and indexes into an index OF
''  ITS OWN, and the message loop keeps reading. Nothing is shared while the
''  work is happening: the worker never touches the open documents, never
''  writes to the protocol stream, and never looks at the live index. The only
''  state crossing threads is a cancellation flag and, at the end, one pointer.
''
''  A POINTER, not a copy. The result is handed over by adopting the worker's
''  index wholesale. Copying it would mean duplicating a quarter of a million
''  symbols on the message loop -- trading a four-second stall for a
''  hundred-millisecond one, which is the same bug with a smaller number.
''
''  WHO WAITS. A request that needs cross-file knowledge -- workspace/symbol,
''  references, rename, a definition this file cannot answer -- waits for the
''  build to finish, because there is no honest answer before it. Everything
''  else -- typing, diagnostics, hover, completion, the outline, formatting --
''  never waits, and that is the whole point: those are the requests a user
''  makes in the first seconds after opening an editor.
'' ############################################################################

#pragma once

#include once "workspace.bi"
#include once "symbol_index.bi"

'' Starts a background build over `roots` (native paths). Any build already
'' running is cancelled and joined first, so there is never more than one.
declare sub StartIndexBuild( byref roots as PathArray )

'' Starts a background REFRESH of specific files -- what a burst of watched-file
'' changes turns into. The result is a small index holding only those files,
'' meant to be merged into the live one rather than to replace it.
''
'' The alternative was to re-scan the whole workspace, which is simpler and
'' measurably worse: on a 2,000-file workspace a 200-file refresh costs the
'' next cross-file request about 0.7 s against 2.9 s for a full re-scan, and
'' re-reading 1,800 files nothing said anything about is work for its own sake.
declare sub StartIndexRefresh( byref paths as PathArray, byref roots as PathArray )

'' True when what is pending -- or waiting to be taken -- is a REFRESH rather
'' than a whole-workspace build. It decides whether the caller adopts the
'' result or merges it.
declare function IndexBuildIsRefresh( ) as boolean

'' True while a build is running or finished-but-not-yet-taken.
declare function IndexBuildPending( ) as boolean

'' True when the worker has FINISHED and its result is only waiting to be
'' collected. It is what lets a request that must never block -- completion,
'' which runs on every keystroke -- use the index the moment it is ready
'' without ever waiting for it to become so.
declare function IndexBuildReady( ) as boolean

'' WAITS for the running build and hands over its index. The caller OWNS the
'' returned pointer and must `delete` it. Returns 0 when there was no build to
'' take -- which is the normal case for every request after the first.
''
'' `summary` comes back with the line to log: files, symbols, milliseconds.
declare function TakeIndexBuild( byref summary as string ) as SymbolIndex ptr

'' Asks a running build to stop and waits for it. The partial index is thrown
'' away. Cancellation is checked between FILES and between FOLDERS, so a
'' single enormous directory walk still has to finish -- about a second on a
'' 4,000-file tree.
declare sub CancelIndexBuild( )

'' Releases the worker's mutex. Called once, at process exit.
declare sub ShutdownIndexBuilder( )
