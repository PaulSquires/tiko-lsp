'' ############################################################################
''  lsp/publish.bi -- turning diagnostics into notifications
''
''  This is the ONLY place a byte offset becomes an LSP range. The analyser
''  works in offsets, the protocol speaks in line + UTF-16 character, and the
''  conversion needs the document's line index -- so it happens here, once,
''  where all three are in scope.
'' ############################################################################

#pragma once

#include once "dispatcher.bi"
#include once "../analysis/diagnostics.bi"

'' Analyses `doc` and sends textDocument/publishDiagnostics for it.
''
'' Called after every change, INCLUDING when the result is empty: an editor
'' clears its squiggles when it receives an empty list, and never otherwise.
declare sub PublishDocumentDiagnostics( byref srv as Server, byval doc as TextDocumentPtr )

'' Sends an empty list for `uri`. Used on didClose, where the document is gone
'' but the editor may still be showing what we last said about it.
declare sub ClearDocumentDiagnostics( byref srv as Server, byref uri as string )
