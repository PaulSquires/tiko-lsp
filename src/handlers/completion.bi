'' ############################################################################
''  handlers/completion.bi -- textDocument/completion
'' ############################################################################

#pragma once

#include once "../lsp/dispatcher.bi"

'' What a file can see for TYPE NAMES: its includes, transitively, and its
'' #imports -- each imported module's files and what those can see.
declare sub VisibleWithImports( byref srv as Server, byval here as long, _
                                byref out_ as containers.Array( of long ) )

'' The type a type NAME finally stands for, lower-cased: aliases are followed
'' among `visible` (`TrkVoidResult` -> `result`, `Logger` -> `logger_`), at most
'' eight hops. The name itself when it is no alias.
declare function FinalTypeName( byref srv as Server, byref visible as containers.Array( of long ), _
                                byref typeName as string ) as string

'' THE MEMBER A CHAIN REACHES: `lowerName` after the dot token `dotIdx`, where
'' what stands left of the dot -- `lg`, `lg.Warn( ).Str( k, v )`, `f( )` -- is
'' resolved to a type a link at a time, as member completion does. `count` is
'' the size of the member's overload set; `preferTyped` picks the overload with
'' a type over the first declared. The index must be built.
declare function ResolveChainMember( byref srv as Server, byval doc as TextDocumentPtr, _
                                     byval dotIdx as long, byref lowerName as string, _
                                     byval preferTyped as boolean, byref sym as SymbolInfo, _
                                     byref count as long ) as boolean

declare sub RegisterCompletionHandlers( )
