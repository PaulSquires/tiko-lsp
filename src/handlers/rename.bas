'' ############################################################################
''  handlers/rename.bas -- textDocument/prepareRename and textDocument/rename
''
''  Rename is the first request in this server that CHANGES the user's code,
''  and that changes what "good enough" means. References may over-report: a
''  spurious entry in a list costs a glance. A rename that over-reaches edits
''  files the user did not open, and the mistake is discovered later, in a
''  build failure or -- worse -- not at all.
''
''  So rename has two modes, and refuses everything that is neither:
''
''    A LOCAL OR PARAMETER is renamed inside its own procedure, in this file
''      only. That is exact: a local cannot be referred to from outside the
''      body it is declared in, so the edit set is provably complete and
''      provably minimal.
''
''    ANYTHING ELSE -- a procedure, a type, a field, a file-level variable --
''      is renamed across the workspace BY NAME, exactly matching what "find
''      all references" reports for it. This is honest but blunt: two unrelated
''      types with a field called `Count` are one name to a name-based index.
''
''    AND IF A LOCAL SOMEWHERE ELSE SHARES THE NAME, the rename is REFUSED.
''      Renaming a file-level `count` by name would silently rewrite the local
''      `count` in an unrelated procedure five files away. Nothing in this
''      server can tell those apart, so it does not pretend to: it says why,
''      and the user can do it by hand knowing what is involved.
''
''  prepareRename gives the same verdict BEFORE the editor asks for a new
''  name, which is the whole reason that request exists.
'' ############################################################################

#include once "rename.bi"
#include once "workspace_symbols.bi"
#include once "hover.bi"
#include once "../lsp/publish.bi"
#include once "../workspace/workspace.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"
#include once "fb/map.bi"

'' A rename that touches more than this is not something to verify by eye, and
'' a truncated rename is CORRUPTION -- so the limit refuses rather than trims.
const MAX_RENAME_EDITS = 5000

type OffsetArrayR_ as FB.Array( of long )

function IsRenameableIdentifier( byref name_ as string ) as boolean
    if( len(name_) = 0 ) then return false

    for i as long = 0 to len(name_) - 1
        dim as ubyte c = name_[i]
        dim as boolean ok_ = false
        if( (c >= 65 andalso c <= 90) orelse (c >= 97 andalso c <= 122) ) then ok_ = true
        if( c = asc("_") ) then ok_ = true
        if( c >= 48 andalso c <= 57 andalso i > 0 ) then ok_ = true
        if( ok_ = false ) then return false
    next

    '' A rename to a reserved word compiles into something else entirely, or
    '' does not compile at all.
    if( IsKeyword( name_ ) ) then return false
    return true
end function

'' The procedure a local belongs to, walking out through the parent chain.
private function EnclosingProcedure( byref symbols as SymbolTable, byval symIndex as long ) as long
    dim as long i = symIndex
    dim as long guard_ = 0

    while( i >= 0 andalso guard_ < 64 )
        select case symbols.Items[i].Kind_
            case SYM_FUNCTION, SYM_METHOD, SYM_CONSTRUCTOR, SYM_OPERATOR, SYM_PROPERTY
                return i
        end select
        i = symbols.Items[i].Parent
        guard_ += 1
    wend

    return -1
end function

