'' ############################################################################
''  utils/uri.bas -- file: URI <-> filesystem path
'' ############################################################################

#import "std/containers"
#import "std/strings"
#include once "uri.bi"

using strings

'' Windows wants backslashes; every other target wants what it already has.
#ifdef __FB_WIN32__
    const NATIVE_SEP = "\"
    const IS_WINDOWS = true
#else
    const NATIVE_SEP = "/"
    const IS_WINDOWS = false
#endif

private function HexDigit( byval c as ubyte ) as long
    if( c >= asc("0") andalso c <= asc("9") ) then return c - asc("0")
    if( c >= asc("a") andalso c <= asc("f") ) then return 10 + (c - asc("a"))
    if( c >= asc("A") andalso c <= asc("F") ) then return 10 + (c - asc("A"))
    return -1
end function

function UriDecode( byref s as string ) as string
    dim as string out_
    dim as long i = 0

    while( i < len(s) )
        if( s[i] = asc("%") andalso i + 2 < len(s) ) then
            dim as long hi = HexDigit( s[i + 1] )
            dim as long lo = HexDigit( s[i + 2] )
            if( hi >= 0 andalso lo >= 0 ) then
                '' Decoding to a BYTE, not a character: a percent-encoded UTF-8
                '' sequence decodes byte by byte and reassembles itself.
                out_ &= chr( hi * 16 + lo )
                i += 3
                continue while
            end if
        end if
        '' A stray '%' that is not a valid escape is kept verbatim rather than
        '' rejected -- the alternative is losing a document over a typo.
        out_ &= chr( s[i] )
        i += 1
    wend

    return out_
end function

function UriEncodePath( byref s as string ) as string
    dim as string out_

    for i as long = 0 to len(s) - 1
        dim as ubyte c = s[i]
        dim as boolean plain = false

        if( c >= asc("a") andalso c <= asc("z") ) then plain = true
        if( c >= asc("A") andalso c <= asc("Z") ) then plain = true
        if( c >= asc("0") andalso c <= asc("9") ) then plain = true
        select case c
            case asc("-"), asc("."), asc("_"), asc("~"), asc("/")
                plain = true
        end select

        if( plain ) then
            out_ &= chr( c )
        else
            out_ &= "%" & ucase( hex( c, 2 ) )
        end if
    next

    return out_
end function

function UriScheme( byref uri as string ) as string
    dim as long colonAt = instr( uri, ":" )

    '' A scheme must be at least TWO characters here. RFC 3986 permits one,
    '' but a single letter before a colon is a Windows drive -- "C:\dev\x.bas"
    '' would otherwise parse as the scheme "c", and a path handed to a URI
    '' function by mistake would be silently accepted.
    if( colonAt < 3 ) then return ""

    '' A scheme is ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ). Anything else
    '' before the colon means this is a path, not a URI -- "C:\dev\x.bas" must
    '' not be mistaken for the scheme "c".
    for i as long = 0 to colonAt - 2
        dim as ubyte c = uri[i]
        dim as boolean okChar = false
        if( c >= asc("a") andalso c <= asc("z") ) then okChar = true
        if( c >= asc("A") andalso c <= asc("Z") ) then okChar = true
        if( i > 0 ) then
            if( c >= asc("0") andalso c <= asc("9") ) then okChar = true
            select case c
                case asc("+"), asc("-"), asc(".") : okChar = true
            end select
        end if
        if( okChar = false ) then return ""
    next

    return lcase( left( uri, colonAt - 1 ) )
end function

function UriIsFile( byref uri as string ) as boolean
    return UriScheme( uri ) = "file"
end function

function UriToPath( byref uri as string ) as string
    if( UriIsFile( uri ) = false ) then return ""

    '' Strip "file:" and any query or fragment.
    dim as string rest = mid( uri, 6 )
    dim as long cut = instr( rest, "?" )
    if( cut > 0 ) then rest = left( rest, cut - 1 )
    cut = instr( rest, "#" )
    if( cut > 0 ) then rest = left( rest, cut - 1 )

    dim as string authority = ""
    if( left( rest, 2 ) = "//" ) then
        rest = mid( rest, 3 )
        dim as long slashAt = instr( rest, "/" )
        if( slashAt = 0 ) then
            authority = rest
            rest = ""
        else
            authority = left( rest, slashAt - 1 )
            rest = mid( rest, slashAt )
        end if
    end if

    dim as string path_ = UriDecode( rest )

    '' file://server/share/x -- a UNC path, and only meaningful on Windows.
    if( len(authority) > 0 andalso lcase(authority) <> "localhost" ) then
        if( IS_WINDOWS ) then
            return "\\" & UriDecode( authority ) & Replace( path_, "/", "\" )
        end if
        return path_
    end if

    '' /c:/dev/x.bas -> C:\dev\x.bas. The leading slash exists only to make the
    '' URI well-formed and is not part of the path.
    if( len(path_) >= 3 ) then
        if( path_[0] = asc("/") andalso path_[2] = asc(":") ) then
            dim as ubyte drive = path_[1]
            dim as boolean isDrive = (drive >= asc("a") andalso drive <= asc("z")) orelse _
                                     (drive >= asc("A") andalso drive <= asc("Z"))
            if( isDrive ) then
                path_ = ucase( chr(drive) ) & mid( path_, 3 )
            end if
        end if
    end if

    if( IS_WINDOWS ) then return Replace( path_, "/", "\" )
    return path_
end function

function PathToUri( byref path_ as string ) as string
    if( len(path_) = 0 ) then return ""

    dim as string p = Replace( path_, "\", "/" )

    '' UNC: //server/share -> file://server/share
    if( left( p, 2 ) = "//" ) then
        dim as string rest = mid( p, 3 )
        dim as long slashAt = instr( rest, "/" )
        if( slashAt = 0 ) then return "file://" & UriEncodePath( rest )
        return "file://" & UriEncodePath( left( rest, slashAt - 1 ) ) & _
               UriEncodePath( mid( rest, slashAt ) )
    end if

    '' C:/dev/x.bas -> file:///c%3A/dev/x.bas. The colon is encoded because
    '' that is what every mainstream client sends, and a document opened by
    '' the client must compare equal to one this server discovered.
    if( len(p) >= 2 andalso mid( p, 2, 1 ) = ":" ) then
        return "file:///" & lcase( left( p, 1 ) ) & "%3A" & UriEncodePath( mid( p, 3 ) )
    end if

    if( left( p, 1 ) <> "/" ) then p = "/" & p
    return "file://" & UriEncodePath( p )
end function

function UriFileName( byref uri as string ) as string
    dim as string s = uri
    dim as long cut = instr( s, "?" )
    if( cut > 0 ) then s = left( s, cut - 1 )
    cut = instr( s, "#" )
    if( cut > 0 ) then s = left( s, cut - 1 )

    dim as long slashAt = instrrev( s, "/" )
    if( slashAt > 0 ) then s = mid( s, slashAt + 1 )
    return UriDecode( s )
end function
