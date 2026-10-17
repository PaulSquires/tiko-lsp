'' ############################################################################
''  json/json.bas -- implementation of the JSON facade over yyjson
''
''  Two yyjson rules are load-bearing here and are enforced in exactly one
''  place each:
''
''    1. A writer buffer comes from the DLL's heap and must be released with
''       yyjson_free_buf, never DEALLOCATE. Only Serialize() ever holds one.
''    2. STRPTR() on an empty FreeBASIC string is NULL, and yyjson reads NULL
''       as "invalid parameter" rather than "empty". Every call that could be
''       handed an empty string goes through TextPtr().
'' ############################################################################

#import "std/containers"
#include once "crt.bi"
#include once "json.bi"

'' A one-byte static that is never written to, so an empty FB string can still
'' be passed as a valid, NUL-terminated, non-NULL zstring.
dim shared as zstring * 1 g_EmptyText

private function TextPtr( byref s as string ) as zstring ptr
    if( len(s) = 0 ) then return @g_EmptyText
    return strptr(s)
end function

'' ############################################################################
''  Invalid UTF-8 on the way out
''
''  yyjson REFUSES to serialise a string that is not valid UTF-8, and it
''  refuses the whole document: one stray byte anywhere and the entire response
''  is lost. What the server did about that was log "failed to serialise" and
''  answer nothing -- so the request simply never completed, in an editor that
''  showed no error and waited.
''
''  This is not a hypothetical. 155 of AfxNova's 179 source files carry a
''  Latin-1 `é` in their copyright line, and a completion list drawn from any
''  of them was silently unanswerable. LSP says content is UTF-8; real files
''  predate the machine that says so.
''
''  So every string that goes out is checked, and a byte that cannot be part of
''  a valid sequence becomes U+FFFD. The user sees one replacement character in
''  a copyright line instead of a feature that does not work.
'' ############################################################################

'' How long a UTF-8 sequence starting with this byte should be, or 0 when the
'' byte cannot start one.
private function Utf8Len( byval c as ubyte ) as long
    if( c < &h80 ) then return 1
    if( c >= &hC2 andalso c <= &hDF ) then return 2
    if( c >= &hE0 andalso c <= &hEF ) then return 3
    if( c >= &hF0 andalso c <= &hF4 ) then return 4
    return 0
end function

private function IsContinuation( byval c as ubyte ) as boolean
    return ( c >= &h80 andalso c <= &hBF )
end function

'' `s` with every byte that is not part of a well-formed sequence replaced. The
'' common case -- text that is already valid -- copies nothing: the scan runs,
'' finds nothing wrong, and the original is returned.
private function SanitiseUtf8( byref s as string ) as string
    dim as long n = len(s)
    dim as long i = 0
    dim as boolean clean_ = true

    while( i < n )
        dim as long need = Utf8Len( s[i] )
        if( need = 0 ) then
            clean_ = false
            exit while
        end if

        if( i + need > n ) then
            clean_ = false
            exit while
        end if

        for k as long = 1 to need - 1
            if( IsContinuation( s[i + k] ) = false ) then
                clean_ = false
                exit for
            end if
        next
        if( clean_ = false ) then exit while

        i += need
    wend

    if( clean_ ) then return s

    '' Rebuild, keeping every valid sequence whole.
    dim as string out_
    i = 0

    while( i < n )
        dim as long need = Utf8Len( s[i] )
        dim as boolean ok_ = ( need > 0 ) andalso ( i + need <= n )

        if( ok_ ) then
            for k as long = 1 to need - 1
                if( IsContinuation( s[i + k] ) = false ) then
                    ok_ = false
                    exit for
                end if
            next
        end if

        if( ok_ ) then
            out_ &= mid( s, i + 1, need )
            i += need
        else
            out_ &= chr( &hEF, &hBF, &hBD )   '' U+FFFD REPLACEMENT CHARACTER
            i += 1
        end if
    wend

    return out_
