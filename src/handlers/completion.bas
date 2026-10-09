'' ############################################################################
''  handlers/completion.bas -- textDocument/completion
''
''  The candidates come from analysis/completion.bas; this file's whole job is
''  turning them into CompletionItems and deciding what a client needs to be
''  told explicitly.
'' ############################################################################

#include once "completion.bi"
#include once "workspace_symbols.bi"
#include once "../workspace/index_builder.bi"
#include once "../analysis/completion.bi"
#include once "../analysis/includes.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

'' A file at the top of a big header tree can see fifty thousand symbols --
'' measured, on C:\dev\tiko. Sending those on every keystroke is a megabyte of
'' JSON the editor renders and then filters down to five, so the list is capped
'' and the client is told it is INCOMPLETE, which is the protocol's way of
'' saying "ask me again when you have typed more".
const MAX_INCLUDED_ITEMS = 1000

'' Everything the files this one includes put into scope.
''
''  WITHOUT THIS, completion was a lie of omission: a file that includes a
''  header saw none of what the header declares, so the one list a user reads
''  on every keystroke stopped exactly at the file boundary the language does
''  not have.
''
''  Local symbols are left out -- another file's locals are not in scope
''  anywhere -- and so are duplicates of what this file already offered, which
''  is what a header and its implementation file look like together.
private function AddIncludedSymbols( byref srv as Server, byval doc as TextDocumentPtr, _
                                     byref prefix as string, _
                                     byref items as CompletionItemArray ) as boolean

    dim as long here = srv.Index->IndexOfUri( doc->Uri( ) )
    if( here < 0 ) then return false

    dim visible as FB.Array( of long )
    srv.Index->VisibleFrom( here, visible )
    if( visible.Count( ) <= 1 ) then return false

    '' The labels already offered, lower-cased once. The list is a few hundred
    '' items and the visible set can be thousands of symbols, so this is the
    '' difference between a millisecond and a hundred.
    dim seen_ as FB.Map( of string, boolean )
    for i as long = 0 to items.Count( ) - 1
        seen_.Put( items[i].LowerLabel, true )
    next

    dim as long added = 0
    dim as boolean truncated = false

    '' The prefix the user has already typed does the filtering a client would
    '' otherwise do for itself -- and it is what keeps the cap from biting: by
    '' the second character the visible set is a handful of names.
    dim as string want = lcase( prefix )

    for v as long = 0 to visible.Count( ) - 1
        dim as long f = visible[v]
        if( f = here ) then continue for
        if( added >= MAX_INCLUDED_ITEMS ) then
            truncated = true
            exit for
        end if

        for i as long = 0 to srv.Index->FileSymbolCount( f ) - 1
            dim as SymbolInfo sym = srv.Index->SymbolAt( f, i )
            if( sym.IsLocal ) then continue for
            if( len(sym.Name_) = 0 ) then continue for
            if( len(want) > 0 andalso left( sym.LowerName, len(want) ) <> want ) then continue for
            if( seen_.Contains( sym.LowerName ) ) then continue for

            if( added >= MAX_INCLUDED_ITEMS ) then
                truncated = true
                exit for
            end if

            seen_.Put( sym.LowerName, true )

            dim as CompletionItem it
            it.Label      = sym.Name_
            it.LowerLabel = sym.LowerName
            it.Kind_      = CompletionKindOf( sym.Kind_ )
            it.Detail_    = sym.Detail_
            it.Doc_       = sym.Doc_
            it.SortGroup  = CMPGROUP_INCLUDE
            items.Push( it )
            added += 1
        next
    next

    LogDebug( "completion: " & added & " item(s) from " & (visible.Count( ) - 1) & _
              " included file(s)" & iif( truncated, " (capped)", "" ) )

    '' Filtered by a prefix is ALSO incomplete: the client must not cache this
    '' list and narrow it locally, because the names it would then never see
    '' are the ones that were filtered out here.
    return truncated orelse ( len(want) > 0 )
end function

'' Is `name_` one of this document's import aliases? Read from its own tokens, so a file
'' that imports nothing never asks the index.
private function IsImportAlias_( byval doc as TextDocumentPtr, byref name_ as string ) as boolean
    dim refs as ImportRefArray
    FindImports( doc->Text( ), doc->Tokens( ), refs )
    dim as string want = lcase( name_ )
    for i as long = 0 to refs.Count( ) - 1
        if( refs[i].Alias_ = want ) then return true
    next
    return false
