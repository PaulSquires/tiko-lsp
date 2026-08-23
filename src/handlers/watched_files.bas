'' ############################################################################
''  handlers/watched_files.bas -- workspace/didChangeWatchedFiles
'' ############################################################################

#include once "watched_files.bi"
#include once "workspace_symbols.bi"
#include once "../workspace/workspace.bi"
#include once "../workspace/index_builder.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

'' FileChangeType, from the specification.
const FILECHANGE_CREATED = 1
const FILECHANGE_CHANGED = 2
const FILECHANGE_DELETED = 3

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
    LogInfo( "asked the client to watch " & LSP_WATCH_GLOB & " (request " & id & ")" )
end sub

'' ----------------------------------------------------------------------------
''  The notification
'' ----------------------------------------------------------------------------
private function OnDidChangeWatchedFiles( byref srv as Server, _
                                          byref req as RpcMessage, _
                                          byref rb as JsonBuilder, _
                                          byref err_ as RpcError ) as JsonNode

    '' A SCAN IN FLIGHT ALREADY COVERS THIS. The worker reads each file as it
    '' reaches it, so whatever these notifications describe is what it will
    '' find -- and anything applied to the live index now would be thrown away
    '' when the fresh one is adopted. Dropping them is not a shortcut; it is
    '' the only version that cannot go stale.
    if( IndexBuildPending( ) ) then
        LogDebug( "watched-file changes ignored: the workspace scan will read " & _
                  "them anyway" )
        return JsonNode( )
    end if

    dim as long indexed = 0
    dim as long removed = 0
    dim as long skipped = 0

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

        select case kind
            case FILECHANGE_CREATED, FILECHANGE_CHANGED
                if( srv.Index->IndexPath( path_ ) ) then
                    indexed += 1
                else
                    '' Created and already gone, or unreadable. Whatever the
                    '' index holds for it is now a guess, so it goes.
                    srv.Index->Remove( uriText )
                    removed += 1
                end if

            case FILECHANGE_DELETED
                srv.Index->Remove( uriText )
                removed += 1

            case else
                skipped += 1
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
