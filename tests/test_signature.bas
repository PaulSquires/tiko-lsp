'' ############################################################################
''  tests/test_signature.bas -- signatures, call contexts and argument sites
''
''  The three things signature help and inlay hints are built on, tested
''  without a server: splitting a recorded signature, finding which call the
''  caret is in, and finding every argument of every call in a range.
''
''  The cases that matter are the ones where a naive split is wrong: a default
''  value containing a comma, a function-pointer parameter containing its own
''  parentheses, and a nested call, where the interesting callee is the INNER
''  one.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#include once "assert.bi"
#include once "../src/analysis/parser.bi"
#include once "../src/analysis/signature.bi"

const LF = chr(10)

dim shared as string          g_Src
dim shared as TokenArray      g_Tokens
dim shared as DiagnosticArray g_Diags
dim shared as SymbolTable     g_Syms

private sub Analyse( byref src as string )
    g_Src = src
    AnalyzeFull( g_Src, g_Tokens, g_Diags, g_Syms )
end sub

'' The byte just after the first occurrence of `after_`: how every case below
'' spells "the caret is here".
private function CaretAfter( byref after_ as string ) as long
    dim as long at_ = instr( g_Src, after_ )
    if( at_ = 0 ) then return -1
    return at_ - 1 + len(after_)
end function

private function ContextAfter( byref after_ as string, byref ctx as CallContext ) as boolean
    return FindCallContext( g_Src, g_Tokens, CaretAfter( after_ ), ctx )
end function

private function CalleeName( byref ctx as CallContext ) as string
    if( ctx.NameTok < 0 ) then return ""
    return TokenText( g_Src, g_Tokens[ctx.NameTok] )
end function

