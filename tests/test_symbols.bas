'' ############################################################################
''  tests/test_symbols.bas -- symbol extraction, scope resolution, hover text
''
''  What phase 4 is: the outline, hover and go-to-definition all read the same
''  table, so a mistake here is three wrong answers rather than one.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#include once "assert.bi"
#include once "../src/analysis/parser.bi"

const LF = chr(10)
const DQ = chr(34)

'' ----------------------------------------------------------------------------
''  Helpers
'' ----------------------------------------------------------------------------

dim shared as string        g_Src
dim shared as TokenArray    g_Tokens
dim shared as DiagnosticArray g_Diags
dim shared as SymbolTable   g_Syms

'' A guarded accessor: an index of -1 comes back as an empty symbol rather
'' than reading off the front of the array. Without it, one failed expectation
'' takes the whole suite down with a segfault instead of reporting.
private function S_( byval i as long ) byref as SymbolInfo
    static as SymbolInfo empty_
    if( i < 0 orelse i >= g_Syms.Count( ) ) then return empty_
    return g_Syms.Items[i]
end function

private sub Analyse( byref src as string )
    g_Src = src
    AnalyzeFull( g_Src, g_Tokens, g_Diags, g_Syms )
end sub

private function IndexOfName( byref name_ as string ) as long
    for i as long = 0 to g_Syms.Count( ) - 1
        if( S_(i).Name_ = name_ ) then return i
    next
    return -1
end function

'' Asserts that a symbol of that name exists, with that kind, and returns it.
private function Expect( byref name_ as string, byval kind as SymbolKind, byref what_ as string ) as long
    dim as long i = IndexOfName( name_ )
    if( i < 0 ) then
        TestFail( what_, "no symbol named '" & name_ & "'" )
        return -1
    end if
    if( S_(i).Kind_ <> kind ) then
        TestFail( what_, "'" & name_ & "' is a " & SymbolKindName( S_(i).Kind_ ) & _
                         ", wanted " & SymbolKindName( kind ) )
        return i
    end if
    TestPass( what_ )
    return i
end function

'' The byte offset of the first occurrence of `needle`, plus `plus_` bytes.
private function ByteAt( byref needle as string, byval plus_ as long = 0 ) as long
    return instr( g_Src, needle ) - 1 + plus_
end function

'' ----------------------------------------------------------------------------
TestGroup( "extraction: procedures" )

scope
    Analyse( "sub Greet( byval times as long )" & LF & _
             "    dim as long i" & LF & _
             "end sub" & LF & _
             "function Add( byval a as long, byval b as long ) as long" & LF & _
             "    return a + b" & LF & _
             "end function" )

    dim as long g = Expect( "Greet", SYM_FUNCTION, "a sub is a symbol" )
    dim as long a = Expect( "Add", SYM_FUNCTION, "a function is a symbol" )

    AssertEqStr( S_(g).Detail_, "(byval times as long)", "the sub's signature" )
    AssertEqStr( S_(a).Detail_, "(byval a as long, byval b as long) as long", _
                 "the function's signature, including the return type" )

    '' The name range is the NAME, not the whole declaration: that is where
    '' go-to-definition puts the caret.
    AssertEqInt( S_(g).NameStart, ByteAt( "Greet" ), "the name range starts at the name" )
    AssertEqInt( S_(g).NameEnd, ByteAt( "Greet" ) + 5, "and ends after it" )

    '' The full range covers the body, so selecting the outline row highlights
    '' the procedure.
    AssertEqInt( S_(g).RangeStart, 0, "the full range starts at the opener" )
    AssertTrue ( S_(g).RangeEnd > ByteAt( "end sub" ), "and ends after `end sub`" )
end scope