'' WHICH FILES A RENAME MAY TOUCH.
''
'' Everything that can SEE the declaration, which is what the include graph is
'' for. Before it, a rename by name reached the whole workspace, and any local
'' anywhere that happened to share the name made it refuse -- so renaming a
'' field called `Count` was impossible in any project that also had a loop
'' variable called `count` somewhere.
''
'' TWO THINGS ARE ADDED TO THE VISIBLE SET, and both are there so that
'' narrowing can never lose an edit:
''
''   - the file the request came from, always;
''   - EVERY FILE WITH AN INCLUDE THIS SERVER COULD NOT RESOLVE. Such a file
''     might reach the declaration by a path we cannot see -- a compiler header
''     that includes it, an -i directory we were never told about -- so it is
''     treated as "maybe" and edited. Unknown visibility is not invisibility.
''
'' Returns false when the graph cannot say anything useful, and the caller then
'' does what it always did: the whole workspace, by name.
private function BuildRenameScope( byref srv as Server, byval doc as TextDocumentPtr, _
                                   byref lowerName as string, _
                                   byref scopeFiles as FB.Array( of long ) ) as boolean
    scopeFiles.Clear( )

    dim as long docFile = srv.Index->IndexOfUri( doc->Uri( ) )

    dim as IndexHit hit
    if( srv.Index->FindDefinitionFrom( docFile, lowerName, hit ) = false ) then return false

    srv.Index->IncludedBy( hit.FileIndex, scopeFiles )
    if( scopeFiles.IsEmpty( ) ) then return false

    dim seen_ as FB.Map( of long, boolean )
    for i as long = 0 to scopeFiles.Count( ) - 1
        seen_.Put( scopeFiles[i], true )
    next

    if( docFile >= 0 andalso seen_.Contains( docFile ) = false ) then
        scopeFiles.Push( docFile )
        seen_.Put( docFile, true )
    end if

    for f as long = 0 to srv.Index->FileCount( ) - 1
        if( seen_.Contains( f ) ) then continue for
        if( srv.Index->HasUnresolvedIncludes( f ) = false ) then continue for
        scopeFiles.Push( f )
        seen_.Put( f, true )
    next

    return true
end function

function RenameRefusal( byref srv as Server, byval doc as TextDocumentPtr, _
                        byval offset as long, byref lowerName as string, _
                        byref localScopeStart as long, byref localScopeEnd as long ) as string

    lowerName       = ""
    localScopeStart = -1
    localScopeEnd   = -1

    if( doc = 0 ) then return "the document is not open"

    dim as long tokIdx = TokenIndexAt( doc->Tokens( ), offset )
    if( tokIdx < 0 ) then return "there is nothing to rename here"
    if( doc->Tokens( )[tokIdx].Kind <> TK_IDENT ) then return "only a name can be renamed"

    lowerName = lcase( TokenText( doc->Text( ), doc->Tokens( )[tokIdx] ) )

    dim as long wordStart, wordEnd
    dim as long symIndex = ResolveAtOffset( doc, offset, wordStart, wordEnd )

    '' -- a local or a parameter: exact, and confined to its procedure --------
    ''
    '' NOT after a dot. `w.Label_` resolves through ResolveMember, which falls
    '' back to any symbol of that name when the field itself is declared in
    '' another file -- and in this file `label_` is very often a PARAMETER.
    '' Renaming the field as though it were that local would rewrite the
    '' parameter and leave the field alone: exactly backwards.
    dim as boolean isMember = IsMemberAccess( doc->Text( ), doc->Tokens( ), tokIdx )

    if( symIndex >= 0 andalso isMember = false ) then
        if( doc->Symbols( ).Items[symIndex].IsLocal ) then
            dim as long procIdx = EnclosingProcedure( doc->Symbols( ), symIndex )
            if( procIdx < 0 ) then return "this local is not inside a procedure"

            localScopeStart = doc->Symbols( ).Items[procIdx].RangeStart
            localScopeEnd   = doc->Symbols( ).Items[procIdx].RangeEnd
            return ""
        end if
    end if

    '' -- everything else: by name, within what can see it --------------------
    ''
    '' The guard below reads the index, so the scan has to have finished. A
    '' rename that silently skipped half the workspace because it was asked
    '' early would be the worst bug this server could have.
    EnsureWorkspaceIndex( srv )

    '' A name the TOOLCHAIN declares -- MessageBoxW, a CWindow method -- is not
    '' this workspace's to rename: the edit would land in windows.bi.
    dim as IndexHit defHit
    if( srv.Index->FindDefinitionFrom( srv.Index->IndexOfUri( doc->Uri( ) ), lowerName, defHit ) ) then
        if( srv.Index->IsExternal( defHit.FileIndex ) ) then
            return "'" & lowerName & "' is declared in a toolchain header (" & _
                   UriFileName( srv.Index->FileUri( defHit.FileIndex ) ) & _
                   ") -- renaming it would mean editing the toolchain"
        end if
    end if

    dim scopeFiles as FB.Array( of long )
    dim as boolean scoped = BuildRenameScope( srv, doc, lowerName, scopeFiles )

    for k as long = 0 to iif( scoped, scopeFiles.Count( ), srv.Index->FileCount( ) ) - 1
        dim as long f = iif( scoped, scopeFiles[k], k )
        if( srv.Index->IsExternal( f ) ) then continue for

        for i as long = 0 to srv.Index->FileSymbolCount( f ) - 1
            if( srv.Index->SymbolAt( f, i ).LowerName <> lowerName ) then continue for
            if( srv.Index->SymbolAt( f, i ).IsLocal = false ) then continue for

            return "'" & lowerName & "' is also a local in " & _
                   UriFileName( srv.Index->FileUri( f ) ) & _
                   " -- this server matches by name, so renaming it here would " & _
                   "change that one too"
        next
    next

    '' The open document may not be in the index at all -- no workspace folder,
    '' or a file outside every folder -- and its locals count just as much.
    if( srv.Index->IndexOfUri( doc->Uri( ) ) < 0 ) then
        for i as long = 0 to doc->Symbols( ).Count( ) - 1
            if( doc->Symbols( ).Items[i].LowerName <> lowerName ) then continue for
            if( doc->Symbols( ).Items[i].IsLocal = false ) then continue for
            if( symIndex >= 0 andalso i = symIndex ) then continue for

            return "'" & lowerName & "' is also a local in this file -- this " & _
                   "server matches by name, so renaming it would change that one too"
        next
    end if

    return ""
