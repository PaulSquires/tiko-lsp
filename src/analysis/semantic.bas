'' ############################################################################
''  analysis/semantic.bas -- semantic tokens
'' ############################################################################

#import "std/containers"
#include once "semantic.bi"

'' The name a client is sent for each legend index. These are the
'' specification's own spellings; a client matches them against its theme, so
'' an invented name simply gets no colour.
function SemanticTypeNames( ) as containers.Array( of string )
    dim out_ as containers.Array( of string )
    out_.Push( "namespace" )
    out_.Push( "type" )
    out_.Push( "struct" )
    out_.Push( "enum" )
    out_.Push( "enumMember" )
    out_.Push( "interface" )
    out_.Push( "typeParameter" )
    out_.Push( "parameter" )
    out_.Push( "variable" )
    out_.Push( "property" )
    out_.Push( "function" )
    out_.Push( "method" )
    out_.Push( "macro" )
    out_.Push( "keyword" )
    out_.Push( "comment" )
    out_.Push( "string" )
    out_.Push( "number" )
    out_.Push( "operator" )
    return out_
end function

function SemanticModifierNames( ) as containers.Array( of string )
    dim out_ as containers.Array( of string )
    out_.Push( "declaration" )
    out_.Push( "readonly" )
    out_.Push( "static" )
    return out_
end function

function SemanticTypeOfKind( byval kind as SymbolKind, byval isLocal as boolean, _
                             byval isParameter as boolean ) as long
    if( isParameter ) then return SEMTYPE_PARAMETER

    select case kind
        case SYM_NAMESPACE                 : return SEMTYPE_NAMESPACE
        case SYM_CLASS, SYM_STRUCT, SYM_OBJECT : return SEMTYPE_STRUCT
        case SYM_INTERFACE                 : return SEMTYPE_INTERFACE
        case SYM_ENUM                      : return SEMTYPE_ENUM
        case SYM_ENUMMEMBER                : return SEMTYPE_ENUMMEMBER
        case SYM_TYPEPARAMETER             : return SEMTYPE_TYPEPARAMETER
        case SYM_FUNCTION                  : return SEMTYPE_FUNCTION
        case SYM_METHOD, SYM_CONSTRUCTOR   : return SEMTYPE_METHOD
        case SYM_OPERATOR                  : return SEMTYPE_METHOD
        case SYM_PROPERTY, SYM_FIELD       : return SEMTYPE_PROPERTY
        case SYM_CONSTANT                  : return SEMTYPE_VARIABLE
        case SYM_VARIABLE                  : return SEMTYPE_VARIABLE
    end select

    return -1
end function

'' ----------------------------------------------------------------------------
''  Classification
'' ----------------------------------------------------------------------------

'' A name's colour, packed into one integer so the lookup is one hash probe:
''     type * 16 + modifiers
private function PackClass( byval type_ as long, byval mods as long ) as long
    return type_ * 16 + mods
end function

'' How strongly a symbol claims a name it shares with another. A file-level
'' declaration wins over a local, because that is the one visible from
'' everywhere the name can be written.
private function ClaimRank( byref sym as SymbolInfo ) as long
    if( sym.IsParameter ) then return 1
    if( sym.IsLocal ) then return 2
    if( sym.IsDeclaration ) then return 3
    return 4
end function

