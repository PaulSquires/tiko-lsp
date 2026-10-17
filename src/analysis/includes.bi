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

#include once "lexer.bi"

type IncludeRef
    Target  as string    '' the path as written, without its quotes
    Once_   as boolean   '' `#include once`
    '' `public #include` / `public #cinclude` in a module file (tiko-vendor RFC-0002 V1):
    '' the header travels with the module's interface, and its names reach every
    '' importer unqualified.
    Public_ as boolean

    '' The QUOTED literal, so a client can be told exactly what to highlight --
    '' and so "go to definition" on an include line has a range to answer with.
    Start_  as long      '' byte offset of the opening quote
    Length_ as long      '' in bytes, quotes included
end type

type IncludeRefArray as containers.Array( of IncludeRef )

'' ONE `#import "path" [as alias] [public] [link static|dynamic]` LINE (tiko-lang ADR 0017; RFC-0001). The alias
'' is lower-cased -- names are compared that way -- and is the path's last segment when no
'' `as` is written.
type ImportRef
    Path_    as string
    Alias_   as string
    Public_  as boolean
    '' `link static` / `link dynamic` (tiko-vendor RFC-0002 V4): "" when not written.
    Link_    as string
    Start_   as long      '' byte offset of the opening quote
    Length_  as long      '' in bytes, quotes included
end type

type ImportRefArray as containers.Array( of ImportRef )

declare sub FindImports( byref text_ as string, byref tokens as TokenArray, _
                         byref out_ as ImportRefArray )

'' ONE NAME A MODULE FILE `#export`s (tiko-lang RFC-0004 §6): a macro an importer writes as
'' `alias.NAME`, and never bare. Joined to the same file's `#define NAME body`, when there is
'' one: a std facade (RFC-0009) is `#define PathJoin FB.PathJoin` + `#export PathJoin`, and
'' the body is what hover and go-to-definition follow.
type ExportRef
    Name_      as string    '' as the `#define` writes it, else as `#export` does
    LowerName  as string
    Body       as string    '' the `#define`'s body as written, "" when there is none
    '' When the body is nothing but `A.B` -- a facade's every body -- A and B, lower-cased.
    TargetNs   as string
    TargetName as string
    Start_     as long      '' byte offset of the name in its `#define`, else in `#export`
    Length_    as long
end type

type ExportRefArray as containers.Array( of ExportRef )

declare sub FindExports( byref text_ as string, byref tokens as TokenArray, _
                         byref out_ as ExportRefArray )

'' Every include directive in the token stream, in source order.
declare sub FindIncludes( byref text_ as string, byref tokens as TokenArray, _
                          byref out_ as IncludeRefArray )

'' Every `#cinclude [once] "header.h"` (tiko-lang ADR 0016), in source order. The header is a
'' C file this server cannot read; the workspace asks tiko for the FreeBASIC binding it makes
'' of it (`tiko --print-cincludes`, workspace/cincludes.bi) and indexes THAT as the include.
declare sub FindCIncludes( byref text_ as string, byref tokens as TokenArray, _
                           byref out_ as IncludeRefArray )

'' The include whose path literal contains `offset`, or -1. This is what turns
'' a click on `#include "shared.bi"` into a jump to that file.
declare function IncludeAtOffset( byref includes_ as IncludeRefArray, byval offset as long ) as long
