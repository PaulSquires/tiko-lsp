'' ############################################################################
''  analysis/lexer.bas -- tiko tokens
'' ############################################################################

#include once "fb/map.bi"
#include once "fb/string.bi"
#include once "lexer.bi"

'' ############################################################################
''  The reserved-word table
''
''  Taken from fbc's own kwdTb in src/compiler/symb-keyword.bas -- 247 words --
''  so "is this a keyword" means exactly what the compiler means by it rather
''  than what a hand-kept list drifted into. To refresh after a language
''  change:
''
''      grep -oE '\( @"[A-Z_0-9]+"' src/compiler/symb-keyword.bas
''
''  The 36 words the block parser reasons about are registered separately,
''  below, and overwrite their KW_OTHER entry.
'' ############################################################################

private function OtherKeywordText( ) as string
    return _
    "abs abstract access acos alias and andalso any append asc asin " & _
    "atan2 atn base binary boolean byref byte byval call cast cbool " & _
    "cbyte cdbl cdecl chr cint circle class clng clngint close color " & _
    "common const cos cptr cshort csign csng cubyte cuint culng " & _
    "culngint cunsg cushort cva_arg cva_copy cva_end cva_start cvd cvi " & _
    "cvl cvlongint cvs cvshort data defbyte defdbl defined defint " & _
    "deflng deflongint defshort defsng defstr defubyte defuint defulng " & _
    "defulongint defushort delete dim double draw dynamic encoding eqv " & _
    "erase err error exp explicit export extends field fix frac get " & _
    "gosub goto iif imagecreate imp implements import include input " & _
    "instr instrrev int integer is lbound lcase len let lib line local " & _
    "lock log long longint lprint lset ltrim mid mkd mki mkl mklongint " & _
    "mks mkshort mod name new not on open option or orelse output " & _
    "overload paint palette pascal peek point pointer poke preserve " & _
    "preset print procptr pset ptr put random read redim rem restore " & _
    "resume return rset rtrim sadd screen seek sgn shared shl short " & _
    "shr sin single sizeof spc sqr stdcall step str string strptr swap " & _
    "tab tan threadcall to trim typeof ubound ubyte ucase uinteger " & _
    "ulong ulongint unlock unsigned until ushort using ustring var " & _
    "varptr va_first view virtual wchr width window winput write wstr " & _
    "wstring xor zstring __fastcall __thiscall"
end function

type KeywordMap as FB.Map( of string, long )

dim shared as KeywordMap    g_Keywords
dim shared as FB.Array( of string ) g_KeywordNames
dim shared as boolean       g_KeywordsReady

private sub Register( byref word_ as string, byval kw as FbKeyword )
    if( g_Keywords.Put( word_, clng(kw) ) ) then g_KeywordNames.Push( word_ )
end sub

private sub EnsureKeywords( )
    if( g_KeywordsReady ) then exit sub
    g_KeywordsReady = true

    '' The split result is bound to a LOCAL first. Iterating the temporary
    '' directly -- `for each w in FB.Split( ... )` -- destroys the array before
    '' the loop body runs, and the iterator is left pointing into freed memory.
    dim words as FB.Array( of string ) = FB.Split( OtherKeywordText( ), " " )
    for each w in words
        if( len(w) > 0 ) then Register( w, KW_OTHER )
    next

    '' Structural words last, so they replace their KW_OTHER entry.
    Register( "sub",         KW_SUB )
    Register( "function",    KW_FUNCTION )
    Register( "property",    KW_PROPERTY )
    Register( "constructor", KW_CONSTRUCTOR )
    Register( "destructor",  KW_DESTRUCTOR )
    Register( "operator",    KW_OPERATOR )
    Register( "type",        KW_TYPE )
    Register( "union",       KW_UNION )
    Register( "enum",        KW_ENUM )
    Register( "namespace",   KW_NAMESPACE )
    Register( "scope",       KW_SCOPE )
    Register( "with",        KW_WITH )
    Register( "extern",      KW_EXTERN )
    Register( "asm",         KW_ASM )
    Register( "if",          KW_IF )
    Register( "select",      KW_SELECT )
    Register( "while",       KW_WHILE )
    Register( "do",          KW_DO )
    Register( "for",         KW_FOR )
    Register( "end",         KW_END )
    Register( "endif",       KW_ENDIF )
    Register( "wend",        KW_WEND )
    Register( "loop",        KW_LOOP )
    Register( "next",        KW_NEXT )
    Register( "then",        KW_THEN )
    Register( "else",        KW_ELSE )
    Register( "elseif",      KW_ELSEIF )
    Register( "case",        KW_CASE )
    Register( "declare",     KW_DECLARE )
    Register( "exit",        KW_EXIT )
    Register( "continue",    KW_CONTINUE )
    Register( "as",          KW_AS )
    Register( "private",     KW_PRIVATE )
    Register( "public",      KW_PUBLIC )
    Register( "protected",   KW_PROTECTED )
    Register( "static",      KW_STATIC )
    Register( "virtual",     KW_VIRTUAL )
    Register( "abstract",    KW_ABSTRACT )
    Register( "const",       KW_CONST )
    Register( "dim",         KW_DIM )
    Register( "var",         KW_VAR )
    Register( "redim",       KW_REDIM )
