'' ############################################################################
''  handlers/completion.bi -- textDocument/completion
'' ############################################################################

#pragma once

#include once "../lsp/dispatcher.bi"

'' What a file can see for TYPE NAMES: its includes, transitively, and its
'' #imports -- each imported module's files and what those can see.
declare sub VisibleWithImports( byref srv as Server, byval here as long, _
                                byref out_ as FB.Array( of long ) )

'' The type a type NAME finally stands for, lower-cased: aliases are followed
'' among `visible` (`TrkVoidResult` -> `result`, `Logger` -> `logger_`), at most
'' eight hops. The name itself when it is no alias.
declare function FinalTypeName( byref srv as Server, byref visible as FB.Array( of long ), _
                                byref typeName as string ) as string

declare sub RegisterCompletionHandlers( )
