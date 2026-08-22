'' ############################################################################
''  utils/uri.bi -- file: URI <-> filesystem path
''
''  The protocol identifies every document by URI. The compiler frontend will
''  want a path. The conversion is not as simple as chopping off "file://":
''
''      file:///c%3A/dev/x.bas   ->  C:\dev\x.bas      (percent-decoded drive)
''      file:///c:/dev/x.bas     ->  C:\dev\x.bas      (some clients do not encode)
''      file:///home/u/x.bas     ->  /home/u/x.bas
''      file://server/share/x    ->  \\server\share\x  (UNC, Windows only)
''
''  THE URI IS THE IDENTITY. A document is stored, looked up and answered under
''  the exact URI string the client sent; the path is a derived convenience and
''  is never used as a key. Two spellings of one file are two documents as far
''  as the protocol is concerned, and pretending otherwise loses edits.
'' ############################################################################

#pragma once

'' True if `uri` begins with a scheme this server can turn into a path.
declare function UriIsFile( byref uri as string ) as boolean

'' Returns the scheme ("file", "untitled", "git", ...) or "" if there is none.
'' Untitled and VCS-provided documents are legal and common: they have no path.
declare function UriScheme( byref uri as string ) as string

'' file: URI -> native path. Returns "" for a non-file URI, which the caller
'' must treat as "this document has no path", not as an error.
declare function UriToPath( byref uri as string ) as string

'' Native path -> file: URI. Backslashes become forward slashes, a drive letter
'' gets the leading slash, and every byte outside the unreserved set is
'' percent-encoded.
declare function PathToUri( byref path_ as string ) as string

'' Percent-decoding on its own, exposed because it is worth testing directly.
declare function UriDecode( byref s as string ) as string
declare function UriEncodePath( byref s as string ) as string

'' The last segment of a URI's path, for log lines and window titles.
declare function UriFileName( byref uri as string ) as string
