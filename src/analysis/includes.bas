'' ############################################################################
''  analysis/includes.bas -- what a file pulls in
'' ############################################################################

#include once "includes.bi"
#include once "fb/map.bi"

'' The text of a string token without its quotes, and without the escape
'' processing a `!"..."` literal would need -- an include path is a path, and
'' `!` before one is not something fbc accepts either.
private function Unquote( byref text_ as string, byref tok as Token ) as string
    dim as string raw_ = TokenText( text_, tok )
    if( len(raw_) < 2 ) then return ""

    '' `$"..."` marks a non-escaping literal, which is what a Windows path
    '' wants; the marker is not part of the path.
    if( left( raw_, 1 ) = "$" orelse left( raw_, 1 ) = "!" ) then raw_ = mid( raw_, 2 )
    if( len(raw_) < 2 ) then return ""

    if( left( raw_, 1 ) <> """" ) then return ""
    raw_ = mid( raw_, 2 )
    if( right( raw_, 1 ) = """" ) then raw_ = left( raw_, len(raw_) - 1 )
    return raw_
end function

sub FindIncludes( byref text_ as string, byref tokens as TokenArray, _
                  byref out_ as IncludeRefArray )
    out_.Clear( )

    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_PP ) then continue for
        if( lcase( TokenText( text_, tokens[i] ) ) <> "#include" ) then continue for

        '' `once` is optional and is an ordinary identifier to the lexer.
        dim as long k = i + 1
        dim as boolean once_ = false

        while( k < tokens.Count( ) )
            dim as Token t = tokens[k]
            if( t.Kind = TK_COMMENT ) then
                k += 1
                continue while
            end if
            if( t.Kind = TK_IDENT andalso lcase( TokenText( text_, t ) ) = "once" ) then
                once_ = true
                k += 1
                continue while
            end if
            exit while
        wend

        if( k >= tokens.Count( ) ) then exit for

        '' Anything but a string literal here is a macro, and a path this
        '' server cannot know without expanding it.
        if( tokens[k].Kind <> TK_STRING ) then continue for

        dim as string target = Unquote( text_, tokens[k] )
        if( len(target) = 0 ) then continue for

        dim as IncludeRef r
        r.Target  = target
        r.Once_   = once_
        r.Start_  = tokens[k].Start_
        r.Length_ = tokens[k].Length_
        out_.Push( r )
    next
end sub

'' THE IMPORTS: `#import "a/b" [as x] [public]`. The path is a plain string literal -- a
'' module path is never a macro -- and anything malformed is skipped rather than reported:
'' the compiler says what is wrong with it, this only needs to know what it names.
sub FindImports( byref text_ as string, byref tokens as TokenArray, _
                 byref out_ as ImportRefArray )
    out_.Clear( )

    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_PP ) then continue for
        if( lcase( TokenText( text_, tokens[i] ) ) <> "#import" ) then continue for

        dim as long k = i + 1
        while( k < tokens.Count( ) andalso tokens[k].Kind = TK_COMMENT )
            k += 1
        wend
        if( k >= tokens.Count( ) ) then exit for
        if( tokens[k].Kind <> TK_STRING ) then continue for

        dim as ImportRef r
        r.Path_   = Unquote( text_, tokens[k] )
        if( len(r.Path_) = 0 ) then continue for
        r.Start_  = tokens[k].Start_
        r.Length_ = tokens[k].Length_
        dim as long sl = instrrev( r.Path_, "/" )
        r.Alias_  = lcase( mid( r.Path_, sl + 1 ) )

        '' `as NAME` and `public`, in that order, on the same line.
        k += 1
        while( k < tokens.Count( ) )
            dim as Token t = tokens[k]
            if( t.Kind = TK_EOL orelse t.Kind = TK_EOF ) then exit while
            dim as string w = lcase( TokenText( text_, t ) )
            if( w = "as" andalso k + 1 < tokens.Count( ) ) then
                dim as Token a = tokens[k + 1]
                if( a.Kind = TK_IDENT orelse a.Kind = TK_KEYWORD ) then
                    r.Alias_ = lcase( TokenText( text_, a ) )
                    k += 1
                end if
            elseif( w = "public" ) then
                r.Public_ = true
            end if
            k += 1
        wend

        out_.Push( r )
    next
end sub

'' The next token that is not a comment, from `k`; tokens.Count( ) when there is none.
private function SkipComments_( byref tokens as TokenArray, byval k as long ) as long
    while( k < tokens.Count( ) andalso tokens[k].Kind = TK_COMMENT )
        k += 1
    wend
    return k
end function

