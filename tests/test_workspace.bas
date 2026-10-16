'' ############################################################################
''  tests/test_workspace.bas -- discovery, the symbol index, reference scanning
''
''  Run with the project root as argv(1); the fixture workspace under
''  tests/fixtures/workspace is what the cross-file assertions are made
''  against, so they do not depend on this project's own source moving around.
''
''  Build: build\_run_tests.bat  (or build/_run_tests.sh)
'' ############################################################################

#include once "assert.bi"
#include once "../src/workspace/workspace.bi"
#include once "../src/workspace/symbol_index.bi"
#include once "../src/workspace/index_builder.bi"
#include once "../src/utils/uri.bi"
#include once "../src/analysis/includes.bi"
#include once "../src/workspace/modules.bi"
#include once "../src/workspace/metadata.bi"
#include once "../src/workspace/cincludes.bi"

const LF = chr(10)

dim shared as string g_Root       '' the project root
dim shared as string g_Fixture    '' tests\fixtures\workspace

'' Module-level statements run in order, so the fixture path is settled
'' BEFORE the first group uses it.
g_Root = command( 1 )
if( len(g_Root) = 0 ) then
    print "usage: test_workspace <project-root>"
    end 2
end if
g_Fixture = g_Root & NativePath( "\tests\fixtures\workspace" )

'' ----------------------------------------------------------------------------
TestGroup( "file discovery" )

AssertTrue ( IsSourceFileName( "main.tiko" ), ".tiko is source" )
AssertTrue ( IsSourceFileName( "MAIN.TIKO" ), ".tiko is matched case-insensitively" )
AssertFalse( IsSourceFileName( "main.tikox" ), "but not a longer extension that starts with it" )
AssertTrue ( IsSourceFileName( "main.tko" ), ".tko is source" )
AssertTrue ( IsSourceFileName( "shared.ti" ), ".ti is source" )
AssertTrue ( IsSourceFileName( "MAIN.TKO" ), ".tko is matched case-insensitively" )
AssertTrue ( IsSourceFileName( "Shared.Ti" ), "and so is .ti" )
AssertFalse( IsSourceFileName( "main.tkox" ), "but a longer extension that starts with it is not" )
AssertFalse( IsSourceFileName( "main.tik" ), "nor a shorter one" )
AssertTrue ( IsSourceFileName( "main.bas" ), ".bas is source" )
AssertTrue ( IsSourceFileName( "shared.bi" ), ".bi is source" )
AssertTrue ( IsSourceFileName( "AfxStr.inc" ), ".inc is source" )
AssertTrue ( IsSourceFileName( "MAIN.BAS" ), "the extension test is case-insensitive" )
AssertFalse( IsSourceFileName( "tiko-lsp.exe" ), "an executable is not source" )
AssertFalse( IsSourceFileName( "notes.txt" ), "nor a text file" )
AssertFalse( IsSourceFileName( "Makefile" ), "nor a file with no extension" )
AssertFalse( IsSourceFileName( "basic" ), "and `bas` inside a name is not an extension" )

AssertTrue ( IsIgnoredPath( NativePath( "C:\dev\proj\.git\hooks\x.bas" ) ), ".git is skipped" )
AssertTrue ( IsIgnoredPath( "/home/u/proj/node_modules/p/x.bi" ), "so is node_modules" )
AssertTrue ( IsIgnoredPath( NativePath( "C:\dev\proj\.vscode\x.bas" ) ), "and .vscode" )
AssertFalse( IsIgnoredPath( NativePath( "C:\dev\proj\src\git\x.bas" ) ), "a folder merely NAMED git is kept" )
AssertFalse( IsIgnoredPath( NativePath( "C:\dev\proj\bin\x.bas" ) ), "build folders are NOT skipped -- the extension filter is enough" )

'' ----------------------------------------------------------------------------
TestGroup( "scanning the fixture workspace" )

scope
    dim as WorkspaceScan scan
    ScanFolder( g_Fixture, scan )

    AssertEqInt( scan.Files.Count( ), 2, "the fixture has two source files" )
    AssertFalse( scan.Truncated, "and does not hit the file cap" )

    dim as boolean sawShared = false, sawWidgets = false
    for i as long = 0 to scan.Files.Count( ) - 1
        dim as string leaf = lcase( scan.Files[i] )
        if( instr( leaf, "shared.bi" ) > 0 ) then sawShared = true
        if( instr( leaf, "widgets.bas" ) > 0 ) then sawWidgets = true
    next
    AssertTrue( sawShared andalso sawWidgets, "both of them by name" )

    dim as string body
    AssertTrue ( ReadSourceFile( g_Fixture & NativePath( "\shared.bi" ), body ), "a source file reads" )
    AssertContains( body, "type Widget", "and the bytes are the file's" )
    AssertFalse( ReadSourceFile( g_Fixture & NativePath( "\nothing-here.bas" ), body ), "a missing file reports false" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "indexing" )

scope
    dim as SymbolIndex idx
    AssertTrue ( idx.IndexPath( g_Fixture & NativePath( "\shared.bi" ) ), "a file indexes" )
    AssertTrue ( idx.IndexPath( g_Fixture & NativePath( "\widgets.bas" ) ), "and another" )
    AssertEqInt( idx.FileCount( ), 2, "two files are in the index" )
    AssertTrue ( idx.SymbolCount( ) >= 6, "carrying their symbols" )

    '' Re-indexing the same file REPLACES it. Two entries for one file would
    '' show every symbol in it twice in a picker.
    idx.IndexPath( g_Fixture & NativePath( "\shared.bi" ) )
    AssertEqInt( idx.FileCount( ), 2, "re-indexing a file does not add a second entry" )

    dim as string sharedUri = PathToUri( g_Fixture & NativePath( "\shared.bi" ) )
    AssertTrue ( idx.IndexOfUri( sharedUri ) >= 0, "a file is found by its URI" )
    AssertTrue ( idx.IndexOfUri( ucase( sharedUri ) ) >= 0, "case-insensitively, as Windows paths are" )
    AssertEqInt( idx.IndexOfUri( "file:///nothing.bas" ), -1, "and an unknown URI is not found" )

    '' -- the range that goes on the wire ----------------------------------
    dim as IndexHit hit
    AssertTrue( idx.FindDefinition( "widget", hit ), "a type is found by name" )
    if( idx.FindDefinition( "widget", hit ) ) then
        dim as SymbolInfo sym = idx.SymbolAt( hit.FileIndex, hit.SymIndex )
        AssertEqStr( sym.Name_, "Widget", "with its name as written" )
        AssertEqInt( sym.Kind_, SYM_STRUCT, "and its kind" )
        AssertContains( lcase( idx.FileUri( hit.FileIndex ) ), "shared.bi", "in the file that declares it" )

        '' shared.bi line 1 is `type Widget`, and the name starts at column 5.
        dim as IndexedRange r = idx.RangeAt( hit.FileIndex, hit.SymIndex )
        AssertEqInt( r.StartLine, 1, "the range is on the declaring line" )
        AssertEqInt( r.StartChar, 5, "at the character the name starts" )
        AssertEqInt( r.EndChar, 11, "and ends after it" )
    end if

    '' A DECLARE loses to a body. `MakeWidget` is declared in shared.bi and
    '' defined in widgets.bas, and the definition is what a user wants.
    dim as IndexHit made
    AssertTrue( idx.FindDefinition( "makewidget", made ), "a procedure is found by name" )
    if( idx.FindDefinition( "makewidget", made ) ) then
        AssertFalse( idx.SymbolAt( made.FileIndex, made.SymIndex ).IsDeclaration, _
                     "and the body wins over the prototype" )
        AssertContains( lcase( idx.FileUri( made.FileIndex ) ), "widgets.bas", _
                        "which is in the other file" )
    end if

    AssertFalse( idx.FindDefinition( "nosuchname", hit ), "an unknown name is not found" )

    idx.Remove( sharedUri )
    AssertEqInt( idx.FileCount( ), 1, "a file can be removed" )
    AssertFalse( idx.FindDefinition( "widget", hit ), "and its symbols go with it" )
