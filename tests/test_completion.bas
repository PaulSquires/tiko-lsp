'' ############################################################################
''  tests/test_completion.bas -- context detection and candidate collection
''
''  The two things that make completion useful rather than annoying:
''
''    - after `customer.`, ONLY members are offered. A list containing `Sub`
''      and `Print` there is worse than an empty one.
''    - in an ordinary position, a local outranks a keyword. There are 247
''      reserved words and usually three locals, and the client sorts on
''      sortText, so the group number is what decides.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#include once "assert.bi"
#include once "../src/analysis/parser.bi"
#include once "../src/analysis/completion.bi"

const LF = chr(10)

'' ----------------------------------------------------------------------------
''  Helpers
'' ----------------------------------------------------------------------------

dim shared as string             g_Src
dim shared as TokenArray         g_Tokens
dim shared as DiagnosticArray    g_Diags
dim shared as SymbolTable        g_Syms
dim shared as CompletionItemArray g_Items

private sub Analyse( byref src as string )
    g_Src = src
    AnalyzeFull( g_Src, g_Tokens, g_Diags, g_Syms )
end sub

'' Completes at the byte just after the first occurrence of `after`, which is
'' how every case below spells "put the cursor here".
private sub CompleteAfter( byref after_ as string )
    dim as long at_ = instr( g_Src, after_ ) - 1 + len(after_)
    CollectCompletions( g_Src, g_Tokens, g_Syms, at_, g_Items )
end sub

private function Has( byref label_ as string ) as boolean
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = lcase( label_ ) ) then return true
    next
    return false
end function

private function GroupOf( byref label_ as string ) as long
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = lcase( label_ ) ) then return g_Items[i].SortGroup
    next
    return -1
end function

private function KindOf( byref label_ as string ) as long
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = lcase( label_ ) ) then return g_Items[i].Kind_
    next
    return -1
end function

private function DetailOf( byref label_ as string ) as string
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = lcase( label_ ) ) then return g_Items[i].Detail_
    next
    return "<absent>"
end function

private function CountKeywords( ) as long
    dim as long n = 0
    for i as long = 0 to g_Items.Count( ) - 1
        if( g_Items[i].Kind_ = CMP_KEYWORD ) then n += 1
    next
    return n
end function

'' ----------------------------------------------------------------------------
TestGroup( "context detection" )

scope
    Analyse( "dim as Customer c" & LF & "c.Na" & LF & "print x" )

    '' Right after the dot.
    dim as long dotAt = instr( g_Src, "c.Na" ) + 1
    dim as CompletionContext c1 = CompletionContextAt( g_Src, g_Tokens, dotAt )
    AssertEqInt( c1.Kind_, CMPCTX_MEMBER, "a position after a dot is a member context" )
    AssertEqStr( c1.BaseName, "c", "and the base is what is left of it" )
    AssertEqStr( c1.Prefix, "", "with nothing typed yet" )

    '' After two letters of the member name.
    dim as CompletionContext c2 = CompletionContextAt( g_Src, g_Tokens, dotAt + 2 )
    AssertEqInt( c2.Kind_, CMPCTX_MEMBER, "a partial member name is still a member context" )
    AssertEqStr( c2.BaseName, "c", "the base survives the partial word" )
    AssertEqStr( c2.Prefix, "na", "and the prefix is what was typed, lower-cased" )

    '' An ordinary identifier position.
    dim as long printAt = instr( g_Src, "print x" ) + 2
    dim as CompletionContext c3 = CompletionContextAt( g_Src, g_Tokens, printAt )
    AssertEqInt( c3.Kind_, CMPCTX_SCOPE, "an ordinary position is a scope context" )
    AssertEqStr( c3.Prefix, "pri", "with the partial word as the prefix" )
end scope

scope
    '' Inside a comment or a string there is nothing to complete. Offering the
    '' scope list there is how an editor suggests `function` mid-sentence.
    Analyse( "x = " & chr(34) & "hello world" & chr(34) & LF & "y = 1 ' a note here" )

    dim as long inString = instr( g_Src, "hello" ) + 2
    CollectCompletions( g_Src, g_Tokens, g_Syms, inString, g_Items )
    AssertEqInt( g_Items.Count( ), 0, "no completions inside a string literal" )

    dim as long inComment = instr( g_Src, "a note" ) + 2
    CollectCompletions( g_Src, g_Tokens, g_Syms, inComment, g_Items )
    AssertEqInt( g_Items.Count( ), 0, "no completions inside a comment" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "member completion: a variable's declared type" )

