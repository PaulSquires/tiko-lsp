'' ############################################################################
''  handlers/workspace_symbols.bi -- workspace/symbol, and building the index
'' ############################################################################

#pragma once

#include once "../lsp/dispatcher.bi"

declare sub RegisterWorkspaceHandlers( )

'' Starts the workspace scan ON A WORKER THREAD and returns at once. Called
'' from the `initialized` notification, and again when the client adds or
'' removes a folder.
declare sub StartWorkspaceIndex( byref srv as Server )

'' WAITS for a scan that is still running and adopts its result.
''
'' Every request that needs cross-file knowledge calls this first, and nothing
'' else does -- that split is the whole design: typing, diagnostics, hover,
'' completion and the outline are answered from the open buffer and never wait
'' for a scan they do not need. See index_builder.bi.
''
'' Cheap and idempotent after the first call: with no build pending it does
'' nothing at all.
declare sub EnsureWorkspaceIndex( byref srv as Server )