end function

'' `http.` WHERE http IS AN IMPORT'S ALIAS (tiko-lang ADR 0017): what the module lets out --
'' its file-level declarations marked `public`, and the macros it `#export`s -- and nothing
'' else. The file-wide member guess CollectCompletions offers for an unknown base is
'' dropped: the base is known. An exported macro that names a declaration -- a std facade's
'' `#define PathJoin FB.PathJoin` (tiko-lang RFC-0009) -- is offered as what it names.
private sub AddModuleMembers( byref srv as Server, byval doc as TextDocumentPtr, _
                              byref alias_ as string, byref items as CompletionItemArray )
    items.Clear( )
    dim as long here = srv.Index->IndexOfUri( doc->Uri( ) )
    if( here < 0 ) then exit sub
    dim hits as IndexHitArray
    srv.Index->ModuleMembers( here, lcase( alias_ ), hits )
    dim seen_ as FB.Map( of string, boolean )
    for i as long = 0 to hits.Count( ) - 1
        dim as SymbolInfo sym = srv.Index->SymbolAt( hits[i].FileIndex, hits[i].SymIndex )
        if( seen_.Contains( sym.LowerName ) ) then continue for
        seen_.Put( sym.LowerName, true )
        dim as CompletionItem it
        it.Label      = sym.Name_
        it.LowerLabel = sym.LowerName
        it.Kind_      = CompletionKindOf( sym.Kind_ )
        it.Detail_    = sym.Detail_
        it.Doc_       = sym.Doc_
        it.SortGroup  = CMPGROUP_INCLUDE
        items.Push( it )
    next
    dim xs as ExportHitArray
    dim ts_ as IndexHitArray
    srv.Index->ModuleExportTargets( here, lcase( alias_ ), xs, ts_ )
    for xi as long = 0 to xs.Count( ) - 1
        dim as ExportEdge e = srv.Index->ExportAt( xs[xi].FileIndex, xs[xi].ExportIndex )
        if( seen_.Contains( e.LowerName ) ) then continue for
        seen_.Put( e.LowerName, true )
        dim as CompletionItem it
        it.Label      = e.Name_
        it.LowerLabel = e.LowerName
        dim as IndexHit t = ts_[xi]
        if( t.FileIndex >= 0 ) then
            dim as SymbolInfo ts = srv.Index->SymbolAt( t.FileIndex, t.SymIndex )
            it.Kind_   = CompletionKindOf( ts.Kind_ )
            it.Detail_ = ts.Detail_
            it.Doc_    = ts.Doc_
        else
            it.Kind_   = CMP_CONSTANT
            it.Detail_ = "#define " & e.Name_ & iif( len(e.Body) > 0, " " & e.Body, "" )
        end if
        it.SortGroup  = CMPGROUP_INCLUDE
        items.Push( it )
    next
    LogDebug( "completion: " & items.Count( ) & " public name(s) of module '" & alias_ & "'" )
end sub

'' What a file can see for the purpose of TYPE NAMES: its includes, transitively
'' (VisibleFrom), and also its #imports -- each imported module's files and what
'' THEY can see. `#import "std/logs"` then `dim as Logger lg`: Logger reaches
'' this file through the module (std/logs re-exports FB.Logger, declared in
'' fb/logger.bi, which logs.bas includes) and through nothing this file
'' #includes, so a type search over its includes alone finds nothing.
sub VisibleWithImports( byref srv as Server, byval here as long, _
                        byref out_ as FB.Array( of long ) )
    srv.Index->VisibleFrom( here, out_ )
    dim seen_ as FB.Map( of long, boolean )
    for i as long = 0 to out_.Count( ) - 1
        seen_.Put( out_[i], true )
    next
    for k as long = 0 to srv.Index->ImportCount( here ) - 1
        dim as ImportEdge e = srv.Index->ImportAt( here, k )
        for each mf as long in e.Files
            dim more as FB.Array( of long )
            srv.Index->VisibleFrom( mf, more )
            for each f as long in more
                if( seen_.Contains( f ) ) then continue for
                seen_.Put( f, true )
                out_.Push( f )
            next
        next
    next
end sub

