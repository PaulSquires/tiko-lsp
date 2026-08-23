'' ############################################################################
''  lsp/protocol.bas -- LSP constants and the capability document
'' ############################################################################

#include once "protocol.bi"

function LspBuildCapabilities( byref rb as JsonBuilder ) as JsonNode
    dim as JsonNode caps = rb.NewObject( )

    '' ------------------------------------------------------------------------
    ''  A capability announced here is a promise that the corresponding request
    ''  works. Nothing is listed before the phase that implements it:
    ''
    ''      phase 2   textDocumentSync, positionEncoding
    ''      phase 3   (diagnostics are pushed, not advertised, before 3.17)
    ''      phase 4   documentSymbolProvider, hoverProvider,
    ''                definitionProvider
    ''      phase 5   completionProvider
    ''      phase 6   workspaceSymbolProvider, referencesProvider,
    ''                workspace.workspaceFolders               <- here now
    ''      phase 7   renameProvider, signatureHelpProvider,
    ''                semanticTokensProvider, inlayHintProvider,
    ''                documentFormattingProvider,
    ''                documentRangeFormattingProvider, codeActionProvider
    '' ------------------------------------------------------------------------

    '' Stated explicitly even though utf-16 is the protocol default, because a
    '' client that offered utf-8 needs to see which one was chosen.
    rb.SetStr( caps, "positionEncoding", LSP_ENCODING_UTF16 )

    '' openClose: didOpen and didClose are wanted.
    '' change: 2  -- Incremental. The document model applies ranges, so asking
    ''               for full text on every keystroke would waste both sides.
    '' save: { includeText: false } -- didSave is wanted as a signal; the
    ''               buffer is already authoritative, so the text is not.
    dim as JsonNode sync = rb.NewObject( )
    rb.SetBool( sync, "openClose", true )
    rb.SetInt ( sync, "change", clngint( LSPSYNC_INCREMENTAL ) )

    dim as JsonNode saveOpts = rb.NewObject( )
    rb.SetBool( saveOpts, "includeText", false )
    rb.SetNode( sync, "save", saveOpts )

    rb.SetNode( caps, "textDocumentSync", sync )

    '' Phase 4. Each of these is answered from the document's own symbol table,
    '' so each is honest for the file being edited -- and only for that file:
    '' definition does not follow an #include yet, and says nothing rather than
    '' guessing.
    rb.SetBool( caps, "documentSymbolProvider", true )
    rb.SetBool( caps, "hoverProvider",          true )
    rb.SetBool( caps, "definitionProvider",     true )

    '' Phase 5. The trigger characters are the ones after which a client should
    '' ask WITHOUT being asked to: a dot begins a member expression, and a
    '' colon ends a statement, so the next thing typed is a fresh identifier.
    ''
    '' resolveProvider is FALSE: every item already carries its detail and its
    '' documentation, so there is no second round trip to serve.
    dim as JsonNode completion = rb.NewObject( )
    rb.SetBool( completion, "resolveProvider", false )

    dim as JsonNode triggers = rb.NewArray( )
    rb.PushStr( triggers, "." )
    rb.PushStr( triggers, ":" )
    rb.SetNode( completion, "triggerCharacters", triggers )

    rb.SetNode( caps, "completionProvider", completion )

    '' Phase 6. Both are answered from the workspace index, which is built once
    '' the client says `initialized` and kept current from the open buffers.
    rb.SetBool( caps, "workspaceSymbolProvider", true )
    rb.SetBool( caps, "referencesProvider",      true )

    '' Saying the server understands multi-root workspaces AND wants to be told
    '' when the set changes. Without changeNotifications the index would go
    '' stale the first time a folder is added, silently.
    dim as JsonNode folders = rb.NewObject( )
    rb.SetBool( folders, "supported", true )
    rb.SetBool( folders, "changeNotifications", true )

    dim as JsonNode wsCaps = rb.NewObject( )
    rb.SetNode( wsCaps, "workspaceFolders", folders )
    rb.SetNode( caps, "workspace", wsCaps )

    '' ------------------------------------------------------------------------
    ''  Phase 7
    '' ------------------------------------------------------------------------

    '' prepareProvider is TRUE, and it is not a formality: this server refuses
    '' renames it cannot do safely, and prepareRename is the only way to say so
    '' BEFORE the user has typed a new name into the editor's box.
    dim as JsonNode renameOpts = rb.NewObject( )
    rb.SetBool( renameOpts, "prepareProvider", true )
    rb.SetNode( caps, "renameProvider", renameOpts )

    '' '(' opens a call and ',' moves to the next argument -- the two moments
    '' a signature should appear without being asked for. ',' retriggers so an
    '' already-open popup follows the caret instead of closing.
    dim as JsonNode sigOpts = rb.NewObject( )
    dim as JsonNode sigTrig = rb.NewArray( )
    rb.PushStr( sigTrig, "(" )
    rb.PushStr( sigTrig, "," )
    rb.SetNode( sigOpts, "triggerCharacters", sigTrig )

    dim as JsonNode sigRetrig = rb.NewArray( )
    rb.PushStr( sigRetrig, "," )
    rb.SetNode( sigOpts, "retriggerCharacters", sigRetrig )
    rb.SetNode( caps, "signatureHelpProvider", sigOpts )

    '' The semantic-token legend. The client caches this and then receives
    '' nothing but numbers, so the order here is the wire format.
    ''
    '' `full` only: no range, and no delta. A delta needs the previous result
    '' kept per document and a result id to match it, and claiming it while
    '' returning a full set every time is the kind of half-support that makes
    '' a client show stale colours.
    dim as JsonNode legend = rb.NewObject( )

    dim as JsonNode typeNames = rb.NewArray( )
    dim names_ as FB.Array( of string ) = SemanticTypeNames( )
    for i as long = 0 to names_.Count( ) - 1
        rb.PushStr( typeNames, names_[i] )
    next
    rb.SetNode( legend, "tokenTypes", typeNames )

    dim as JsonNode modNames = rb.NewArray( )
    dim mods_ as FB.Array( of string ) = SemanticModifierNames( )
    for i as long = 0 to mods_.Count( ) - 1
        rb.PushStr( modNames, mods_[i] )
    next
    rb.SetNode( legend, "tokenModifiers", modNames )

    dim as JsonNode semOpts = rb.NewObject( )
    rb.SetNode( semOpts, "legend", legend )
    rb.SetBool( semOpts, "full", true )
    rb.SetNode( caps, "semanticTokensProvider", semOpts )

    '' resolveProvider is absent: a hint is complete when it is sent.
    rb.SetBool( caps, "inlayHintProvider", true )

    rb.SetBool( caps, "documentFormattingProvider",      true )
    rb.SetBool( caps, "documentRangeFormattingProvider", true )

    '' Only quickfix. Announcing `refactor` or `source` and returning nothing
    '' for them puts empty entries in the editor's lightbulb menu.
    dim as JsonNode caOpts  = rb.NewObject( )
    dim as JsonNode caKinds = rb.NewArray( )
    rb.PushStr( caKinds, "quickfix" )
    rb.SetNode( caOpts, "codeActionKinds", caKinds )
    rb.SetNode( caps, "codeActionProvider", caOpts )

    return caps
end function

function LspBuildServerInfo( byref rb as JsonBuilder ) as JsonNode
    dim as JsonNode info = rb.NewObject( )
    rb.SetStr( info, "name",    LSP_SERVER_NAME )
    rb.SetStr( info, "version", LSP_SERVER_VERSION )
    return info
end function

function LspIsKnownEncoding( byref enc as string ) as boolean
    select case lcase( trim(enc) )
        case LSP_ENCODING_UTF8, LSP_ENCODING_UTF16, LSP_ENCODING_UTF32
            return true
    end select
    return false
end function
