'' ############################################################################
''  handlers/watched_files.bi -- workspace/didChangeWatchedFiles
''
''  What this fixes: the index describing a file that no longer exists, or
''  missing one that appeared. A branch switch, a `git pull`, a build step that
''  generates a header -- none of them goes through the editor, so none of them
''  produces a didOpen or a didChange, and until now the index simply went
''  stale until the server was restarted.
''
''  THE SERVER DOES NOT WATCH ANYTHING ITSELF. Walking a tree for changes costs
''  a thread and a wakeup budget, and every editor already has a watcher tuned
''  to its platform. LSP's answer is to ask the client to do it -- which is why
''  registering is a request rather than a capability, and why a client that
''  cannot register leaves this feature switched off rather than half-working.
'' ############################################################################

#pragma once

#include once "../lsp/dispatcher.bi"

declare sub RegisterWatchedFilesHandlers( )

'' Asks the client to watch the workspace for FreeBASIC source files. Called
'' from `initialized`, and only when the client offered dynamic registration.
declare sub RequestFileWatching( byref srv as Server )
