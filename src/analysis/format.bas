'' ############################################################################
''  analysis/format.bas -- re-indenting a document
'' ############################################################################

#include once "format.bi"
#include once "lexer.bi"

function DefaultFormatOptions( ) as FormatOptions
    dim as FormatOptions o
    o.TabSize                = 4
    o.InsertSpaces           = true
    o.TrimTrailingWhitespace = true
    o.InsertFinalNewline     = true
    o.TrimFinalNewlines      = false
    return o
end function

'' The whitespace one indent level costs, repeated.
private function IndentText( byref opts as FormatOptions, byval depth as long ) as string
    if( depth <= 0 ) then return ""
    if( opts.InsertSpaces = false ) then return string( depth, chr(9) )

    dim as long width_ = opts.TabSize
    if( width_ < 1 ) then width_ = 4
    return space( depth * width_ )
end function

'' Bytes of leading whitespace on a line.
private function LeadingWhitespace( byref text_ as string, byval lineStart as long, byval lineEnd as long ) as long
    dim as long i = lineStart
    while( i < lineEnd )
        if( text_[i] <> 32 andalso text_[i] <> 9 ) then exit while
        i += 1
    wend
    return i - lineStart
end function

'' Offset one past the last non-whitespace byte of a line.
private function ContentEnd( byref text_ as string, byval lineStart as long, byval lineEnd as long ) as long
    dim as long i = lineEnd
    while( i > lineStart )
        if( text_[i - 1] <> 32 andalso text_[i - 1] <> 9 ) then exit while
        i -= 1
    wend
    return i
end function

'' Whether each line's statement CONTINUES on the next one.
''
'' Taken from the lexer rather than from the text, because the lexer's rule is
'' subtler than "ends with an underscore": a `_` followed by a comment still
'' continues, a `_` at the end of an identifier does not, and a `_` inside a
'' string is nothing at all. The lexer emits a TK_EOL at the end of every
'' LOGICAL line and at no other time -- so a line with content and no TK_EOL
'' on it is a line that continues.
''
'' The first version of this read the text and missed `& _   '' note`, which is
'' written on four consecutive lines of this project's own test suite.
private sub FindContinuations( byref idx as LineIndex, byref tokens as TokenArray, _
                               byval lineCount as long, byref continued_ as FB.Array( of boolean ) )
    dim hasEol as FB.Array( of boolean )
    for ln as long = 0 to lineCount - 1
        hasEol.Push( false )
        continued_.Push( false )
    next

    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_EOL ) then continue for
        dim as long ln = idx.LineOfOffset( tokens[i].Start_ )
        if( ln < lineCount ) then hasEol[ln] = true
    next

    '' Line 0 can never be a continuation; every other line is one when the
    '' line above it never ended.
    for ln as long = 1 to lineCount - 1
        continued_[ln] = ( hasEol[ln - 1] = false )
    next
end sub

function ApplyTextEdits( byref text_ as string, byref idx as LineIndex, _
                         byref edits as TextEditArray ) as string
    dim as string out_
    dim as longint cursor = 0

    for i as long = 0 to edits.Count( ) - 1
        dim as longint s = LspPositionToOffset( text_, idx, edits[i].StartLine, edits[i].StartChar )
        dim as longint e = LspPositionToOffset( text_, idx, edits[i].EndLine,   edits[i].EndChar )
        if( s < cursor ) then continue for

        out_ &= mid( text_, cursor + 1, s - cursor )
        out_ &= edits[i].NewText
        cursor = e
    next

    out_ &= mid( text_, cursor + 1 )
    return out_
end function

