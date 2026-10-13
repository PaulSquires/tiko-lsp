'' ############################################################################
''  workspace/index_builder.bas -- the workspace scan, off the message loop
'' ############################################################################

#include once "index_builder.bi"
#include once "metadata.bi"
#include once "cincludes.bi"
#include once "../utils/logging.bi"

'' ----------------------------------------------------------------------------
''  Worker state
''
''  Deliberately module-level and deliberately singular: there is one workspace
''  and there is never a reason to scan it twice at once. A second Start
''  cancels the first.
''
''  WHAT CROSSES THREADS, and what does not:
''
''    g_cancel     written by the loop, read by the worker -- the mutex exists
''                 for this and for nothing else.
''    g_roots      written before the thread starts, read only by it.
''    g_result     written by the worker, read by the loop AFTER the join.
''    g_summary    the same.
''
''  A join is a happens-before edge, so the last two need no lock: by the time
''  the loop looks at them the worker has finished writing and stopped.
'' ----------------------------------------------------------------------------
dim shared as any ptr        g_idxThread
dim shared as any ptr        g_idxMutex
dim shared as boolean        g_idxCancel
dim shared as PathArray      g_idxRoots

'' The workspace folders, kept separately from the work list: a REFRESH's work
'' list is files, and the include graph still has to be resolved against the
'' folders.
dim shared as PathArray      g_idxSearch
dim shared as SymbolIndex ptr g_idxResult
dim shared as string         g_idxSummary

'' Which of the two jobs is in flight: a whole-workspace scan, or a refresh of
'' named files. The difference matters only at the end -- one result is
'' ADOPTED, the other is MERGED.
dim shared as boolean        g_idxRefresh

'' Set by the worker as its last act, read by the loop without a lock. A
'' boolean written once and read repeatedly is the one shape where that is
'' safe: the reader either sees the old value and waits, or the new one and
'' collects. Neither is wrong, and the wrong answer costs a keystroke's worth
'' of completion items rather than correctness.
dim shared as boolean        g_idxDone

'' Before main( ), so no two callers can create it at once -- the same rule as
'' the file mutex next door in workspace.bas.
private sub InitIndexMutex constructor
    g_idxMutex = mutexcreate( )
end sub

private function CancelRequested( ) as boolean
    dim as boolean v = false
    mutexlock( g_idxMutex )
    v = g_idxCancel
    mutexunlock( g_idxMutex )
    return v
end function

private sub SetCancel( byval v as boolean )
    mutexlock( g_idxMutex )
    g_idxCancel = v
    mutexunlock( g_idxMutex )
end sub

'' ----------------------------------------------------------------------------
''  The worker
''
''  Everything it touches is its own. It reads files, it builds an index, it
''  writes a summary. It does NOT look at the open documents -- those belong to
''  the message loop, and the loop re-indexes them over the result when it
''  adopts it, which is both simpler than sharing them and more correct: a
''  buffer edited during the scan wins anyway.
'' ----------------------------------------------------------------------------
private sub IndexBuildWorker( byval param as any ptr )
    dim as double started = timer( )

    '' What the configured compiler says (metadata.bi) is asked for FIRST: the scan's
    '' import resolution reads it. Nothing happens when no compiler is configured.
    LoadMetadata( g_idxRoots )

    dim as SymbolIndex ptr idx = new SymbolIndex
    idx->SetSearchPaths( g_idxSearch )

    dim as WorkspaceScan scan

    for i as long = 0 to g_idxRoots.Count( ) - 1
        if( CancelRequested( ) ) then exit for
        LogInfo( "scanning " & g_idxRoots[i] )
        ScanFolder( g_idxRoots[i], scan )
    next

    dim as long indexed = 0
    dim as long failed  = 0
    dim as boolean cancelled = false

    for i as long = 0 to scan.Files.Count( ) - 1
        '' Checked per file rather than per batch: one file is milliseconds, so
        '' this is the finest granularity that costs nothing.
        if( CancelRequested( ) ) then
            cancelled = true
            exit for
        end if

        if( idx->IndexPath( scan.Files[i] ) ) then
            indexed += 1
        else
            failed += 1
        end if
    next

    if( cancelled ) then
        '' Nobody will ever look at a partial index, and the thread that
        '' cancelled is waiting on the join -- so it is freed here.
        delete idx
        g_idxResult  = 0
        g_idxSummary = "workspace scan cancelled after " & indexed & " file(s)"
        LogInfo( g_idxSummary )
        exit sub
    end if

    '' The include graph is pointed at real files once, here, rather than as
    '' each file is read: an include can name a file that has not been scanned
    '' yet, and resolving it early would only have to be undone. This is also
    '' the ONE place the toolchain headers the workspace includes are read --
    '' seconds of parsing for a Win32 project, so off the message loop.
    idx->ResolveIncludes( true )

    '' THE #cincludes, asked of the compiler now that every file -- toolchain headers
    '' included -- is known (cincludes.bi). Each binding is indexed, and the graph
    '' resolved again: the #cinclude edges point at them, and what they #include
    '' (crt/long.bi) is read in.
    if( len(CompilerPath( )) > 0 ) then
        LoadCIncludes( *idx, true )
        idx->ResolveIncludes( true )
    end if

    dim as long headers = 0
    for f as long = 0 to idx->FileCount( ) - 1
        if( idx->IsExternal( f ) ) then headers += 1
    next

    dim as double elapsed = timer( ) - started
    dim as string summary = "indexed " & idx->FileCount( ) & " file(s)" & _
                            iif( headers > 0, " (" & headers & " toolchain header(s))", "" ) & ", " & _
                            idx->SymbolCount( ) & " symbol(s) in " & _
                            int( elapsed * 1000 ) & " ms"

    if( failed > 0 ) then summary &= " (" & failed & " unreadable)"
    if( scan.Skipped > 0 ) then summary &= " (" & scan.Skipped & " unreadable folder(s))"
    if( scan.Truncated ) then
        summary &= " -- STOPPED at the " & WS_MAX_FILES & " file limit"
    end if


    g_idxResult  = idx
    g_idxSummary = summary
    g_idxDone    = true
