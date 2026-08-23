'' ############################################################################
''  tests/test_semantic.bas -- semantic tokens
''
''  The encoding is where this feature fails silently: a client that receives
''  a token spanning a line, an unsorted list, or a delta computed against the
''  wrong previous token renders nonsense or nothing at all, and reports
''  neither. So the tests are mostly about the ENCODING, not about colours.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#include once "assert.bi"
#include once "../src/analysis/parser.bi"
#include once "../src/analysis/semantic.bi"

const LF = chr(10)

dim shared as string          g_Src
dim shared as TokenArray      g_Tokens
dim shared as DiagnosticArray g_Diags
dim shared as SymbolTable     g_Syms
dim shared as LineIndex       g_Index
dim shared as SemTokenArray   g_Toks

private sub Analyse( byref src as string )
    g_Src = src
    AnalyzeFull( g_Src, g_Tokens, g_Diags, g_Syms )
    g_Index.Rebuild( g_Src )
    ComputeSemanticTokens( g_Src, g_Index, g_Tokens, g_Syms, g_Toks )
end sub

'' The first semantic token at a line and character, or -1.
private function At_( byval lineNo as long, byval charNo as long ) as long
    for i as long = 0 to g_Toks.Count( ) - 1
        if( g_Toks[i].Line = lineNo andalso g_Toks[i].Char_ = charNo ) then return i
    next
    return -1
end function

private function TypeAt( byval lineNo as long, byval charNo as long ) as long
    dim as long i = At_( lineNo, charNo )
    if( i < 0 ) then return -1
    return g_Toks[i].Type_
end function

private function ModsAt( byval lineNo as long, byval charNo as long ) as long
    dim as long i = At_( lineNo, charNo )
    if( i < 0 ) then return -1
    return g_Toks[i].Mods
end function

'' ############################################################################
''  The legend
'' ############################################################################
private sub TestLegend( )
    TestGroup( "the legend" )

    dim names_ as FB.Array( of string ) = SemanticTypeNames( )
    AssertEqInt( names_.Count( ), SEMTYPE_COUNT, "one name per type index" )
    AssertEqStr( names_[SEMTYPE_KEYWORD],  "keyword",  "the index IS the wire format" )
    AssertEqStr( names_[SEMTYPE_PARAMETER], "parameter", "and so is this one" )

    dim mods_ as FB.Array( of string ) = SemanticModifierNames( )
    AssertEqInt( mods_.Count( ), 3, "three modifiers" )
    AssertEqStr( mods_[0], "declaration", "bit 1 is `declaration`" )
end sub

'' ############################################################################
''  What each token is
'' ############################################################################
private sub TestClassification( )
    TestGroup( "classification" )

    ''         0         1         2
    ''         0123456789012345678901234567890
    Analyse( "type Widget" & LF & _                        '' line 0
             "    Count as long" & LF & _                  '' line 1
             "end type" & LF & _                           '' line 2
             "" & LF & _                                   '' line 3
             "sub Show( byval w as long )" & LF & _        '' line 4
             "    dim as long n = 42" & LF & _             '' line 5
             "    print ""hi"", w, n" & LF & _             '' line 6
             "end sub" & LF )                              '' line 7

    AssertEqInt( TypeAt( 0, 0 ), SEMTYPE_KEYWORD, "TYPE is a keyword" )
    AssertEqInt( TypeAt( 0, 5 ), SEMTYPE_STRUCT,  "the type's name is a struct" )
    AssertEqInt( ModsAt( 0, 5 ) and SEMMOD_DECLARATION, SEMMOD_DECLARATION, _
                 "and this occurrence is its declaration" )

    AssertEqInt( TypeAt( 1, 4 ), SEMTYPE_PROPERTY, "a field is a property" )
    AssertEqInt( TypeAt( 4, 4 ), SEMTYPE_FUNCTION, "a file-level SUB is a function" )
    AssertEqInt( TypeAt( 4, 16 ), SEMTYPE_PARAMETER, "a parameter is a parameter" )
    AssertEqInt( TypeAt( 5, 16 ), SEMTYPE_VARIABLE, "a local is a variable" )
    AssertEqInt( TypeAt( 5, 20 ), SEMTYPE_NUMBER, "a literal is a number" )
    AssertEqInt( TypeAt( 6, 10 ), SEMTYPE_STRING, "a string literal is a string" )

    '' The USE of the parameter, not its declaration, carries no declaration
    '' bit -- which is what tells an editor to render it differently.
    AssertEqInt( TypeAt( 6, 16 ), SEMTYPE_PARAMETER, "the use of a parameter is one too" )
    AssertEqInt( ModsAt( 6, 16 ) and SEMMOD_DECLARATION, 0, "but it is not a declaration" )

    '' Punctuation is deliberately absent: a client's own grammar colours it,
    '' and sending it would double the payload.
    AssertEqInt( At_( 4, 8 ), -1, "an opening parenthesis produces no token" )

    '' An identifier this file never declares gets no colour rather than a
    '' guessed one.
    Analyse( "sub Go_( )" & LF & _
             "    MysteryCall( 1 )" & LF & _
             "end sub" & LF )
    AssertEqInt( At_( 1, 4 ), -1, "an unknown identifier is left to the grammar" )