scope
    '' This is the spec's own example: `customer.` offers the members of
    '' Customer, and NOTHING else.
    Analyse( "type Customer" & LF & _
             "    Name_ as string" & LF & _
             "    Age as long" & LF & _
             "    declare sub SetName( byref v as string )" & LF & _
             "end type" & LF & _
             "type Order_" & LF & _
             "    Total as double" & LF & _
             "end type" & LF & _
             "sub Use( )" & LF & _
             "    dim as Customer customer" & LF & _
             "    customer." & LF & _
             "end sub" )

    CompleteAfter( "customer." )

    AssertTrue ( Has( "Name_" ), "a field of the type is offered" )
    AssertTrue ( Has( "Age" ), "every field is offered" )
    AssertTrue ( Has( "SetName" ), "and its methods" )
    AssertFalse( Has( "Total" ), "a field of ANOTHER type is not" )
    AssertFalse( Has( "Customer" ), "nor the type itself" )
    AssertFalse( Has( "sub" ), "and no keywords at all after a dot" )
    AssertEqInt( CountKeywords( ), 0, "the member list is only members" )

    AssertEqInt( KindOf( "Name_" ), CMP_FIELD, "a field is a Field" )
    AssertEqInt( KindOf( "SetName" ), CMP_METHOD, "a method is a Method" )
    AssertEqStr( DetailOf( "Age" ), "as long", "with its type as the detail" )
    AssertEqInt( GroupOf( "Name_" ), CMPGROUP_MEMBER, "members sort first" )
end scope

scope
    '' A pointer declaration names the same type.
    Analyse( "type Node_" & LF & "    Value_ as long" & LF & "end type" & LF & _
             "sub Walk( byval n as Node_ ptr )" & LF & _
             "    n." & LF & "end sub" )

    CompleteAfter( "    n." )
    AssertTrue( Has( "Value_" ), "`as Node_ ptr` resolves to Node_" )
end scope

scope
    '' Out-of-line members are parented to the file, not to the type, so they
    '' have to be found by their dotted name or they vanish from the list.
    Analyse( "type Customer" & LF & "    Name_ as string" & LF & "end type" & LF & _
             "sub Customer.SetName( byref v as string )" & LF & "end sub" & LF & _
             "function Customer.GetName( ) as string" & LF & "end function" & LF & _
             "sub Use( )" & LF & "    dim as Customer c" & LF & "    c." & LF & "end sub" )

    CompleteAfter( "    c." )
    AssertTrue( Has( "SetName" ), "an out-of-line method is offered" )
    AssertTrue( Has( "GetName" ), "including a function" )
    AssertTrue( Has( "Name_" ), "alongside the fields" )
    AssertFalse( Has( "Customer.SetName" ), "offered by its LAST segment, not its full name" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "member completion: types, enums, namespaces, this" )

scope
    Analyse( "enum Colour" & LF & "    Red" & LF & "    Green" & LF & "end enum" & LF & _
             "x = Colour." )

    CompleteAfter( "Colour." )
    AssertTrue ( Has( "Red" ), "an enum offers its members" )
    AssertTrue ( Has( "Green" ), "all of them" )
    AssertEqInt( KindOf( "Red" ), CMP_ENUMMEMBER, "as EnumMembers" )
end scope

scope
    Analyse( "namespace App" & LF & _
             "    const MAX_ITEMS = 100" & LF & _
             "    declare sub Run( )" & LF & _
             "end namespace" & LF & _
             "App." )

    CompleteAfter( "end namespace" & LF & "App." )
    AssertTrue( Has( "MAX_ITEMS" ), "a namespace offers its constants" )
    AssertTrue( Has( "Run" ), "and its procedures" )
end scope

scope
    '' `this.` inside an out-of-line method: the type is named by the method.
    Analyse( "type Customer" & LF & "    Name_ as string" & LF & "    Age as long" & LF & "end type" & LF & _
             "sub Customer.SetName( byref v as string )" & LF & _
             "    this." & LF & "end sub" )

    CompleteAfter( "    this." )
    AssertTrue ( Has( "Name_" ), "`this.` offers the enclosing type's fields" )
    AssertTrue ( Has( "Age" ), "all of them" )
    AssertEqInt( CountKeywords( ), 0, "and nothing else" )
end scope

scope
    '' An unresolvable base -- a call, an #included type, half-typed text --
    '' falls back to every member in the file. A guess, but a useful one, and
    '' still better than keywords.
    Analyse( "type Customer" & LF & "    Name_ as string" & LF & "end type" & LF & _
             "GetCustomer( )." )

    CompleteAfter( "GetCustomer( )." )
    AssertTrue ( Has( "Name_" ), "an unresolved base falls back to known members" )
    AssertEqInt( CountKeywords( ), 0, "and never to keywords" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "scope completion" )

