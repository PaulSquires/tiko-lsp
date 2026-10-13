'' ############################################################################
''  workspace/workspace.bi -- finding the source files
''
''  The editor tells us the folders; this finds the tiko in them. It is
''  deliberately conservative: a language server that walks a network share or
''  a node_modules tree at startup looks hung, and the user cannot tell the
''  difference between slow and broken.
'' ############################################################################

#pragma once

#include once "fb/array.bi"

'' A container held as a FIELD must be a named instantiation.
type PathArray as FB.Array( of string )

'' Caps, so a scan of the wrong folder is slow rather than fatal.
const WS_MAX_FILES      = 4000
const WS_MAX_FILE_BYTES = 4 * 1024 * 1024

type WorkspaceScan
    Files     as PathArray   '' native paths, UTF-8
    Skipped   as long        '' unreadable, or over the size cap
    Truncated as boolean     '' the file cap was reached and the walk stopped
end type

'' .tiko, .tko and .ti, plus the legacy .bas, .bi and .inc, case-insensitively.
'' Nothing else is tiko source, and guessing wider means indexing build output.
declare function IsSourceFileName( byref name_ as string ) as boolean

'' True if any component of the path is a directory that should never be
'' indexed -- .git and friends.
declare function IsIgnoredPath( byref path_ as string ) as boolean

'' Appends every source file under `rootPath` to `scan`. Recursive, and safe
'' against symlink cycles because it does not follow directory symlinks.
declare sub ScanFolder( byref rootPath as string, byref scan as WorkspaceScan )

'' Resolves '.' and '..' and makes the path absolute, WITHOUT requiring it to
'' exist. Used to give one file one identity: `C:\dev\p\build\..\x.bas` and
'' `C:\dev\p\x.bas` are the same file and must not be indexed twice.
declare function NormalizePath( byref path_ as string ) as string

'' Reads a file as BYTES. Deliberately not ReadAllText: the analyser works in
'' UTF-8 byte offsets, and a decode-and-re-encode round trip would move them.
'' False for a file over `maxBytes`: a source is capped at 4 MB, a #cinclude binding is not
'' a source (windows.h's is larger), so cincludes.bi reads with its own cap.
declare function ReadSourceFile( byref path_ as string, byref outText as string, _
                                 byval maxBytes as longint = WS_MAX_FILE_BYTES ) as boolean
