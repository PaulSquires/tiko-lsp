'' ############################################################################
''  handlers/text_document.bi -- document synchronisation
''
''  didOpen / didChange / didSave / didClose. All four are NOTIFICATIONS: they
''  are never answered, and a failure inside one can only be logged.
'' ############################################################################

#pragma once

#include once "../lsp/dispatcher.bi"

declare sub RegisterTextDocumentHandlers( )
