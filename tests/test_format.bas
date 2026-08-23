'' ############################################################################
''  tests/test_format.bas -- re-indentation
''
''  A formatter is judged by what it leaves alone. Every case here is written
''  as "this text formats to that text", so a change in behaviour shows up as
''  a diff of the file rather than as an edit count.
''
''  The two rules that matter most are the refusals: broken structure produces
''  NO edits, and a file that is already correctly indented produces no edits
''  either -- an editor that reports "formatted" and rewrites nothing is what
''  makes format-on-save safe to leave on.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#include once "assert.bi"
#include once "../src/analysis/format.bi"

const LF = chr(10)

dim shared as LineIndex     g_Index
dim shared as TextEditArray g_Edits
dim shared as string        g_Reason

'' Formats `src` and returns the result. `g_Edits` and `g_Reason` are left for
'' a caller that wants to assert on them.
private function Format_( byref src as string, byref opts as FormatOptions ) as string
    g_Index.Rebuild( src )
    if( ComputeFormatEdits( src, g_Index, opts, 0, -1, g_Edits, g_Reason ) = false ) then return src
    return ApplyTextEdits( src, g_Index, g_Edits )
end function

private function Fmt( byref src as string ) as string
    dim as FormatOptions o = DefaultFormatOptions( )
    o.InsertFinalNewline = false
    return Format_( src, o )
end function

'' ############################################################################
''  Indentation
'' ############################################################################
private sub TestIndent( )
    TestGroup( "indentation" )

    AssertEqStr( Fmt( "sub Go_( )" & LF & "print 1" & LF & "end sub" & LF ), _
                 "sub Go_( )" & LF & "    print 1" & LF & "end sub" & LF, _
                 "a procedure body is indented one level" )

    AssertEqStr( Fmt( "sub Go_( )" & LF & _
                      "        print 1" & LF & _
                      "  end sub" & LF ), _
                 "sub Go_( )" & LF & "    print 1" & LF & "end sub" & LF, _
                 "and over-indented lines come back" )

    AssertEqStr( Fmt( "sub Go_( )" & LF & _
                      "if x then" & LF & _
                      "print 1" & LF & _
                      "else" & LF & _
                      "print 2" & LF & _
                      "end if" & LF & _
                      "end sub" & LF ), _
                 "sub Go_( )" & LF & _
                 "    if x then" & LF & _
                 "        print 1" & LF & _
                 "    else" & LF & _
                 "        print 2" & LF & _
                 "    end if" & LF & _
                 "end sub" & LF, _
                 "ELSE goes back out to its IF, and the arm back in" )

    '' A single-line IF opens nothing, which is the case a formatter that
    '' matches on the first keyword gets wrong -- and then indents the rest of
    '' the file by one.
    AssertEqStr( Fmt( "sub Go_( )" & LF & _
                      "if x then print 1" & LF & _
                      "print 2" & LF & _
                      "end sub" & LF ), _
                 "sub Go_( )" & LF & _
                 "    if x then print 1" & LF & _
                 "    print 2" & LF & _
                 "end sub" & LF, _
                 "a single-line IF opens no block" )

    AssertEqStr( Fmt( "select case n" & LF & _
                      "case 1" & LF & _
                      "print 1" & LF & _
                      "case else" & LF & _
                      "print 2" & LF & _
                      "end select" & LF ), _
                 "select case n" & LF & _
                 "    case 1" & LF & _
                 "        print 1" & LF & _
                 "    case else" & LF & _
                 "        print 2" & LF & _
                 "end select" & LF, _
                 "CASE is indented inside its SELECT, and its arm one further" )

    AssertEqStr( Fmt( "type Widget" & LF & _
                      "Count as long" & LF & _
                      "end type" & LF ), _
                 "type Widget" & LF & "    Count as long" & LF & "end type" & LF, _
                 "a TYPE body is indented" )

    AssertEqStr( Fmt( "for i as long = 0 to 9" & LF & _
                      "do" & LF & _
                      "print i" & LF & _
                      "loop" & LF & _
                      "next" & LF ), _
                 "for i as long = 0 to 9" & LF & _
                 "    do" & LF & _
                 "        print i" & LF & _
                 "    loop" & LF & _
                 "next" & LF, _
                 "loops nest" )

    '' A DECLARE is not a block, however much it looks like one.
    AssertEqStr( Fmt( "type Widget" & LF & _
                      "declare sub Reset_( )" & LF & _
                      "Count as long" & LF & _
                      "end type" & LF ), _
                 "type Widget" & LF & _
                 "    declare sub Reset_( )" & LF & _
                 "    Count as long" & LF & _
                 "end type" & LF, _
                 "a DECLARE does not open a block" )
end sub

