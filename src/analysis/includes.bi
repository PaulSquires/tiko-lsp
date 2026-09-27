'' ############################################################################
''  analysis/includes.bi -- what a file pulls in
''
''  One line of the token stream, read for one thing: the `#include` directives
''  and the path each one names. That is the raw material of the include graph
''  -- everything else about it (which file that path really is, what a file can
''  therefore see) belongs to the workspace, not to a single document.
''
''  WHAT IS AND IS NOT AN INCLUDE HERE:
''
''      #include once "shared.bi"     yes
''      #include "..\other.bi"        yes
''      #inclib "yyjson64"            NO -- a library, not a source file
''      #include SOME_MACRO           NO -- the path is not a literal, and
''                                    expanding it needs a preprocessor
''
''  A directive inside a `#if` branch IS reported. This server does not
''  evaluate conditionals, so `#ifdef __FB_WIN32__ / #include "win.bi"` counts
''  as an include -- the honest reading is "visible in some configuration", and
''  the alternative is to lose every platform-specific header in the workspace.
'' ############################################################################

#pragma once

#include once "fb/array.bi"
#include once "lexer.bi"

type IncludeRef
    Target  as string    '' the path as written, without its quotes
    Once_   as boolean   '' `#include once`

    '' The QUOTED literal, so a client can be told exactly what to highlight --
    '' and so "go to definition" on an include line has a range to answer with.
    Start_  as long      '' byte offset of the opening quote
    Length_ as long      '' in bytes, quotes included
end type

type IncludeRefArray as FB.Array( of IncludeRef )

'' ONE `#import "path" [as alias] [public]` LINE (tiko-lang ADR 0017; RFC-0001). The alias
'' is lower-cased -- names are compared that way -- and is the path's last segment when no
'' `as` is written.
type ImportRef
    Path_    as string
    Alias_   as string
    Public_  as boolean
    Start_   as long      '' byte offset of the opening quote
    Length_  as long      '' in bytes, quotes included
end type

type ImportRefArray as FB.Array( of ImportRef )

declare sub FindImports( byref text_ as string, byref tokens as TokenArray, _
                         byref out_ as ImportRefArray )

'' Every include directive in the token stream, in source order.
declare sub FindIncludes( byref text_ as string, byref tokens as TokenArray, _
                          byref out_ as IncludeRefArray )

'' The include whose path literal contains `offset`, or -1. This is what turns
'' a click on `#include "shared.bi"` into a jump to that file.
declare function IncludeAtOffset( byref includes_ as IncludeRefArray, byval offset as long ) as long