end sub

'' BUILT BEFORE main( ) RUNS, and this is not a style preference.
''
'' The table used to be filled on first use. That was correct for exactly as
'' long as this server was single-threaded: the moment the index worker started
'' lexing at the same time as the message loop, both raced through the guard,
'' one set the "ready" flag and began filling the map, and the other read an
'' EMPTY map -- so no word in the language was a keyword, no statement opened a
'' block, and a whole workspace indexed to two files and ZERO symbols. No
'' crash, no diagnostic, nothing in the log: just an index that knew nothing.
''
'' A module constructor runs while the program is still single-threaded, which
'' removes the race rather than locking against it -- a lock here would sit on
'' the hottest path in the lexer, one acquisition per token.
private sub InitKeywords constructor
    EnsureKeywords( )
end sub

function KeywordOf( byref word_ as string ) as FbKeyword
    EnsureKeywords( )
    dim as long kw = 0
    if( g_Keywords.TryGet( lcase(word_), kw ) ) then return cast( FbKeyword, kw )
    return KW_NONE
end function

function IsKeyword( byref word_ as string ) as boolean
    return KeywordOf( word_ ) <> KW_NONE
end function

function AllKeywords( ) as FB.Array( of string )
    EnsureKeywords( )
    return g_KeywordNames
end function

'' ############################################################################
''  The fixed-width type names
''
''  tiko-lang declares ten typedefs for every program, in its prelude:
''  `type int32 as long` and its siblings. They are NOT in the table above,
''  and must not be: a program's own declaration of one of the names replaces
''  tiko's -- a variable called int32, win/basetsd.bi's `type INT32 as long`
''  -- so to the lexer they are identifiers like any other, and only a name
''  the file does not declare itself means the built-in.
'' ############################################################################

function BuiltinTypedefTarget( byref word_ as string ) as string
    select case lcase(word_)
        case "int8"    : return "byte"
        case "uint8"   : return "ubyte"
        case "int16"   : return "short"
        case "uint16"  : return "ushort"
        case "int32"   : return "long"
        case "uint32"  : return "ulong"
        case "int64"   : return "longint"
        case "uint64"  : return "ulongint"
        case "float32" : return "single"
        case "float64" : return "double"
    end select
    return ""
end function

function AllBuiltinTypedefs( ) as FB.Array( of string )
    dim out_ as FB.Array( of string )
    out_.Push( "int8" )
    out_.Push( "uint8" )
    out_.Push( "int16" )
    out_.Push( "uint16" )
    out_.Push( "int32" )
    out_.Push( "uint32" )
    out_.Push( "int64" )
    out_.Push( "uint64" )
    out_.Push( "float32" )
    out_.Push( "float64" )
    return out_
end function