scope
    Analyse( "declare sub Later( byref s as string )" & LF & _
             "sub Later( byref s as string )" & LF & "end sub" )

    dim as long n = 0
    for i as long = 0 to g_Syms.Count( ) - 1
        if( S_(i).Name_ = "Later" ) then n += 1
    next
    AssertEqInt( n, 2, "a prototype and its body are two symbols" )

    '' Resolution must prefer the body: hovering a call should point at the
    '' code, not at the promise of it.
    dim as long r = g_Syms.Resolve( "later", len(g_Src) - 1 )
    AssertFalse( S_(r).IsDeclaration, "a definition beats a declare" )
end scope

scope
    '' Constructors and destructors have no name of their own, and members are
    '' written with a dot.
    Analyse( "constructor Customer( )" & LF & "end constructor" & LF & _
             "destructor Customer( )" & LF & "end destructor" & LF & _
             "sub Customer.SetName( byref v as string )" & LF & "end sub" & LF & _
             "operator Customer.let( byref rhs as Customer )" & LF & "end operator" )

    AssertTrue( IndexOfName( "Customer" ) >= 0, "a constructor is named after its type" )
    dim as long m = Expect( "Customer.SetName", SYM_METHOD, "a dotted name is a method" )
    AssertEqStr( S_(m).Detail_, "(byref v as string)", "with its signature" )
    AssertTrue( IndexOfName( "Customer.let" ) >= 0, "an operator body is a symbol" )
end scope

scope
    '' A generic member: the type-argument list is part of the name, or the
    '' name reads as `Optional` and the member ends up in the signature.
    Analyse( "function Optional( of T ).Value( ) byref as T" & LF & _
             "    return this.v" & LF & "end function" )

    dim as long i = IndexOfName( "Optional (of T).Value" )
    AssertTrue( i >= 0, "a generic member keeps its type arguments in the name" )
    if( i >= 0 ) then
        AssertEqStr( S_(i).Detail_, "() byref as T", "and its signature is only the signature" )
        AssertEqStr( S_(i).LowerName, "value", "while lookup uses the last segment" )
    end if
end scope

'' ----------------------------------------------------------------------------
TestGroup( "extraction: types, enums, namespaces" )

scope
    Analyse( "type Customer" & LF & _
             "    Name_ as string" & LF & _
             "    Age as long" & LF & _
             "    as long Extra1, Extra2" & LF & _
             "    declare sub SetName( byref v as string )" & LF & _
             "end type" )

    dim as long t = Expect( "Customer", SYM_STRUCT, "a type is a symbol" )
    dim as long f = Expect( "Name_", SYM_FIELD, "a field is a symbol" )
    AssertEqInt( S_(f).Parent, t, "and is parented to its type" )
    AssertEqStr( S_(f).Detail_, "as string", "with its type as the detail" )

    '' `as long Extra1, Extra2` -- the type-first form, with two names.
    dim as long e1 = Expect( "Extra1", SYM_FIELD, "the type-first field form" )
    dim as long e2 = Expect( "Extra2", SYM_FIELD, "declares every name in the list" )
    AssertEqStr( S_(e1).Detail_, "as long", "and gives them all the type" )
    AssertEqStr( S_(e2).Detail_, "as long", "including the last one" )

    dim as long m = Expect( "SetName", SYM_METHOD, "a declare inside a type is a method" )
    AssertTrue ( S_(m).IsDeclaration, "marked as a declaration" )
    AssertEqInt( S_(m).Parent, t, "and parented to the type" )
end scope

scope
    Analyse( "enum Colour" & LF & "    Red" & LF & "    Green = 5" & LF & "end enum" )

    dim as long e = Expect( "Colour", SYM_ENUM, "an enum is a symbol" )
    dim as long r = Expect( "Red", SYM_ENUMMEMBER, "a member is a symbol" )
    dim as long g = Expect( "Green", SYM_ENUMMEMBER, "including one with a value" )
    AssertEqInt( S_(r).Parent, e, "parented to the enum" )
    AssertEqStr( S_(g).Detail_, "= 5", "and the value is shown" )
end scope