end function

'' Builds a FreeBASIC string from a pointer/length pair. yyjson strings are
'' counted, not NUL-terminated in the FB sense: an escaped u0000 unescapes to
'' a real zero byte inside the text, and LEFT(*p, n) would stop early on it.
private function TextFrom( byval p as const zstring ptr, byval n as uinteger ) as string
    if( p = NULL orelse n = 0 ) then return ""
    dim as string s = space( n )
    memcpy( strptr(s), p, n )
    return s
end function

'' ############################################################################
''  JsonValue
'' ############################################################################

constructor JsonValue( )
    this.m_val = NULL
end constructor

constructor JsonValue( byval v as yyjson_val ptr )
    this.m_val = v
end constructor

function JsonValue.Handle( ) as yyjson_val ptr
    return this.m_val
end function

function JsonValue.IsValid( ) as boolean
    return this.m_val <> NULL
end function

function JsonValue.IsNull( ) as boolean
    if( this.m_val = NULL ) then return false
    return yyjson_is_null( this.m_val )
end function

function JsonValue.IsObject( ) as boolean
    if( this.m_val = NULL ) then return false
    return yyjson_is_obj( this.m_val )
end function

function JsonValue.IsArray( ) as boolean
    if( this.m_val = NULL ) then return false
    return yyjson_is_arr( this.m_val )
end function

function JsonValue.IsString( ) as boolean
    if( this.m_val = NULL ) then return false
    return yyjson_is_str( this.m_val )
end function

function JsonValue.IsNumber( ) as boolean
    if( this.m_val = NULL ) then return false
    return yyjson_is_num( this.m_val )
end function

function JsonValue.IsBool( ) as boolean
    if( this.m_val = NULL ) then return false
    return yyjson_is_bool( this.m_val )
end function

function JsonValue.Has( byref key as string ) as boolean
    if( this.IsObject( ) = false ) then return false
    return yyjson_obj_getn( this.m_val, TextPtr(key), len(key) ) <> NULL
end function

function JsonValue.Member( byref key as string ) as JsonValue
    if( this.IsObject( ) = false ) then return JsonValue( )
    return JsonValue( yyjson_obj_getn( this.m_val, TextPtr(key), len(key) ) )
end function

function JsonValue.Count( ) as long
    if( this.m_val = NULL ) then return 0
    if( yyjson_is_arr( this.m_val ) ) then return clng( yyjson_arr_size( this.m_val ) )
    if( yyjson_is_obj( this.m_val ) ) then return clng( yyjson_obj_size( this.m_val ) )
    return 0
end function

function JsonValue.Item( byval idx as long ) as JsonValue
    if( this.IsArray( ) = false ) then return JsonValue( )
    if( idx < 0 orelse idx >= this.Count( ) ) then return JsonValue( )
    return JsonValue( yyjson_arr_get( this.m_val, culng(idx) ) )
end function

function JsonValue.AsString( byref dflt as string = "" ) as string
    if( this.IsString( ) = false ) then return dflt
    return TextFrom( yyjson_get_str( this.m_val ), yyjson_get_len( this.m_val ) )
end function

function JsonValue.AsLongInt( byval dflt as longint = 0 ) as longint
    if( this.IsNumber( ) = false ) then return dflt
    if( yyjson_is_real( this.m_val ) ) then return clngint( yyjson_get_num( this.m_val ) )
    return yyjson_get_sint( this.m_val )
end function

function JsonValue.AsDouble( byval dflt as double = 0.0 ) as double
    if( this.IsNumber( ) = false ) then return dflt
    return yyjson_get_num( this.m_val )
end function

function JsonValue.AsBoolean( byval dflt as boolean = false ) as boolean
    if( this.IsBool( ) = false ) then return dflt
    return yyjson_get_bool( this.m_val )
end function

'' ############################################################################
''  JsonArrayIterator / JsonArray
'' ############################################################################