end function

'' ----------------------------------------------------------------------------
''  prepareRename
'' ----------------------------------------------------------------------------
private function OnPrepareRename( byref srv as Server, _
                                  byref req as RpcMessage, _
                                  byref rb as JsonBuilder, _
                                  byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )
    if( doc = 0 ) then return rb.NewNull( )

    dim as JsonValue posVal = req.Params( ).Member( "position" )
    dim as long lineNo = clng( posVal.Member( "line"      ).AsLongInt( 0 ) )
    dim as long charNo = clng( posVal.Member( "character" ).AsLongInt( 0 ) )
    dim as long offset = clng( doc->PositionToOffset( lineNo, charNo ) )

    dim as string lowerName
    dim as long scopeStart, scopeEnd
    dim as string refusal = RenameRefusal( srv, doc, offset, lowerName, scopeStart, scopeEnd )

    '' An ERROR, not a null result: a null makes the editor say "cannot be
    '' renamed" with no reason, and the reason is the useful part.
    if( len(refusal) > 0 ) then
        err_.SetErr( RPC_REQUEST_FAILED, refusal )
        return JsonNode( )
    end if

    dim as long tokIdx = TokenIndexAt( doc->Tokens( ), offset )
    dim as Token tok = doc->Tokens( )[tokIdx]

    dim as JsonNode result_ = rb.NewObject( )
    rb.SetNode( result_, "range", _
                BuildLspRange( rb, doc->Text( ), doc->Index( ), tok.Start_, tok.Start_ + tok.Length_ ) )

    '' The placeholder is the name AS WRITTEN, not the lower-cased key: the
    '' editor puts it in the box for the user to edit.
    rb.SetStr( result_, "placeholder", TokenText( doc->Text( ), tok ) )
    return result_
end function

'' ----------------------------------------------------------------------------
''  rename
'' ----------------------------------------------------------------------------