'' ############################################################################
''  Splitting a recorded signature
'' ############################################################################
private sub TestParseSignature( )
    TestGroup( "ParseSignature" )

    dim params as SigParamArray
    dim as string label

    AssertTrue( ParseSignature( "Add", "(byval a as long, byval b as long) as long", label, params ), _
                "an ordinary signature parses" )
    AssertEqStr( label, "Add(byval a as long, byval b as long) as long", _
                 "the label is the name plus the detail" )
    AssertEqInt( params.Count( ), 2, "two parameters" )
    AssertEqStr( params[0].Label, "byval a as long", "the first parameter's label" )
    AssertEqStr( params[0].Name_, "a", "and its name" )
    AssertEqStr( params[1].Name_, "b", "the second parameter's name" )

    '' The [start, end) span is what a client highlights, so it has to index
    '' the label it was given.
    AssertEqStr( mid( label, params[1].LabelStart + 1, params[1].LabelEnd - params[1].LabelStart ), _
                 "byval b as long", "the span picks the parameter out of the label" )

    params.Clear( )
    AssertTrue( ParseSignature( "Now_", "()", label, params ), "an empty list is still a signature" )
    AssertEqInt( params.Count( ), 0, "with no parameters" )

    params.Clear( )
    AssertFalse( ParseSignature( "total", "as long", label, params ), _
                 "a variable's detail is not a parameter list" )

    '' A TYPED VARIADIC is one parameter, named, with its '...' in the label.
    params.Clear( )
    AssertTrue( ParseSignature( "Fmt", "(byref f as const ustring, args() as const FormatArg ...) as ustring", _
                                label, params ), "a typed variadic signature parses" )
    AssertEqInt( params.Count( ), 2, "the variadic is one parameter" )
    AssertEqStr( params[1].Name_, "args", "named by its array" )
    AssertEqStr( params[1].Label, "args() as const FormatArg ...", "with the '...' in its label" )

    params.Clear( )
    AssertFalse( ParseSignature( "MAXV", "= 100", label, params ), _
                 "and neither is a constant's value" )

    '' A comma inside a default value is not a separator. This is the case a
    '' split-on-comma gets wrong, and it produces a signature with a phantom
    '' third parameter.
    params.Clear( )
    ParseSignature( "Join_", "(byref parts as string, byval sep as string = "","")", label, params )
    AssertEqInt( params.Count( ), 2, "a comma inside a string default does not split" )
    AssertEqStr( params[1].Name_, "sep", "and the parameter after it is still named" )

    '' Nor is a comma inside a nested parameter list.
    params.Clear( )
    ParseSignature( "Sort_", "(byval cmp as function( byval a as long, byval b as long ) as long, byval n as long)", _
                    label, params )
    AssertEqInt( params.Count( ), 2, "a function-pointer parameter counts as one" )
    AssertEqStr( params[1].Name_, "n", "and the one after it is found" )

    params.Clear( )
    ParseSignature( "Peek_", "(as long)", label, params )
    AssertEqInt( params.Count( ), 1, "an unnamed parameter is still a parameter" )
    AssertEqStr( params[0].Name_, "", "with no name to show" )

    params.Clear( )
    ParseSignature( "Fill_", "(bytes() as ubyte, byval n as long)", label, params )
    AssertEqStr( params[0].Name_, "bytes", "an array parameter's name stops at its ()" )

    params.Clear( )
    ParseSignature( "Printf_", "(byval fmt as zstring ptr, ...)", label, params )
    AssertEqInt( params.Count( ), 2, "an ellipsis is a parameter" )
    AssertEqStr( params[1].Name_, "", "with no name" )

    '' Mid-edit: the user has typed the opener and nothing else.
    params.Clear( )
    AssertTrue( ParseSignature( "Half", "(byval a as long", label, params ), _
                "an unbalanced list is still reported as a signature" )
    AssertEqInt( params.Count( ), 0, "but nothing can be located inside it" )

    '' PROCEDURE MODIFIERS before the list -- how fb/*.bi and the Win32 headers
    '' declare. They used to mean no signature at all.
    params.Clear( )
    AssertTrue ( ParseSignature( "PadLeft", "overload alias ""fb_StrPadLeft"" (byref s as const string, byval width as integer) as string", label, params ), _
                 "overload alias before the list: still a signature" )
    AssertEqStr( label, "PadLeft(byref s as const string, byval width as integer) as string", _
                 "labelled without the modifiers" )
    AssertEqInt( params.Count( ), 2, "with both parameters" )
    AssertEqStr( mid( label, params[1].LabelStart + 1, params[1].LabelEnd - params[1].LabelStart ), _
                 "byval width as integer", "and spans that index the shorter label" )

    params.Clear( )
    AssertTrue ( ParseSignature( "Beep_", "cdecl lib ""k(32)"" alias ""Beep"" (byval f as ulong)", label, params ), _
                 "cdecl lib alias, with a parenthesis INSIDE a quoted name" )
    AssertEqInt( params.Count( ), 1, "one parameter, not a list opened inside the string" )

    params.Clear( )
    AssertFalse( ParseSignature( "fp", "as function( byval x as long ) as long", label, params ), _
                 "a function-pointer TYPE is not reread as a parameter list" )
end sub

'' ############################################################################
''  Which call the caret is in
'' ############################################################################
private sub TestCallContext( )
    TestGroup( "FindCallContext" )

    Analyse( "sub Move_( byval x as long, byval y as long )" & LF & _
             "end sub" & LF & _
             "" & LF & _
             "sub Go_( )" & LF & _
             "    Move_( 10, 3 )" & LF & _
             "end sub" & LF )

    dim as CallContext ctx

    AssertTrue( ContextAfter( "Move_( ", ctx ), "the caret inside a call finds it" )
    AssertEqStr( CalleeName( ctx ), "Move_", "and names the callee" )
    AssertEqInt( ctx.ActiveArg, 0, "the first argument is active" )

    AssertTrue( ContextAfter( "Move_( 10, ", ctx ), "after the comma" )
    AssertEqInt( ctx.ActiveArg, 1, "the second argument is active" )

    AssertFalse( ContextAfter( "end sub", ctx ), "outside any call there is no context" )

    '' The declaration's own parameter list is a call context by shape. It is
    '' harmless -- `Move_` there resolves to the procedure being declared --
    '' but the callee has to be the name, not the keyword.
    AssertTrue( ContextAfter( "sub Move_( byval x", ctx ), "a parameter list looks like a call" )
    AssertEqStr( CalleeName( ctx ), "Move_", "and the callee is the procedure's own name" )

    '' Nesting: the innermost unclosed '(' is the one that matters.
    Analyse( "sub Go_( )" & LF & _
             "    dim as long n = Sum_( 1, Max_( 2, " & LF & _
             "end sub" & LF )
    AssertTrue( ContextAfter( "Max_( 2, ", ctx ), "a nested call is found" )
    AssertEqStr( CalleeName( ctx ), "Max_", "and it is the INNER callee" )
    AssertEqInt( ctx.ActiveArg, 1, "with its own argument index" )

    '' A closed call before the caret must not be mistaken for an open one.
    Analyse( "sub Go_( )" & LF & _
             "    Outer_( Inner_( 1 ), " & LF & _
             "end sub" & LF )
    AssertTrue( ContextAfter( "Inner_( 1 ), ", ctx ), "a completed nested call is skipped over" )
    AssertEqStr( CalleeName( ctx ), "Outer_", "the enclosing call is the context" )
    AssertEqInt( ctx.ActiveArg, 1, "and the caret is in its second argument" )

    '' A continuation is one logical line, so a wrapped argument list still
    '' resolves -- the lexer emits no TK_EOL for it.
    Analyse( "sub Go_( )" & LF & _
             "    Move_( 10, _" & LF & _
             "           20 )" & LF & _
             "end sub" & LF )
    AssertTrue( ContextAfter( "10, _" & LF & "           ", ctx ), _
                "a wrapped argument list is still one call" )
    AssertEqInt( ctx.ActiveArg, 1, "and the argument index carries across the line" )

    '' But a stray '(' on an earlier line must not swallow the file.
    Analyse( "dim as long a = (1 + 2" & LF & _
             "dim as long b = 3" & LF )
    AssertFalse( ContextAfter( "b = 3", ctx ), "the search stops at the end of the logical line" )

    '' A member spelled like a keyword -- LogEvent.Str -- is a callee after a
    '' dot, and only there: `print(` stays no call.
    Analyse( "lg.Warn( ).Str( k, " & LF & "print( 1, " & LF )
    AssertTrue( ContextAfter( ".Str( k, ", ctx ), "a keyword-named member call is found" )
    AssertEqStr( CalleeName( ctx ), "Str", "and named" )
    AssertEqInt( ctx.ActiveArg, 1, "with its argument index" )
    AssertFalse( ContextAfter( "print( 1, ", ctx ), "a keyword with no dot before it is no callee" )
end sub

'' ############################################################################
''  Every argument of every call
'' ############################################################################
private sub TestArgSites( )
    TestGroup( "FindArgSites" )

    Analyse( "sub Go_( )" & LF & _
             "    Move_( 10, 3 )" & LF & _
             "    Wait_( )" & LF & _
             "end sub" & LF )

    dim sites as ArgSiteArray
    FindArgSites( g_Src, g_Tokens, 0, len(g_Src), sites )

    AssertEqInt( sites.Count( ), 2, "two arguments across the range" )
    AssertEqStr( TokenText( g_Src, g_Tokens[ sites[0].NameTok ] ), "Move_", "both belong to the call" )
    AssertEqInt( sites[0].ArgIndex, 0, "the first is argument 0" )
    AssertEqInt( sites[1].ArgIndex, 1, "the second is argument 1" )
    AssertEqStr( TokenText( g_Src, g_Tokens[ sites[1].ArgTok ] ), "3", "and points at the argument itself" )

    '' A range is honoured: hints are asked for one screen at a time.
    dim as long secondLine = instr( g_Src, "Wait_" ) - 1
    FindArgSites( g_Src, g_Tokens, secondLine, len(g_Src), sites )
    AssertEqInt( sites.Count( ), 0, "a call outside the range is not reported" )

    '' A space between the name and the '(' is not a call.
    Analyse( "dim as long n = (a + b) * 2" & LF )
    FindArgSites( g_Src, g_Tokens, 0, len(g_Src), sites )
    AssertEqInt( sites.Count( ), 0, "a parenthesised expression is not a call" )

    '' Nested calls produce sites for both.
    Analyse( "sub Go_( )" & LF & _
             "    Outer_( Inner_( 1 ), 2 )" & LF & _
             "end sub" & LF )
    FindArgSites( g_Src, g_Tokens, 0, len(g_Src), sites )
    AssertEqInt( sites.Count( ), 3, "the outer call's two arguments and the inner call's one" )
end sub

'' ############################################################################
''  Which declaration is being called
'' ############################################################################
private sub TestFindCallable( )
    TestGroup( "FindCallable" )

    Analyse( "declare sub Ping_( byval n as long )" & LF & _
             "sub Ping_( byval n as long )" & LF & _
             "end sub" & LF & _
             "dim shared as long Ping2_" & LF )

    dim as long alternatives = 0
    dim as long idx = FindCallable( g_Syms, "ping_", 0, alternatives )

    AssertTrue( idx >= 0, "the procedure is found" )
    AssertFalse( g_Syms.Items[idx].IsDeclaration, "the BODY is preferred over the prototype" )
    AssertEqInt( alternatives, 1, "a DECLARE and its body are one procedure, not two" )

    idx = FindCallable( g_Syms, "ping2_", 0, alternatives )
    AssertEqInt( idx, -1, "a variable is not callable" )

    Analyse( "sub Add_( byval a as long )" & LF & _
             "end sub" & LF & _
             "sub Add_( byval a as string )" & LF & _
             "end sub" & LF )
    idx = FindCallable( g_Syms, "add_", 0, alternatives )
    AssertTrue( idx >= 0, "an overloaded name resolves" )
    AssertEqInt( alternatives, 2, "and the overload count is reported" )
end sub

'' ############################################################################
''  Main
'' ############################################################################
print "tiko-lsp -- signature, call context and argument site tests"

TestParseSignature( )
TestCallContext( )
TestArgSites( )
TestFindCallable( )

end TestSummary( "signature" )
