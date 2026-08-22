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
    ''                definitionProvider                       <- here now
    ''      phase 5   completionProvider { triggerCharacters: [".", ":"] }
    ''      phase 6   workspaceSymbolProvider, referencesProvider
    ''      phase 7   renameProvider, signatureHelpProvider, semanticTokens...
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
