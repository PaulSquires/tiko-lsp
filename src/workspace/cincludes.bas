'' ############################################################################
''  workspace/cincludes.bas -- what a `#cinclude` brings in. See cincludes.bi.
'' ############################################################################

#include once "cincludes.bi"
#include once "metadata.bi"
#include once "modules.bi"
#include once "../json/json.bi"
#include once "../utils/process.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"
#include once "fb/map.bi"

'' A COLD import of windows.h is ~19 s and a warm one well under one; the limit is
'' for a compiler that hangs, not for a slow header.
const CINCLUDE_TIMEOUT_MS = 120000

'' THE STORE: "<includer key>|<header, lower-cased>" -> the binding's path. Written by
'' AcceptCIncludes and ClearCIncludes, under g_cincMutex.
dim shared as any ptr g_cincMutex
dim shared as FB.Map( of string, string ) g_cincBinding

private sub InitCIncludeMutex constructor
    g_cincMutex = mutexcreate( )
end sub

'' One file to one key, as symbol_index's KeyFor makes it: absolute, normalised,
'' lower-cased. The header is compared as written, case aside.
private function StoreKey( byref includerPath as string, byref header as string ) as string
    return lcase( NormalizePath( includerPath ) ) & "|" & lcase( header )
end function

function AcceptCIncludes( byref jsonText as string ) as boolean
    dim as JsonDoc doc
    if( doc.Parse( jsonText ) = false ) then return false
    dim as JsonValue root = doc.Root( )
    if( root.IsObject( ) = false orelse root.Member( "format" ).AsLongInt( 0 ) <> 1 ) then return false

    mutexlock( g_cincMutex )
    for each entry in ArrayOf( root.Member( "cincludes" ) )
        dim as string file_   = entry.Member( "file" ).AsString( "" )
        dim as string header  = entry.Member( "header" ).AsString( "" )
        dim as string binding = entry.Member( "binding" ).AsString( "" )
        if( len(file_) = 0 orelse len(header) = 0 ) then continue for
        if( len(binding) = 0 ) then
            LogInfo( "tiko --print-cincludes: " & file_ & ": " & header & ": " & _
                     entry.Member( "error" ).AsString( "no binding" ) )
            continue for
        end if
        g_cincBinding.Put( StoreKey( file_, header ), NormalizePath( binding ) )
    next
    mutexunlock( g_cincMutex )
    return true
end function

sub ClearCIncludes( )
    mutexlock( g_cincMutex )
    g_cincBinding.Clear( )
    mutexunlock( g_cincMutex )
end sub

function CIncludeBinding( byref includerPath as string, byref header as string ) as string
    dim as string b = ""
    mutexlock( g_cincMutex )
    if( g_cincBinding.TryGet( StoreKey( includerPath, header ), b ) = false ) then b = ""
    mutexunlock( g_cincMutex )
    return b
end function

private function DirOf_( byref path_ as string ) as string
    dim as long i = instrrev( path_, any "\/" )
    if( i <= 1 ) then return path_
    return left( path_, i - 1 )
end function

'' The first line of what the compiler wrote to stderr, for the log.
private function FirstLine_( byref s as string ) as string
    dim as long e = instr( s, chr(10) )
    if( e = 0 ) then return trim( s, any chr(13) & " " )
    return trim( left( s, e - 1 ), any chr(13) & " " )
end function

'' Asks about one file; false when the compiler could not be run at all, so the caller
'' stops asking. The bindings named are indexed into `idx`.
private function QueryFile( byref idx as SymbolIndex, byref path_ as string ) as boolean
    dim as string here = DirOf_( path_ )
    '' Run where a build would: the package's directory when there is one -- the
    '' working directory is part of tiko's cache key, so this is what shares the build's
    '' entries -- else the file's own folder.
    dim as string cwd = ManifestDirAbove( here )
    if( len(cwd) = 0 ) then cwd = here

    dim args as FB.Array( of string )
    args.Push( "--print-cincludes" )
    '' The directories an `#include` on the way to a `#cinclude` is found in.
    dim as PathArray incs = ToolchainIncDirs( )
    for i as long = 0 to incs.Count( ) - 1
        args.Push( "-i" )
        args.Push( incs[i] )
    next
    args.Push( path_ )

    dim as double t0 = timer( )
    dim as ProcessResult r = RunCaptured( CompilerPath( ), args, cwd, CINCLUDE_TIMEOUT_MS )
    dim as long ms = int( (timer( ) - t0) * 1000 )

    if( r.Started = false ) then
        LogWarn( "tiko --print-cincludes: could not run " & CompilerPath( ) )
        return false
    end if
    if( r.TimedOut ) then
        LogWarn( "tiko --print-cincludes: " & path_ & " took longer than " & _
                 CINCLUDE_TIMEOUT_MS \ 1000 & " s and was stopped" )
        return true
    end if
    '' A header that cannot be imported exits 1 WITH an answer: the rest of the file's
    '' #cincludes, and that one's error. The answer is taken.
    if( r.Exit_ <> 0 ) then
        LogInfo( "tiko --print-cincludes: " & path_ & " exited " & r.Exit_ & _
                 iif( len(r.Stderr_) > 0, ": " & FirstLine_( r.Stderr_ ), "" ) )
    end if
    if( AcceptCIncludes( r.Stdout_ ) = false ) then
        if( r.Exit_ = 0 ) then
            LogWarn( "tiko --print-cincludes: " & path_ & " -- the answer is not a cincludes object" )
        end if
        return true
    end if
    LogInfo( "tiko --print-cincludes: " & path_ & " in " & ms & " ms" )

    '' THE BINDINGS THEMSELVES, read now -- each once, however many files name it.
    dim as long fi = idx.IndexOfUri( PathToUri( path_ ) )
    for k as long = 0 to idx.IncludeCount( fi ) - 1
        dim as IncludeEdge e = idx.IncludeAt( fi, k )
        if( e.IsC_ = false ) then continue for
        dim as string b = CIncludeBinding( path_, e.Target )
        if( len(b) = 0 ) then continue for
        if( idx.IndexOfUri( PathToUri( b ) ) >= 0 ) then continue for
        if( idx.IndexBinding( b ) = false ) then
            LogWarn( "tiko --print-cincludes: could not read the binding " & b )
        end if
    next
    return true
end function

sub LoadCIncludes( byref idx as SymbolIndex, byval fresh as boolean )
    if( len(CompilerPath( )) = 0 ) then exit sub
    if( fresh ) then ClearCIncludes( )

    '' The files known NOW: a binding indexed below has no #cinclude of its own.
    dim as long n = idx.FileCount( )
    for f as long = 0 to n - 1
        if( idx.HasCIncludes( f ) = false ) then continue for
        if( QueryFile( idx, idx.FilePath( f ) ) = false ) then exit for
    next
end sub