scope
    Analyse( "namespace App" & LF & _
             "    const MAX_ITEMS = 100" & LF & _
             "    dim shared as long g_Count" & LF & _
             "end namespace" )

    dim as long n = Expect( "App", SYM_NAMESPACE, "a namespace is a symbol" )
    dim as long c = Expect( "MAX_ITEMS", SYM_CONSTANT, "a const is a constant" )
    dim as long v = Expect( "g_Count", SYM_VARIABLE, "a dim shared is a variable" )

    AssertEqInt( S_(c).Parent, n, "both are parented to the namespace" )
    AssertEqStr( S_(c).Detail_, "= 100", "an untyped const shows its value" )

    '' `dim shared as long g_Count`: SHARED is a modifier, the type is `long`,
    '' and the name must not end up inside the type.
    AssertEqStr( S_(v).Detail_, "as long", "SHARED does not confuse the type" )
    AssertEqStr( S_(v).Name_, "g_Count", "and the underscore survives" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "extraction: locals and parameters" )

scope
    Analyse( "sub Work( byval count as long, byref name_ as string )" & LF & _
             "    dim as long total = 0" & LF & _
             "    dim i as long, j as long" & LF & _
             "    static as long calls_" & LF & _
             "end sub" )

    dim as long w = IndexOfName( "Work" )

    dim as long p1 = IndexOfName( "count" )
    dim as long p2 = IndexOfName( "name_" )
    AssertTrue ( p1 >= 0 andalso p2 >= 0, "both parameters are symbols" )
    AssertTrue ( S_(p1).IsLocal, "a parameter is local" )
    AssertEqInt( S_(p1).Parent, w, "and belongs to its procedure" )

    dim as long l1 = IndexOfName( "total" )
    dim as long l2 = IndexOfName( "i" )
    dim as long l3 = IndexOfName( "j" )
    dim as long l4 = IndexOfName( "calls_" )
    AssertTrue ( l1 >= 0 andalso l2 >= 0 andalso l3 >= 0 andalso l4 >= 0, _
                 "every local form is captured" )
    AssertTrue ( S_(l1).IsLocal, "a dim inside a sub is local" )
    AssertEqStr( S_(l2).Detail_, "as long", "name-first with two names: first type" )
    AssertEqStr( S_(l3).Detail_, "as long", "name-first with two names: second type" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "documentation comments" )

scope
    Analyse( "'' Adds two numbers." & LF & _
             "'' The second line." & LF & _
             "function Add( byval a as long ) as long" & LF & "end function" & LF & _
             LF & _
             "'' Not attached to anything." & LF & _
             LF & _
             "sub Orphan( )" & LF & "end sub" & LF & _
             "sub Trailing( ) '' a remark, not documentation" & LF & "end sub" )

    dim as long a = IndexOfName( "Add" )
    AssertContains( S_(a).Doc_, "Adds two numbers.", "the comment above a declaration is its doc" )
    AssertContains( S_(a).Doc_, "The second line.", "and the whole block is kept" )

    dim as long o = IndexOfName( "Orphan" )
    AssertEqStr( S_(o).Doc_, "", "a blank line separates a comment from what follows" )

    dim as long t = IndexOfName( "Trailing" )
    AssertEqStr( S_(t).Doc_, "", "a comment on the same line is a remark, not doc" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "resolution" )

scope
    Analyse( "dim shared as long total" & LF & _
             "sub Work( byval total as long )" & LF & _
             "    dim as long inner_ = total" & LF & _
             "end sub" & LF & _
             "sub Other( )" & LF & _
             "    total = 1" & LF & _
             "end sub" )

    '' Inside Work, `total` is the PARAMETER; inside Other it is the global.
    '' Getting this backwards is the classic scope bug, and it is silent.
    dim as long inWork  = g_Syms.Resolve( "total", ByteAt( "inner_ = total", 9 ) )
    dim as long inOther = g_Syms.Resolve( "total", ByteAt( "total = 1" ) )

    AssertTrue( inWork >= 0 andalso inOther >= 0, "both resolve" )
    AssertTrue( S_(inWork).IsLocal, "inside the sub, the parameter wins" )
    AssertFalse( S_(inOther).IsLocal, "outside it, the global does" )
    AssertTrue( inWork <> inOther, "and they are different symbols" )
