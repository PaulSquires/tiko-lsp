'' ############################################################################
''  tests/test_position.bas -- the line index and UTF-16 <-> byte conversion
''
''  This is the module every later feature sits on: a hover, a definition and a
''  rename are all "turn this LSP position into an offset, and this offset back
''  into a position". An error here is invisible in ASCII and wrong in every
''  file that contains one non-Latin character.
'' ############################################################################

#include once "assert.bi"
#include once "../src/utils/position.bi"

const LF  = chr(10)
const CR  = chr(13)

'' 中 = E4 B8 AD, 文 = E6 96 87 -- 3 bytes each, ONE UTF-16 unit each.
const CJK1 = chr(228,184,173)
const CJK2 = chr(230,150,135)

'' U+1F600 GRINNING FACE = F0 9F 98 80 -- 4 bytes, TWO UTF-16 units.
const EMOJI = chr(240,159,152,128)

'' ----------------------------------------------------------------------------
TestGroup( "line index: terminators" )

scope
    dim as LineIndex idx

    idx.Rebuild( "" )
    AssertEqInt( idx.LineCount( ), 1, "an empty document still has one line" )
    AssertEqInt( idx.LineStart( 0 ), 0, "line 0 starts at 0" )
    AssertEqInt( idx.TextLength( ), 0, "an empty document is zero bytes" )

    idx.Rebuild( "abc" )
    AssertEqInt( idx.LineCount( ), 1, "text with no terminator is one line" )
    AssertEqInt( idx.LineContentEnd( "abc", 0 ), 3, "its content ends at the end" )

    idx.Rebuild( "a" & LF & "b" )
    AssertEqInt( idx.LineCount( ), 2, "LF splits two lines" )
    AssertEqInt( idx.LineStart( 1 ), 2, "the second line starts after the LF" )

    dim as string crlf = "a" & CR & LF & "b"
    idx.Rebuild( crlf )
    AssertEqInt( idx.LineCount( ), 2, "CRLF is ONE terminator, not two" )
    AssertEqInt( idx.LineStart( 1 ), 3, "the second line starts after the CRLF" )
    AssertEqInt( idx.LineContentEnd( crlf, 0 ), 1, "the CR is not part of the content" )

    dim as string cronly = "a" & CR & "b"
    idx.Rebuild( cronly )
    AssertEqInt( idx.LineCount( ), 2, "a lone CR also terminates a line" )
    AssertEqInt( idx.LineContentEnd( cronly, 0 ), 1, "the lone CR is not content" )

    idx.Rebuild( "a" & LF )
    AssertEqInt( idx.LineCount( ), 2, "a trailing newline creates an empty last line" )
    AssertEqInt( idx.LineStart( 1 ), 2, "the empty last line starts at the end" )

    idx.Rebuild( LF & LF & LF )
    AssertEqInt( idx.LineCount( ), 4, "three newlines are four lines" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "line index: lookup and clamping" )

scope
    dim as string src = "one" & LF & "two" & LF & "three"
    dim as LineIndex idx
    idx.Rebuild( src )

    AssertEqInt( idx.LineOfOffset( 0 ),  0, "offset 0 is on line 0" )
    AssertEqInt( idx.LineOfOffset( 3 ),  0, "the terminator belongs to its own line" )
    AssertEqInt( idx.LineOfOffset( 4 ),  1, "the first byte after LF is the next line" )
    AssertEqInt( idx.LineOfOffset( 8 ),  2, "the third line is found" )
    AssertEqInt( idx.LineOfOffset( 13 ), 2, "the end of the document is on the last line" )
    AssertEqInt( idx.LineOfOffset( -5 ), 0, "a negative offset clamps to line 0" )

    AssertEqInt( idx.LineStart( 99 ), len(src), "a line past the end clamps to the end" )
    AssertEqInt( idx.LineStart( -1 ), 0, "a negative line clamps to 0" )
    AssertEqInt( idx.LineContentEnd( src, 1 ), 7, "line 1 content ends before its LF" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "UTF-16 counting" )

scope
    dim as string ascii_ = "hello"
    AssertEqInt( Utf16UnitsInRange( ascii_, 0, 5 ), 5, "ASCII is one unit per byte" )

    dim as string cjk = CJK1 & CJK2
    AssertEqInt( len(cjk), 6, "two CJK characters are six bytes" )
    AssertEqInt( Utf16UnitsInRange( cjk, 0, 6 ), 2, "but only two UTF-16 units" )
    AssertEqInt( Utf16UnitsInRange( cjk, 0, 3 ), 1, "one character is one unit" )

    AssertEqInt( len(EMOJI), 4, "an astral character is four bytes" )
    AssertEqInt( Utf16UnitsInRange( EMOJI, 0, 4 ), 2, "and TWO UTF-16 units -- a surrogate pair" )

    dim as string mixed = "a" & CJK1 & EMOJI & "b"
    AssertEqInt( Utf16UnitsInRange( mixed, 0, len(mixed) ), 5, "1 + 1 + 2 + 1 units" )
    AssertEqInt( Utf16UnitsInRange( mixed, 0, 0 ), 0, "an empty range is zero units" )

    '' Malformed UTF-8 must be counted, not rejected: a language server sees
    '' half-typed text constantly.
    dim as string broken = "a" & chr(&hFF) & chr(&hFE) & "b"
    AssertEqInt( Utf16UnitsInRange( broken, 0, 4 ), 4, "invalid bytes count one unit each" )

    '' A truncated sequence at the range edge counts once and stops.
    AssertEqInt( Utf16UnitsInRange( CJK1, 0, 2 ), 1, "a sequence cut by the range end counts once" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "LSP position -> byte offset" )