constructor JsonArrayIterator( )
    this.m_arr = NULL
    this.m_idx = 0
    this.m_max = 0
end constructor

constructor JsonArrayIterator( byval arr as yyjson_val ptr )
    this.m_arr = NULL
    this.m_idx = 0
    this.m_max = 0
    if( arr <> NULL ) then
        if( yyjson_is_arr( arr ) ) then
            this.m_arr = arr
            this.m_max = clng( yyjson_arr_size( arr ) )
        end if
    end if
end constructor

function JsonArrayIterator.IsValid( ) as boolean
    return this.m_idx < this.m_max
end function

function JsonArrayIterator.Value( ) as JsonValue
    if( this.IsValid( ) = false ) then return JsonValue( )
    return JsonValue( yyjson_arr_get( this.m_arr, culng(this.m_idx) ) )
end function

sub JsonArrayIterator.MoveNext( )
    this.m_idx += 1
end sub

constructor JsonArray( )
    this.m_arr = NULL
end constructor

constructor JsonArray( byval v as JsonValue )
    this.m_arr = iif( v.IsArray( ), v.Handle( ), cast( yyjson_val ptr, NULL ) )
end constructor

function JsonArray.Count( ) as long
    if( this.m_arr = NULL ) then return 0
    return clng( yyjson_arr_size( this.m_arr ) )
end function

function JsonArray.GetIterator( ) as JsonArrayIterator
    return JsonArrayIterator( this.m_arr )
end function

function ArrayOf( byval v as JsonValue ) as JsonArray
    return JsonArray( v )
end function

'' ############################################################################
''  JsonDoc
'' ############################################################################

constructor JsonDoc( )
    this.m_doc = NULL
end constructor

constructor JsonDoc( byref rhs as JsonDoc )
    this.m_doc = NULL
    this.m_err = rhs.m_err
    if( rhs.m_doc <> NULL ) then
        '' yyjson has no immutable-to-immutable clone, so the copy goes out
        '' through the mutable form and back.
        dim as yyjson_mut_doc ptr tmp = yyjson_doc_mut_copy( rhs.m_doc, NULL )
        if( tmp <> NULL ) then
            this.m_doc = yyjson_mut_doc_imut_copy( tmp, NULL )
            yyjson_mut_doc_free( tmp )
        end if
    end if
end constructor

operator JsonDoc.let( byref rhs as JsonDoc )
    if( @rhs = @this ) then exit operator
    this.Clear( )
    this.m_err = rhs.m_err
    if( rhs.m_doc <> NULL ) then
        dim as yyjson_mut_doc ptr tmp = yyjson_doc_mut_copy( rhs.m_doc, NULL )
        if( tmp <> NULL ) then
            this.m_doc = yyjson_mut_doc_imut_copy( tmp, NULL )
            yyjson_mut_doc_free( tmp )
        end if
    end if
end operator

destructor JsonDoc( )
    this.Clear( )
end destructor

sub JsonDoc.Clear( )
    if( this.m_doc <> NULL ) then
        yyjson_doc_free( this.m_doc )
        this.m_doc = NULL
    end if
    this.m_err = ""
end sub

function JsonDoc.Parse( byref text_ as string ) as boolean
    this.Clear( )

    if( len(text_) = 0 ) then
        this.m_err = "empty content"
        return false
    end if

    dim as yyjson_read_err rerr
    '' Strict RFC 8259: no comments, no trailing commas, no NaN. A client that
    '' sends those is broken, and accepting them would hide the bug.
    this.m_doc = yyjson_read_opts( strptr(text_), len(text_), YYJSON_READ_NOFLAG, NULL, @rerr )

    if( this.m_doc = NULL ) then
        dim as string detail = ""
        if( rerr.msg <> NULL ) then detail = *rerr.msg
        this.m_err = detail & " (at byte " & rerr.pos & ")"
        return false
    end if

    return true
end function

function JsonDoc.IsValid( ) as boolean
    return this.m_doc <> NULL
