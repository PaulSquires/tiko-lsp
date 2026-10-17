'' ############################################################################
''  analysis/semantic.bi -- semantic tokens
''
''  What a client already knows from a TextMate grammar: this is a keyword,
''  this is a string. What only a server knows: this identifier is a TYPE, that
''  one is a PARAMETER, and the one after the dot is a FIELD. Semantic tokens
''  are the channel for the second kind, layered on top of the first.
''
''  THREE RULES THE PROTOCOL IMPOSES, each of which is a silent failure when
''  broken -- the client shows nothing and reports nothing:
''
''    1. tokens are sorted by position, and encoded as DELTAS from the previous
''       token: line delta, then character delta within a line;
''    2. NO TOKEN MAY SPAN A LINE. A block comment over four lines is four
''       tokens, and this is the rule most easily missed, because most tokens
''       never span one;
''    3. lengths and characters are in UTF-16 CODE UNITS, like every other
''       position in LSP.
''
''  WHAT IS DELIBERATELY NOT EMITTED: punctuation. Every parenthesis and comma
''  in a file would double the payload to tell a client what its own grammar
''  already coloured. An identifier that resolves to nothing is also left
''  alone -- an unknown name is better left to the grammar than coloured as a
''  variable on a guess.
''
''  COLOURED BY NAME, NOT BY RESOLUTION. Full-file tokens are recomputed on
''  every keystroke by clients that do not implement deltas, so this must cost
''  a millisecond, not a scope walk per identifier. Two symbols with one name
''  therefore share a colour -- which they would anyway, in every case but the
''  rare one where a field and a procedure are called the same thing.
'' ############################################################################

#pragma once

#include once "lexer.bi"
#include once "symbols.bi"
#include once "../utils/position.bi"

'' ----------------------------------------------------------------------------
''  The legend
''
''  These indices ARE the wire format: a client is sent this list once, in
''  ServerCapabilities, and then receives numbers. Append only -- renumbering
''  after a client has cached the legend recolours the file wrongly.
'' ----------------------------------------------------------------------------
enum SemTokenType
    SEMTYPE_NAMESPACE     = 0
    SEMTYPE_TYPE          = 1
    SEMTYPE_STRUCT        = 2
    SEMTYPE_ENUM          = 3
    SEMTYPE_ENUMMEMBER    = 4
    SEMTYPE_INTERFACE     = 5
    SEMTYPE_TYPEPARAMETER = 6
    SEMTYPE_PARAMETER     = 7
    SEMTYPE_VARIABLE      = 8
    SEMTYPE_PROPERTY      = 9
    SEMTYPE_FUNCTION      = 10
    SEMTYPE_METHOD        = 11
    SEMTYPE_MACRO         = 12
    SEMTYPE_KEYWORD       = 13
    SEMTYPE_COMMENT       = 14
    SEMTYPE_STRING        = 15
    SEMTYPE_NUMBER        = 16
    SEMTYPE_OPERATOR      = 17
    SEMTYPE_COUNT         = 18
end enum

'' A bit set, sent as one integer per token.
enum SemTokenModifier
    SEMMOD_DECLARATION = 1    '' this occurrence is where the name is declared
    SEMMOD_READONLY    = 2    '' a CONST or an enum member
    SEMMOD_STATIC      = 4    '' declared at file level rather than in a scope
end enum

'' The legend, in index order, as the strings the specification defines.
declare function SemanticTypeNames    ( ) as containers.Array( of string )
declare function SemanticModifierNames( ) as containers.Array( of string )

'' ----------------------------------------------------------------------------
''  One token, before encoding
'' ----------------------------------------------------------------------------
type SemToken
    Line    as long        '' 0-based
    Char_   as long        '' 0-based, UTF-16 code units
    Length_ as long        '' UTF-16 code units; never crosses a line
    Type_   as long        '' a SemTokenType
    Mods    as long        '' a bit set of SemTokenModifier
end type

type SemTokenArray as containers.Array( of SemToken )

'' Classifies every token of an analysed document. Output is in source order
'' and no entry spans a line.
declare sub ComputeSemanticTokens( byref text_ as string, byref idx as LineIndex, _
                                   byref tokens as TokenArray, byref symbols as SymbolTable, _
                                   byref out_ as SemTokenArray )

'' The delta encoding the protocol asks for: five integers per token.
declare sub EncodeSemanticTokens( byref toks as SemTokenArray, byref data_ as containers.Array( of long ) )

'' The semantic type for a symbol kind, or -1 when it has none.
declare function SemanticTypeOfKind( byval kind as SymbolKind, byval isLocal as boolean, _
                                     byval isParameter as boolean ) as long