end scope

scope
    Analyse( "type Customer" & LF & "    Name_ as string" & LF & "end type" & LF & _
             "sub Use( )" & LF & _
             "    dim as Customer c" & LF & _
             "    print c.Name_" & LF & _
             "end sub" )

    '' Member access resolves against members, not against whatever else has
    '' that name.
    dim as long m = g_Syms.ResolveMember( "name_" )
    AssertTrue ( m >= 0, "a member resolves" )
    AssertEqInt( S_(m).Kind_, SYM_FIELD, "to the field" )

    AssertEqInt( g_Syms.Resolve( "nosuchthing", 0 ), -1, "an unknown name resolves to nothing" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "the token under the cursor" )

scope
    Analyse( "dim as long counter" & LF & "counter = 1" )

    dim as long nameAt = ByteAt( "counter" )

    AssertTrue( TokenIndexAt( g_Tokens, nameAt ) >= 0, "a position inside a name finds it" )
    AssertEqStr( TokenText( g_Src, g_Tokens[ TokenIndexAt( g_Tokens, nameAt ) ] ), "counter", _
                 "and it is the right token" )

    '' The caret sitting just after the last letter still means that word --
    '' which is where it is when a user double-clicks and hovers.
    AssertEqStr( TokenText( g_Src, g_Tokens[ TokenIndexAt( g_Tokens, nameAt + 7 ) ] ), "counter", _
                 "a position at the end of a name still finds it" )

    '' `dim as long counter`: offset 4 is the `a` of `as`, and offset 3 is the
    '' space just after `dim` -- which still means `dim`, by the same
    '' end-inclusive rule.
    AssertEqStr( TokenText( g_Src, g_Tokens[ TokenIndexAt( g_Tokens, 4 ) ] ), "as", _
                 "a position on a keyword finds it" )
    AssertEqStr( TokenText( g_Src, g_Tokens[ TokenIndexAt( g_Tokens, 3 ) ] ), "dim", _
                 "a position just after a token still belongs to it" )
    AssertEqInt( TokenIndexAt( g_Tokens, 9999 ), -1, "a position past the end finds nothing" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "hover text" )

scope
    Analyse( "'' Adds two numbers." & LF & _
             "function Add( byval a as long, byval b as long ) as long" & LF & _
             "end function" )

    dim as long a = IndexOfName( "Add" )
    dim as string h = SymbolHoverMarkdown( S_(a) )

    AssertContains( h, "```tiko", "hover is markdown with a code block" )
    AssertContains( h, "Add (byval a as long, byval b as long) as long", "showing the declaration" )
    AssertContains( h, "procedure", "naming the kind" )
    AssertContains( h, "Adds two numbers.", "and carrying the documentation" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "half-typed code" )

scope
    '' A file being typed into must still yield an outline: a blank outline is
    '' what makes an editor feel broken.
    Analyse( "type Customer" & LF & "    Name_ as string" )
    AssertTrue( IndexOfName( "Customer" ) >= 0, "an unclosed type is still a symbol" )
    AssertTrue( IndexOfName( "Name_" ) >= 0, "and its fields are still symbols" )

    dim as long t = IndexOfName( "Customer" )
    AssertTrue( S_(t).RangeEnd >= S_(t).RangeStart, _
                "an unclosed block still has a usable range" )

    Analyse( "sub " )
    AssertTrue( g_Syms.Count( ) >= 0, "`sub ` mid-word does not crash" )
    Analyse( "function Foo( byval" )
    AssertTrue( g_Syms.Count( ) >= 0, "a half-typed parameter list does not crash" )
    Analyse( "" )
    AssertEqInt( g_Syms.Count( ), 0, "an empty document declares nothing" )
end scope

end TestSummary( "symbols" )
