'' ############################################################################
''  handlers/watched_files.bas -- workspace/didChangeWatchedFiles
'' ############################################################################

#include once "watched_files.bi"
#include once "workspace_symbols.bi"
#include once "../workspace/workspace.bi"
#include once "../workspace/index_builder.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"
#include once "../workspace/metadata.bi"
#include once "fb/map.bi"

'' FileChangeType, from the specification.
const FILECHANGE_CREATED = 1
const FILECHANGE_CHANGED = 2
const FILECHANGE_DELETED = 3

'' Above this many DISTINCT source files in one notification, the batch is not
'' applied file by file -- the whole workspace is re-scanned on the worker
'' instead. See OnDidChangeWatchedFiles for why that is the better answer and
'' not merely the cheaper one to write.
''
'' The number comes from measurement: re-indexing one file into a 4,000-file
'' index costs 1-3 ms, so a hundred is a hiccup of 100-200 ms and five hundred
'' is well over a second of a frozen editor.
const WATCHED_BURST_LIMIT = 100

'' One change, after filtering: what the server would actually do about it.
type WatchedChange
    Uri   as string
    Path_ as string
    Kind_ as long
end type

type WatchedChangeArray as FB.Array( of WatchedChange )

'' ----------------------------------------------------------------------------
''  Registering
'' ----------------------------------------------------------------------------
sub RequestFileWatching( byref srv as Server )
    if( srv.SupportsFileWatching = false ) then
        '' Not an error and not worth a window message: plenty of clients do
        '' not do dynamic registration. The index will simply be as current as
        '' the last scan, and the log says so once.
        LogInfo( "client cannot register file watching -- the index will not " & _
                 "notice files changed outside the editor" )
        exit sub
    end if

    dim as JsonBuilder rb

    dim as JsonNode watcher = rb.NewObject( )
    rb.SetStr( watcher, "globPattern", LSP_WATCH_GLOB )
    rb.SetInt( watcher, "kind", LSP_WATCH_KIND )

    dim as JsonNode watchers = rb.NewArray( )
    rb.PushNode( watchers, watcher )

    dim as JsonNode manifests = rb.NewObject( )
    rb.SetStr( manifests, "globPattern", LSP_WATCH_MANIFEST_GLOB )
    rb.SetInt( manifests, "kind", LSP_WATCH_KIND )
    rb.PushNode( watchers, manifests )

    dim as JsonNode options_ = rb.NewObject( )
    rb.SetNode( options_, "watchers", watchers )

    '' The id is ours to choose and ours to remember -- it is what an
    '' unregisterCapability would name. One registration, one id, fixed.
    dim as JsonNode registration = rb.NewObject( )
    rb.SetStr ( registration, "id", "tiko-watched-files" )
    rb.SetStr ( registration, "method", LSP_DID_CHANGE_WATCHED )
    rb.SetNode( registration, "registerOptions", options_ )

    dim as JsonNode list_ = rb.NewArray( )
    rb.PushNode( list_, registration )

    dim as JsonNode params = rb.NewObject( )
    rb.SetNode( params, "registrations", list_ )

    dim as string id = srv.SendRequest( LSP_REGISTER_CAPABILITY, rb, params )
    LogInfo( "asked the client to watch " & LSP_WATCH_GLOB & " and " & LSP_WATCH_MANIFEST_GLOB & _
             " (request " & id & ")" )
end sub