scope
    Analyse( "dim shared as long g_Total" & LF & _
             "const MAX_ITEMS = 100" & LF & _
             "type Customer" & LF & "    Name_ as string" & LF & "end type" & LF & _
             "declare sub Helper( )" & LF & _
             "sub Work( byval count as long )" & LF & _
             "    dim as string local_" & LF & _
             "    x" & LF & _
             "end sub" )

    CompleteAfter( "    x" )

    AssertTrue( Has( "local_" ), "a local is offered" )
    AssertTrue( Has( "count" ), "a parameter is offered" )
    AssertTrue( Has( "g_Total" ), "a global is offered" )
    AssertTrue( Has( "MAX_ITEMS" ), "a constant is offered" )
    AssertTrue( Has( "Customer" ), "a type is offered" )
    AssertTrue( Has( "Helper" ), "a procedure is offered" )
    AssertTrue( Has( "Work" ), "including the one we are inside" )
    AssertTrue( Has( "sub" ), "and the keywords, too" )
    AssertTrue( Has( "byref" ), "all of them" )

    '' The ordering that matters: nearest scope first, language last.
    AssertEqInt( GroupOf( "local_" ), CMPGROUP_LOCAL, "locals are the nearest group" )
    AssertEqInt( GroupOf( "count" ), CMPGROUP_LOCAL, "so are parameters" )
    AssertEqInt( GroupOf( "g_Total" ), CMPGROUP_FILE, "file declarations come next" )
    AssertEqInt( GroupOf( "sub" ), CMPGROUP_KEYWORD, "and keywords last" )
    AssertTrue ( GroupOf( "local_" ) < GroupOf( "sub" ), "a local outranks a keyword" )

    AssertEqInt( KindOf( "Customer" ), CMP_STRUCT, "a type is a Struct" )
    AssertEqInt( KindOf( "MAX_ITEMS" ), CMP_CONSTANT, "a const is a Constant" )
    AssertEqInt( KindOf( "count" ), CMP_VARIABLE, "a parameter is a Variable" )
    AssertEqInt( KindOf( "sub" ), CMP_KEYWORD, "a keyword is a Keyword" )
    AssertTrue ( CountKeywords( ) > 200, "the whole reserved list is there" )
end scope

scope
    '' Inside a method, the enclosing type's members are in scope without a
    '' `this.`, and rank above the file's other declarations.
    Analyse( "type Customer" & LF & "    Name_ as string" & LF & _
             "    declare sub SetName( )" & LF & "end type" & LF & _
             "sub Customer.SetName( )" & LF & "    x" & LF & "end sub" )

    CompleteAfter( "    x" )
    AssertTrue( Has( "Name_" ), "a field is in scope inside its own method" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "the fixed-width type names" )

scope
    Analyse( "sub Work( )" & LF & "    x" & LF & "end sub" )
    CompleteAfter( "    x" )

    AssertTrue ( Has( "int32" ), "tiko-lang's int32 is offered" )
    AssertTrue ( Has( "float64" ), "and so is float64" )
    AssertEqInt( KindOf( "uint8" ), CMP_STRUCT, "as a type, as a UDT is" )
    AssertEqStr( DetailOf( "int64" ), "type int64 as longint", "naming the type it stands for" )
    AssertEqInt( GroupOf( "int16" ), CMPGROUP_KEYWORD, "ranked with the language" )
end scope

scope
    '' A file's own float32 has replaced tiko's: one candidate, the file's.
    Analyse( "dim shared as long float32" & LF & "x" )
    CompleteAfter( LF & "x" )

    AssertEqInt( KindOf( "float32" ), CMP_VARIABLE, "a file's own float32 wins" )
    dim as long n = 0
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = "float32" ) then n += 1
    next
    AssertEqInt( n, 1, "and is the only float32 offered" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "the predeclared constant nullptr" )

scope
    Analyse( "sub Work( )" & LF & "    x" & LF & "end sub" )
    CompleteAfter( "    x" )

    AssertTrue ( Has( "nullptr" ), "tiko-lang's nullptr is offered" )
    AssertEqInt( KindOf( "nullptr" ), CMP_CONSTANT, "as a constant" )
    AssertEqStr( DetailOf( "nullptr" ), "const nullptr as any ptr = 0", "naming the prelude's declaration" )
    AssertEqInt( GroupOf( "nullptr" ), CMPGROUP_KEYWORD, "ranked with the language" )
