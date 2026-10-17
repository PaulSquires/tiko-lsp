'' ############################################################################
''  workspace/workspace.bas -- finding the source files
'' ############################################################################

#import "std/containers"
#import "std/fs"
#include once "workspace.bi"
#include once "../utils/logging.bi"

using fs

function IsSourceFileName( byref name_ as string ) as boolean
    dim as long dotAt = instrrev( name_, "." )
    if( dotAt = 0 ) then return false

    select case lcase( mid( name_, dotAt ) )
        case ".tiko", ".tko", ".ti", ".bas", ".bi", ".inc" : return true
    end select
    return false
end function

private function HasComponent( byref lowerPath as string, byref comp as string ) as boolean
    if( instr( lowerPath, "\" & comp & "\" ) > 0 ) then return true
    return instr( lowerPath, "/" & comp & "/" ) > 0
end function

function IsIgnoredPath( byref path_ as string ) as boolean
    '' Matched on the whole path rather than pruned during the walk, because
    '' WalkDir has no "skip this subtree" signal. One INSTR per file is
    '' cheaper than the directories it saves reading.
    ''
    '' Build output is not listed: the extension filter already excludes .exe
    '' and .o, and a project that keeps sources in bin\ should still find them.
    dim as string p = lcase( path_ )

    if( HasComponent( p, ".git" ) ) then return true
    if( HasComponent( p, ".svn" ) ) then return true
    if( HasComponent( p, ".hg" ) ) then return true
    if( HasComponent( p, ".vs" ) ) then return true
    if( HasComponent( p, ".vscode" ) ) then return true
    if( HasComponent( p, ".idea" ) ) then return true
    if( HasComponent( p, "node_modules" ) ) then return true
    if( HasComponent( p, "__pycache__" ) ) then return true

    return false
end function

function NormalizePath( byref path_ as string ) as string
    if( len(path_) = 0 ) then return ""

    '' AbsolutePath is LEXICAL and does not require the path to exist, which
    '' is the right trade here. CanonicalPath would also resolve symlinks,
    '' need the file to be there, and hand back a differently-shaped path.
    dim as FsResultUStr resolved = AbsolutePath( path_ )
    if( resolved.IsOk( ) = false ) then return path_
    return resolved.Value( )
end function

sub ScanFolder( byref rootPath as string, byref scan as WorkspaceScan )
    if( len(rootPath) = 0 ) then exit sub

    '' The root is resolved FIRST, so a path written through `build\..`
    '' does not turn every indexed file's URI into one no client will match
    '' against its own.
    dim as string root = NormalizePath( rootPath )

    '' A FILE, not a folder. Zed sends the file itself as the workspace folder
    '' when a single file is opened (`zed widgets.bas`), and walking a file
    '' finds nothing -- so the file IS the workspace. Walking its directory
    '' instead would be worse: opening one file out of C:\dev would index
    '' every project on the disk.
    if( fs.IsFile( root ) ) then
        if( IsSourceFileName( root ) ) then scan.Files.Push( root )
        exit sub
    end if

    '' WalkDir is reentrant and does not follow directory symlinks, so the
    '' traversal is a tree by construction -- no visited set, no cycles. FB's
    '' own DIR/DIRNEXT is a per-thread global and cannot be nested at all.
    for each r in WalkDir( root )
        if( scan.Files.Count( ) >= WS_MAX_FILES ) then
            scan.Truncated = true
            exit for
        end if

        if( r.IsOk( ) = false ) then
            '' A subtree we cannot read. The walk continues; saying so once is
            '' more useful than failing the whole scan.
            scan.Skipped += 1
            continue for
        end if

        if( r.Value( ).IsFile( ) = false ) then continue for

        dim as string name_ = r.Value( ).Name( )
        if( IsSourceFileName( name_ ) = false ) then continue for

        dim as string full = r.Value( ).Path( )
        if( IsIgnoredPath( full ) ) then continue for

        scan.Files.Push( full )
    next
end sub

'' FREEFILE IS A RACE, and this is the one function in the server that two
'' threads call: the index worker reads every file in the workspace while the
'' message loop may be reading files for a rename. FREEFILE returns a number
'' that is free RIGHT NOW; between the return and the OPEN that claims it,
'' the other thread can be handed the same one, and then one of them fails to
'' open a file that is perfectly readable. The lock covers exactly that gap --
'' the READ itself is not serialised.
dim shared as any ptr g_fileMutex

'' Created before main( ), for the same reason the keyword table is: two
'' threads lazily creating "the" mutex make two mutexes, and two mutexes
'' exclude nothing.
private sub InitFileMutex constructor
    g_fileMutex = mutexcreate( )
end sub

private sub FreeFileMutex destructor
    if( g_fileMutex <> 0 ) then
        mutexdestroy( g_fileMutex )
        g_fileMutex = 0
    end if
end sub

function ReadSourceFile( byref path_ as string, byref outText as string, _
                         byval maxBytes as longint ) as boolean
    outText = ""

    mutexlock( g_fileMutex )
    dim as long f = freefile( )
    dim as long openErr = open( path_ for binary access read as #f )
    mutexunlock( g_fileMutex )

    if( openErr <> 0 ) then return false

    dim as longint n = lof( f )
    if( n > maxBytes ) then
        close #f
        return false
    end if

    if( n > 0 ) then
        outText = space( n )
        get #f, , outText
    end if

    close #f
    return true
end function