'' The preprocessor directives that open or close a block; every other
'' directive is KW_PP_OTHER and the parser ignores the rest of its line.
private function PpKeywordOf( byref word_ as string ) as FbKeyword
    select case lcase(word_)
        case "if"       : return KW_PP_IF
        case "ifdef"    : return KW_PP_IFDEF
        case "ifndef"   : return KW_PP_IFNDEF
        case "else"     : return KW_PP_ELSE
        case "elseif"   : return KW_PP_ELSEIF
        case "endif"    : return KW_PP_ENDIF
        case "macro"    : return KW_PP_MACRO
        case "endmacro" : return KW_PP_ENDMACRO
        case "define"   : return KW_DEFINE
    end select
    return KW_PP_OTHER
end function

'' ############################################################################
''  Character classes
'' ############################################################################

private function IsDigit( byval c as ubyte ) as boolean
    return c >= asc("0") andalso c <= asc("9")
end function

private function IsHexDigit( byval c as ubyte ) as boolean
    if( IsDigit( c ) ) then return true
    if( c >= asc("a") andalso c <= asc("f") ) then return true
    if( c >= asc("A") andalso c <= asc("F") ) then return true
    return false
end function

private function IsAlpha( byval c as ubyte ) as boolean
    if( c >= asc("a") andalso c <= asc("z") ) then return true
    if( c >= asc("A") andalso c <= asc("Z") ) then return true
    '' A byte >= 128 is part of a UTF-8 sequence. tiko does not accept it
    '' in an identifier, but treating it as one keeps a stray non-ASCII byte
    '' inside a word rather than spraying "unexpected character" over it.
    return c >= 128
end function

private function IsIdentStart( byval c as ubyte ) as boolean
    return IsAlpha( c ) orelse c = asc("_")
end function

private function IsIdentPart( byval c as ubyte ) as boolean
    return IsIdentStart( c ) orelse IsDigit( c )
end function

'' $ % & ! # after an identifier are tiko's type suffixes: a$ is one name.
private function IsTypeSuffix( byval c as ubyte ) as boolean
    select case c
        case asc("$"), asc("%"), asc("&"), asc("!"), asc("#") : return true
    end select
    return false
end function

'' ############################################################################
''  Lexing
'' ############################################################################

function TokenText( byref text_ as string, byref tok as Token ) as string
    if( tok.Length_ <= 0 ) then return ""
    if( tok.Start_ < 0 orelse tok.Start_ >= len(text_) ) then return ""
    return mid( text_, tok.Start_ + 1, tok.Length_ )
end function

private sub Emit( byref tokens as TokenArray, byval kind as TokenKind, _
                  byval start_ as long, byval length_ as long, _
                  byval kw as FbKeyword = KW_NONE )
    dim as Token t
    t.Kind    = kind
    t.Kw      = kw
    t.Start_  = start_
    t.Length_ = length_
    tokens.Push( t )
end sub