'' Appends the TextEdits for one file to `editList`, and returns how many.
private function EditsForFile( byref rb as JsonBuilder, byval editList as JsonNode, _
                               byref text_ as string, byref lowerName as string, _
                               byref newName as string, _
                               byval fromOffset as long, byval toOffset as long ) as long

    dim offsets as OffsetArrayR_
    FindIdentifierOffsets( text_, lowerName, offsets )
    if( offsets.Count( ) = 0 ) then return 0

    dim as LineIndex lines_
    lines_.Rebuild( text_ )

    dim as long made = 0

    for i as long = 0 to offsets.Count( ) - 1
        '' A local rename is confined to its own procedure. -1 means the whole
        '' file, which is what a workspace rename passes.
        if( fromOffset >= 0 andalso offsets[i] <  fromOffset ) then continue for
        if( toOffset   >= 0 andalso offsets[i] >= toOffset   ) then continue for

        dim as SourcePosition a = OffsetToSourcePosition( text_, lines_, offsets[i] )
        dim as SourcePosition b = OffsetToSourcePosition( text_, lines_, offsets[i] + len(lowerName) )

        dim as JsonNode start_ = rb.NewObject( )
        rb.SetInt( start_, "line", a.Line )
        rb.SetInt( start_, "character", a.Column )

        dim as JsonNode end_ = rb.NewObject( )
        rb.SetInt( end_, "line", b.Line )
        rb.SetInt( end_, "character", b.Column )

        dim as JsonNode range_ = rb.NewObject( )
        rb.SetNode( range_, "start", start_ )
        rb.SetNode( range_, "end", end_ )

        dim as JsonNode edit_ = rb.NewObject( )
        rb.SetNode( edit_, "range", range_ )
        rb.SetStr ( edit_, "newText", newName )

        rb.PushNode( editList, edit_ )
        made += 1
    next

    return made
end function