'' ############################################################################
''  What it leaves alone
'' ############################################################################
private sub TestLeavesAlone( )
    TestGroup( "what it leaves alone" )

    dim as string tidy = "sub Go_( )" & LF & _
                         "    if x then" & LF & _
                         "        print 1" & LF & _
                         "    end if" & LF & _
                         "end sub" & LF

    AssertEqStr( Fmt( tidy ), tidy, "an already-correct file is unchanged" )
    AssertEqInt( g_Edits.Count( ), 0, "and produces no edits at all" )

    '' Broken structure: the indentation is not known, so nothing is touched.
    dim as string broken = "sub Go_( )" & LF & "print 1" & LF
    AssertEqStr( Fmt( broken ), broken, "an unclosed block is left alone" )
    AssertEqStr( g_Reason, "unclosed-block", "and the reason says why" )

    broken = "sub Go_( )" & LF & "end sub" & LF & "end if" & LF
    AssertEqStr( Fmt( broken ), broken, "an orphan closer is left alone too" )
    AssertEqStr( g_Reason, "unexpected-end", "with its own reason" )

    '' Comment art survives: only the FIRST line of a block comment moves.
    dim as string art = "sub Go_( )" & LF & _
                        "/' +---+" & LF & _
                        "   | a |" & LF & _
                        "   +---+ '/" & LF & _
                        "end sub" & LF
    AssertEqStr( Fmt( art ), _
                 "sub Go_( )" & LF & _
                 "    /' +---+" & LF & _
                 "   | a |" & LF & _
                 "   +---+ '/" & LF & _
                 "end sub" & LF, _
                 "the inside of a block comment is not re-indented" )

    '' A macro body is text, and blocks in it need not balance.
    dim as string macro_ = "#macro OPEN_( )" & LF & _
                           "scope" & LF & _
                           "#endmacro" & LF & _
                           "dim as long n = 1" & LF
    AssertEqStr( Fmt( macro_ ), macro_, "a #macro body is left as written" )
end sub

'' ############################################################################
''  Continuations
'' ############################################################################
private sub TestContinuations( )
    TestGroup( "continuations" )

    '' A continuation line keeps the column it was written in -- see
    '' format.bas for the corpus result that settled this. The statement it
    '' belongs to is still re-indented, and the line after it goes back to the
    '' block's own level.
    AssertEqStr( Fmt( "sub Go_( )" & LF & _
                      "print 1, _" & LF & _
                      "         2" & LF & _
                      "print 3" & LF & _
                      "end sub" & LF ), _
                 "sub Go_( )" & LF & _
                 "    print 1, _" & LF & _
                 "         2" & LF & _
                 "    print 3" & LF & _
                 "end sub" & LF, _
                 "a continuation keeps its alignment, and only it" )

    '' `_` at the end of a NAME is not a continuation. Treating it as one
    '' would indent the following line for no reason.
    AssertEqStr( Fmt( "sub Go_( )" & LF & _
                      "dim as long g_" & LF & _
                      "print 1" & LF & _
                      "end sub" & LF ), _
                 "sub Go_( )" & LF & _
                 "    dim as long g_" & LF & _
                 "    print 1" & LF & _
                 "end sub" & LF, _
                 "a trailing underscore inside a name is not a continuation" )
end sub

'' ############################################################################
''  What the corpus taught it
''
''  Every case here is a rule that came out of running the formatter over this
''  project's own source and AfxNova's, not out of thinking about it first.
'' ############################################################################
private sub TestCorpusRules( )
    TestGroup( "rules the corpus taught" )

    '' An access specifier adds a level, exactly as a CASE does -- and the
    '' block stack has no frame for it, because it opens nothing.
    AssertEqStr( Fmt( "type Widget" & LF & _
                      "private:" & LF & _
                      "m_count as long" & LF & _
                      "public:" & LF & _
                      "declare function Count( ) as long" & LF & _
                      "end type" & LF ), _
                 "type Widget" & LF & _
                 "    private:" & LF & _
                 "        m_count as long" & LF & _
                 "    public:" & LF & _
                 "        declare function Count( ) as long" & LF & _
                 "end type" & LF, _
                 "a TYPE's access specifiers indent their members" )

    '' A divider comment between two arms belongs with the arm BELOW it.
    AssertEqStr( Fmt( "select case n" & LF & _
                      "    case 1" & LF & _
                      "        print 1" & LF & _
                      "        '' -- the other arm --" & LF & _
                      "    case 2" & LF & _
                      "        print 2" & LF & _
                      "end select" & LF ), _
                 "select case n" & LF & _
                 "    case 1" & LF & _
                 "        print 1" & LF & _
                 "    '' -- the other arm --" & LF & _
                 "    case 2" & LF & _
                 "        print 2" & LF & _
                 "end select" & LF, _
                 "a divider comment moves down to the clause it introduces" )

    '' But a comment that IS the arm stays inside it: it follows a clause
    '' rather than code, which is the whole discriminator.
    dim as string arm = "select case n" & LF & _
                        "    case 1" & LF & _
                        "        '' nothing to do" & LF & _
                        "    case 2" & LF & _
                        "        print 2" & LF & _
                        "end select" & LF
    AssertEqStr( Fmt( arm ), arm, "a comment that is the whole arm stays in it" )

    '' A doc block above a declaration takes the declaration's level.
    AssertEqStr( Fmt( "sub Go_( )" & LF & _
                      "'' what this is" & LF & _
                      "dim as long n = 1" & LF & _
                      "end sub" & LF ), _
                 "sub Go_( )" & LF & _
                 "    '' what this is" & LF & _
                 "    dim as long n = 1" & LF & _
                 "end sub" & LF, _
                 "a doc comment is indented with what it documents" )

    '' `_` followed by a COMMENT is still a continuation. The first version of
    '' this read the text and missed it, and then re-indented four lines of
    '' this project's own test suite.
    dim as string wrapped = "sub Go_( )" & LF & _
                            "    print 1, _   '' first" & LF & _
                            "          2" & LF & _
                            "end sub" & LF
    AssertEqStr( Fmt( wrapped ), wrapped, "a `_` before a comment still continues the line" )

    '' A preprocessor conditional does NOT indent. An include guard wraps a
    '' whole file, and indenting inside one would move every line in it.
    dim as string guarded = "#ifndef WIDGET_BI" & LF & _
                            "#define WIDGET_BI" & LF & _
                            "type Widget" & LF & _
                            "    Count as long" & LF & _
                            "end type" & LF & _
                            "#endif" & LF
    AssertEqStr( Fmt( guarded ), guarded, "a #if body keeps the level it is written at" )