sub LexSource( byref text_ as string, byref tokens as TokenArray, byref diags as DiagnosticArray )
    EnsureKeywords( )
    tokens.Clear( )

    dim as long n = len(text_)
    dim as long i = 0

    '' A UTF-8 BOM is not part of the program. Left in, it lexes as three
    '' "unexpected character" errors on line 1 of every file an editor saved
    '' with one.
    if( n >= 3 ) then
        if( text_[0] = &hEF andalso text_[1] = &hBB andalso text_[2] = &hBF ) then i = 3
    end if

    '' True until the first token of a logical line is emitted. Two things
    '' depend on it: '#' only starts a directive at the head of a line, and
    '' REM is only a comment there.
    dim as boolean atLineStart = true

    while( i < n )
        dim as ubyte c = text_[i]

        '' -- horizontal whitespace ------------------------------------------
        if( c = asc(" ") orelse c = 9 ) then
            i += 1
            continue while
        end if

        '' -- line continuation ----------------------------------------------
        ''
        '' A lone underscore continues the logical line. `_foo` is an ordinary
        '' identifier, so the next byte decides which this is.
        if( c = asc("_") ) then
            '' An underscore continues the line only when NOTHING but blanks or
            '' a comment follows it on that physical line. Two other things
            '' spell it the same way and are not continuations:
            ''
            ''     _myVar = 1           an ordinary identifier
            ''     V3##_( x, y, z )     a macro paste, where _ is the argument
            ''
            '' Getting this wrong ate the rest of the line in every macro in
            '' fb/vector.bi, and surfaced far away as "unmatched ')'".
            dim as boolean isContinuation = true
            if( i + 1 < n ) then
                if( IsIdentPart( text_[i + 1] ) ) then isContinuation = false
            end if

            if( isContinuation ) then
                dim as long look = i + 1
                while( look < n andalso (text_[look] = asc(" ") orelse text_[look] = 9) )
                    look += 1
                wend
                if( look < n ) then
                    select case text_[look]
                        case 10, 13, asc("'")   '' end of line, or a ' comment
                        case asc("/")
                            '' A BLOCK comment may follow the underscore too,
                            '' which fbc's own ir-gas64.bas does on nine lines
                            '' of one initialiser: `NULL, _ /' name '/`.
                            if( look + 1 >= n ) then
                                isContinuation = false
                            elseif( text_[look + 1] <> asc("'") ) then
                                isContinuation = false
                            end if
                        case else
                            isContinuation = false
                    end select
                end if
            end if

            if( isContinuation ) then
                '' Consume to and including the newline. A comment may follow
                '' the underscore, and does not end the continuation.
                dim as long j = i + 1
                while( j < n andalso text_[j] <> 10 )
                    j += 1
                wend
                if( j < n ) then j += 1
                i = j
                '' No TK_EOL: the statement continues on the next line.
                continue while
            end if
        end if

        '' -- end of line -----------------------------------------------------
        if( c = 13 orelse c = 10 ) then
            dim as long start_ = i
            if( c = 13 ) then
                i += 1
                if( i < n andalso text_[i] = 10 ) then i += 1
            else
                i += 1
            end if
            Emit( tokens, TK_EOL, start_, i - start_ )
            atLineStart = true
            continue while
        end if

        '' -- line comment ----------------------------------------------------
        if( c = asc("'") ) then
            dim as long start_ = i
            while( i < n andalso text_[i] <> 10 andalso text_[i] <> 13 )
                i += 1
            wend
            Emit( tokens, TK_COMMENT, start_, i - start_ )
            atLineStart = false
            continue while
        end if

        '' -- block comment, which NESTS in tiko ---------------------------
        if( c = asc("/") andalso i + 1 < n andalso text_[i + 1] = asc("'") ) then
            dim as long start_ = i
            dim as long depth = 0

            while( i < n )
                if( text_[i] = asc("/") andalso i + 1 < n andalso text_[i + 1] = asc("'") ) then
                    depth += 1
                    i += 2
                elseif( text_[i] = asc("'") andalso i + 1 < n andalso text_[i + 1] = asc("/") ) then
                    depth -= 1
                    i += 2
                    if( depth = 0 ) then exit while
                else
                    i += 1
                end if
            wend

            if( depth <> 0 ) then
                AddDiagnostic( diags, DIAG_ERROR, start_, start_ + 2, _
                               DIAGCODE_UNTERMINATED_COMMENT, _
                               "unterminated block comment: no matching '/" )
            end if

            Emit( tokens, TK_COMMENT, start_, i - start_ )
            atLineStart = false
            continue while
        end if

        '' -- string literal ---------------------------------------------------
        ''
        '' Three spellings: "...", !"..." with backslash escapes, and $"..."
        '' with none. In a plain string "" is one quote.
        dim as boolean isString = (c = asc(""""))
        dim as long quoteAt = i
        if( isString = false ) then
            if( c = asc("!") orelse c = asc("$") ) then
                if( i + 1 < n andalso text_[i + 1] = asc("""") ) then
                    isString = true
                    quoteAt = i + 1
                end if
            end if
        end if

        if( isString ) then
            dim as long start_ = i
            dim as boolean escaped = (text_[i] = asc("!"))
            dim as boolean closed = false

            i = quoteAt + 1
            while( i < n )
                dim as ubyte s = text_[i]

                '' A string never spans a line in tiko.
                if( s = 10 orelse s = 13 ) then exit while

                if( escaped andalso s = asc("\") andalso i + 1 < n ) then
                    i += 2
                    continue while
                end if

                if( s = asc("""") ) then
                    if( escaped = false andalso i + 1 < n andalso text_[i + 1] = asc("""") ) then
                        i += 2          '' "" is one embedded quote
                        continue while
                    end if
                    i += 1
                    closed = true
                    exit while
                end if

                i += 1
            wend

            if( closed = false ) then
                AddDiagnostic( diags, DIAG_ERROR, start_, i, _
                               DIAGCODE_UNTERMINATED_STRING, _
                               "unterminated string literal" )
            end if

            Emit( tokens, TK_STRING, start_, i - start_ )
            atLineStart = false
            continue while
        end if

        '' -- number ------------------------------------------------------------
        dim as boolean isNumber = IsDigit( c )
        if( isNumber = false andalso c = asc(".") andalso i + 1 < n ) then
            isNumber = IsDigit( text_[i + 1] )
        end if
        if( isNumber = false andalso c = asc("&") andalso i + 1 < n ) then
            select case text_[i + 1]
                case asc("h"), asc("H"), asc("o"), asc("O"), asc("b"), asc("B")
                    isNumber = true
            end select
        end if

        if( isNumber ) then
            dim as long start_ = i
            dim as boolean bad = false

            if( c = asc("&") ) then
                dim as ubyte base_ = text_[i + 1]
                i += 2
                dim as long digitsAt = i

                select case base_
                    case asc("h"), asc("H")
                        while( i < n andalso IsHexDigit( text_[i] ) )
                            i += 1
                        wend
                    case asc("o"), asc("O")
                        while( i < n andalso text_[i] >= asc("0") andalso text_[i] <= asc("7") )
                            i += 1
                        wend
                    case else
                        while( i < n andalso (text_[i] = asc("0") orelse text_[i] = asc("1")) )
                            i += 1
                        wend
                end select

                if( i = digitsAt ) then bad = true
            else
                dim as long dots = 0
                while( i < n )
                    if( IsDigit( text_[i] ) ) then
                        i += 1
                    elseif( text_[i] = asc(".") ) then
                        dots += 1
                        if( dots > 1 ) then bad = true
                        i += 1
                    else
                        exit while
                    end if
                wend

                '' Exponent: e/d, an optional sign, then at least one digit.
                if( i < n ) then
                    dim as ubyte e = text_[i]
                    if( e = asc("e") orelse e = asc("E") orelse e = asc("d") orelse e = asc("D") ) then
                        dim as long save_ = i
                        i += 1
                        if( i < n andalso (text_[i] = asc("+") orelse text_[i] = asc("-")) ) then i += 1
                        if( i < n andalso IsDigit( text_[i] ) ) then
                            while( i < n andalso IsDigit( text_[i] ) )
                                i += 1
                            wend
                        else
                            '' Not an exponent after all -- 1e is 1 followed by
                            '' the identifier e, which is what fbc reports too.
                            i = save_
                        end if
                    end if
                end if
            end if

            '' Literal suffixes: u, l, ll, f, d, and the sigils.
            while( i < n )
                dim as ubyte s = text_[i]
                if( s = asc("u") orelse s = asc("U") orelse _
                    s = asc("l") orelse s = asc("L") orelse _
                    s = asc("f") orelse s = asc("F") orelse _
                    s = asc("d") orelse s = asc("D") ) then
                    i += 1
                elseif( IsTypeSuffix( s ) andalso s <> asc("&") ) then
                    i += 1
                    exit while
                else
                    exit while
                end if
            wend

            '' A digit or letter still touching the number means it was never a
            '' valid literal: 1.2.3, &hzz, 12abc.
            if( i < n andalso IsIdentPart( text_[i] ) ) then
                bad = true
                while( i < n andalso IsIdentPart( text_[i] ) )
                    i += 1
                wend
            end if

            if( bad ) then
                AddDiagnostic( diags, DIAG_ERROR, start_, i, _
                               DIAGCODE_INVALID_NUMBER, _
                               "invalid numeric literal '" & mid( text_, start_ + 1, i - start_ ) & "'" )
            end if

            Emit( tokens, TK_NUMBER, start_, i - start_ )
            atLineStart = false
            continue while
        end if

        '' -- preprocessor directive ---------------------------------------------
        ''
        '' Only at the head of a logical line: '#' is also a file number in
        '' PRINT #1 and a stringify in a macro body.
        if( c = asc("#") andalso atLineStart ) then
            dim as long start_ = i
            i += 1
            while( i < n andalso IsIdentPart( text_[i] ) )
                i += 1
            wend
            dim as string word_ = mid( text_, start_ + 2, i - start_ - 1 )
            Emit( tokens, TK_PP, start_, i - start_, PpKeywordOf( word_ ) )
            atLineStart = false
            continue while
        end if

        '' -- identifier or keyword -----------------------------------------------
        if( IsIdentStart( c ) ) then
            dim as long start_ = i
            while( i < n andalso IsIdentPart( text_[i] ) )
                i += 1
            wend

            dim as string word_ = mid( text_, start_ + 1, i - start_ )
            dim as FbKeyword kw = KeywordOf( word_ )

            '' REM at the head of a statement comments out the rest of the line.
            if( lcase(word_) = "rem" ) then
                while( i < n andalso text_[i] <> 10 andalso text_[i] <> 13 )
                    i += 1
                wend
                Emit( tokens, TK_COMMENT, start_, i - start_ )
                atLineStart = false
                continue while
            end if

            '' A type suffix belongs to the identifier: a$ is one name. Never to
            '' a keyword, so that `end` in `end if` stays `end`.
            if( kw = KW_NONE andalso i < n ) then
                if( IsTypeSuffix( text_[i] ) ) then i += 1
            end if

            if( kw = KW_NONE ) then
                Emit( tokens, TK_IDENT, start_, i - start_ )
            else
                Emit( tokens, TK_KEYWORD, start_, i - start_, kw )
            end if

            atLineStart = false
            continue while
        end if

        '' -- punctuation and operators ---------------------------------------------
        dim as long start_ = i
        dim as TokenKind kind = TK_OP

        select case c
            case asc("(") : kind = TK_LPAREN   : i += 1
            case asc(")") : kind = TK_RPAREN   : i += 1
            case asc("[") : kind = TK_LBRACKET : i += 1
            case asc("]") : kind = TK_RBRACKET : i += 1
            case asc(",") : kind = TK_COMMA    : i += 1
            case asc(":") : kind = TK_COLON    : i += 1

            case asc("<")
                i += 1
                if( i < n andalso (text_[i] = asc("=") orelse text_[i] = asc(">")) ) then i += 1
            case asc(">")
                i += 1
                if( i < n andalso text_[i] = asc("=") ) then i += 1
            case asc("=")
                i += 1
                if( i < n andalso text_[i] = asc(">") ) then i += 1
            case asc("-")
                i += 1
                if( i < n andalso text_[i] = asc(">") ) then i += 1
            '' Braces are ordinary punctuation here: they delimit array and
            '' UDT initialisers -- `dim a(0 to 2) as long = { 1, 2, 3 }` -- and
            '' those routinely span lines, so they are deliberately NOT part of
            '' the per-statement balance check.
            case asc("+"), asc("*"), asc("/"), asc("\"), asc("^"), asc("&"), _
                 asc("@"), asc("."), asc(";"), asc("?"), asc("!"), asc("$"), _
                 asc("%"), asc("#"), asc("~"), asc("{"), asc("}")
                i += 1

            case else
                '' Nothing in the language begins with this byte.
                i += 1
                AddDiagnostic( diags, DIAG_ERROR, start_, i, _
                               DIAGCODE_UNEXPECTED_CHAR, _
                               "unexpected character '" & chr(c) & "'" )
                kind = TK_BAD
        end select

        Emit( tokens, kind, start_, i - start_ )
        atLineStart = false
    wend

    '' A trailing TK_EOL for the last line if the file does not end with one,
    '' so the parser can close its statement without a special case, then EOF.
    if( tokens.Count( ) > 0 ) then
        if( tokens[ tokens.Count( ) - 1 ].Kind <> TK_EOL ) then Emit( tokens, TK_EOL, n, 0 )
    end if
    Emit( tokens, TK_EOF, n, 0 )
end sub