end scope

scope
    '' The open buffer beats the file on disk, which is what makes a symbol
    '' findable from another file before it is saved.
    dim as SymbolIndex idx
    idx.IndexPath( g_Fixture & NativePath( "\shared.bi" ) )

    dim as string uri = PathToUri( g_Fixture & NativePath( "\shared.bi" ) )
    idx.IndexText( uri, g_Fixture & NativePath( "\shared.bi" ), _
                   "type Widget" & LF & "end type" & LF & "sub JustTyped( )" & LF & "end sub", true )

    AssertEqInt( idx.FileCount( ), 1, "indexing from a buffer replaces the disk entry" )
    AssertTrue ( idx.IsFromBuffer( 0 ), "and is marked as coming from a buffer" )

    dim as IndexHit hit
    AssertTrue( idx.FindDefinition( "justtyped", hit ), "a symbol that exists only in the buffer is found" )
end scope

scope
    '' ONE FILE, TWO SPELLINGS. The workspace scan builds one URI and the
    '' client sends another -- through `build/..`, or with a different drive
    '' case -- and both name the same file. Indexed twice, every symbol in it
    '' is found twice and every reference reported twice, which is what the
    '' piped session caught before this was keyed on the resolved path.
    dim as SymbolIndex idx
    idx.IndexPath( g_Fixture & NativePath( "\shared.bi" ) )

    dim as string roundabout = g_Fixture & NativePath( "\..\workspace\shared.bi" )
    idx.IndexPath( roundabout )
    AssertEqInt( idx.FileCount( ), 1, "a path through `..` is the SAME file" )

    dim as string body
    ReadSourceFile( g_Fixture & NativePath( "\shared.bi" ), body )
    idx.IndexText( PathToUri( roundabout ), roundabout, body, true )
    AssertEqInt( idx.FileCount( ), 1, "and so is the client's spelling of it" )

    AssertTrue( idx.IndexOfUri( PathToUri( g_Fixture & NativePath( "\shared.bi" ) ) ) >= 0, _
                "either spelling finds the one entry" )
    AssertTrue( idx.IndexOfUri( PathToUri( roundabout ) ) >= 0, _
                "including the roundabout one" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "workspace/symbol queries" )

scope
    dim as SymbolIndex idx
    idx.IndexPath( g_Fixture & NativePath( "\shared.bi" ) )
    idx.IndexPath( g_Fixture & NativePath( "\widgets.bas" ) )

    dim as IndexHitArray hits

    idx.Query( "widget", 200, hits )
    AssertTrue( hits.Count( ) >= 4, "a query matches exactly, by prefix and by substring" )
    AssertEqStr( idx.SymbolAt( hits[0].FileIndex, hits[0].SymIndex ).Name_, "Widget", _
                 "and the EXACT match is first" )

    '' Scoring order: exact, then prefix, then substring.
    idx.Query( "widget_l", 200, hits )
    AssertTrue( hits.Count( ) >= 1, "a subsequence still matches" )
    AssertEqStr( idx.SymbolAt( hits[0].FileIndex, hits[0].SymIndex ).Name_, "WIDGET_LIMIT", _
                 "and finds the constant" )

    idx.Query( "mkwdgt", 200, hits )
    AssertTrue( hits.Count( ) >= 1, "letters in order find MakeWidget, as a picker expects" )

    idx.Query( "", 200, hits )
    AssertTrue( hits.Count( ) >= 6, "an empty query returns everything" )

    idx.Query( "zzzznothing", 200, hits )
    AssertEqInt( hits.Count( ), 0, "and a query that matches nothing returns nothing" )

    '' The cap is honoured, because a client shows a list and not a database.
    idx.Query( "", 3, hits )
    AssertEqInt( hits.Count( ), 3, "the limit is respected" )

    '' Locals are never offered: they are not addressable from another file.
    idx.Query( "w", 200, hits )
    dim as boolean sawLocal = false
    for i as long = 0 to hits.Count( ) - 1
        if( idx.SymbolAt( hits[i].FileIndex, hits[i].SymIndex ).IsLocal ) then sawLocal = true
    next
    AssertFalse( sawLocal, "a local never appears in a workspace query" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "reference scanning" )

scope
    dim as string src = "dim as long counter" & LF & _
                        "counter = counter + 1" & LF & _
                        "dim as long counter_total" & LF & _
                        "print " & chr(34) & "counter" & chr(34) & LF & _
                        "' counter in a comment"

    dim offsets as FB.Array( of long )
    FindIdentifierOffsets( src, "counter", offsets )

    '' Three real uses. NOT `counter_total`, NOT the word inside the string,
    '' and NOT the one in the comment -- which is why this is a lexer pass and
    '' not a text search.
    AssertEqInt( offsets.Count( ), 3, "only identifier occurrences count" )
    AssertEqInt( offsets[0], instr( src, "counter" ) - 1, "the first is the declaration" )

    FindIdentifierOffsets( src, "nothinghere", offsets )
    AssertEqInt( offsets.Count( ), 0, "a name that does not occur yields nothing" )

    FindIdentifierOffsets( src, "", offsets )
    AssertEqInt( offsets.Count( ), 0, "an empty name yields nothing" )

    '' Case-insensitively, as the language is.
    FindIdentifierOffsets( "dim as long Total" & LF & "TOTAL = 1" & LF & "total += 2", "total", offsets )
    AssertEqInt( offsets.Count( ), 3, "matching ignores case" )
end scope

scope
    '' Across the fixture: `Widget` appears twice in each file.
    dim as string sharedText, widgetsText
    ReadSourceFile( g_Fixture & NativePath( "\shared.bi" ), sharedText )
    ReadSourceFile( g_Fixture & NativePath( "\widgets.bas" ), widgetsText )

    dim offsets as FB.Array( of long )
    FindIdentifierOffsets( sharedText, "widget", offsets )
    AssertEqInt( offsets.Count( ), 2, "shared.bi mentions Widget twice" )

    FindIdentifierOffsets( widgetsText, "widget", offsets )
    AssertEqInt( offsets.Count( ), 2, "and so does widgets.bas" )

    '' `MakeWidget` contains "widget" but is a different identifier.
    FindIdentifierOffsets( widgetsText, "makewidget", offsets )
    AssertEqInt( offsets.Count( ), 1, "a longer name containing it is its own identifier" )
end scope


scope
    '' A FILE as the workspace root. An editor that opens a single file -- `zed
    '' widgets.bas` -- sends that file as the workspace folder, and walking a
    '' file finds nothing at all.
    dim as WorkspaceScan one_
    ScanFolder( g_Fixture & NativePath( "\widgets.bas" ), one_ )
    AssertEqInt( one_.Files.Count( ), 1, "a file root scans to itself" )

    dim as WorkspaceScan none_
    ScanFolder( g_Fixture & NativePath( "\notes.txt" ), none_ )
    AssertEqInt( none_.Files.Count( ), 0, "and a file that is not tiko source scans to nothing" )

    dim as WorkspaceScan gone_
    ScanFolder( g_Fixture & NativePath( "\nothing-here.bas" ), gone_ )
    AssertEqInt( gone_.Files.Count( ), 0, "a path that does not exist is not a file either" )
end scope

'' ############################################################################
''  The include graph
''
''  Built from synthetic files: IndexText takes the TEXT, and resolution is
''  lexical, so a graph can be described here without writing anything to disk.
''  The paths are real-looking because that is what resolution compares -- and
''  the URI is derived from the path rather than invented, because the index
''  keys on the RESOLVED PATH and a URI that does not agree with its path is a
''  file the index cannot find again.
'' ############################################################################
TestGroup( "the include graph" )