end scope

scope
    '' A file's own nullptr has replaced tiko's: one candidate, the file's.
    Analyse( "dim shared as long nullptr" & LF & "x" )
    CompleteAfter( LF & "x" )

    AssertEqInt( KindOf( "nullptr" ), CMP_VARIABLE, "a file's own nullptr wins" )
    dim as long n = 0
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = "nullptr" ) then n += 1
    next
    AssertEqInt( n, 1, "and is the only nullptr offered" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "no duplicates" )

scope
    '' A prototype and its body are two symbols with one name, and tiko
    '' is case-insensitive, so `Helper` and `helper` are the same candidate.
    Analyse( "declare sub Helper( )" & LF & _
             "sub Helper( )" & LF & "end sub" & LF & _
             "dim as long helper_count" & LF & _
             "x" )

    CompleteAfter( LF & "x" )

    dim as long n = 0
    for i as long = 0 to g_Items.Count( ) - 1
        if( lcase( g_Items[i].Label ) = "helper" ) then n += 1
    next
    AssertEqInt( n, 1, "a declare and its body are one candidate" )
    AssertTrue ( Has( "helper_count" ), "a different name is still its own candidate" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "member completion: aliases and qualified types" )

'' `type CustAlias as Customer`: the variable's type is the alias, and the
'' members are Customer's. An alias was no symbol at all before, and once it
'' was one it had no members of its own -- both read as "nothing after the dot".
scope
    Analyse( "type Customer" & LF & _
             "    Name_ as string" & LF & _
             "    declare sub SetName( byref v as string )" & LF & _
             "end type" & LF & _
             "type Unrelated" & LF & "    Zzz as long" & LF & "end type" & LF & _
             "type CustAlias as Customer" & LF & _
             "type AliasOfAlias as CustAlias" & LF & _
             "sub Use( )" & LF & _
             "    dim as AliasOfAlias c" & LF & _
             "    c." & LF & _
             "end sub" )
    CompleteAfter( "    c." )
    AssertTrue ( Has( "Name_" ), "through two aliases: the field" )
    AssertTrue ( Has( "SetName" ), "and the method" )
    AssertFalse( Has( "Zzz" ), "and NOT a guess from every type in the file" )
    AssertEqInt( CountKeywords( ), 0, "and nothing else" )
end scope

'' Constructors, destructors and operators are not offered after a dot.
scope
    Analyse( "type Widget" & LF & _
             "    W as long" & LF & _
             "    declare constructor( )" & LF & _
             "    declare destructor( )" & LF & _
             "    declare operator let( byref o as Widget )" & LF & _
             "    declare sub Draw( )" & LF & _
             "end type" & LF & _
             "sub Use( )" & LF & "    dim as Widget w" & LF & "    w." & LF & "end sub" )
    CompleteAfter( "    w." )
    AssertTrue ( Has( "Draw" ) andalso Has( "W" ), "w.: the method and the field" )
    AssertFalse( Has( "constructor" ) orelse Has( "destructor" ), "not the constructor or destructor" )
    AssertFalse( Has( "let" ), "nor an operator" )
end scope

'' A cycle of aliases ends: nothing to offer, and no hang.
scope
    Analyse( "type A1 as B1" & LF & "type B1 as A1" & LF & _
             "sub Use( )" & LF & "    dim as A1 x" & LF & "    x." & LF & "end sub" )
    CompleteAfter( "    x." )
    AssertTrue( g_Items.Count( ) >= 0, "an alias cycle terminates" )
end scope

'' A QUALIFIED type names its last segment: `App.Customer` is Customer.
scope
    Analyse( "namespace App" & LF & _
             "type Customer" & LF & _
             "    Age as long" & LF & _
             "end type" & LF & _
             "end namespace" & LF & _
             "sub Use( )" & LF & _
             "    dim as App.Customer q" & LF & _
             "    q." & LF & _
             "end sub" )
    CompleteAfter( "    q." )
    AssertTrue( Has( "Age" ), "dim as App.Customer: Customer's members" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "member completion: chained calls" )

