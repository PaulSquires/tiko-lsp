'' ############################################################################
''  utils/position.bas -- line index and UTF-16 <-> byte conversion
'' ############################################################################

#include once "position.bi"

'' Bytes in the UTF-8 sequence that starts with `b`. A continuation byte or an
'' illegal lead byte counts as one, which keeps the walk moving forward on
'' malformed input instead of looping or overrunning.
private function SeqLen( byval b as ubyte ) as long
    if( b < &h80 ) then return 1
    if( (b and &hE0) = &hC0 ) then return 2
    if( (b and &hF0) = &hE0 ) then return 3
    if( (b and &hF8) = &hF0 ) then return 4
    return 1
end function

'' UTF-16 code units a sequence of `n` bytes occupies. Only U+10000 and above
'' -- the four-byte forms -- need a surrogate pair.
private function UnitsForSeq( byval n as long ) as long
    if( n = 4 ) then return 2
    return 1
end function

'' ############################################################################
''  LineIndex
'' ############################################################################

constructor LineIndex( )
    this.m_textLen = 0
    '' An empty document still has one line, and every caller depends on that:
    '' LineCount() is never 0.
    this.m_starts.Push( 0LL )
end constructor

sub LineIndex.Rebuild( byref text_ as string )
    this.m_starts.Clear( )
    this.m_starts.Push( 0LL )
    this.m_textLen = len(text_)

    dim as longint i = 0
    dim as longint n = len(text_)

    while( i < n )
        dim as ubyte c = text_[i]
        if( c = 10 ) then                    '' LF
            i += 1
            this.m_starts.Push( i )
        elseif( c = 13 ) then                '' CR or CRLF
            i += 1
            if( i < n andalso text_[i] = 10 ) then i += 1
            this.m_starts.Push( i )
        else
            i += 1
        end if
    wend
end sub

function LineIndex.LineCount( ) as long
    return this.m_starts.Count( )
end function

function LineIndex.TextLength( ) as longint
    return this.m_textLen
end function

function LineIndex.LineStart( byval lineNo as long ) as longint
    if( lineNo <= 0 ) then return 0
    if( lineNo >= this.m_starts.Count( ) ) then return this.m_textLen
    return this.m_starts[ lineNo ]
end function

function LineIndex.LineContentEnd( byref text_ as string, byval lineNo as long ) as longint
    dim as longint stop_ = this.m_textLen
    if( lineNo + 1 < this.m_starts.Count( ) ) then stop_ = this.m_starts[ lineNo + 1 ]

    '' Walk back over the terminator so a column can never address it.
    if( stop_ > 0 andalso stop_ <= len(text_) ) then
        if( stop_ >= 1 andalso text_[ stop_ - 1 ] = 10 ) then
            stop_ -= 1
            if( stop_ >= 1 andalso text_[ stop_ - 1 ] = 13 ) then stop_ -= 1
        elseif( stop_ >= 1 andalso text_[ stop_ - 1 ] = 13 ) then
            stop_ -= 1
        end if
    end if

    dim as longint begin_ = this.LineStart( lineNo )
    if( stop_ < begin_ ) then return begin_
    return stop_
end function

function LineIndex.LineOfOffset( byval offset as longint ) as long
    if( offset <= 0 ) then return 0

    dim as long lo = 0
    dim as long hi = this.m_starts.Count( ) - 1

    '' Largest line whose start is <= offset.
    while( lo < hi )
        dim as long mid_ = (lo + hi + 1) \ 2
        if( this.m_starts[ mid_ ] <= offset ) then
            lo = mid_
        else
            hi = mid_ - 1
        end if
    wend

    return lo
end function

'' ############################################################################
''  Conversions
'' ############################################################################

function Utf16UnitsInRange( byref text_ as string, byval fromByte as longint, byval toByte as longint ) as long
    dim as longint n = len(text_)
    dim as longint i = fromByte
    dim as longint stop_ = toByte

    if( i < 0 ) then i = 0
    if( stop_ > n ) then stop_ = n

    dim as long units = 0
    while( i < stop_ )
        dim as long seq = SeqLen( text_[i] )
        '' A sequence truncated by the end of the range still counts as one
        '' unit; the range boundary is authoritative.
        if( i + seq > stop_ ) then
            units += 1
            exit while
        end if
        units += UnitsForSeq( seq )
        i += seq
    wend

    return units
end function

function Utf16ColumnToByte( byref text_ as string, byval lineStart as longint, byval lineEnd as longint, byval utf16Col as long ) as longint
    if( utf16Col <= 0 ) then return lineStart

    dim as longint i = lineStart
    dim as long remaining = utf16Col

    while( i < lineEnd andalso remaining > 0 )
        dim as long seq = SeqLen( text_[i] )
        if( i + seq > lineEnd ) then seq = lineEnd - i

        dim as long units = UnitsForSeq( seq )
        '' A column landing between the two halves of a surrogate pair rounds
        '' DOWN to the start of the character. There is no byte offset for the
        '' middle of a character, and rounding up would silently include it.
        if( units > remaining ) then exit while

        remaining -= units
        i += seq
    wend

    '' Columns past the end of the line clamp to the end of the line, which is
    '' what the specification requires of a server.
    return i
end function

function LspPositionToOffset( byref text_ as string, byref idx as LineIndex, byval lineNo as long, byval character as long ) as longint
    dim as long ln = lineNo
    if( ln < 0 ) then ln = 0

    '' A line past the end clamps to the end of the document rather than
    '' failing: clients do send stale positions while the user types.
    if( ln >= idx.LineCount( ) ) then return idx.TextLength( )

    dim as longint lineStart = idx.LineStart( ln )
    dim as longint lineEnd   = idx.LineContentEnd( text_, ln )
    return Utf16ColumnToByte( text_, lineStart, lineEnd, character )
end function

function OffsetToSourcePosition( byref text_ as string, byref idx as LineIndex, byval offset as longint ) as SourcePosition
    dim as SourcePosition p

    dim as longint off = offset
    if( off < 0 ) then off = 0
    if( off > idx.TextLength( ) ) then off = idx.TextLength( )

    p.Line   = idx.LineOfOffset( off )
    p.Offset = off
    p.Column = Utf16UnitsInRange( text_, idx.LineStart( p.Line ), off )
    return p
end function

function LspPositionToSourcePosition( byref text_ as string, byref idx as LineIndex, byval lineNo as long, byval character as long ) as SourcePosition
    dim as SourcePosition p
    p.Offset = LspPositionToOffset( text_, idx, lineNo, character )

    '' Line and column are recomputed from the offset rather than echoed back,
    '' so a clamped input comes back as the position that was actually used.
    p.Line   = idx.LineOfOffset( p.Offset )
    p.Column = Utf16UnitsInRange( text_, idx.LineStart( p.Line ), p.Offset )
    return p
end function

function MakeSourcePosition( byval lineNo as long, byval character as long, byval offset as longint ) as SourcePosition
    dim as SourcePosition p
    p.Line   = lineNo
    p.Column = character
    p.Offset = offset
    return p
end function

function MakeSourceRange( byval startPos as SourcePosition, byval endPos as SourcePosition ) as SourceRange
    dim as SourceRange r
    r.StartPos = startPos
    r.EndPos   = endPos
    return r
end function