'' Indexes one made-up file under the fixture directory.
private sub Fake( byref idx as SymbolIndex, byref name_ as string, byref text_ as string )
    dim as string path_ = g_Fixture & NativePath( "\" ) & name_
    idx.IndexText( PathToUri( path_ ), path_, text_ )
end sub

private function FakeIndex( byref idx as SymbolIndex, byref name_ as string ) as long
    return idx.IndexOfUri( PathToUri( g_Fixture & NativePath( "\" ) & name_ ) )
end function

scope
    '' a.bas -> b.bi -> c.bi, a chain three deep.
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( g_Fixture )
    idx.SetSearchPaths( roots )

    Fake( idx, "a.bas", "#include once ""b.bi""" & LF & "dim shared as long AAA" & LF )
    Fake( idx, "b.bi",  "#include once ""c.bi""" & LF & "dim shared as long BBB" & LF )
    Fake( idx, "c.bi",  "dim shared as long CCC" & LF )
    idx.ResolveIncludes( )

    dim as long a = FakeIndex( idx, "a.bas" )
    dim as long b = FakeIndex( idx, "b.bi" )
    dim as long c = FakeIndex( idx, "c.bi" )

    AssertTrue( a >= 0 andalso b >= 0 andalso c >= 0, "the three files are indexed" )
    AssertEqInt( idx.IncludeCount( a ), 1, "one include is recorded" )
    AssertEqStr( idx.IncludeAt( a, 0 ).Target, "b.bi", "with the path as written" )
    AssertEqInt( idx.IncludeAt( a, 0 ).ToFile, b, "pointing at the file it names" )
    AssertEqInt( idx.IncludeAt( a, 0 ).Line, 0, "on the line it is written on" )
    AssertFalse( idx.HasUnresolvedIncludes( a ), "and nothing is left dangling" )

    dim visible as FB.Array( of long )
    idx.VisibleFrom( a, visible )
    AssertEqInt( visible.Count( ), 3, "the visible set is TRANSITIVE: a sees b sees c" )

    idx.VisibleFrom( c, visible )
    AssertEqInt( visible.Count( ), 1, "and it is DIRECTED: c sees only itself" )

    AssertTrue ( idx.CanSee( a, c ), "a can see c" )
    AssertFalse( idx.CanSee( c, a ), "c cannot see a" )

    dim users as FB.Array( of long )
    idx.IncludedBy( c, users )
    AssertEqInt( users.Count( ), 3, "everyone that reaches c, however indirectly" )

    idx.IncludedBy( a, users )
    AssertEqInt( users.Count( ), 1, "and nobody includes the file at the top" )
end scope

scope
    '' A CYCLE. `#include once` exists because this is legal and common, and a
    '' walk that did not remember where it had been would not return.
    dim as SymbolIndex idx
    Fake( idx, "x.bi", "#include once ""y.bi""" & LF )
    Fake( idx, "y.bi", "#include once ""x.bi""" & LF )
    idx.ResolveIncludes( )

    dim visible as FB.Array( of long )
    idx.VisibleFrom( FakeIndex( idx, "x.bi" ), visible )
    AssertEqInt( visible.Count( ), 2, "a cycle terminates, and each file appears once" )
end scope

scope
    '' AN EDGE TO NOWHERE. A compiler header, or anything outside the folders
    '' the client named. It is not an error and not a diagnostic -- it is the
    '' reason this file's visible set is a lower bound rather than an answer.
    dim as SymbolIndex idx
    Fake( idx, "z.bas", "#include once ""crt.bi""" & LF & "#include once ""fb/array.bi""" & LF )
    idx.ResolveIncludes( )

    dim as long z = FakeIndex( idx, "z.bas" )
    AssertEqInt( idx.IncludeCount( z ), 2, "both includes are recorded" )
    AssertEqInt( idx.IncludeAt( z, 0 ).ToFile, -1, "and neither resolves" )
    AssertTrue ( idx.HasUnresolvedIncludes( z ), "which the file is marked with" )

    dim visible as FB.Array( of long )
    idx.VisibleFrom( z, visible )
    AssertEqInt( visible.Count( ), 1, "so it sees only itself" )
end scope

scope
    '' A path with the OTHER separator, and in the wrong case. tiko
    '' accepts both on Windows and the filesystem does not care about case, so
    '' neither may cost a resolution.
    dim as SymbolIndex idx
    Fake( idx, "m.bas",   "#include once ""sub/D.BI""" & LF )
    Fake( idx, NativePath( "sub\d.bi" ), "dim shared as long DDD" & LF )
    idx.ResolveIncludes( )

    AssertEqInt( idx.IncludeAt( FakeIndex( idx, "m.bas" ), 0 ).ToFile, _
                 FakeIndex( idx, NativePath( "sub\d.bi" ) ), _
                 "a forward slash and the wrong case still find the file" )
end scope

scope
    '' NOT RELATIVE TO THE INCLUDER. The workspace folders stand in for fbc's
    '' -i paths, which this server is never told.
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( g_Fixture )
    idx.SetSearchPaths( roots )

    Fake( idx, NativePath( "deep\down\far.bas" ), "#include once ""shared.bi""" & LF )
    idx.ResolveIncludes( )

    dim as long far_ = FakeIndex( idx, NativePath( "deep\down\far.bas" ) )
    AssertTrue( idx.IncludeAt( far_, 0 ).ToFile < 0, _
                "with no search path hit and no neighbour, it stays unresolved" )

    '' The real shared.bi, in the fixture root, is what the search path finds.
    idx.IndexPath( g_Fixture & NativePath( "\shared.bi" ) )
    idx.ResolveIncludes( )

    far_ = FakeIndex( idx, NativePath( "deep\down\far.bas" ) )
    AssertTrue( idx.IncludeAt( far_, 0 ).ToFile >= 0, _
                "a search path resolves what the includer's directory cannot" )
end scope

scope
    '' WHICH DECLARATION DID YOU MEAN. Two files declare `Thing`; only one of
    '' them is visible from where the question is asked.
    dim as SymbolIndex idx
    Fake( idx, "user.bas",  "#include once ""mine.bi""" & LF & "dim as long n = 1" & LF )
    Fake( idx, "mine.bi",   "sub Thing( )" & LF & "end sub" & LF )
    Fake( idx, "theirs.bi", "sub Thing( )" & LF & "end sub" & LF )
    idx.ResolveIncludes( )

    dim as IndexHit hit
    AssertTrue( idx.FindDefinitionFrom( FakeIndex( idx, "user.bas" ), "thing", hit ), _
                "the name resolves" )
    AssertEqInt( hit.FileIndex, FakeIndex( idx, "mine.bi" ), _
                 "to the declaration this file can SEE, not to the other one" )

    '' Asked from nowhere -- a file the index does not hold -- it still answers,
    '' because a definition the user can be shown beats none.
    AssertTrue( idx.FindDefinitionFrom( -1, "thing", hit ), "and from nowhere it still answers" )
end scope

scope
    '' And the real fixture, which is what the piped session reads.
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( g_Fixture )
    idx.SetSearchPaths( roots )

    dim as WorkspaceScan scan
    ScanFolder( g_Fixture, scan )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    idx.ResolveIncludes( )

    dim as long widgets = -1, shared_ = -1
    for i as long = 0 to idx.FileCount( ) - 1
        if( instr( lcase( idx.FilePath( i ) ), "widgets.bas" ) > 0 ) then widgets = i
        if( instr( lcase( idx.FilePath( i ) ), "shared.bi" ) > 0 ) then shared_ = i
    next

    AssertTrue( widgets >= 0 andalso shared_ >= 0, "both fixture files are indexed" )
    AssertEqInt( idx.IncludeCount( widgets ), 1, "widgets.bas includes one file" )
    AssertEqInt( idx.IncludeAt( widgets, 0 ).ToFile, shared_, "and it is shared.bi" )
    AssertEqInt( idx.IncludeAt( widgets, 0 ).Line, 1, "on line 1, where it is written" )
    AssertTrue ( idx.CanSee( widgets, shared_ ), "so widgets.bas can see it" )
    AssertFalse( idx.CanSee( shared_, widgets ), "and shared.bi cannot see back" )
end scope

scope
    '' THE .tko / .ti SPELLINGS, through the REAL scan rather than Fake( ): it
    '' is the scan's extension filter that decides what gets indexed at all.
    '' gadgets.tko includes parts.ti and the legacy legacy.bi; assembly.tiko, in
    '' tiko's current extension, includes parts.ti too; notes.txt is not source
    '' and must stay out.
    dim as string tkoFixture = g_Root & NativePath( "\tests\fixtures\tko" )
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( tkoFixture )
    idx.SetSearchPaths( roots )

    dim as WorkspaceScan scan
    ScanFolder( tkoFixture, scan )
    AssertEqInt( scan.Files.Count( ), 4, "the scan finds the .tiko, the .tko, the .ti and the .bi, and not the .txt" )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    idx.ResolveIncludes( )

    dim as long gadgets = -1, parts = -1, legacy = -1, assembly = -1
    for i as long = 0 to idx.FileCount( ) - 1
        dim as string p = lcase( idx.FilePath( i ) )
        if( instr( p, "gadgets.tko" ) > 0 ) then gadgets = i
        if( instr( p, "parts.ti" ) > 0 ) then parts = i
        if( instr( p, "legacy.bi" ) > 0 ) then legacy = i
        if( instr( p, "assembly.tiko" ) > 0 ) then assembly = i
    next

    AssertTrue( gadgets >= 0 andalso parts >= 0 andalso legacy >= 0, "all three files are indexed" )
    AssertEqInt( idx.IncludeCount( gadgets ), 2, "gadgets.tko includes two files" )
    AssertEqInt( idx.IncludeAt( gadgets, 0 ).ToFile, parts, "the first is parts.ti" )
    AssertEqInt( idx.IncludeAt( gadgets, 1 ).ToFile, legacy, "the second is the legacy legacy.bi" )
    AssertFalse( idx.HasUnresolvedIncludes( gadgets ), "and nothing is left dangling" )
    AssertTrue ( idx.CanSee( gadgets, parts ), "so gadgets.tko can see parts.ti" )
    AssertFalse( idx.CanSee( parts, gadgets ), "and parts.ti cannot see back" )

    dim as IndexHit hit
    AssertTrue( idx.FindDefinitionFrom( gadgets, "gadget", hit ), "`Gadget` resolves from gadgets.tko" )
    AssertEqInt( hit.FileIndex, parts, "to its declaration in parts.ti" )
    AssertTrue( idx.FindDefinitionFrom( gadgets, "legacy_parts", hit ), "and `LEGACY_PARTS` resolves" )
    AssertEqInt( hit.FileIndex, legacy, "to legacy.bi" )

    AssertTrue( assembly >= 0, "the .tiko file is indexed" )
    AssertEqInt( idx.IncludeAt( assembly, 0 ).ToFile, parts, "its include resolves to parts.ti" )
    AssertTrue( idx.FindDefinitionFrom( assembly, "gadget", hit ), "`Gadget` resolves from assembly.tiko" )
    AssertEqInt( hit.FileIndex, parts, "to parts.ti" )
end scope

'' ############################################################################
''  Modules: #import (tiko-lang ADR 0017)
''
''  tests/fixtures/modules holds two modules (acme/net/http, two files, and
''  acme/text/esc), a root that imports them, and a package with a tiko.toml
''  and a path dependency. tests/fixtures/modpkg stands in for the toolchain's
''  pkg/, outside every workspace folder.
'' ############################################################################
TestGroup( "modules" )

scope
    dim tokens as TokenArray
    dim diags  as DiagnosticArray
    dim syms   as SymbolTable
    dim as string src = "#import ""acme/net/http""" & LF & _
                        "#import ""x/y"" as zz public" & LF & _
                        "public function A( ) as long" & LF & "end function" & LF & _
                        "function B( ) as long" & LF & "end function" & LF
    AnalyzeFull( src, tokens, diags, syms )

    dim refs as ImportRefArray
    FindImports( src, tokens, refs )
    AssertEqInt( refs.Count( ), 2, "two #import lines are found" )
    AssertEqStr( refs[0].Path_, "acme/net/http", "the first names its path" )
    AssertEqStr( refs[0].Alias_, "http", "and binds its last segment" )
    AssertEqStr( refs[1].Alias_, "zz", "the second binds what 'as' says" )
    AssertTrue ( refs[1].Public_, "and is a re-export" )
    AssertEqInt( diags.Count( ), 0, "#import is no diagnostic" )

    dim as long a = -1, b = -1
    for i as long = 0 to syms.Count( ) - 1
        if( syms.Items[i].LowerName = "a" ) then a = i
        if( syms.Items[i].LowerName = "b" ) then b = i
    next
    AssertTrue ( a >= 0 andalso b >= 0, "both functions are symbols" )
    AssertTrue ( syms.Items[a].IsPublic, "a leading 'public' marks A" )
    AssertFalse( syms.Items[b].IsPublic, "and B, without it, is not public" )
end scope

'' The toolchain's pkg/: std/strings lives there and in no workspace folder.
dim shared as string g_pkgEnv
g_pkgEnv = "TKO_PKG=" & g_Root & NativePath( "\tests\fixtures\modpkg" )
setenviron g_pkgEnv

scope
    dim as string fx = g_Root & NativePath( "\tests\fixtures\modules" )
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( fx )
    idx.SetSearchPaths( roots )

    dim as WorkspaceScan scan
    ScanFolder( fx, scan )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    dim as long before = idx.FileCount( )
    idx.ResolveIncludes( )

    dim as long app = -1, proj = -1
    for i as long = 0 to idx.FileCount( ) - 1
        dim as string p = lcase( idx.FilePath( i ) )
        if( instr( p, NativePath( "app\main.bas" ) ) > 0 ) then app = i
        if( instr( p, NativePath( "pkgproj\main.bas" ) ) > 0 ) then proj = i
    next
    AssertTrue( app >= 0 andalso proj >= 0, "both roots are indexed" )
    AssertEqInt( idx.ImportCount( app ), 3, "app/main.bas imports three modules" )

    dim files_ as FB.Array( of long )
    AssertTrue ( idx.ModuleFilesOf( app, "http", files_ ), "'http' is one of its aliases" )
    AssertEqInt( files_.Count( ), 2, "and names a module of two files" )
    AssertTrue ( idx.ModuleFilesOf( app, "e", files_ ), "'e' is esc's alias, by 'as'" )
    AssertEqInt( files_.Count( ), 1, "one file" )
    AssertFalse( idx.ModuleFilesOf( app, "esc", files_ ), "and 'esc' is not an alias there" )

    dim hits as IndexHitArray
    idx.ModuleMembers( app, "http", hits )
    dim as string names_ = ""
    for i as long = 0 to hits.Count( ) - 1
        names_ &= " " & idx.SymbolAt( hits[i].FileIndex, hits[i].SymIndex ).LowerName
    next
    AssertTrue ( instr( names_, " fetch" ) > 0, "http. offers Fetch" )
    AssertTrue ( instr( names_, " response" ) > 0, "and the public type Response" )
    AssertTrue ( instr( names_, " port" ) > 0, "and PORT, from the module's other file" )
    AssertFalse( instr( names_, " send_" ) > 0, "but not Send_, which is not public" )

    '' std: no workspace folder holds it; the toolchain's pkg/ does, and its files are
    '' indexed when the import is resolved.
    AssertTrue ( idx.ModuleFilesOf( app, "strings", files_ ), "std/strings resolves" )
    AssertEqInt( files_.Count( ), 1, "to the toolchain's one file" )
    AssertTrue ( idx.FileCount( ) > before, "which was indexed on demand" )
    idx.ModuleMembers( app, "strings", hits )
    AssertEqInt( hits.Count( ), 1, "and offers Repeat" )

    '' A package: its own module by its manifest's name, and a path dependency.
    AssertTrue ( idx.ModuleFilesOf( proj, "util", files_ ), "proj/util: the current package" )
    AssertEqInt( files_.Count( ), 1, "one file" )
    AssertTrue ( idx.ModuleFilesOf( proj, "core", files_ ), "libz/core: a [dependencies] path" )
    AssertEqInt( files_.Count( ), 1, "one file" )
    AssertTrue ( instr( lcase( idx.FilePath( files_[0] ) ), NativePath( "pkglib\core" ) ) > 0, "in ../pkglib" )
end scope


'' VENDOR PACKAGES (tiko-vendor RFC-0002): `#import "vendor/clib" link dynamic` -- the link
'' clause is read and is no diagnostic; vendor/ resolves to the toolchain's pkg/ alone, not
'' to the workspace's own vendor/ directory; and the header the module carries with
'' `public #include` is visible to the importer bare, while the one it includes for itself
'' is not.
scope
    dim tokens as TokenArray
    dim diags  as DiagnosticArray
    dim syms   as SymbolTable
    dim as string src = "#import ""vendor/clib"" link dynamic" & LF & _
                        "#import ""vendor/zz"" as q public link static" & LF
    AnalyzeFull( src, tokens, diags, syms )
    dim refs as ImportRefArray
    FindImports( src, tokens, refs )
    AssertEqInt( refs.Count( ), 2, "two #import lines with 'link'" )
    AssertEqStr( refs[0].Link_, "dynamic", "the first links dynamic" )
    AssertEqStr( refs[0].Alias_, "clib", "and still binds its last segment" )
    AssertEqStr( refs[1].Alias_, "q", "'as' before 'link'" )
    AssertTrue ( refs[1].Public_, "'public' before 'link'" )
    AssertEqStr( refs[1].Link_, "static", "'link static', static being a keyword" )
    AssertEqInt( diags.Count( ), 0, "'link' is no diagnostic" )

    dim as string m = "#module ""clib""" & LF & _
                      "public #include once ""clib.ti""" & LF & _
                      "#include once ""clibpriv.ti""" & LF & _
                      "public #cinclude ""c.h""" & LF
    AnalyzeFull( m, tokens, diags, syms )
    dim incs as IncludeRefArray
    FindIncludes( m, tokens, incs )
    AssertEqInt( incs.Count( ), 2, "'public #include' is an include" )
    AssertTrue ( incs[0].Public_, "and a public one" )
    AssertFalse( incs[1].Public_, "the plain one is not" )
    dim cincs as IncludeRefArray
    FindCIncludes( m, tokens, cincs )
    AssertEqInt( cincs.Count( ), 1, "'public #cinclude' is a #cinclude" )
    AssertTrue ( cincs[0].Public_, "and a public one" )
    AssertEqInt( diags.Count( ), 0, "'public #include' is no diagnostic" )
end scope

setenviron g_pkgEnv
scope
    dim as string fx = g_Root & NativePath( "\tests\fixtures\modules" )
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( fx )
    idx.SetSearchPaths( roots )
    dim as WorkspaceScan scan
    ScanFolder( fx, scan )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    idx.ResolveIncludes( )

    dim as long app = -1
    for i as long = 0 to idx.FileCount( ) - 1
        if( instr( lcase( idx.FilePath( i ) ), NativePath( "vendorapp\main.tiko" ) ) > 0 ) then app = i
    next
    AssertTrue( app >= 0, "the vendor importer is indexed" )

    dim files_ as FB.Array( of long )
    AssertTrue ( idx.ModuleFilesOf( app, "clib", files_ ), "vendor/clib resolves" )
    AssertEqInt( files_.Count( ), 1, "to one file" )
    AssertTrue ( instr( lcase( idx.FilePath( files_[0] ) ), NativePath( "modpkg\vendor\clib" ) ) > 0, _
                 "in the toolchain's pkg/, not the workspace's vendor/" )

    dim as IndexHit hit
    AssertTrue ( idx.FindDefinitionFrom( app, "clib_open", hit ), "clib_open is found from the importer" )
    AssertTrue ( instr( lcase( idx.FilePath( hit.FileIndex ) ), "clib.ti" ) > 0, "in the public header" )
    dim vis as FB.Array( of long )
    idx.VisibleFrom( app, vis )
    dim as boolean seesPub = false, seesPriv = false, seesMod = false
    for each f as long in vis
        dim as string p = lcase( idx.FilePath( f ) )
        if( right( p, 7 ) = "clib.ti" ) then seesPub = true
        if( instr( p, "clibpriv.ti" ) > 0 ) then seesPriv = true
        if( right( p, 9 ) = "clib.tiko" ) then seesMod = true
    next
    AssertTrue ( seesPub, "the importer sees the public header" )
    AssertFalse( seesPriv, "but not the header the module keeps" )
    AssertFalse( seesMod, "nor the module's own file, which stays behind its alias" )
end scope

setenviron "TKO_PKG="

'' EXPORTED MACROS: a facade (tiko-lang RFC-0009) is `#define N FB.N` + `#export N`. Its
'' names are offered after `fs.` as what they name -- FB.PathJoin, in a header found through
'' the toolchain's include directory (TKO_INCLUDE here) -- and are never symbols.
dim shared as string g_incEnv
g_incEnv = "TKO_INCLUDE=" & g_Root & NativePath( "\tests\fixtures\modinc" )
setenviron g_incEnv
setenviron g_pkgEnv

scope
    dim as string fx = g_Root & NativePath( "\tests\fixtures\modules" )
    dim as SymbolIndex idx
    dim roots as PathArray
    roots.Push( fx )
    idx.SetSearchPaths( roots )
    dim as WorkspaceScan scan
    ScanFolder( fx, scan )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    idx.ResolveIncludes( )

    dim as long fac = -1, app = -1
    for i as long = 0 to idx.FileCount( ) - 1
        dim as string p = lcase( idx.FilePath( i ) )
        if( instr( p, NativePath( "facade\main.bas" ) ) > 0 ) then fac = i
        if( instr( p, NativePath( "app\main.bas" ) ) > 0 ) then app = i
    next
    AssertTrue( fac >= 0, "the facade's importer is indexed" )
    AssertEqInt( idx.ImportCount( app ), 3, "app/main.bas still imports three modules" )

    dim xs as ExportHitArray
    idx.ModuleExports( fac, "fs", xs )
    dim as string xnames = ""
    for each x as ExportHit in xs
        xnames &= " " & idx.ExportAt( x.FileIndex, x.ExportIndex ).LowerName
    next
    AssertEqInt( xs.Count( ), 3, "fs. has three exported macros" )
    AssertTrue ( instr( xnames, " pathjoin" ) > 0 andalso instr( xnames, " isdir" ) > 0 andalso _
                 instr( xnames, " twice" ) > 0, "PathJoin, IsDir and Twice" )
    AssertFalse( instr( xnames, " hidden" ) > 0, "but not Hidden, defined and never exported" )

    dim hits as IndexHitArray
    idx.ModuleMembers( fac, "fs", hits )
    AssertEqInt( hits.Count( ), 1, "its public symbols are still offered: Version" )

    '' The whole module at once, as completion asks: targets aligned with the exports.
    dim txs as ExportHitArray
    dim tts as IndexHitArray
    idx.ModuleExportTargets( fac, "fs", txs, tts )
    AssertEqInt( tts.Count( ), txs.Count( ), "one target per export" )
    dim as long resolved = 0
    for ti as long = 0 to txs.Count( ) - 1
        dim as string nm = idx.ExportAt( txs[ti].FileIndex, txs[ti].ExportIndex ).LowerName
        if( tts[ti].FileIndex >= 0 ) then
            resolved += 1
            AssertEqStr( nm, "pathjoin", "only PathJoin names a declaration" )
            AssertEqStr( idx.SymbolAt( tts[ti].FileIndex, tts[ti].SymIndex ).LowerName, "pathjoin", _
                         "and it is FB.PathJoin" )
        end if
    next
    AssertEqInt( resolved, 1, "IsDir and Twice name nothing found" )

    '' What each names.
    dim as IndexHit t
    dim as ExportHit x
    AssertEqInt( idx.ModuleMemberAt( fac, "fs", "pathjoin", t, x ), 2, "fs.PathJoin is an exported macro" )
    AssertTrue ( t.FileIndex >= 0, "that names a declaration" )
    if( t.FileIndex >= 0 ) then
        AssertTrue ( instr( lcase( idx.FilePath( t.FileIndex ) ), NativePath( "modinc\fb\fakefs.bi" ) ) > 0, _
                     "in the header, read in from the toolchain's include directory" )
        dim as SymbolInfo ts = idx.SymbolAt( t.FileIndex, t.SymIndex )
        AssertEqStr( ts.LowerName, "pathjoin", "FB.PathJoin itself" )
        AssertContains( ts.Doc_, "Joins two paths", "with the header's doc comment" )
    end if
    dim as ExportEdge e = idx.ExportAt( x.FileIndex, x.ExportIndex )
    AssertEqStr( e.Body, "FB.PathJoin", "the body as written" )
    AssertEqInt( e.Line, 4, "at its #define, zero-based line 4" )

    AssertEqInt( idx.ModuleMemberAt( fac, "fs", "isdir", t, x ), 2, "fs.IsDir is exported" )
    AssertEqInt( t.FileIndex, -1, "but the header declares no IsDir: nothing to name" )
    AssertEqInt( idx.ModuleMemberAt( fac, "fs", "twice", t, x ), 2, "fs.Twice, function-like" )
    AssertEqStr( idx.ExportAt( x.FileIndex, x.ExportIndex ).Body, "( ( x ) * 2 )", "its body without its parameters" )
    AssertEqInt( idx.ModuleMemberAt( fac, "fs", "version", t, x ), 1, "fs.Version is a public symbol" )
    AssertEqInt( idx.ModuleMemberAt( fac, "fs", "hidden", t, x ), 0, "fs.Hidden is neither" )

    '' Qualified only: an exported macro is no symbol, so nothing bare -- workspace/symbol,
    '' the outline, a bare name's definition -- ever finds the facade's #define.
    dim as long facFile = x.FileIndex
    dim as boolean asSymbol = false
    for s as long = 0 to idx.FileSymbolCount( facFile ) - 1
        if( idx.SymbolAt( facFile, s ).LowerName = "pathjoin" ) then asSymbol = true
    next
    AssertFalse( asSymbol, "the facade file declares no symbol PathJoin" )
    dim qh as IndexHitArray
    idx.Query( "pathjoin", 50, qh )
    dim as boolean inFacade = false
    for each q as IndexHit in qh
        if( q.FileIndex = facFile ) then inFacade = true
    next
    AssertFalse( inFacade, "workspace/symbol finds only the header's PathJoin" )
end scope

setenviron "TKO_INCLUDE="
setenviron "TKO_PKG="

'' ############################################################################
''  Toolchain headers
''
''  `#include once "windows.bi"` names a file in the TOOLCHAIN's include
''  directory, which no workspace folder holds. With include directories
''  configured (initializationOptions.includePaths), the full build reads the
''  headers the workspace reaches -- transitively -- and marks them external:
''  visible to completion, hover, definition and signature help; never in
''  workspace/symbol, never searched for references, never renamed.
''
''  tests/fixtures/incws is the workspace (app.bas includes fakewin.bi and its
''  own helper.bi); tests/fixtures/toolinc stands in for the toolchain's inc,
''  where fakewin.bi includes win/fakeuser.bi, which declares MessageBoxW.
'' ############################################################################
TestGroup( "toolchain headers" )

dim shared as string g_incWs
g_incWs = g_Root & NativePath( "\tests\fixtures\incws" )

'' Builds an index of the incws workspace the way the worker does -- every file,
'' then the graph -- reading headers only when `readHeaders` says so.
private sub BuildIncWs( byref idx as SymbolIndex, byval readHeaders as boolean )
    dim roots as PathArray
    roots.Push( g_incWs )
    idx.SetSearchPaths( roots )
    dim as WorkspaceScan scan
    ScanFolder( g_incWs, scan )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    idx.ResolveIncludes( readHeaders )
end sub

private function FileEndingIn( byref idx as SymbolIndex, byref tail_ as string ) as long
    for i as long = 0 to idx.FileCount( ) - 1
        dim as string p = lcase( idx.FilePath( i ) )
        if( right( p, len(tail_) ) = lcase( tail_ ) ) then return i
    next
    return -1
end function

dim shared as PathArray g_noIncDirs

'' WITHOUT include directories: the include is an edge to nowhere, as before,
'' and nothing outside the workspace is read.
scope
    SetConfiguredIncludeDirs( g_noIncDirs )
    dim as SymbolIndex idx
    BuildIncWs( idx, true )
    AssertEqInt( idx.FileCount( ), 3, "no include directory: only the workspace's three files" )
    dim as long app = FileEndingIn( idx, NativePath( "incws\app.bas" ) )
    AssertTrue ( idx.HasUnresolvedIncludes( app ), "and fakewin.bi is an edge to nowhere" )
    dim as IndexHit hit
    AssertFalse( idx.FindDefinitionFrom( app, "messageboxw", hit ), "MessageBoxW is unknown" )
end scope

scope
    dim dirs as PathArray
    dirs.Push( g_Root & NativePath( "\tests\fixtures\toolinc" ) )
    SetConfiguredIncludeDirs( dirs )

    '' The message loop's resolution stays lexical: it reads no header THE WORKSPACE
    '' includes. It does find imp.bas's #import "demo" -- tests/fixtures/pkg, beside
    '' the include directory -- and, as it always has, the header a module includes.
    dim as SymbolIndex lexical_
    BuildIncWs( lexical_, false )
    AssertEqInt( FileEndingIn( lexical_, NativePath( "toolinc\fakewin.bi" ) ), -1, _
                 "a lexical resolve reads no header the workspace includes" )
    AssertTrue ( FileEndingIn( lexical_, NativePath( "pkg\demo\demo.bas" ) ) >= 0, _
                 NativePath( "but finds the imported package as <include dir>\..\pkg" ) )

    '' The worker's full build does.
    dim as SymbolIndex idx
    BuildIncWs( idx, true )
    AssertEqInt( idx.FileCount( ), 6, "a full build: 3 workspace files, the package, fakewin.bi and what it includes" )

    dim as long app  = FileEndingIn( idx, NativePath( "incws\app.bas" ) )
    dim as long help = FileEndingIn( idx, NativePath( "incws\helper.bi" ) )
    dim as long win_ = FileEndingIn( idx, NativePath( "toolinc\fakewin.bi" ) )
    dim as long user = FileEndingIn( idx, NativePath( "toolinc\win\fakeuser.bi" ) )
    AssertTrue ( win_ >= 0 andalso user >= 0, "both toolchain headers are indexed" )
    AssertTrue ( idx.IsExternal( win_ ) andalso idx.IsExternal( user ), "and marked external" )
    AssertFalse( idx.IsExternal( app ) orelse idx.IsExternal( help ), "the workspace's own files are not" )

    AssertFalse( idx.HasUnresolvedIncludes( app ), "app.bas's includes all resolve" )
    AssertTrue ( idx.CanSee( app, user ), "app.bas sees win/fakeuser.bi, through fakewin.bi" )

    dim as IndexHit hit
    AssertTrue ( idx.FindDefinitionFrom( app, "messageboxw", hit ), "MessageBoxW is found from app.bas" )
    AssertEqInt( hit.FileIndex, user, "in the toolchain header" )
    AssertContains( idx.SymbolAt( hit.FileIndex, hit.SymIndex ).Detail_, "byval uType as ulong", _
                    "with its whole parameter list, continuation line included" )

    '' Not the workspace's: workspace/symbol does not offer it.
    dim qh as IndexHitArray
    idx.Query( "onlyinthetoolchain", 50, qh )
    AssertEqInt( qh.Count( ), 0, "workspace/symbol skips toolchain headers" )
    idx.Query( "helper", 50, qh )
    AssertEqInt( qh.Count( ), 1, "but still finds the workspace's own names" )

    '' A second full build over the same files reads nothing twice.
    idx.ResolveIncludes( true )
    AssertEqInt( idx.FileCount( ), 6, "re-resolving does not index a header twice" )
end scope

SetConfiguredIncludeDirs( g_noIncDirs )

'' ############################################################################
''  The background build
''
''  The scan runs on a worker thread so the message loop can keep reading. What
''  matters here is that the result is the SAME as the synchronous one, that
''  ownership is unambiguous, and that a cancelled build hands back nothing.
'' ############################################################################
TestGroup( "the background index build" )

scope
    '' The baseline: what a synchronous scan of the fixture produces.
    dim as WorkspaceScan scan
    ScanFolder( g_Fixture, scan )

    dim as SymbolIndex direct_
    for i as long = 0 to scan.Files.Count( ) - 1
        direct_.IndexPath( scan.Files[i] )
    next

    AssertTrue( direct_.SymbolCount( ) > 0, "the fixture has symbols to find" )

    '' The same work, on the worker.
    dim roots as PathArray
    roots.Push( g_Fixture )

    StartIndexBuild( roots )
    AssertTrue( IndexBuildPending( ), "a build is pending as soon as it is started" )

    dim as string summary
    dim as SymbolIndex ptr fresh = TakeIndexBuild( summary )

    AssertTrue( fresh <> 0, "taking it hands back an index" )
    AssertFalse( IndexBuildPending( ), "and nothing is pending afterwards" )

    if( fresh <> 0 ) then
        AssertEqInt( fresh->FileCount( ),   direct_.FileCount( ),   "the same files as a synchronous scan" )
        AssertEqInt( fresh->SymbolCount( ), direct_.SymbolCount( ), "and the same symbols" )

        '' THE REGRESSION THIS EXISTS FOR. The lexer's keyword table used to be
        '' built on first use; two threads lexing at once raced through the
        '' guard and one of them saw an empty table, so every file indexed to
        '' zero symbols -- with no crash and nothing in the log.
        AssertTrue( fresh->SymbolCount( ) > 0, "with symbols in them, not zero" )
        delete fresh
    end if

    AssertContains( summary, "indexed", "and a summary line to log" )
end scope

scope
    '' Taking when there is nothing to take is the normal case: every request
    '' after the first calls this.
    dim as string summary
    AssertEqInt( cast( integer, TakeIndexBuild( summary ) ), 0, _
                 "taking with no build pending hands back nothing" )
    AssertEqStr( summary, "", "and no summary" )
end scope

scope
    '' A cancelled build produces nothing at all -- a half-scanned index would
    '' answer "not found" for files it simply had not reached yet.
    dim roots as PathArray
    roots.Push( g_Root )        '' the whole project: big enough to still be running

    StartIndexBuild( roots )
    CancelIndexBuild( )

    AssertFalse( IndexBuildPending( ), "a cancelled build leaves nothing pending" )

    dim as string summary
    AssertEqInt( cast( integer, TakeIndexBuild( summary ) ), 0, _
                 "and hands back no index" )
end scope

scope
    '' TWO THREADS ANALYSING AT ONCE, which is what the server does from the
    '' moment a document opens during a scan. This can only ever be evidence
    '' rather than proof -- a race that has been fixed cannot be observed -- but
    '' it is the shape of the failure that was actually shipped and caught.
    dim roots as PathArray
    roots.Push( g_Root )
    StartIndexBuild( roots )

    dim as long analysed = 0
    for i as long = 1 to 200
        dim tokens as TokenArray
        dim diags  as DiagnosticArray
        dim syms   as SymbolTable
        dim as string src = "type Widget" & LF & "    Count as long" & LF & "end type" & LF & _
                            "sub Go_( )" & LF & "end sub" & LF
        AnalyzeFull( src, tokens, diags, syms )
        if( syms.Count( ) >= 3 ) then analysed += 1
    next

    AssertEqInt( analysed, 200, "the main thread analyses correctly while the worker runs" )

    dim as string summary
    dim as SymbolIndex ptr fresh = TakeIndexBuild( summary )
    if( fresh <> 0 ) then
        AssertTrue( fresh->SymbolCount( ) > 0, "and so does the worker" )
        delete fresh
    else
        TestFail( "and so does the worker", "the build produced nothing" )
    end if
end scope

ShutdownIndexBuilder( )

'' ----------------------------------------------------------------------------
TestGroup( "compiler metadata (tiko metadata)" )

scope
    dim as string metaWs  = g_Root & NativePath( "\tests\fixtures\meta\ws" )
    dim as string metaLib = g_Root & NativePath( "\tests\fixtures\meta\lib" )
    dim as string mainFile = metaWs & NativePath( "\src\main.tiko" )
    dim as string answer
    AssertTrue( ReadSourceFile( metaWs & NativePath( "\tiko-metadata.json" ), answer ), "the fixture answer is readable" )

    '' -- with nothing known: the private resolver alone ---------------------------
    ClearMetadata( )
    dim roots as PathArray
    roots.Push( metaWs )
    dim cands as PathArray
    ModuleCandidates( mainFile, "gadgets", roots, cands )
    dim as boolean sawLib = false
    for i as long = 0 to cands.Count( ) - 1
        if( lcase( cands[i] ) = lcase( NormalizePath( metaLib & NativePath( "\gadgets" ) ) ) ) then sawLib = true
    next
    AssertFalse( sawLib, "without metadata, a module reached by a target's -i is not a candidate" )
    AssertEqStr( MetadataModuleDir( mainFile, "gadgets" ), "", "and no module directory is known" )

    '' -- one answer, accepted directly ------------------------------------------
    AssertFalse( AcceptMetadata( metaWs, "{" & chr(34) & "format" & chr(34) & ":2}" ), _
                 "an answer in another format is refused" )
    AssertFalse( AcceptMetadata( metaWs, "not json" ), "and so is one that is not JSON" )
    AssertTrue ( AcceptMetadata( metaWs, answer ), "the fixture's answer is accepted" )

    dim as string want = NormalizePath( metaLib & NativePath( "\gadgets" ) )
    AssertEqStr( lcase( MetadataModuleDir( mainFile, "gadgets" ) ), lcase( want ), _
                 "the module's directory, read against the manifest's directory" )
    AssertEqStr( lcase( MetadataModuleDir( mainFile, "GADGETS" ) ), lcase( want ), _
                 "matched by chain, case-insensitively" )
    AssertEqStr( MetadataModuleDir( mainFile, "./gadgets" ), "", "a relative import is never looked up" )
    AssertEqStr( MetadataModuleDir( mainFile, "nosuch" ), "", "nor is a module no target reaches" )
    AssertEqStr( MetadataModuleDir( metaLib & NativePath( "\gadgets\gadgets.tiko" ), "gadgets" ), "", _
                 "and a file outside the manifest's directory has no package here" )

    ModuleCandidates( mainFile, "gadgets", roots, cands )
    AssertTrue( cands.Count( ) > 0, "with metadata there are candidates" )
    if( cands.Count( ) > 0 ) then
        AssertEqStr( lcase( cands[0] ), lcase( want ), "and the compiler's directory is FIRST" )
    end if
    dim as long rootAt = -1, wsAt = -1
    for i as long = 0 to cands.Count( ) - 1
        if( lcase( cands[i] ) = lcase( NormalizePath( metaWs & NativePath( "\gadgets" ) ) ) ) then wsAt = i
        if( lcase( cands[i] ) = lcase( want ) andalso i > 0 ) then rootAt = i
    next
    AssertTrue( rootAt > 0, "the -i root the compiler searched is a candidate too" )
    AssertTrue( wsAt > rootAt, "ahead of the workspace folder that stands in for it" )

    dim ir as PathArray
    MetadataSearchRoots( mainFile, ir )
    AssertEqInt( ir.Count( ), 1, "one -i root" )
    if( ir.Count( ) = 1 ) then AssertEqStr( lcase( ir[0] ), lcase( NormalizePath( metaLib ) ), "../lib, made absolute" )

    AssertEqStr( lcase( MetadataPkgDir( ) ), lcase( NormalizePath( g_Root & NativePath( "\tests\fixtures\meta\nopkg" ) ) ), _
                 "the pkg/ the compiler named" )
    AssertTrue( lcase( ToolchainPkgDir( ) ) <> lcase( MetadataPkgDir( ) ), _
                "but not used as the toolchain's when it is not a directory" )

    dim incs as PathArray = MetadataIncludeDirs( )
    AssertEqInt( incs.Count( ), 2, "both include directories of the one unit" )
    dim tinc as PathArray = ToolchainIncDirs( )
    dim as boolean sawToolinc = false
    for i as long = 0 to tinc.Count( ) - 1
        if( lcase( tinc[i] ) = lcase( NormalizePath( g_Root & NativePath( "\tests\fixtures\toolinc" ) ) ) ) then sawToolinc = true
    next
    AssertTrue( sawToolinc, "and they are the toolchain include directories when none is configured" )

    dim as string md, js
    AssertTrue( MetadataFor( mainFile, md, js ), "a file in the package has its manifest's answer" )
    AssertEqStr( lcase( md ), lcase( NormalizePath( metaWs ) ), "that manifest's directory" )
    AssertContains( js, chr(34) & "main" & chr(34) & ":" & chr(34) & "src/main.tiko" & chr(34), _
                    "and the answer as the compiler printed it" )
    AssertTrue ( MetadataFor( "", md, js ), "with no file, the first package known" )
    AssertFalse( MetadataFor( metaLib & NativePath( "\gadgets\gadgets.tiko" ), md, js ), "a file in no known package has none" )

    ClearMetadata( )
    AssertEqStr( MetadataModuleDir( mainFile, "gadgets" ), "", "ClearMetadata forgets it all" )
    AssertEqInt( MetadataIncludeDirs( ).Count( ), 0, "include directories too" )

    '' -- LoadMetadata: a real child process, in the manifest's directory ----------
    SetCompilerPath( "" )
    LoadMetadata( roots )
    AssertEqStr( MetadataModuleDir( mainFile, "gadgets" ), "", "with no compiler configured, LoadMetadata does nothing" )

#ifdef __FB_WIN32__
    dim as string fakeExe = g_Root & NativePath( "\bin\fake_tiko.exe" )
#else
    dim as string fakeExe = g_Root & "/bin/fake_tiko"
#endif
    SetCompilerPath( fakeExe )
    dim nested as PathArray
    nested.Push( metaWs & NativePath( "\src" ) )
    nested.Push( metaWs )
    LoadMetadata( nested )
    AssertEqStr( lcase( MetadataModuleDir( mainFile, "gadgets" ) ), lcase( want ), _
                 "LoadMetadata runs the compiler for the manifest at or ABOVE a folder" )
    AssertTrue( MetadataFor( "", md, js ), "and keeps its answer" )
    AssertEqInt( MetadataManifestCount( ), 1, "once: two folders under one manifest ask once" )

    SetCompilerPath( g_Root & NativePath( "\bin\no_such_tiko.exe" ) )
    LoadMetadata( roots )
    AssertEqStr( MetadataModuleDir( mainFile, "gadgets" ), "", "a compiler that cannot run leaves nothing known" )
    ModuleCandidates( mainFile, "gadgets", roots, cands )
    AssertTrue( cands.Count( ) > 0, "and the private resolver still answers" )
    SetCompilerPath( "" )
    ClearMetadata( )
end scope

'' ############################################################################
''  #cinclude: the binding tiko makes of a C header, indexed as an #include
''
''  tests/fixtures/cinc/ws/main.bas #cincludes fake.h, which fake_tiko says became
''  ../cache/fake-binding.bi, and broken.h, which it says could not be imported.
'' ############################################################################
TestGroup( "#cinclude" )

'' The worker's order: every file, the graph, the #cincludes, the graph again.
private sub BuildCincWs( byref idx as SymbolIndex )
    dim as string ws = g_Root & NativePath( "\tests\fixtures\cinc\ws" )
    dim roots as PathArray
    roots.Push( ws )
    idx.SetSearchPaths( roots )
    dim as WorkspaceScan scan
    ScanFolder( ws, scan )
    for i as long = 0 to scan.Files.Count( ) - 1
        idx.IndexPath( scan.Files[i] )
    next
    idx.ResolveIncludes( true )
    LoadCIncludes( idx, true )
    idx.ResolveIncludes( true )
end sub

scope
    '' THE EDGES are read whether or not a compiler is configured.
    dim as SymbolIndex bare
    SetCompilerPath( "" )
    BuildCincWs( bare )
    dim as long m0 = FileEndingIn( bare, NativePath( "cinc\ws\main.bas" ) )
    AssertTrue ( bare.HasCIncludes( m0 ), "main.bas has #cinclude edges" )
    AssertEqInt( bare.IncludeCount( m0 ), 2, "two of them" )
    AssertTrue ( bare.IncludeAt( m0, 0 ).IsC_ andalso bare.IncludeAt( m0, 1 ).IsC_, "both marked as C" )
    AssertEqStr( bare.IncludeAt( m0, 1 ).Target, "broken.h", "'once' is read past" )
    AssertEqInt( bare.IncludeAt( m0, 0 ).ToFile, -1, "with no compiler, the header resolves to nothing" )
    AssertEqInt( FileEndingIn( bare, "fake.h" ), -1, "and the C header itself is never read" )
    AssertTrue ( bare.HasUnresolvedIncludes( m0 ), "so main.bas's visible set is a lower bound" )

#ifdef __FB_WIN32__
    SetCompilerPath( g_Root & NativePath( "\bin\fake_tiko.exe" ) )
#else
    SetCompilerPath( g_Root & "/bin/fake_tiko" )
#endif
    dim as SymbolIndex idx
    BuildCincWs( idx )
    dim as long m = FileEndingIn( idx, NativePath( "cinc\ws\main.bas" ) )
    dim as long b = FileEndingIn( idx, NativePath( "cinc\cache\fake-binding.bi" ) )
    AssertTrue ( b >= 0, "the binding the compiler named is indexed" )
    AssertTrue ( idx.IsExternal( b ), "as an external file" )
    AssertEqInt( idx.IncludeAt( m, 0 ).ToFile, b, "#cinclude ""fake.h"" points at it" )
    AssertEqInt( idx.IncludeAt( m, 1 ).ToFile, -1, "a header that could not be imported points at nothing" )
    AssertTrue ( idx.CanSee( m, b ), "main.bas sees the binding" )

    dim as IndexHit hit
    AssertTrue ( idx.FindDefinitionFrom( m, "fakeadd", hit ), "FakeAdd is found from main.bas" )
    AssertEqInt( hit.FileIndex, b, "in the binding" )
    AssertContains( idx.SymbolAt( hit.FileIndex, hit.SymIndex ).Detail_, "byval b as long", _
                    "with its parameters, for signature help" )
    AssertTrue ( idx.FindDefinitionFrom( m, "fakecolor", hit ), "and the C struct's type" )

    dim qh as IndexHitArray
    idx.Query( "fakeadd", 50, qh )
    AssertEqInt( qh.Count( ), 0, "workspace/symbol skips the binding, as a toolchain header" )

    AssertEqStr( lcase( CIncludeBinding( idx.FilePath( m ), "FAKE.H" ) ), lcase( idx.FilePath( b ) ), _
                 "the store answers by includer and header, case aside" )
    AssertFalse( AcceptCIncludes( "{""format"":2}" ), "an answer in another format is refused" )

    '' A compiler that cannot run leaves the edges unresolved and nothing broken.
    SetCompilerPath( g_Root & NativePath( "\bin\no_such_tiko.exe" ) )
    dim as SymbolIndex gone
    BuildCincWs( gone )
    AssertEqInt( gone.IncludeAt( FileEndingIn( gone, NativePath( "cinc\ws\main.bas" ) ), 0 ).ToFile, -1, _
                 "a compiler that cannot run resolves nothing" )
    SetCompilerPath( "" )
    ClearCIncludes( )
end scope

end TestSummary( "workspace" )