'' THE EXPORTS: each name on an `#export` line, joined to its `#define` in the same file.
'' A module's macros are defined in the file that exports them -- the compiler refuses an
'' export of a name nothing defined (TKO0365) -- so one file is all this needs to read.
sub FindExports( byref text_ as string, byref tokens as TokenArray, _
                 byref out_ as ExportRefArray )
    out_.Clear( )

    '' Every `#define NAME ...`, by lower-cased name: where the name is, and the body.
    dim defs as FB.Map( of string, long )
    dim defNames as FB.Array( of ExportRef )
    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_PP ) then continue for
        if( lcase( TokenText( text_, tokens[i] ) ) <> "#define" ) then continue for
        dim as long k = SkipComments_( tokens, i + 1 )
        if( k >= tokens.Count( ) ) then exit for
        if( tokens[k].Kind <> TK_IDENT andalso tokens[k].Kind <> TK_KEYWORD ) then continue for
        dim as ExportRef d
        d.Name_     = TokenText( text_, tokens[k] )
        d.LowerName = lcase( d.Name_ )
        d.Start_    = tokens[k].Start_
        d.Length_   = tokens[k].Length_
        '' A function-like macro's parameters are not its body: `NAME(` with no space.
        dim as long b = k + 1
        if( b < tokens.Count( ) andalso tokens[b].Kind = TK_LPAREN andalso _
            tokens[b].Start_ = tokens[k].Start_ + tokens[k].Length_ ) then
            while( b < tokens.Count( ) andalso tokens[b].Kind <> TK_RPAREN andalso _
                   tokens[b].Kind <> TK_EOL andalso tokens[b].Kind <> TK_EOF )
                b += 1
            wend
            b += 1
        end if
        '' The body: to the end of the line, comments aside.
        dim as long first_ = -1, last_ = -1

        dim bodyToks as FB.Array( of long )
        while( b < tokens.Count( ) )
            if( tokens[b].Kind = TK_EOL orelse tokens[b].Kind = TK_EOF ) then exit while
            if( tokens[b].Kind <> TK_COMMENT ) then
                if( first_ < 0 ) then first_ = b
                last_ = b
                bodyToks.Push( b )
            end if
            b += 1
        wend
        if( first_ >= 0 ) then
            d.Body = mid( text_, tokens[first_].Start_ + 1, _
                          tokens[last_].Start_ + tokens[last_].Length_ - tokens[first_].Start_ )
            '' `A.B`: three tokens, a name, a dot, a name.
            if( bodyToks.Count( ) = 3 ) then
                dim as Token ta = tokens[bodyToks[0]], td = tokens[bodyToks[1]], tb = tokens[bodyToks[2]]
                dim as boolean shaped = (ta.Kind = TK_IDENT orelse ta.Kind = TK_KEYWORD) andalso _
                                        (td.Kind = TK_OP) andalso _
                                        (tb.Kind = TK_IDENT orelse tb.Kind = TK_KEYWORD)
                if( shaped ) then shaped = ( TokenText( text_, td ) = "." )
                if( shaped ) then
                    d.TargetNs   = lcase( TokenText( text_, ta ) )
                    d.TargetName = lcase( TokenText( text_, tb ) )
                end if
            end if
        end if
        defs.Put( d.LowerName, defNames.Count( ) )
        defNames.Push( d )
    next

    '' Every `#export A, B, ...`.
    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_PP ) then continue for
        if( lcase( TokenText( text_, tokens[i] ) ) <> "#export" ) then continue for
        dim as long k = i + 1
        while( k < tokens.Count( ) )
            dim as Token t = tokens[k]
            if( t.Kind = TK_EOL orelse t.Kind = TK_EOF ) then exit while
            if( t.Kind = TK_IDENT orelse t.Kind = TK_KEYWORD ) then
                dim as ExportRef r
                dim as long di = -1
                if( defs.TryGet( lcase( TokenText( text_, t ) ), di ) ) then
                    r = defNames[di]
                else
                    r.Name_     = TokenText( text_, t )
                    r.LowerName = lcase( r.Name_ )
                    r.Start_    = t.Start_
                    r.Length_   = t.Length_
                end if
                out_.Push( r )
            end if
            k += 1
        wend
    next
end sub

function IncludeAtOffset( byref includes_ as IncludeRefArray, byval offset as long ) as long
    for i as long = 0 to includes_.Count( ) - 1
        '' Inclusive of both ends: a caret resting on the closing quote is
        '' still on the path as far as a user is concerned.
        if( offset >= includes_[i].Start_ andalso _
            offset <= includes_[i].Start_ + includes_[i].Length_ ) then return i
    next
    return -1
end function
