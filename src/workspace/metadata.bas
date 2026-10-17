'' ############################################################################
''  workspace/metadata.bas -- what the compiler says about a package. See metadata.bi.
'' ############################################################################

#import "std/containers"
#import "std/fs"
#include once "metadata.bi"
#include once "modules.bi"
#include once "../json/json.bi"
#include once "../utils/process.bi"
#include once "../utils/logging.bi"

const METADATA_TIMEOUT_MS = 30000

'' THE STORE: flat arrays, joined by manifest index. Written by AcceptMetadata,
'' LoadMetadata and ClearMetadata, all under g_metaMutex.
dim shared as any ptr   g_metaMutex
dim shared as string    g_compiler

dim shared as PathArray g_manDirs         '' one per manifest
dim shared as PathArray g_manJson         '' ...and what the compiler printed for it

dim shared as containers.Array( of long ) g_modMan
dim shared as PathArray g_modChain        '' lower-cased
dim shared as PathArray g_modDir

dim shared as containers.Array( of long ) g_rootMan
dim shared as PathArray g_rootDir

dim shared as string    g_pkgDir
dim shared as PathArray g_incDirs

private sub InitMetadataMutex constructor
    g_metaMutex = mutexcreate( )
end sub

sub SetCompilerPath( byref path_ as string )
    g_compiler = path_
end sub

function CompilerPath( ) as string
    return g_compiler
end function

private function IsAbsolute( byref p as string ) as boolean
#ifdef __FB_WIN32__
    if( len(p) >= 2 andalso p[1] = asc( ":" ) ) then return true
    return left( p, 2 ) = "\\"
#else
    return left( p, 1 ) = "/"
#endif
end function

'' A path from the compiler's answer: '/' or '\' as it came, relative to the
'' manifest's directory or absolute. Native and absolute here.
private function Resolve( byref manifestDir as string, byref p as string ) as string
    if( len(p) = 0 ) then return ""
    dim as string t = p
