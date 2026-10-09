'' ############################################################################
''  workspace/modules.bas -- where a tiko `#import` leads. See modules.bi.
'' ############################################################################

#include once "modules.bi"
#include once "fb/filesystem.bi"

private function DirPart( byref path_ as string ) as string
    for i as long = len(path_) - 1 to 0 step -1
        if( path_[i] = asc( "\" ) orelse path_[i] = asc( "/" ) ) then
            return left( path_, i )
        end if
    next
    return ""
end function

'' `base` joined with a '/'-separated `rel`, native and absolute.
private function JoinNative( byref base_ as string, byref rel as string ) as string
    if( len(rel) = 0 ) then return NormalizePath( base_ )
    dim as string t = rel
#ifdef __FB_WIN32__
    for i as long = 0 to len(t) - 1
        if( t[i] = asc( "/" ) ) then t[i] = asc( "\" )
    next
    return NormalizePath( base_ & "\" & t )
#else
    return NormalizePath( base_ & "/" & t )
#endif
end function

'' THE MANIFEST, as much of it as resolution reads: [package] name, and the path of each
'' [dependencies] entry. The TOML subset tiko-lang accepts (its RFC-0007 section 2) is read
'' line by line; anything this does not understand is passed over -- the compiler says
'' what is wrong with a manifest, and this only has to find modules.
private sub ReadManifest( byref dir_ as string, byref name_ as string, _
                          byref depNames as PathArray, byref depPaths as PathArray )
    name_ = ""
    dim as string text_
    if( ReadSourceFile( dir_ & "\tiko.toml", text_ ) = false ) then
        if( ReadSourceFile( dir_ & "/tiko.toml", text_ ) = false ) then exit sub
    end if

    dim as string table_ = ""
    dim as long p = 1
    while( p <= len(text_) )
        dim as long e = instr( p, text_, chr(10) )
        if( e = 0 ) then e = len(text_) + 1
        dim as string ln = trim( mid( text_, p, e - p ), any chr(13) & chr(9) & " " )
        p = e + 1
        if( len(ln) = 0 orelse left( ln, 1 ) = "#" ) then continue while

        if( left( ln, 1 ) = "[" ) then
            table_ = lcase( trim( mid( ln, 2, instr( ln, "]" ) - 2 ) ) )
            continue while
        end if

        dim as long eq = instr( ln, "=" )
        if( eq = 0 ) then continue while
        dim as string k = lcase( trim( left( ln, eq - 1 ), any chr(34) & "' " ) )
        dim as string v = trim( mid( ln, eq + 1 ) )

        '' The first quoted string in v: a value, or an inline table's `path`.
        dim as string s = ""
        dim as long q1 = instr( v, chr(34) )
        dim as long qa = instr( v, "'" )
        dim as string qc = chr(34)
        if( q1 = 0 orelse (qa > 0 andalso qa < q1) ) then
            q1 = qa
            qc = "'"
        end if
        if( q1 > 0 ) then
            dim as long q2 = instr( q1 + 1, v, qc )
            if( q2 > q1 ) then s = mid( v, q1 + 1, q2 - q1 - 1 )
        end if

        if( table_ = "package" andalso k = "name" ) then
            name_ = lcase( s )
        elseif( table_ = "dependencies" andalso instr( v, "path" ) > 0 andalso len(s) > 0 ) then
            depNames.Push( k )
            depPaths.Push( JoinNative( dir_, s ) )
        elseif( left( table_, 13 ) = "dependencies." andalso k = "path" andalso len(s) > 0 ) then
            dim as string dn = mid( table_, 14 )
            if( instr( dn, "." ) = 0 ) then
                depNames.Push( dn )
                depPaths.Push( JoinNative( dir_, s ) )
            end if
        end if
    wend
end sub

'' The nearest directory at or above `dir_` holding a tiko.toml, or "".
private function ManifestDirAbove( byref dir_ as string ) as string
    dim as string d = dir_
    for guard as long = 0 to 64
        if( len(d) = 0 ) then exit for
        if( FB.IsFile( d & "\tiko.toml" ) orelse FB.IsFile( d & "/tiko.toml" ) ) then return d
        dim as string up_ = DirPart( d )
        if( len(up_) = 0 orelse up_ = d ) then exit for
        d = up_
    next
    return ""
end function

function ToolchainPkgDir( ) as string
    dim as string env_ = environ( "TKO_PKG" )
    if( len(env_) > 0 ) then return NormalizePath( env_ )

    '' BESIDE A `tiko` ON PATH, found without running it: <dir>/pkg in a packaged
    '' toolchain, <dir>/../pkg in the tiko-lang repository.
    dim as string p = environ( "PATH" )
#ifdef __FB_WIN32__
    dim as string sep = ";", exe = "\tiko.exe"
#else
    dim as string sep = ":", exe = "/tiko"
#endif
    dim as long st = 1
    while( st <= len(p) )
        dim as long en = instr( st, p, sep )
        if( en = 0 ) then en = len(p) + 1
        dim as string d = trim( mid( p, st, en - st ), any chr(34) )
        st = en + 1
        if( len(d) = 0 ) then continue while
        if( FB.IsFile( d & exe ) = false ) then continue while
        dim as string cand = JoinNative( d, "pkg" )
        if( FB.IsDir( cand ) ) then return cand
        cand = JoinNative( d, "../pkg" )
        if( FB.IsDir( cand ) ) then return cand
    wend
    return ""
end function

function ToolchainIncDir( ) as string
    dim as string env_ = environ( "TKO_INCLUDE" )
    if( len(env_) > 0 ) then return NormalizePath( env_ )
    dim as string p = environ( "PATH" )
#ifdef __FB_WIN32__
    dim as string sep = ";", exe = "\tiko.exe"
#else
    dim as string sep = ":", exe = "/tiko"
#endif
    dim as long st = 1
    while( st <= len(p) )
        dim as long en = instr( st, p, sep )
        if( en = 0 ) then en = len(p) + 1
        dim as string d = trim( mid( p, st, en - st ), any chr(34) )
        st = en + 1
        if( len(d) = 0 ) then continue while
        if( FB.IsFile( d & exe ) = false ) then continue while
        dim as string cand = JoinNative( d, "inc" )
        if( FB.IsDir( cand ) ) then return cand
        cand = JoinNative( d, "../inc" )
        if( FB.IsDir( cand ) ) then return cand
    wend
    return ""
end function

'' What `initialize` was told. Written once, before the index worker starts.
dim shared as PathArray g_configuredIncludeDirs

sub SetConfiguredIncludeDirs( byref dirs as PathArray )
    g_configuredIncludeDirs.Clear( )
    for i as long = 0 to dirs.Count( ) - 1
        dim as string d = NormalizePath( dirs[i] )
        if( len(d) > 0 ) then g_configuredIncludeDirs.Push( d )
    next
end sub

function ToolchainIncDirs( ) as PathArray
    dim out_ as PathArray
    for i as long = 0 to g_configuredIncludeDirs.Count( ) - 1
        if( FB.IsDir( g_configuredIncludeDirs[i] ) ) then out_.Push( g_configuredIncludeDirs[i] )
    next
    if( out_.IsEmpty( ) ) then
        dim as string d = ToolchainIncDir( )
        if( len(d) > 0 ) then out_.Push( d )
    end if
    return out_
end function

sub ModuleCandidates( byref importerPath as string, byref importPath as string, _
                      byref roots as PathArray, byref outDirs as PathArray )
    outDirs.Clear( )
    dim as string p = importPath
    if( len(p) = 0 ) then exit sub
    dim as string here = DirPart( importerPath )

    '' 1. relative.
    if( left( p, 2 ) = "./" orelse left( p, 3 ) = "../" ) then
        outDirs.Push( JoinNative( here, p ) )
        exit sub
    end if

    dim as long sl = instr( p, "/" )
    dim as string first_ = lcase( iif( sl = 0, p, left( p, sl - 1 ) ) )
    dim as string rest = iif( sl = 0, "", mid( p, sl + 1 ) )

    if( first_ <> "std" ) then
        '' 2 and 3: the importing file's package, and its manifest's dependencies.
        dim as string md = ManifestDirAbove( here )
        if( len(md) > 0 ) then
            dim as string pkgName
            dim depNames as PathArray
            dim depPaths as PathArray
            ReadManifest( md, pkgName, depNames, depPaths )
            if( pkgName = first_ ) then outDirs.Push( JoinNative( md, rest ) )
            for i as long = 0 to depNames.Count( ) - 1
                if( depNames[i] = first_ ) then outDirs.Push( JoinNative( depPaths[i], rest ) )
            next
        end if

        '' 4. the workspace folders.
        for i as long = 0 to roots.Count( ) - 1
            outDirs.Push( JoinNative( roots[i], p ) )
        next
    end if

    '' 5. the toolchain.
    dim as string pk = ToolchainPkgDir( )
    if( len(pk) > 0 ) then outDirs.Push( JoinNative( pk, p ) )
end sub