end function

function JsonDoc.Root( ) as JsonValue
    if( this.m_doc = NULL ) then return JsonValue( )
    return JsonValue( yyjson_doc_get_root( this.m_doc ) )
end function

function JsonDoc.ErrorText( ) as string
    return this.m_err
end function

'' ############################################################################
''  JsonNode
'' ############################################################################

constructor JsonNode( )
    this.m_val = NULL
end constructor

constructor JsonNode( byval v as yyjson_mut_val ptr )
    this.m_val = v
end constructor

function JsonNode.Handle( ) as yyjson_mut_val ptr
    return this.m_val
end function

function JsonNode.IsValid( ) as boolean
    return this.m_val <> NULL
end function

'' ############################################################################
''  JsonBuilder
'' ############################################################################

constructor JsonBuilder( )
    this.m_doc = yyjson_mut_doc_new( NULL )
end constructor

destructor JsonBuilder( )
    if( this.m_doc <> NULL ) then
        '' Frees the document and every node carved out of it. Any JsonNode
        '' still held by the caller dangles from here on -- by design, and the
        '' reason nodes are never stored beyond the request that built them.
        yyjson_mut_doc_free( this.m_doc )
        this.m_doc = NULL
    end if
end destructor

function JsonBuilder.IsValid( ) as boolean
    return this.m_doc <> NULL
end function