#ifdef __FB_WIN32__
    for i as long = 0 to len(t) - 1
        if( t[i] = asc( "/" ) ) then t[i] = asc( "\" )
    next
    if( IsAbsolute( t ) = false ) then t = manifestDir & "\" & t
#else
    if( IsAbsolute( t ) = false ) then t = manifestDir & "/" & t
#endif
    return NormalizePath( t )
end function

'' The index of the manifest `path_` lies under -- the longest directory that is a
'' prefix of it -- or -1. Called with the mutex held.
private function ManifestOf( byref path_ as string ) as long
    dim as string p = lcase( NormalizePath( path_ ) )
    dim as long best = -1, bestLen = 0
    for i as long = 0 to g_manDirs.Count( ) - 1
        dim as string d = lcase( g_manDirs[i] )
        dim as long n = len(d)
        if( n <= bestLen orelse len(p) <= n ) then continue for
        if( left( p, n ) <> d ) then continue for
        dim as ubyte sep = p[n]
        if( sep <> asc( "\" ) andalso sep <> asc( "/" ) ) then continue for
        best = i
        bestLen = n
    next
    return best
end function

private sub PushUnique( byref arr as PathArray, byref v as string )
    if( len(v) = 0 ) then exit sub
    for i as long = 0 to arr.Count( ) - 1
        if( lcase( arr[i] ) = lcase( v ) ) then exit sub
    next
    arr.Push( v )
end sub

function AcceptMetadata( byref manifestDir as string, byref jsonText as string ) as boolean
    dim as JsonDoc doc
    if( doc.Parse( jsonText ) = false ) then return false
    dim as JsonValue root = doc.Root( )
    if( root.IsObject( ) = false orelse root.Member( "format" ).AsLongInt( 0 ) <> 1 ) then return false

    dim as string md = NormalizePath( manifestDir )
    mutexlock( g_metaMutex )
    dim as long m = g_manDirs.Count( )
    g_manDirs.Push( md )
    g_manJson.Push( jsonText )

    for each modVal in ArrayOf( root.Member( "modules" ) )
        dim as string chn = lcase( modVal.Member( "chain" ).AsString( "" ) )
        dim as string dir_ = Resolve( md, modVal.Member( "dir" ).AsString( "" ) )
        if( len(chn) = 0 orelse len(dir_) = 0 ) then continue for
        g_modMan.Push( m )
        g_modChain.Push( chn )
        g_modDir.Push( dir_ )
    next

    dim as JsonValue sp = root.Member( "searchPaths" )
    for each rootVal in ArrayOf( sp.Member( "roots" ) )
        dim as string d = Resolve( md, rootVal.AsString( "" ) )
        if( len(d) = 0 ) then continue for
        g_rootMan.Push( m )
        g_rootDir.Push( d )
    next
    if( len(g_pkgDir) = 0 ) then g_pkgDir = Resolve( md, sp.Member( "pkg" ).AsString( "" ) )

    for each unitVal in ArrayOf( root.Member( "units" ) )
        for each incVal in ArrayOf( unitVal.Member( "includes" ) )
            PushUnique( g_incDirs, Resolve( md, incVal.AsString( "" ) ) )
        next
    next
    mutexunlock( g_metaMutex )
    return true
end function

sub ClearMetadata( )
    mutexlock( g_metaMutex )
    g_manDirs.Clear( )
    g_manJson.Clear( )
    g_modMan.Clear( )
    g_modChain.Clear( )
    g_modDir.Clear( )
    g_rootMan.Clear( )
    g_rootDir.Clear( )
    g_pkgDir = ""
    g_incDirs.Clear( )
    mutexunlock( g_metaMutex )
end sub

'' The first line of what the compiler wrote to stderr, for the log.
private function FirstLine( byref s as string ) as string
    dim as long e = instr( s, chr(10) )
    if( e = 0 ) then return trim( s, any chr(13) & " " )
    return trim( left( s, e - 1 ), any chr(13) & " " )
end function

sub LoadMetadata( byref roots as PathArray )
    if( len(g_compiler) = 0 ) then exit sub
    ClearMetadata( )

    dim seen as PathArray
    for i as long = 0 to roots.Count( ) - 1
        dim as string md = ManifestDirAbove( NormalizePath( roots[i] ) )
        if( len(md) = 0 ) then continue for
        dim as boolean again = false
        for k as long = 0 to seen.Count( ) - 1
            if( lcase( seen[k] ) = lcase( md ) ) then again = true
        next
        if( again ) then continue for
        seen.Push( md )

        '' Run IN the manifest's directory, naming it as '.': a target's `-i` options are
        '' read against the current directory, and every path that comes back is then
        '' relative to the one directory Resolve reads it against.
        dim args as containers.Array( of string )
        args.Push( "metadata" )
        args.Push( "--manifest" )
        args.Push( "." )
        args.Push( "--format" )
        args.Push( "json" )
        dim as double t0 = timer( )
        dim as ProcessResult r = RunCaptured( g_compiler, args, md, METADATA_TIMEOUT_MS )
        dim as long ms = int( (timer( ) - t0) * 1000 )

        if( r.Started = false ) then
            LogWarn( "tiko metadata: could not run " & g_compiler & " -- resolving without it" )
            exit for
        end if
        if( r.TimedOut ) then
            LogWarn( "tiko metadata: " & md & " took longer than " & METADATA_TIMEOUT_MS \ 1000 & _
                     " s and was stopped" )
            continue for
        end if
        '' A graph with an error in it still exits 1 WITH an answer -- the targets, and
        '' what of the graph was read. A workspace being edited is often in that state,
        '' and the answer is taken: what it lacks, modules.bi still resolves.
        if( r.Exit_ <> 0 ) then
            LogInfo( "tiko metadata: " & md & " exited " & r.Exit_ & _
                     iif( len(r.Stderr_) > 0, ": " & FirstLine( r.Stderr_ ), "" ) )
        end if
        if( AcceptMetadata( md, r.Stdout_ ) ) then
            LogInfo( "tiko metadata: " & md & " read in " & ms & " ms" )
        elseif( r.Exit_ = 0 ) then
            LogWarn( "tiko metadata: " & md & " -- the answer is not a metadata object" )
        end if
    next
end sub

'' `acme/net/http` as a chain: `acme.net.http`, lower-cased.
private function ChainOf( byref importPath as string ) as string
    dim as string c = lcase( importPath )
    for i as long = 0 to len(c) - 1
        if( c[i] = asc( "/" ) ) then c[i] = asc( "." )
    next
    return c
end function

function MetadataModuleDir( byref importerPath as string, byref importPath as string ) as string
    if( left( importPath, 2 ) = "./" orelse left( importPath, 3 ) = "../" ) then return ""
    dim as string chn = ChainOf( importPath )
    dim as string r = ""
    mutexlock( g_metaMutex )
    dim as long m = ManifestOf( importerPath )
    if( m >= 0 ) then
        for i as long = 0 to g_modChain.Count( ) - 1
            if( g_modMan[i] = m andalso g_modChain[i] = chn ) then
                r = g_modDir[i]
                exit for
            end if
        next
    end if
    mutexunlock( g_metaMutex )
    return r
end function

sub MetadataSearchRoots( byref importerPath as string, byref outDirs as PathArray )
    outDirs.Clear( )
    mutexlock( g_metaMutex )
    dim as long m = ManifestOf( importerPath )
    for i as long = 0 to g_rootDir.Count( ) - 1
        if( g_rootMan[i] = m ) then outDirs.Push( g_rootDir[i] )
    next
    mutexunlock( g_metaMutex )
end sub

function MetadataPkgDir( ) as string
    mutexlock( g_metaMutex )
    dim as string r = g_pkgDir
    mutexunlock( g_metaMutex )
    return r
end function

function MetadataIncludeDirs( ) as PathArray
    dim out_ as PathArray
    mutexlock( g_metaMutex )
    for i as long = 0 to g_incDirs.Count( ) - 1
        out_.Push( g_incDirs[i] )
    next
    mutexunlock( g_metaMutex )
    return out_
end function

function MetadataManifestCount( ) as long
    mutexlock( g_metaMutex )
    dim as long n = g_manDirs.Count( )
    mutexunlock( g_metaMutex )
    return n
end function

function MetadataFor( byref path_ as string, byref manifestDir as string, _
                      byref jsonText as string ) as boolean
    manifestDir = ""
    jsonText = ""
    mutexlock( g_metaMutex )
    dim as long m = iif( len(path_) = 0, iif( g_manDirs.Count( ) > 0, 0, -1 ), ManifestOf( path_ ) )
    if( m >= 0 ) then
        manifestDir = g_manDirs[m]
        jsonText = g_manJson[m]
    end if
    mutexunlock( g_metaMutex )
    return m >= 0
end function