private function OnRename( byref srv as Server, _
                           byref req as RpcMessage, _
                           byref rb as JsonBuilder, _
                           byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as string newName = req.Params( ).Member( "newName" ).AsString( "" )

    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )
    if( doc = 0 ) then
        err_.SetErr( RPC_INVALID_PARAMS, "no open document for " & uriText )
        return JsonNode( )
    end if

    if( IsRenameableIdentifier( newName ) = false ) then
        err_.SetErr( RPC_INVALID_PARAMS, _
                     "'" & newName & "' is not a name tiko would accept" )
        return JsonNode( )
    end if

    dim as JsonValue posVal = req.Params( ).Member( "position" )
    dim as long lineNo = clng( posVal.Member( "line"      ).AsLongInt( 0 ) )
    dim as long charNo = clng( posVal.Member( "character" ).AsLongInt( 0 ) )
    dim as long offset = clng( doc->PositionToOffset( lineNo, charNo ) )

    dim as string lowerName
    dim as long scopeStart, scopeEnd
    dim as string refusal = RenameRefusal( srv, doc, offset, lowerName, scopeStart, scopeEnd )
    if( len(refusal) > 0 ) then
        err_.SetErr( RPC_REQUEST_FAILED, refusal )
        return JsonNode( )
    end if

    if( lcase( newName ) = lowerName ) then
        '' Renaming a name to itself, case aside, is not an error and not work
        '' either. An empty WorkspaceEdit is the correct answer.
        dim as JsonNode empty_ = rb.NewObject( )
        rb.SetNode( empty_, "changes", rb.NewObject( ) )
        return empty_
    end if

    dim as double started = timer( )
    dim as long total = 0

    '' `changes` is the simple form and every client understands it.
    '' `documentChanges` additionally carries the version each edit was
    '' computed against, so a client can refuse an edit that raced with a
    '' keystroke -- worth having, and only sent to clients that asked for it.
    dim as JsonNode changes  = rb.NewObject( )
    dim as JsonNode docChges = rb.NewArray( )
    dim as boolean useDocChanges = srv.SupportsDocumentChanges

    '' -- a local: this file, this procedure ----------------------------------
    if( scopeStart >= 0 ) then
        dim as JsonNode editList = rb.NewArray( )
        total = EditsForFile( rb, editList, doc->Text( ), lowerName, newName, scopeStart, scopeEnd )

        if( useDocChanges ) then
            dim as JsonNode ident = rb.NewObject( )
            rb.SetStr( ident, "uri", doc->Uri( ) )
            rb.SetInt( ident, "version", doc->Version( ) )

            dim as JsonNode entry = rb.NewObject( )
            rb.SetNode( entry, "textDocument", ident )
            rb.SetNode( entry, "edits", editList )
            rb.PushNode( docChges, entry )
        else
            rb.SetNode( changes, doc->Uri( ), editList )
        end if

        LogDebug( "rename local '" & lowerName & "' -> '" & newName & "': " & _
                  total & " edit(s) in one procedure" )
    else
        '' -- everything else: by name, every file that CAN SEE it --------------
        dim as long files_ = 0

        dim scopeFiles as FB.Array( of long )
        dim as boolean scoped = BuildRenameScope( srv, doc, lowerName, scopeFiles )

        if( scoped ) then
            LogDebug( "rename '" & lowerName & "': " & scopeFiles.Count( ) & " of " & _
                      srv.Index->FileCount( ) & " file(s) can see the declaration" )
        end if

        for k as long = 0 to iif( scoped, scopeFiles.Count( ), srv.Index->FileCount( ) ) - 1
            dim as long f = iif( scoped, scopeFiles[k], k )

            '' NEVER a toolchain header, whatever the scope says: a workspace
            '' name that a header happens to share must not rewrite the header.
            if( srv.Index->IsExternal( f ) ) then continue for

            dim as string fileUri = srv.Index->FileUri( f )

            '' The open buffer, when there is one: it is the truth, and its
            '' version is what the edit must be applied against.
            dim as TextDocumentPtr openDoc = srv.Documents.Find( fileUri )
            dim as string body
            if( openDoc <> 0 ) then
                body = openDoc->Text( )
            elseif( ReadSourceFile( srv.Index->FilePath( f ), body ) = false ) then
                continue for
            end if

            dim as JsonNode editList = rb.NewArray( )
            dim as long made = EditsForFile( rb, editList, body, lowerName, newName, -1, -1 )
            if( made = 0 ) then continue for

            total  += made
            files_ += 1

            if( useDocChanges ) then
                dim as JsonNode ident = rb.NewObject( )
                rb.SetStr( ident, "uri", fileUri )
                if( openDoc <> 0 ) then
                    rb.SetInt ( ident, "version", openDoc->Version( ) )
                else
                    '' null means "whatever is on disk", which is exactly the
                    '' case for a file no editor has open.
                    rb.SetNull( ident, "version" )
                end if

                dim as JsonNode entry = rb.NewObject( )
                rb.SetNode( entry, "textDocument", ident )
                rb.SetNode( entry, "edits", editList )
                rb.PushNode( docChges, entry )
            else
                rb.SetNode( changes, fileUri, editList )
            end if
        next

        '' A file the index has never seen -- no workspace folder, or one
        '' outside every folder -- still has to be renamed in.
        if( srv.Index->IndexOfUri( uriText ) < 0 ) then
            dim as JsonNode editList = rb.NewArray( )
            dim as long made = EditsForFile( rb, editList, doc->Text( ), lowerName, newName, -1, -1 )

            if( made > 0 ) then
                total  += made
                files_ += 1

                if( useDocChanges ) then
                    dim as JsonNode ident = rb.NewObject( )
                    rb.SetStr( ident, "uri", doc->Uri( ) )
                    rb.SetInt( ident, "version", doc->Version( ) )

                    dim as JsonNode entry = rb.NewObject( )
                    rb.SetNode( entry, "textDocument", ident )
                    rb.SetNode( entry, "edits", editList )
                    rb.PushNode( docChges, entry )
                else
                    rb.SetNode( changes, doc->Uri( ), editList )
                end if
            end if
        end if

        LogDebug( "rename '" & lowerName & "' -> '" & newName & "': " & total & _
                  " edit(s) in " & files_ & " file(s), " & _
                  int( (timer( ) - started) * 1000 ) & " ms" )
    end if

    if( total > MAX_RENAME_EDITS ) then
        err_.SetErr( RPC_REQUEST_FAILED, _
                     "'" & lowerName & "' occurs " & total & " times -- more than this " & _
                     "server will rewrite in one edit" )
        return JsonNode( )
    end if

    dim as JsonNode result_ = rb.NewObject( )
    if( useDocChanges ) then
        rb.SetNode( result_, "documentChanges", docChges )
    else
        rb.SetNode( result_, "changes", changes )
    end if
    return result_
end function

sub RegisterRenameHandlers( )
    RegisterHandler( LSP_PREPARE_RENAME, @OnPrepareRename )
    RegisterHandler( LSP_RENAME,         @OnRename )
end sub
