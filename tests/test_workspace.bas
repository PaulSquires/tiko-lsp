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
#include once "../src/utils/uri.bi"

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
g_Fixture = g_Root & "\tests\fixtures\workspace"

'' ----------------------------------------------------------------------------
TestGroup( "file discovery" )

AssertTrue ( IsSourceFileName( "main.bas" ), ".bas is source" )
AssertTrue ( IsSourceFileName( "shared.bi" ), ".bi is source" )
AssertTrue ( IsSourceFileName( "AfxStr.inc" ), ".inc is source" )
AssertTrue ( IsSourceFileName( "MAIN.BAS" ), "the extension test is case-insensitive" )
AssertFalse( IsSourceFileName( "tiko-lsp.exe" ), "an executable is not source" )
AssertFalse( IsSourceFileName( "notes.txt" ), "nor a text file" )
AssertFalse( IsSourceFileName( "Makefile" ), "nor a file with no extension" )
AssertFalse( IsSourceFileName( "basic" ), "and `bas` inside a name is not an extension" )

AssertTrue ( IsIgnoredPath( "C:\dev\proj\.git\hooks\x.bas" ), ".git is skipped" )
AssertTrue ( IsIgnoredPath( "/home/u/proj/node_modules/p/x.bi" ), "so is node_modules" )
AssertTrue ( IsIgnoredPath( "C:\dev\proj\.vscode\x.bas" ), "and .vscode" )
AssertFalse( IsIgnoredPath( "C:\dev\proj\src\git\x.bas" ), "a folder merely NAMED git is kept" )
AssertFalse( IsIgnoredPath( "C:\dev\proj\bin\x.bas" ), "build folders are NOT skipped -- the extension filter is enough" )

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
    AssertTrue ( ReadSourceFile( g_Fixture & "\shared.bi", body ), "a source file reads" )
    AssertContains( body, "type Widget", "and the bytes are the file's" )
    AssertFalse( ReadSourceFile( g_Fixture & "\nothing-here.bas", body ), "a missing file reports false" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "indexing" )

scope
    dim as SymbolIndex idx
    AssertTrue ( idx.IndexPath( g_Fixture & "\shared.bi" ), "a file indexes" )
    AssertTrue ( idx.IndexPath( g_Fixture & "\widgets.bas" ), "and another" )
    AssertEqInt( idx.FileCount( ), 2, "two files are in the index" )
    AssertTrue ( idx.SymbolCount( ) >= 6, "carrying their symbols" )

    '' Re-indexing the same file REPLACES it. Two entries for one file would
    '' show every symbol in it twice in a picker.
    idx.IndexPath( g_Fixture & "\shared.bi" )
    AssertEqInt( idx.FileCount( ), 2, "re-indexing a file does not add a second entry" )

    dim as string sharedUri = PathToUri( g_Fixture & "\shared.bi" )
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
    idx.IndexPath( g_Fixture & "\shared.bi" )

    dim as string uri = PathToUri( g_Fixture & "\shared.bi" )
    idx.IndexText( uri, g_Fixture & "\shared.bi", _
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
    idx.IndexPath( g_Fixture & "\shared.bi" )

    dim as string roundabout = g_Fixture & "\..\workspace\shared.bi"
    idx.IndexPath( roundabout )
    AssertEqInt( idx.FileCount( ), 1, "a path through `..` is the SAME file" )

    dim as string body
    ReadSourceFile( g_Fixture & "\shared.bi", body )
    idx.IndexText( PathToUri( roundabout ), roundabout, body, true )
    AssertEqInt( idx.FileCount( ), 1, "and so is the client's spelling of it" )

    AssertTrue( idx.IndexOfUri( PathToUri( g_Fixture & "\shared.bi" ) ) >= 0, _
                "either spelling finds the one entry" )
    AssertTrue( idx.IndexOfUri( PathToUri( roundabout ) ) >= 0, _
                "including the roundabout one" )
end scope

'' ----------------------------------------------------------------------------
TestGroup( "workspace/symbol queries" )

scope
    dim as SymbolIndex idx
    idx.IndexPath( g_Fixture & "\shared.bi" )
    idx.IndexPath( g_Fixture & "\widgets.bas" )

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
    ReadSourceFile( g_Fixture & "\shared.bi", sharedText )
    ReadSourceFile( g_Fixture & "\widgets.bas", widgetsText )

    dim offsets as FB.Array( of long )
    FindIdentifierOffsets( sharedText, "widget", offsets )
    AssertEqInt( offsets.Count( ), 2, "shared.bi mentions Widget twice" )

    FindIdentifierOffsets( widgetsText, "widget", offsets )
    AssertEqInt( offsets.Count( ), 2, "and so does widgets.bas" )

    '' `MakeWidget` contains "widget" but is a different identifier.
    FindIdentifierOffsets( widgetsText, "makewidget", offsets )
    AssertEqInt( offsets.Count( ), 1, "a longer name containing it is its own identifier" )
end scope

end TestSummary( "workspace" )