'' ----------------------------------------------------------------------------
''  The formatter
'' ----------------------------------------------------------------------------
function ComputeFormatEdits( byref text_ as string, byref idx as LineIndex, _
                             byref opts as FormatOptions, _
                             byval firstLine as long, byval lastLine as long, _
                             byref edits as TextEditArray, _
                             byref reason as string ) as boolean

    edits.Clear( )
    reason = ""

    dim tokens as TokenArray
    dim diags  as DiagnosticArray
    dim marks  as IndentTrace

    LexSource( text_, tokens, diags )
    ParseTokens( text_, tokens, diags, 0, @marks )

    '' -- refuse on broken structure -------------------------------------------
    for i as long = 0 to diags.Count( ) - 1
        if( diags[i].Severity = DIAG_ERROR ) then
            reason = diags[i].Code_
            return false
        end if
    next

    dim as long lineCount = idx.LineCount( )
    if( lineCount = 0 ) then return true

    if( lastLine < 0 orelse lastLine >= lineCount ) then lastLine = lineCount - 1
    if( firstLine < 0 ) then firstLine = 0

    '' -- lines that must not be touched ---------------------------------------
    ''
    '' The CONTINUATION lines of a multi-line comment: their leading spaces are
    '' part of a drawing, not of a block structure. The opening line is fair
    '' game, and moves the whole comment with it.
    dim protected_ as FB.Array( of boolean )
    for ln as long = 0 to lineCount - 1
        protected_.Push( false )
    next

    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_COMMENT andalso tokens[i].Kind <> TK_STRING ) then continue for

        dim as long a = idx.LineOfOffset( tokens[i].Start_ )
        dim as long b = idx.LineOfOffset( tokens[i].Start_ + tokens[i].Length_ - 1 )
        for ln as long = a + 1 to b
            if( ln < lineCount ) then protected_[ln] = true
        next
    next

    '' A #macro body is text: fbc's own test suite opens a block in one macro
    '' and closes it in another, so there is no structure here to indent to.
    dim as long macroFrom = -1
    for i as long = 0 to tokens.Count( ) - 1
        if( tokens[i].Kind <> TK_PP ) then continue for
        dim as long ln = idx.LineOfOffset( tokens[i].Start_ )

        select case tokens[i].Kw
            case KW_PP_MACRO
                if( macroFrom < 0 ) then macroFrom = ln
            case KW_PP_ENDMACRO
                if( macroFrom >= 0 ) then
                    for k as long = macroFrom to ln
                        if( k < lineCount ) then protected_[k] = true
                    next
                    macroFrom = -1
                end if
        end select
    next

    '' An unterminated #macro leaves the whole rest of the file as macro body,
    '' and nothing after it can be indented from a structure that was never
    '' closed. The parser does not call that an error -- half a macro is legal
    '' in a header -- so the refusal is made here.
    if( macroFrom >= 0 ) then
        reason = "unterminated-macro"
        return false
    end if

    '' -- which lines are comment and which are code ---------------------------
    dim hasCode_ as FB.Array( of boolean )
    dim hasComment_ as FB.Array( of boolean )
    for ln as long = 0 to lineCount - 1
        hasCode_.Push( false )
        hasComment_.Push( false )
    next

    for i as long = 0 to tokens.Count( ) - 1
        select case tokens[i].Kind
            case TK_EOL, TK_EOF
                continue for
        end select

        dim as long ln = idx.LineOfOffset( tokens[i].Start_ )
        if( ln >= lineCount ) then continue for

        if( tokens[i].Kind = TK_COMMENT ) then
            hasComment_[ln] = true
        else
            hasCode_[ln] = true
        end if
    next

    '' -- the depth every line wants -------------------------------------------
    dim want_ as FB.Array( of long )

    dim continued_ as FB.Array( of boolean )
    FindContinuations( idx, tokens, lineCount, continued_ )

    '' Whether the line is a CLAUSE -- an ELSE, an ELSEIF, a CASE. It steps out
    '' to its opener and steps back in again, which is what tells it from a
    '' closer (out, and stays out) and from an opener (in from where it is).
    dim clause_ as FB.Array( of boolean )

    dim as long markIdx = 0
    dim as long depth   = 0

    for ln as long = 0 to lineCount - 1
        dim as longint lineStart = idx.LineStart( ln )
        dim as longint lineEnd   = idx.LineContentEnd( text_, ln )

        '' The marks that fall on this line. The FIRST decides where the line
        '' goes; the LAST decides where the next one starts.
        dim as long selfDepth = -1
        while( markIdx < marks.Count( ) andalso marks[markIdx].Offset < lineStart )
            depth = marks[markIdx].NextDepth
            markIdx += 1
        wend

        while( markIdx < marks.Count( ) andalso marks[markIdx].Offset < lineEnd )
            if( selfDepth < 0 ) then selfDepth = marks[markIdx].SelfDepth
            depth = marks[markIdx].NextDepth
            markIdx += 1
        wend

        dim as long d = depth
        dim as boolean isClause = false
        if( selfDepth >= 0 ) then
            isClause = ( selfDepth < d ) andalso ( depth > selfDepth )
            d = selfDepth
        end if

        clause_.Push( isClause )
        want_.Push( d )
    next

    '' A DIVIDER COMMENT BELONGS TO THE CLAUSE BELOW IT.
    ''
    ''         case KW_END
    ''             ...
    ''
    ''         '' -- clauses ------------          <- here
    ''         case KW_ELSE
    ''
    '' Written inside the arm above, it belongs with the CASE below, and every
    '' one of them in this project's own source was being pushed in a level.
    '' The rule is narrow on purpose: only a comment block that FOLLOWS ORDINARY
    '' CODE and PRECEDES A CLAUSE moves. A comment that is the whole body of an
    '' arm --
    ''
    ''         case TK_IDENT
    ''             '' part of the type
    ''         case TK_LPAREN
    ''
    '' -- follows a clause rather than code, and stays where it was written.
    dim as long prevCode = -1

    for ln as long = 0 to lineCount - 1
        if( hasCode_[ln] ) then
            prevCode = ln
            continue for
        end if
        if( hasComment_[ln] = false ) then continue for
        if( prevCode < 0 ) then continue for
        if( clause_[prevCode] ) then continue for

        for k as long = ln + 1 to lineCount - 1
            if( hasCode_[k] ) then
                if( clause_[k] ) then want_[ln] = want_[k]
                exit for
            end if
            if( hasComment_[k] = false ) then exit for   '' a blank line ends the block
        next
    next

    '' -- the edits ------------------------------------------------------------
    for ln as long = firstLine to lastLine
        if( protected_[ln] ) then continue for

        dim as longint lineStart = idx.LineStart( ln )
        dim as longint lineEnd   = idx.LineContentEnd( text_, ln )

        dim as long lead    = LeadingWhitespace( text_, lineStart, lineEnd )
        dim as long content = ContentEnd( text_, lineStart, lineEnd )
        dim as boolean blank_ = ( content <= lineStart )

        '' -- the indent ------------------------------------------------------
        dim as string wanted = IndentText( opts, want_[ln] )
        if( blank_ ) then wanted = ""      '' nothing to indent

        dim as string have_ = mid( text_, lineStart + 1, lead )

        '' A CONTINUATION LINE IS LEFT WHERE IT IS.
        ''
        '' This was not the first rule tried. Indenting a continuation one
        '' level past its statement is defensible in the abstract and wrong in
        '' practice: real FreeBASIC aligns a wrapped parameter list UNDER THE
        '' OPENING PARENTHESIS, and a formatter cannot know which column that
        '' is without deciding how the line should have been wrapped. Applied
        '' to this project's own source the rule produced a thousand edits,
        '' every one of them destroying an alignment somebody chose.
        if( continued_[ln] andalso blank_ = false ) then wanted = have_

        if( wanted <> have_ ) then
            '' A blank line's whitespace is only removed when the client asked
            '' for trailing whitespace to be trimmed -- it IS trailing
            '' whitespace, and some editors keep it deliberately.
            if( blank_ = false orelse opts.TrimTrailingWhitespace ) then
                dim as TextEditRec e
                e.StartLine = ln
                e.StartChar = 0
                e.EndLine   = ln
                e.EndChar   = lead        '' whitespace is ASCII: bytes = units
                e.NewText   = wanted
                edits.Push( e )
            end if
        end if

        '' -- trailing whitespace ----------------------------------------------
        if( opts.TrimTrailingWhitespace andalso blank_ = false andalso content < lineEnd ) then
            dim as TextEditRec e
            e.StartLine = ln
            e.StartChar = Utf16UnitsInRange( text_, lineStart, content )
            e.EndLine   = ln
            e.EndChar   = Utf16UnitsInRange( text_, lineStart, lineEnd )
            e.NewText   = ""
            edits.Push( e )
        end if
    next

    '' -- the final newline ----------------------------------------------------
    ''
    '' Only when the whole document was formatted: a range format that happens
    '' to include the last line should not silently change the file's ending.
    if( opts.InsertFinalNewline andalso firstLine = 0 andalso lastLine = lineCount - 1 ) then
        dim as longint total = len( text_ )
        if( total > 0 andalso text_[total - 1] <> 10 andalso text_[total - 1] <> 13 ) then
            '' Match the file's own line ending rather than imposing one.
            dim as string eol = chr(10)
            if( instr( text_, chr(13) & chr(10) ) > 0 ) then eol = chr(13) & chr(10)

            dim as SourcePosition endPos = OffsetToSourcePosition( text_, idx, total )
            dim as TextEditRec e
            e.StartLine = endPos.Line
            e.StartChar = endPos.Column
            e.EndLine   = endPos.Line
            e.EndChar   = endPos.Column
            e.NewText   = eol
            edits.Push( e )
        end if
    end if

    return true
end function
