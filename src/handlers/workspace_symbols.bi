'' ############################################################################
''  handlers/workspace_symbols.bi -- workspace/symbol, and building the index
'' ############################################################################

#pragma once

#include once "../lsp/dispatcher.bi"

declare sub RegisterWorkspaceHandlers( )

'' Scans every workspace folder and indexes what it finds. Called once, from
'' the `initialized` notification, and again when the client adds or removes a
'' folder. Reports what it did through window/logMessage as well as the log,
'' because a user watching an editor start deserves to know.
declare sub BuildWorkspaceIndex( byref srv as Server )