function JsonBuilder.NewObject( ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    return JsonNode( yyjson_mut_obj( this.m_doc ) )
end function

function JsonBuilder.CopyOf( byval v as JsonValue ) as JsonNode
    if( this.m_doc = NULL orelse v.Handle( ) = NULL ) then return JsonNode( )
    return JsonNode( yyjson_val_mut_copy( this.m_doc, v.Handle( ) ) )
end function

function JsonBuilder.NewArray( ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    return JsonNode( yyjson_mut_arr( this.m_doc ) )
end function

'' EVERY string value on the wire passes through here, which is why the
'' sanitising happens here and nowhere else.
function JsonBuilder.NewString( byref v as string ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    '' strncpy, not str: the FB string may be a temporary that dies before the
    '' document is serialised. And sanitised: yyjson refuses to write a
    '' document containing invalid UTF-8, and refuses ALL of it.
    dim as string clean_ = SanitiseUtf8( v )
    return JsonNode( yyjson_mut_strncpy( this.m_doc, TextPtr(clean_), len(clean_) ) )
end function

function JsonBuilder.NewInt( byval v as longint ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    return JsonNode( yyjson_mut_sint( this.m_doc, v ) )
end function

function JsonBuilder.NewDouble( byval v as double ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    return JsonNode( yyjson_mut_real( this.m_doc, v ) )
end function

function JsonBuilder.NewBool( byval v as boolean ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    return JsonNode( yyjson_mut_bool( this.m_doc, v ) )
end function

function JsonBuilder.NewNull( ) as JsonNode
    if( this.m_doc = NULL ) then return JsonNode( )
    return JsonNode( yyjson_mut_null( this.m_doc ) )
end function

'' ----------------------------------------------------------------------------
''  Object writers
''
''  EVERY ONE OF THESE GOES THROUGH SetNode, and SetNode COPIES THE KEY.
''
''  yyjson's convenience adders -- yyjson_mut_obj_add_sint and friends -- store
''  the key POINTER without copying it, even the _strcpy variants, which copy
''  only the value. A FreeBASIC string literal at a call site is a temporary,
''  so the key would dangle and the document would serialise with corrupted
''  key text: {"{\"{\\":-32700} instead of {"code":-32700}. It is not a crash
''  and not an error return, which is what makes it worth this comment.
'' ----------------------------------------------------------------------------

function JsonBuilder.SetNode( byval obj as JsonNode, byref key as string, byval v as JsonNode ) as boolean
    if( cbool(this.m_doc = NULL) orelse obj.IsValid( ) = false orelse v.IsValid( ) = false ) then return false

    dim as yyjson_mut_val ptr keyNode = yyjson_mut_strncpy( this.m_doc, TextPtr(key), len(key) )
    if( keyNode = NULL ) then return false

    return yyjson_mut_obj_add( obj.Handle( ), keyNode, v.Handle( ) )
end function

function JsonBuilder.SetStr( byval obj as JsonNode, byref key as string, byref v as string ) as boolean
    return this.SetNode( obj, key, this.NewString( v ) )
end function

function JsonBuilder.SetInt( byval obj as JsonNode, byref key as string, byval v as longint ) as boolean
    return this.SetNode( obj, key, this.NewInt( v ) )
end function

function JsonBuilder.SetDouble( byval obj as JsonNode, byref key as string, byval v as double ) as boolean
    return this.SetNode( obj, key, this.NewDouble( v ) )
end function

function JsonBuilder.SetBool( byval obj as JsonNode, byref key as string, byval v as boolean ) as boolean
    return this.SetNode( obj, key, this.NewBool( v ) )
end function

function JsonBuilder.SetNull( byval obj as JsonNode, byref key as string ) as boolean
    return this.SetNode( obj, key, this.NewNull( ) )
end function

function JsonBuilder.PushStr( byval arr as JsonNode, byref v as string ) as boolean
    if( cbool(this.m_doc = NULL) orelse arr.IsValid( ) = false ) then return false
    return yyjson_mut_arr_add_strncpy( this.m_doc, arr.Handle( ), TextPtr(v), len(v) )
end function

function JsonBuilder.PushInt( byval arr as JsonNode, byval v as longint ) as boolean
    if( cbool(this.m_doc = NULL) orelse arr.IsValid( ) = false ) then return false
    dim as JsonNode n = this.NewInt( v )
    if( n.IsValid( ) = false ) then return false
    return yyjson_mut_arr_add_val( arr.Handle( ), n.Handle( ) )
end function

function JsonBuilder.PushNode( byval arr as JsonNode, byval v as JsonNode ) as boolean
    if( arr.IsValid( ) = false orelse v.IsValid( ) = false ) then return false
    return yyjson_mut_arr_add_val( arr.Handle( ), v.Handle( ) )
end function

sub JsonBuilder.SetRoot( byval root as JsonNode )
    if( cbool(this.m_doc = NULL) orelse root.IsValid( ) = false ) then exit sub
    yyjson_mut_doc_set_root( this.m_doc, root.Handle( ) )
end sub

function JsonBuilder.Serialize( byval pretty as boolean = false ) as string
    if( this.m_doc = NULL ) then return ""

    dim as yyjson_write_flag flg = YYJSON_WRITE_NOFLAG
    if( pretty ) then flg = YYJSON_WRITE_PRETTY

    dim as uinteger n = 0
    dim as zstring ptr buf = yyjson_mut_write( this.m_doc, flg, @n )
    if( buf = NULL ) then return ""

    dim as string out_ = TextFrom( buf, n )

    '' The DLL allocated it, so the DLL releases it. DEALLOCATE here would
    '' corrupt the process heap.
    yyjson_free_buf( buf )
    return out_
end function

'' ############################################################################
''  Free helpers
'' ############################################################################

function JsonQuote( byref v as string ) as string
    dim as string out_ = """"

    for i as long = 0 to len(v) - 1
        dim as ubyte c = v[i]
        select case c
            case asc("""") : out_ &= "\"""
            case asc("\")  : out_ &= "\\"
            case 8         : out_ &= "\b"
            case 9         : out_ &= "\t"
            case 10        : out_ &= "\n"
            case 12        : out_ &= "\f"
            case 13        : out_ &= "\r"
            case else
                if( c < 32 ) then
                    out_ &= "\u" & lcase( hex( c, 4 ) )
                else
                    out_ &= chr( c )
                end if
        end select
    next

    return out_ & """"
end function