'' AN ALIAS IS FOLLOWED to what it names, as many hops as there are:
''     dim as TrkVoidResult cfg              cfg's type is TrkVoidResult,
''     type TrkVoidResult as FB.Result( of boolean, TrkError )
'' and the members are Result's, in the toolchain's fb/result.bi. Looked for in
'' the asking file as well -- an alias is often declared beside its use.
'' Bounded, so `type A as B` / `type B as A` cannot loop.
function FinalTypeName( byref srv as Server, byref visible as FB.Array( of long ), _
                        byref typeName as string ) as string
    dim as string want = lcase( typeName )
    for hop as long = 1 to 8
        dim as string target = ""
        for v as long = 0 to visible.Count( ) - 1
            dim as long f = visible[v]
            for t as long = 0 to srv.Index->FileSymbolCount( f ) - 1
                dim as SymbolInfo a = srv.Index->SymbolAt( f, t )
                if( a.LowerName <> want ) then continue for
                if( a.Kind_ <> SYM_STRUCT ) then continue for
                target = lcase( DeclaredTypeName( a ) )
                if( len(target) > 0 ) then exit for
            next
            if( len(target) > 0 ) then exit for
        next
        if( len(target) = 0 orelse target = want ) then exit for
        want = target
    next
    return want
end function

'' The members of a type declared in an INCLUDED file.
''
'' `w.` where `w as Widget` and Widget lives in a header was the case that made
'' member completion look broken: the type is in scope, its fields are in
'' scope, and the server offered nothing at all.
private sub AddIncludedMembers( byref srv as Server, byval doc as TextDocumentPtr, _
                                byref typeName as string, byref items as CompletionItemArray )

    if( len(typeName) = 0 ) then exit sub

    dim as long here = srv.Index->IndexOfUri( doc->Uri( ) )
    if( here < 0 ) then exit sub

    dim visible as FB.Array( of long )
    VisibleWithImports( srv, here, visible )

    dim as string want = FinalTypeName( srv, visible, typeName )

    dim seen_ as FB.Map( of string, boolean )
    for i as long = 0 to items.Count( ) - 1
        seen_.Put( items[i].LowerLabel, true )
    next

    for v as long = 0 to visible.Count( ) - 1
        dim as long f = visible[v]
        if( f = here ) then continue for

        '' Find the type, then everything whose parent it is. The table is
        '' flat with parent INDICES, so its members are one pass away.
        for t as long = 0 to srv.Index->FileSymbolCount( f ) - 1
            dim as SymbolInfo owner = srv.Index->SymbolAt( f, t )
            if( owner.LowerName <> want ) then continue for

            select case owner.Kind_
                case SYM_STRUCT, SYM_CLASS, SYM_ENUM, SYM_NAMESPACE, SYM_INTERFACE
                case else
                    continue for
            end select

            '' An alias declares no members of its own.
            if( lcase( left( owner.Detail_, 3 ) ) = "as " ) then continue for

            for i as long = 0 to srv.Index->FileSymbolCount( f ) - 1
                dim as SymbolInfo m = srv.Index->SymbolAt( f, i )
                if( m.Parent <> t ) then continue for
                if( len(m.Name_) = 0 ) then continue for
                if( IsOfferedMember( m ) = false ) then continue for
                if( seen_.Contains( m.LowerName ) ) then continue for

                seen_.Put( m.LowerName, true )

                dim as CompletionItem it
                it.Label      = m.Name_
                it.LowerLabel = m.LowerName
                it.Kind_      = CompletionKindOf( m.Kind_ )
                it.Detail_    = m.Detail_
                it.Doc_       = m.Doc_
                it.SortGroup  = CMPGROUP_MEMBER
                items.Push( it )
            next
            exit for
        next
    next
end sub