scope
    dim as string src = "abc" & LF & "de" & CJK1 & "f"
    dim as LineIndex idx
    idx.Rebuild( src )

    AssertEqInt( LspPositionToOffset( src, idx, 0, 0 ), 0, "line 0 char 0 is offset 0" )
    AssertEqInt( LspPositionToOffset( src, idx, 0, 2 ), 2, "ASCII columns are byte columns" )
    AssertEqInt( LspPositionToOffset( src, idx, 1, 0 ), 4, "line 1 starts after the LF" )
    AssertEqInt( LspPositionToOffset( src, idx, 1, 2 ), 6, "column before the CJK character" )
    AssertEqInt( LspPositionToOffset( src, idx, 1, 3 ), 9, "ONE column skips THREE bytes" )
    AssertEqInt( LspPositionToOffset( src, idx, 1, 4 ), 10, "the column after it" )

    '' Clamping, which the specification requires rather than an error.
    AssertEqInt( LspPositionToOffset( src, idx, 0, 99 ), 3, "a column past the line clamps to its end" )
    AssertEqInt( LspPositionToOffset( src, idx, 99, 0 ), len(src), "a line past the end clamps to the document end" )
    AssertEqInt( LspPositionToOffset( src, idx, -1, -1 ), 0, "negative coordinates clamp to the start" )

    '' A column must never land on the terminator itself.
    dim as string crlfSrc = "ab" & CR & LF & "cd"
    dim as LineIndex idx2
    idx2.Rebuild( crlfSrc )
    AssertEqInt( LspPositionToOffset( crlfSrc, idx2, 0, 5 ), 2, "a column past a CRLF line stops before the CR" )
end scope

scope
    '' The surrogate-pair case: a column landing between the halves of one
    '' character rounds DOWN, because there is no byte offset in the middle.
    dim as string src = "x" & EMOJI & "y"
    dim as LineIndex idx
    idx.Rebuild( src )

    AssertEqInt( LspPositionToOffset( src, idx, 0, 1 ), 1, "before the astral character" )
    AssertEqInt( LspPositionToOffset( src, idx, 0, 2 ), 1, "mid-surrogate rounds down to the character start" )
    AssertEqInt( LspPositionToOffset( src, idx, 0, 3 ), 5, "after the astral character" )
    AssertEqInt( LspPositionToOffset( src, idx, 0, 4 ), 6, "after the following byte" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "byte offset -> LSP position" )

scope
    dim as string src = "abc" & LF & "de" & CJK1 & "f" & LF & "z"
    dim as LineIndex idx
    idx.Rebuild( src )

    dim as SourcePosition p

    p = OffsetToSourcePosition( src, idx, 0 )
    AssertEqInt( p.Line, 0, "offset 0 -> line 0" )
    AssertEqInt( p.Column, 0, "offset 0 -> column 0" )

    p = OffsetToSourcePosition( src, idx, 6 )
    AssertEqInt( p.Line, 1, "offset 6 -> line 1" )
    AssertEqInt( p.Column, 2, "offset 6 -> column 2" )

    p = OffsetToSourcePosition( src, idx, 9 )
    AssertEqInt( p.Line, 1, "after the CJK character -> still line 1" )
    AssertEqInt( p.Column, 3, "after the CJK character -> column 3, not 5" )

    p = OffsetToSourcePosition( src, idx, 999 )
    AssertEqInt( p.Offset, len(src), "an offset past the end clamps" )
    AssertEqInt( p.Line, 2, "the clamped offset is on the last line" )
end scope

scope
    '' Round trip: every offset in a mixed-script document must survive
    '' offset -> position -> offset unchanged, except inside a multi-byte
    '' sequence, where the position rounds to the character start.
    dim as string src = "dim as string s" & LF & "print """ & CJK1 & EMOJI & """" & LF & "end"
    dim as LineIndex idx
    idx.Rebuild( src )

    dim as long mismatches = 0
    for off as long = 0 to len(src)
        dim as SourcePosition p = OffsetToSourcePosition( src, idx, off )
        dim as longint back = LspPositionToOffset( src, idx, p.Line, p.Column )

        '' Offsets that are the start of a character must come back exactly.
        dim as boolean isLead = true
        if( off < len(src) ) then
            if( (src[off] and &hC0) = &h80 ) then isLead = false
        end if
        if( isLead andalso back <> off ) then mismatches += 1
    next

    AssertEqInt( mismatches, 0, "every character boundary round-trips offset -> position -> offset" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "SourcePosition helpers" )

scope
    dim as string src = "one" & LF & "two"
    dim as LineIndex idx
    idx.Rebuild( src )

    dim as SourcePosition p = LspPositionToSourcePosition( src, idx, 1, 2 )
    AssertEqInt( p.Line, 1, "line is carried" )
    AssertEqInt( p.Column, 2, "column is carried" )
    AssertEqInt( p.Offset, 6, "offset is computed" )

    '' A clamped input comes back as the position that was actually used, not
    '' as the one that was asked for.
    dim as SourcePosition c = LspPositionToSourcePosition( src, idx, 1, 99 )
    AssertEqInt( c.Column, 3, "a clamped column reports where it landed" )
    AssertEqInt( c.Offset, 7, "and the matching offset" )

    dim as SourceRange r = MakeSourceRange( p, c )
    AssertEqInt( r.StartPos.Offset, 6, "range start" )
    AssertEqInt( r.EndPos.Offset, 7, "range end" )
end scope

end TestSummary( "position" )