'' ----------------------------------------------------------------------------
''  The notification
'' ----------------------------------------------------------------------------
private function OnDidChangeWatchedFiles( byref srv as Server, _
                                          byref req as RpcMessage, _
                                          byref rb as JsonBuilder, _
                                          byref err_ as RpcError ) as JsonNode

    '' A CHANGED tiko.toml, WITH A COMPILER CONFIGURED, is a new scan: what the compiler says
    '' (workspace/metadata.bi) is read ahead of every scan, and a manifest moves where every
    '' import of its package resolves -- not one file, all of them. Started even over a scan
    '' in flight, which may have read the manifest before it changed. Without a compiler,
    '' a manifest is not a source file and falls through to be ignored, as it always was.
    if( len( CompilerPath( ) ) > 0 ) then
        for each mc in ArrayOf( req.Params( ).Member( "changes" ) )
            dim as string mp = UriToPath( mc.Member( "uri" ).AsString( "" ) )
            dim as long n = len(mp)
            if( n < 9 ) then continue for
            if( lcase( right( mp, 9 ) ) <> "tiko.toml" ) then continue for
            dim as ubyte sep = iif( n = 9, asc( "/" ), mp[n - 10] )
            if( sep <> asc( "/" ) andalso sep <> asc( "\" ) ) then continue for
            LogInfo( "watched files: " & mp & " changed -- re-reading the compiler's metadata " & _
                     "and the workspace" )
            StartWorkspaceIndex( srv )
            srv.SendTrace( "didChangeWatchedFiles (manifest)", "workspace scan restarted" )
            return JsonNode( )
        next
    end if

    '' A SCAN IN FLIGHT ALREADY COVERS THIS. The worker reads each file as it
    '' reaches it, so whatever these notifications describe is what it will
    '' find -- and anything applied to the live index now would be thrown away
    '' when the fresh one is adopted. Dropping them is not a shortcut; it is
    '' the only version that cannot go stale.
    if( IndexBuildPending( ) andalso IndexBuildIsRefresh( ) = false ) then
        LogDebug( "watched-file changes ignored: the workspace scan will read " & _
                  "them anyway" )
        return JsonNode( )
    end if

    '' A REFRESH is a different matter: it covers only the files it was handed,
    '' so this batch cannot be dropped on its account. Take delivery of the one
    '' in flight -- sub-second, and only when bursts arrive back to back -- and
    '' then deal with this one.
    if( IndexBuildPending( ) ) then EnsureWorkspaceIndex( srv )

    dim as long indexed = 0
    dim as long removed = 0
    dim as long skipped = 0

    '' -- what is actually worth doing, once each ------------------------------
    ''
    '' A single checkout reports the same file more than once -- deleted then
    '' created, or changed twice -- and only the LAST word about it matters.
    '' Collapsing here rather than acting twice is what makes the count below
    '' mean something.
    dim work_ as WatchedChangeArray
    dim seen_ as FB.Map( of string, long )

    for each change in ArrayOf( req.Params( ).Member( "changes" ) )
        dim as string uriText = change.Member( "uri" ).AsString( "" )
        dim as long   kind    = clng( change.Member( "type" ).AsLongInt( 0 ) )
        if( len(uriText) = 0 ) then continue for

        dim as string path_ = UriToPath( uriText )
        if( len(path_) = 0 ) then
            '' Not a file: URI. Nothing on disk to read.
            skipped += 1
            continue for
        end if

        '' A client may watch more than it was asked to -- some send every
        '' change under the workspace root regardless of the glob.
        if( IsSourceFileName( path_ ) = false orelse IsIgnoredPath( path_ ) ) then
            skipped += 1
            continue for
        end if

        '' THE OPEN BUFFER STILL WINS. A file the editor has open is indexed
        '' from its buffer, and re-reading the disk copy behind it would
        '' replace what the user can see with what was last saved -- including
        '' for a `git checkout` that happens while the file is open, where the
        '' editor decides what to do about it and tells us in a didChange.
        if( srv.Documents.Find( uriText ) <> 0 ) then
            skipped += 1
            continue for
        end if

        if( kind <> FILECHANGE_CREATED andalso kind <> FILECHANGE_CHANGED andalso _
            kind <> FILECHANGE_DELETED ) then
            skipped += 1
            continue for
        end if

        '' The same key the index uses: one file has one identity however the
        '' client spelled its URI.
        dim as string key_ = lcase( NormalizePath( path_ ) )
        dim as long at_ = 0

        if( seen_.TryGet( key_, at_ ) ) then
            work_[at_].Uri   = uriText
            work_[at_].Path_ = path_
            work_[at_].Kind_ = kind
            continue for
        end if

        dim as WatchedChange w
        w.Uri   = uriText
        w.Path_ = path_
        w.Kind_ = kind
        seen_.Put( key_, work_.Count( ) )
        work_.Push( w )
    next

    '' -- a burst is a workspace change, not a list of file changes ------------
    ''
    '' Past a hundred files this stops applying them one at a time and re-scans
    '' the workspace on the worker instead. Three reasons, in order of weight:
    ''
    ''   - a thousand events applied here is a thousand milliseconds of an
    ''     editor that does not respond, which is the whole thing phase 8 was
    ''     about;
    ''   - a burst this size IS a workspace change -- a branch switch, a pull,
    ''     a generated tree -- and re-reading the workspace is the answer that
    ''     matches what happened;
    ''   - AND A WATCHER IS LEAST RELIABLE EXACTLY WHEN IT IS BUSIEST. Editors
    ''     coalesce and drop file events under load, so the list that arrives
    ''     after a big checkout is the one least worth trusting to be complete.
    ''     A scan does not depend on it being complete.
    if( work_.Count( ) > WATCHED_BURST_LIMIT ) then
        '' Deletions are free -- no file is read for one -- so they are applied
        '' here, and only the reading goes to the worker.
        dim toRead as PathArray

        for i as long = 0 to work_.Count( ) - 1
            if( work_[i].Kind_ = FILECHANGE_DELETED ) then
                srv.Index->Remove( work_[i].Uri )
                removed += 1
            else
                toRead.Push( work_[i].Path_ )
            end if
        next

        LogInfo( "watched files: " & work_.Count( ) & " changed at once -- " & _
                 removed & " removed here, " & toRead.Count( ) & " re-indexed in " & _
                 "the background" )
        RefreshWorkspaceFiles( srv, toRead )

        srv.SendTrace( "didChangeWatchedFiles (" & work_.Count( ) & " change(s))", _
                       "burst -- " & removed & " removed, " & toRead.Count( ) & _
                       " re-indexed in the background" )
        return JsonNode( )
    end if

    for i as long = 0 to work_.Count( ) - 1
        select case work_[i].Kind_
            case FILECHANGE_CREATED, FILECHANGE_CHANGED
                if( srv.Index->IndexPath( work_[i].Path_ ) ) then
                    indexed += 1
                else
                    '' Created and already gone, or unreadable. Whatever the
                    '' index holds for it is now a guess, so it goes.
                    srv.Index->Remove( work_[i].Uri )
                    removed += 1
                end if

            case FILECHANGE_DELETED
                srv.Index->Remove( work_[i].Uri )
                removed += 1
        end select
    next

    if( indexed + removed > 0 ) then
        LogInfo( "watched files: " & indexed & " re-indexed, " & removed & " removed" & _
                 iif( skipped > 0, ", " & skipped & " ignored", "" ) & _
                 " -- " & srv.Index->FileCount( ) & " file(s) indexed" )
    elseif( skipped > 0 ) then
        LogDebug( "watched files: " & skipped & " change(s) ignored" )
    end if

    '' A trace, so the piped session can see what a notification did -- the
    '' same hook didOpen and didChange use.
    srv.SendTrace( "didChangeWatchedFiles (" & (indexed + removed + skipped) & " change(s))", _
                   indexed & " re-indexed, " & removed & " removed, " & skipped & _
                   " ignored, " & srv.Index->FileCount( ) & " file(s) indexed" )
    return JsonNode( )
end function

sub RegisterWatchedFilesHandlers( )
    RegisterHandler( LSP_DID_CHANGE_WATCHED, @OnDidChangeWatchedFiles )
end sub