private function OnCompletion( byref srv as Server, _
                               byref req as RpcMessage, _
                               byref rb as JsonBuilder, _
                               byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )

    '' An empty list, not null: a client shows "no suggestions" for the first
    '' and may retry for the second.
    if( doc = 0 ) then return rb.NewArray( )

    dim as JsonValue posVal = req.Params( ).Member( "position" )
    dim as long lineNo = clng( posVal.Member( "line"      ).AsLongInt( 0 ) )
    dim as long charNo = clng( posVal.Member( "character" ).AsLongInt( 0 ) )
    dim as long offset = clng( doc->PositionToOffset( lineNo, charNo ) )

    dim as CompletionItemArray items
    CollectCompletions( doc->Text( ), doc->Tokens( ), doc->Symbols( ), offset, items )

    '' -- and what the includes bring in ---------------------------------------
    ''
    '' The index is needed for this and only for this, so a file with no
    '' includes -- and a server whose scan has not finished -- pays nothing.
    dim as CompletionContext ctx = CompletionContextAt( doc->Text( ), doc->Tokens( ), offset )

    '' COMPLETION NEVER WAITS. It runs on every keystroke, and a first
    '' completion that blocked for the four seconds a large workspace takes to
    '' scan would be worse than one that offers a shorter list. So the index is
    '' used when it is THERE -- collected here if the worker has finished, and
    '' silently skipped while it has not.
    dim as boolean indexUsable = ( IndexBuildPending( ) = false ) orelse IndexBuildReady( )
    dim as boolean incomplete_ = false

    '' An import's alias before a dot names a module, not a variable (tiko-lang ADR 0017).
    dim as boolean onModule = false
    if( ctx.Kind_ = CMPCTX_MEMBER andalso indexUsable ) then onModule = IsImportAlias_( doc, ctx.BaseName )

    if( ctx.Kind_ = CMPCTX_SCOPE andalso indexUsable ) then
        EnsureWorkspaceIndex( srv )
        incomplete_ = AddIncludedSymbols( srv, doc, ctx.Prefix, items )

    elseif( onModule ) then
        EnsureWorkspaceIndex( srv )
        AddModuleMembers( srv, doc, ctx.BaseName, items )

    elseif( ctx.Kind_ = CMPCTX_MEMBER andalso indexUsable ) then
        '' The base's type is read from ITS declaration, which is in this file
        '' -- a variable is declared where it is used. Only the TYPE lives
        '' somewhere else, and that is what the graph is asked about.
        dim as long baseIdx = doc->Symbols( ).Resolve( ctx.BaseName, ctx.BaseOffset )
        if( baseIdx >= 0 ) then
            dim as string typeName = DeclaredTypeName( doc->Symbols( ).Items[baseIdx] )
            if( len(typeName) > 0 ) then
                EnsureWorkspaceIndex( srv )
                AddIncludedMembers( srv, doc, typeName, items )
            end if
        end if
    end if

    dim as JsonNode list_ = rb.NewArray( )

    for i as long = 0 to items.Count( ) - 1
        dim as CompletionItem it = items[i]

        dim as JsonNode node = rb.NewObject( )
        rb.SetStr( node, "label", it.Label )
        rb.SetInt( node, "kind",  clngint( it.Kind_ ) )
        if( len(it.Detail_) > 0 ) then rb.SetStr( node, "detail", it.Detail_ )

        if( len(it.Doc_) > 0 ) then
            dim as JsonNode docNode = rb.NewObject( )
            rb.SetStr( docNode, "kind",  "markdown" )
            rb.SetStr( docNode, "value", it.Doc_ )
            rb.SetNode( node, "documentation", docNode )
        end if

        '' sortText decides the ORDER, filterText decides what the client
        '' matches the typed prefix against, and insertText is what lands in
        '' the buffer. All three are stated rather than left to default,
        '' because the defaults all fall back to `label` and that would put a
        '' keyword above a local whenever the alphabet says so.
        rb.SetStr( node, "sortText",   chr( asc("0") + it.SortGroup ) & lcase( it.Label ) )
        rb.SetStr( node, "filterText", it.Label )
        rb.SetStr( node, "insertText", it.Label )

        rb.PushNode( list_, node )
    next

    LogDebug( "completion at " & UriFileName( uriText ) & " " & lineNo & ":" & charNo & _
              " -> " & items.Count( ) & " item(s)" & iif( incomplete_, " (incomplete)", "" ) )

    '' A CompletionList rather than a bare array, so `isIncomplete` can be
    '' said. It matters exactly when the list was filtered by what has been
    '' typed so far or cut off at the cap: a client that believed a filtered
    '' list was the whole truth would narrow it locally from then on, and the
    '' names it never saw would never appear however much more the user typed.
    dim as JsonNode result_ = rb.NewObject( )
    rb.SetBool( result_, "isIncomplete", incomplete_ )
    rb.SetNode( result_, "items", list_ )
    return result_
end function

sub RegisterCompletionHandlers( )
    RegisterHandler( LSP_COMPLETION, @OnCompletion )
end sub