sub ComputeSemanticTokens( byref text_ as string, byref idx as LineIndex, _
                           byref tokens as TokenArray, byref symbols as SymbolTable, _
                           byref out_ as SemTokenArray )

    out_.Clear( )

    '' -- what each NAME is, and where each name is DECLARED -------------------
    dim byName as containers.Map( of string, long )
    dim byRank as containers.Map( of string, long )
    dim declAt as containers.Map( of long, long )

    for i as long = 0 to symbols.Count( ) - 1
        dim as long type_ = SemanticTypeOfKind( symbols.Items[i].Kind_, _
                                                symbols.Items[i].IsLocal, _
                                                symbols.Items[i].IsParameter )
        if( type_ < 0 ) then continue for

        dim as long mods = 0
        if( symbols.Items[i].Kind_ = SYM_CONSTANT orelse _
            symbols.Items[i].Kind_ = SYM_ENUMMEMBER ) then mods or= SEMMOD_READONLY
        if( symbols.Items[i].IsLocal = false ) then mods or= SEMMOD_STATIC

        '' The declaration itself, found by its exact offset -- this is the one
        '' occurrence that can be marked `declaration` without resolving
        '' anything.
        declAt.Put( symbols.Items[i].NameStart, PackClass( type_, mods or SEMMOD_DECLARATION ) )

        dim as long rank = ClaimRank( symbols.Items[i] )
        dim as long seen = 0
        if( byRank.TryGet( symbols.Items[i].LowerName, seen ) ) then
            if( seen >= rank ) then continue for
        end if

        byRank.Put( symbols.Items[i].LowerName, rank )
        byName.Put( symbols.Items[i].LowerName, PackClass( type_, mods ) )
    next

    '' -- one classified span per token ---------------------------------------
    for i as long = 0 to tokens.Count( ) - 1
        dim as Token tok = tokens[i]
        if( tok.Length_ <= 0 ) then continue for

        dim as long type_ = -1
        dim as long mods  = 0

        select case tok.Kind
            case TK_COMMENT : type_ = SEMTYPE_COMMENT
            case TK_STRING  : type_ = SEMTYPE_STRING
            case TK_NUMBER  : type_ = SEMTYPE_NUMBER
            case TK_KEYWORD : type_ = SEMTYPE_KEYWORD
            case TK_PP      : type_ = SEMTYPE_MACRO

            case TK_IDENT
                '' The declaration site first: it is exact, and it is the only
                '' place the `declaration` modifier is honest.
                dim as long packed = 0
                if( declAt.TryGet( tok.Start_, packed ) = false ) then
                    if( byName.TryGet( lcase( TokenText( text_, tok ) ), packed ) = false ) then
                        '' One of tiko-lang's own typedefs, int32 and the rest.
                        '' Only here, after the file's own names: a file that
                        '' declares int32 itself has replaced tiko's. Never after
                        '' a dot, where `rec.int32` is a member of something.
                        dim as boolean builtinType = _
                            len( BuiltinTypedefTarget( TokenText( text_, tok ) ) ) > 0
                        if( builtinType ) then builtinType = ( IsMemberAccess( text_, tokens, i ) = false )
                        '' ...and its predeclared constant, nullptr: coloured as a
                        '' file-level CONST is, readonly and static.
                        dim as boolean builtinConst = _
                            len( BuiltinConstantDecl( TokenText( text_, tok ) ) ) > 0
                        if( builtinConst ) then builtinConst = ( IsMemberAccess( text_, tokens, i ) = false )
                        if( builtinType ) then
                            packed = SEMTYPE_TYPE * 16
                        elseif( builtinConst ) then
                            packed = PackClass( SEMTYPE_VARIABLE, SEMMOD_READONLY or SEMMOD_STATIC )
                        else
                            '' An identifier this file never declares: a name
                            '' from an #include, or one being typed. The
                            '' grammar can have it -- a guess here would be a
                            '' wrong colour rather than no colour.
                            continue for
                        end if
                    end if
                end if

                type_ = packed \ 16
                mods  = packed and 15
        end select

        if( type_ < 0 ) then continue for

        '' -- split at line boundaries -----------------------------------------
        ''
        '' A nesting block comment routinely spans a screenful, and a token
        '' that crosses a line makes a client drop the WHOLE response.
        dim as long tokEnd   = tok.Start_ + tok.Length_
        dim as long firstLn  = idx.LineOfOffset( tok.Start_ )
        dim as long lastLn   = idx.LineOfOffset( tokEnd - 1 )

        for ln as long = firstLn to lastLn
            dim as longint lineStart = idx.LineStart( ln )
            dim as longint lineEnd   = idx.LineContentEnd( text_, ln )

            dim as longint segStart = lineStart
            if( tok.Start_ > segStart ) then segStart = tok.Start_

            dim as longint segEnd = lineEnd
            if( tokEnd < segEnd ) then segEnd = tokEnd

            if( segEnd <= segStart ) then continue for

            dim as SemToken st
            st.Line    = ln
            st.Char_   = Utf16UnitsInRange( text_, lineStart, segStart )
            st.Length_ = Utf16UnitsInRange( text_, segStart, segEnd )
            st.Type_   = type_
            st.Mods    = mods

            if( st.Length_ > 0 ) then out_.Push( st )
        next
    next
end sub

sub EncodeSemanticTokens( byref toks as SemTokenArray, byref data_ as containers.Array( of long ) )
    data_.Clear( )

    dim as long prevLine = 0
    dim as long prevChar = 0

    for i as long = 0 to toks.Count( ) - 1
        dim as long dLine = toks[i].Line - prevLine

        '' A negative delta means the input was not sorted, which the client
        '' has no way to detect -- it would simply render nonsense. Dropping
        '' the token is the containable failure.
        if( dLine < 0 ) then continue for

        dim as long dChar = toks[i].Char_
        if( dLine = 0 ) then
            dChar = toks[i].Char_ - prevChar
            if( dChar < 0 ) then continue for
        end if

        data_.Push( dLine )
        data_.Push( dChar )
        data_.Push( toks[i].Length_ )
        data_.Push( toks[i].Type_ )
        data_.Push( toks[i].Mods )

        prevLine = toks[i].Line
        prevChar = toks[i].Char_
    next
end sub