end sub

'' ############################################################################
''  Whitespace and options
'' ############################################################################
private sub TestOptions( )
    TestGroup( "options" )

    dim as FormatOptions o = DefaultFormatOptions( )
    o.InsertFinalNewline = false
    o.TabSize = 2

    AssertEqStr( Format_( "sub Go_( )" & LF & "print 1" & LF & "end sub" & LF, o ), _
                 "sub Go_( )" & LF & "  print 1" & LF & "end sub" & LF, _
                 "tabSize is honoured" )

    o = DefaultFormatOptions( )
    o.InsertFinalNewline = false
    o.InsertSpaces = false
    AssertEqStr( Format_( "sub Go_( )" & LF & "print 1" & LF & "end sub" & LF, o ), _
                 "sub Go_( )" & LF & chr(9) & "print 1" & LF & "end sub" & LF, _
                 "insertSpaces = false indents with tabs" )

    o = DefaultFormatOptions( )
    o.InsertFinalNewline = false
    AssertEqStr( Format_( "dim as long n = 1   " & LF & "   " & LF, o ), _
                 "dim as long n = 1" & LF & "" & LF, _
                 "trailing whitespace goes, including a whitespace-only line" )

    o.TrimTrailingWhitespace = false
    AssertEqStr( Format_( "dim as long n = 1   " & LF, o ), _
                 "dim as long n = 1   " & LF, _
                 "and stays when the client asked to keep it" )

    o = DefaultFormatOptions( )
    AssertEqStr( Format_( "dim as long n = 1", o ), _
                 "dim as long n = 1" & LF, _
                 "insertFinalNewline adds the missing newline" )

    dim as string crlf = "sub Go_( )" & chr(13) & LF & "print 1" & chr(13) & LF & "end sub"
    AssertContains( Format_( crlf, o ), "end sub" & chr(13) & LF, _
                    "and matches the file's own CRLF ending" )
end sub

'' ############################################################################
''  Formatting one range
'' ############################################################################
private sub TestRange( )
    TestGroup( "range formatting" )

    dim as string src = "sub Go_( )" & LF & _
                        "print 1" & LF & _
                        "print 2" & LF & _
                        "end sub" & LF

    dim as FormatOptions o = DefaultFormatOptions( )
    o.InsertFinalNewline = false

    g_Index.Rebuild( src )
    AssertTrue( ComputeFormatEdits( src, g_Index, o, 1, 1, g_Edits, g_Reason ), _
                "one line can be formatted on its own" )
    AssertEqStr( ApplyTextEdits( src, g_Index, g_Edits ), _
                 "sub Go_( )" & LF & "    print 1" & LF & "print 2" & LF & "end sub" & LF, _
                 "and only that line moves" )

    '' The depth still comes from the whole document: a range knows nothing
    '' about how deeply it is already nested.
    AssertEqInt( g_Edits.Count( ), 1, "one edit for one line" )
end sub

'' ############################################################################
''  Main
'' ############################################################################
print "tiko-lsp -- formatting tests"

TestIndent( )
TestLeavesAlone( )
TestContinuations( )
TestCorpusRules( )
TestOptions( )
TestRange( )

end TestSummary( "formatting" )