scope
    '' The std/logs shape, in one file: Logger_.Warn( ) returns a LogEvent and
    '' each LogEvent method returns `byref as LogEvent`. `sub Warn( m )` is an
    '' overload with no type -- the chain must take the function.
    Analyse( "type LogEvent" & LF & _
             "    declare function Str( byref k as string, byref v as string ) byref as LogEvent" & LF & _
             "    declare function Int_( byref k as string, byval v as longint ) byref as LogEvent" & LF & _
             "    declare sub Msg( byref m as string )" & LF & _
             "end type" & LF & _
             "type Logger_" & LF & _
             "    declare sub Warn( byref m as string )" & LF & _
             "    declare function Warn( ) as LogEvent" & LF & _
             "    declare property MinLevel( ) as long" & LF & _
             "end type" & LF & _
             "type Logger as Logger_" & LF & _
             "function MakeLogger( ) as Logger" & LF & _
             "end function" & LF & _
             "dim shared as Logger lg" & LF & _
             "lg.Warn( ).Str( " & chr(34) & "user" & chr(34) & ", " & chr(34) & "Paul (P.) Squires" & chr(34) & " ).Int_( " & chr(34) & "n" & chr(34) & ", 4 ).Msg( " & chr(34) & "x" & chr(34) & " )" & LF & _
             "MakeLogger( ).Warn( ).Ms" & LF )

    '' The context: base, chain, and the arguments skipped -- including a
    '' string holding a parenthesis and a dot.
    dim as long msgAt = instr( g_Src, ".Msg(" )
    dim as CompletionContext cc = CompletionContextAt( g_Src, g_Tokens, msgAt + 1 )
    AssertEqInt( cc.Kind_, CMPCTX_MEMBER, "after `).` is a member context" )
    AssertEqStr( cc.BaseName, "lg", "the base is the chain's leftmost name" )
    AssertEqInt( cc.Chain.Count( ), 3, "with three links between it and the dot" )
    if( cc.Chain.Count( ) = 3 ) then
        AssertEqStr( cc.Chain[0] & "," & cc.Chain[1] & "," & cc.Chain[2], "warn,str,int_", "in order, lower-cased" )
    end if

    dim as CompletionContext c0 = CompletionContextAt( g_Src, g_Tokens, instr( g_Src, "lg.Warn" ) + 2 )
    AssertEqInt( c0.Chain.Count( ), 0, "a plain `lg.` has no chain" )

    '' The list after `.Int_( "n", 4 ).` is LogEvent's.
    CollectCompletions( g_Src, g_Tokens, g_Syms, msgAt + 1, g_Items )
    AssertTrue ( Has( "Msg" ), "a chained call offers its return type's members" )
    AssertTrue ( Has( "Str" ), "every one of them" )
    AssertFalse( Has( "MinLevel" ), "and not the base's" )

    '' Partway down the chain: `lg.Warn( ).` -- the link's return type.
    CollectCompletions( g_Src, g_Tokens, g_Syms, instr( g_Src, ".Str(" ), g_Items )
    AssertTrue ( Has( "Int_" ), "after the first call, its return type's members" )
    AssertFalse( Has( "Warn" ), "not Logger_'s" )

    '' A function's result as the base, and a partial word after the chain.
    CompleteAfter( "MakeLogger( ).Warn( ).Ms" )
    AssertTrue ( Has( "Msg" ), "a function call as the base resolves to its return type" )
    AssertFalse( Has( "MinLevel" ), "through the alias, then the chain" )
end scope

scope
    Analyse( "type Pt" & LF & "    x as long" & LF & "end type" & LF & _
             "dim as Pt p" & LF & "( p ).x" & LF )
    dim as CompletionContext cp = CompletionContextAt( g_Src, g_Tokens, instr( g_Src, ").x" ) + 1 )
    AssertEqStr( cp.BaseName, "", "a parenthesised expression has no base" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "half-typed code" )

scope
    Analyse( "sub Work( )" & LF & "    dim as long total" & LF & "    tot" )
    CompleteAfter( "    tot" )
    AssertTrue( Has( "total" ), "a partial word still offers what it could become" )

    Analyse( "" )
    CollectCompletions( g_Src, g_Tokens, g_Syms, 0, g_Items )
    AssertTrue( g_Items.Count( ) > 200, "an empty document still offers the language" )

    Analyse( "customer." )
    CollectCompletions( g_Src, g_Tokens, g_Syms, len(g_Src), g_Items )
    AssertEqInt( g_Items.Count( ), 0, "a dot on an unknown name in an empty file offers nothing" )

    Analyse( "dim as Customer c" & LF & "c." )
    CollectCompletions( g_Src, g_Tokens, g_Syms, len(g_Src), g_Items )
    AssertEqInt( g_Items.Count( ), 0, "a type that is not in this file offers nothing" )

    Analyse( "sub " )
    CollectCompletions( g_Src, g_Tokens, g_Syms, 4, g_Items )
    AssertTrue( g_Items.Count( ) >= 0, "`sub ` mid-word does not crash" )
end scope

end TestSummary( "completion" )