end sub

'' Re-indexes the named files and nothing else. Same thread, same handover,
'' same rules -- only the work is smaller.
private sub IndexRefreshWorker( byval param as any ptr )
    dim as double started = timer( )

    dim as SymbolIndex ptr idx = new SymbolIndex
    idx->SetSearchPaths( g_idxSearch )

    dim as long indexed = 0
    dim as long failed  = 0

    for i as long = 0 to g_idxRoots.Count( ) - 1
        if( CancelRequested( ) ) then
            delete idx
            g_idxResult  = 0
            g_idxSummary = "refresh cancelled after " & indexed & " file(s)"
            LogInfo( g_idxSummary )
            exit sub
        end if

        if( idx->IndexPath( g_idxRoots[i] ) ) then
            indexed += 1
        else
            '' Gone again, or unreadable. It is NOT merged as an empty entry:
            '' a file that cannot be read keeps whatever the live index last
            '' knew, which is a better answer than none.
            failed += 1
        end if
    next

    '' A changed file's #cincludes are asked again: a header added or edited, a
    '' #cinclude typed and saved. Its bindings join the merge as external files.
    LoadCIncludes( *idx, false )

    g_idxResult  = idx
    g_idxSummary = "re-indexed " & indexed & " of " & g_idxRoots.Count( ) & " file(s) in " & _
                   int( (timer( ) - started) * 1000 ) & " ms"
    if( failed > 0 ) then g_idxSummary &= " (" & failed & " unreadable)"
    g_idxDone    = true
end sub

'' ----------------------------------------------------------------------------
''  The interface the message loop uses
'' ----------------------------------------------------------------------------
sub StartIndexBuild( byref roots as PathArray )
    CancelIndexBuild( )

    '' Written before the thread exists, so the worker cannot be reading them.
    g_idxRoots.Clear( )
    g_idxSearch.Clear( )
    for i as long = 0 to roots.Count( ) - 1
        g_idxRoots.Push( roots[i] )
        g_idxSearch.Push( roots[i] )
    next

    if( g_idxResult <> 0 ) then
        delete g_idxResult
        g_idxResult = 0
    end if
    g_idxSummary = ""

    SetCancel( false )
    g_idxRefresh = false
    g_idxDone    = false
    g_idxThread  = threadcreate( @IndexBuildWorker, 0 )

    if( g_idxThread = 0 ) then
        '' No thread available. Rather than leave the workspace unindexed, the
        '' build runs HERE -- slowly, on the message loop, exactly as phase 6
        '' did. A degraded server beats a silent one.
        LogWarn( "could not start the index thread -- scanning on the message loop" )
        IndexBuildWorker( 0 )
    end if
end sub

sub StartIndexRefresh( byref paths as PathArray, byref roots as PathArray )
    CancelIndexBuild( )

    g_idxRoots.Clear( )
    for i as long = 0 to paths.Count( ) - 1
        g_idxRoots.Push( paths[i] )
    next

    g_idxSearch.Clear( )
    for i as long = 0 to roots.Count( ) - 1
        g_idxSearch.Push( roots[i] )
    next

    if( g_idxResult <> 0 ) then
        delete g_idxResult
        g_idxResult = 0
    end if
    g_idxSummary = ""

    SetCancel( false )
    g_idxRefresh = true
    g_idxDone    = false
    g_idxThread  = threadcreate( @IndexRefreshWorker, 0 )

    if( g_idxThread = 0 ) then
        LogWarn( "could not start the index thread -- refreshing on the message loop" )
        IndexRefreshWorker( 0 )
    end if
end sub

function IndexBuildIsRefresh( ) as boolean
    return g_idxRefresh
end function

function IndexBuildPending( ) as boolean
    return ( g_idxThread <> 0 ) orelse ( g_idxResult <> 0 )
end function

function IndexBuildReady( ) as boolean
    if( IndexBuildPending( ) = false ) then return false
    return ( g_idxThread = 0 ) orelse g_idxDone
end function

function TakeIndexBuild( byref summary as string ) as SymbolIndex ptr
    if( g_idxThread <> 0 ) then
        '' The wait. Everything the worker wrote is visible after it.
        threadwait( g_idxThread )
        g_idxThread = 0
    end if

    dim as SymbolIndex ptr result_ = g_idxResult
    g_idxResult = 0

    summary      = g_idxSummary
    g_idxSummary = ""
    return result_
end function

sub CancelIndexBuild( )
    if( g_idxThread <> 0 ) then
        SetCancel( true )
        threadwait( g_idxThread )
        g_idxThread = 0
        SetCancel( false )
    end if

    if( g_idxResult <> 0 ) then
        delete g_idxResult
        g_idxResult = 0
    end if
    g_idxSummary = ""
end sub

sub ShutdownIndexBuilder( )
    CancelIndexBuild( )
    if( g_idxMutex <> 0 ) then
        mutexdestroy( g_idxMutex )
        g_idxMutex = 0
    end if
end sub