end sub

'' ############################################################################
''  Tokens never span a line
'' ############################################################################
private sub TestLineSplitting( )
    TestGroup( "line splitting" )

    Analyse( "/' one" & LF & _
             "   two" & LF & _
             "   three '/" & LF & _
             "dim as long n = 1" & LF )

    dim as long comments = 0
    for i as long = 0 to g_Toks.Count( ) - 1
        if( g_Toks[i].Type_ = SEMTYPE_COMMENT ) then comments += 1
    next

    '' THE rule that breaks a client silently when it is missed.
    AssertEqInt( comments, 3, "a three-line block comment is three tokens" )
    AssertEqInt( TypeAt( 0, 0 ), SEMTYPE_COMMENT, "starting on line 0" )
    AssertEqInt( TypeAt( 2, 0 ), SEMTYPE_COMMENT, "and ending on line 2" )

    for i as long = 0 to g_Toks.Count( ) - 1
        dim as longint lineEnd = g_Index.LineContentEnd( g_Src, g_Toks[i].Line )
        dim as longint lineStart = g_Index.LineStart( g_Toks[i].Line )
        if( g_Toks[i].Char_ + g_Toks[i].Length_ > lineEnd - lineStart ) then
            TestFail( "a token runs past the end of its line", _
                      "line " & g_Toks[i].Line & " char " & g_Toks[i].Char_ )
            exit sub
        end if
    next
    TestPass( "no token runs past the end of its line" )
end sub

'' ############################################################################
''  The delta encoding
'' ############################################################################
private sub TestEncoding( )
    TestGroup( "the delta encoding" )

    Analyse( "dim as long alpha = 1" & LF & _
             "dim as long beta = 2" & LF )

    dim data_ as FB.Array( of long )
    EncodeSemanticTokens( g_Toks, data_ )

    AssertEqInt( data_.Count( ) mod 5, 0, "five integers per token" )
    AssertEqInt( data_.Count( ) \ 5, g_Toks.Count( ), "and one group per token" )

    '' The first token's delta is its absolute position.
    AssertEqInt( data_[0], g_Toks[0].Line,  "the first line delta is absolute" )
    AssertEqInt( data_[1], g_Toks[0].Char_, "and so is the first character delta" )

    '' Every later token is relative -- to the line, and within a line to the
    '' character. Rebuilding the absolute positions from the deltas must give
    '' back exactly what was encoded; this is the check a client performs.
    dim as long line_ = 0
    dim as long char_ = 0
    dim as boolean ok_ = true

    for i as long = 0 to data_.Count( ) - 1 step 5
        line_ += data_[i]
        if( data_[i] = 0 ) then char_ += data_[i + 1] else char_ = data_[i + 1]

        dim as long t = i \ 5
        if( line_ <> g_Toks[t].Line orelse char_ <> g_Toks[t].Char_ ) then ok_ = false
        if( data_[i] < 0 ) then ok_ = false
    next

    AssertTrue( ok_, "the deltas rebuild the original positions" )

    '' An empty document encodes to an empty array -- which CLEARS the
    '' client's colours, and is a different thing from sending nothing.
    dim empty_ as SemTokenArray
    EncodeSemanticTokens( empty_, data_ )
    AssertEqInt( data_.Count( ), 0, "no tokens encodes to no integers" )
end sub

'' ############################################################################
''  UTF-16, as everywhere else
'' ############################################################################
private sub TestUtf16( )
    TestGroup( "UTF-16 columns" )

    '' The name is preceded by a CJK ideograph in a comment: three bytes, one
    '' UTF-16 unit. An emoji is four bytes and TWO units.
    Analyse( "'" & chr(228,184,173) & LF & _
             "dim as long n = 1" & LF )

    AssertEqInt( TypeAt( 0, 0 ), SEMTYPE_COMMENT, "the comment starts at column 0" )
    dim as long ci = At_( 0, 0 )
    AssertEqInt( g_Toks[ci].Length_, 2, "and is two UTF-16 units long, not four bytes" )

    Analyse( "dim as string s = """ & chr(240,159,152,128) & """" & LF )
    dim as long si = At_( 0, 18 )
    AssertTrue( si >= 0, "the string literal starts at the right column" )
    AssertEqInt( g_Toks[si].Length_, 4, "an emoji counts as two units inside it" )
end sub

'' ############################################################################
''  Main
'' ############################################################################
print "tiko-lsp -- semantic token tests"

TestLegend( )
TestClassification( )
TestLineSplitting( )
TestEncoding( )
TestUtf16( )

end TestSummary( "semantic tokens" )
