'' ############################################################################
''  handlers/text_document.bas -- document synchronisation
'' ############################################################################

#include once "text_document.bi"
#include once "../lsp/publish.bi"
#include once "../workspace/workspace.bi"
#include once "../utils/logging.bi"
#include once "../utils/uri.bi"

'' Every one of these params objects starts with a TextDocumentIdentifier.
private function ParamUri( byref req as RpcMessage ) as string
    return req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
end function

private function DescribeDoc( byval doc as TextDocumentPtr ) as string
    if( doc = 0 ) then return "<none>"
    return UriFileName( doc->Uri( ) ) & " v" & doc->Version( ) & _
           ", " & doc->LineCount( ) & " line(s), " & doc->TextLength( ) & " byte(s)"
end function

'' ----------------------------------------------------------------------------
''  textDocument/didOpen
''
''  From here until didClose the client's copy is the only one that counts, and
''  nothing in the server may read the file from disk.
'' ----------------------------------------------------------------------------
private function OnDidOpen( byref srv as Server, _
                            byref req as RpcMessage, _
                            byref rb as JsonBuilder, _
                            byref err_ as RpcError ) as JsonNode

    dim as JsonValue td = req.Params( ).Member( "textDocument" )

    dim as string uriText = td.Member( "uri" ).AsString( "" )
    if( len(uriText) = 0 ) then
        LogWarn( "didOpen without a uri -- ignored" )
        return JsonNode( )
    end if

    dim as string  langId  = td.Member( "languageId" ).AsString( "" )
    dim as longint version_ = td.Member( "version" ).AsLongInt( 0 )

    '' `text` is REQUIRED on didOpen. An absent one means an empty buffer, not
    '' "read it yourself".
    dim as string body = td.Member( "text" ).AsString( "" )

    dim as TextDocumentPtr doc = srv.Documents.Open( uriText, langId, version_, body )
    if( doc = 0 ) then
        LogError( "didOpen failed to allocate a document for " & uriText )
        return JsonNode( )
    end if

    LogInfo( "opened " & DescribeDoc( doc ) & " [" & langId & "], " & _
             srv.Documents.Count( ) & " open" )
    srv.SendTrace( "didOpen " & UriFileName( uriText ), DescribeDoc( doc ) )

    '' The index switches to the BUFFER for this file. From here until didClose
    '' the editor's copy is what the workspace knows, so a symbol typed but not
    '' saved is still found from another file.
    srv.Index->IndexText( doc->Uri( ), doc->FilePath( ), doc->Text( ), true )

    '' The buffer may have just gained or lost an #include, and the graph is
    '' what completion and definition read to know what this file can see. One
    '' hash probe per edge in the workspace -- a fraction of the analysis that
    '' just ran.
    srv.Index->ResolveIncludes( )

    PublishDocumentDiagnostics( srv, doc )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------
''  textDocument/didChange
''
''  contentChanges is an ORDERED list and each entry applies to the document as
''  left by the previous one. Applying them out of order, or computing all the
''  offsets against the original text, corrupts the buffer in a way that only
''  shows up several edits later.
'' ----------------------------------------------------------------------------
private function OnDidChange( byref srv as Server, _
                              byref req as RpcMessage, _
                              byref rb as JsonBuilder, _
                              byref err_ as RpcError ) as JsonNode

    dim as string uriText = ParamUri( req )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )

    if( doc = 0 ) then
        '' A change for a document we were never told about. Dropping it is
        '' the only safe answer -- there is no base text to apply it to.
        LogWarn( "didChange for a document that is not open: " & uriText )
        return JsonNode( )
    end if

    dim as longint version_ = req.Params( ).Member( "textDocument" ).Member( "version" ) _
                                 .AsLongInt( doc->Version( ) )

    dim as long applied = 0
    dim as long fullReplacements = 0

    for each change in ArrayOf( req.Params( ).Member( "contentChanges" ) )
        dim as string newText = change.Member( "text" ).AsString( "" )
        dim as JsonValue rangeVal = change.Member( "range" )

        if( rangeVal.IsObject( ) = false ) then
            '' No range: this entry replaces the whole document. Legal even
            '' under incremental sync, and what clients send after an external
            '' change such as a git checkout.
            doc->ReplaceAll( newText, version_ )
            fullReplacements += 1
            applied += 1
            continue for
        end if

        dim as JsonValue startVal = rangeVal.Member( "start" )
        dim as JsonValue endVal   = rangeVal.Member( "end" )

        '' rangeLength is deliberately ignored: it is deprecated, it is in
        '' UTF-16 units, and the range already says what to replace.
        doc->ApplyRange( clng( startVal.Member( "line"      ).AsLongInt( 0 ) ), _
                         clng( startVal.Member( "character" ).AsLongInt( 0 ) ), _
                         clng( endVal  .Member( "line"      ).AsLongInt( 0 ) ), _
                         clng( endVal  .Member( "character" ).AsLongInt( 0 ) ), _
                         newText, version_ )
        applied += 1
    next

    if( applied = 0 ) then
        '' An empty contentChanges array is legal and means "nothing changed";
        '' the version still moves.
        doc->SetVersion( version_ )
    end if

    LogDebug( "changed " & DescribeDoc( doc ) & " (" & applied & " edit(s), " & _
              fullReplacements & " full)" )
    srv.SendTrace( "didChange " & UriFileName( uriText ) & " (" & applied & " edit(s))", _
                   DescribeDoc( doc ) )

    '' The workspace index follows the buffer, so a rename typed in one file
    '' is visible from another before it is saved.
    srv.Index->IndexText( doc->Uri( ), doc->FilePath( ), doc->Text( ), true )

    '' The buffer may have just gained or lost an #include, and the graph is
    '' what completion and definition read to know what this file can see. One
    '' hash probe per edge in the workspace -- a fraction of the analysis that
    '' just ran.
    srv.Index->ResolveIncludes( )

    '' Re-analysed on every change, synchronously. Measured on win64/gas64:
    '' 0.3 ms for a 700-line file, 10 ms for the 8,645-line ir-gas64.bas, which
    '' is the largest source in fbc's own compiler. That is comfortably inside
    '' a keystroke for anything normal, and the reason there is no debouncing
    '' yet -- it belongs with the background analysis of phase 6.
    PublishDocumentDiagnostics( srv, doc )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------
''  textDocument/didSave
''
''  The server advertises includeText:false, so `text` is normally absent and
''  the buffer is already correct. It is honoured when present anyway, because
''  a client may send it regardless.
'' ----------------------------------------------------------------------------
private function OnDidSave( byref srv as Server, _
                            byref req as RpcMessage, _
                            byref rb as JsonBuilder, _
                            byref err_ as RpcError ) as JsonNode

    dim as string uriText = ParamUri( req )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )

    if( doc = 0 ) then
        LogWarn( "didSave for a document that is not open: " & uriText )
        return JsonNode( )
    end if

    dim as JsonValue textVal = req.Params( ).Member( "text" )
    if( textVal.IsString( ) ) then
        doc->ReplaceAll( textVal.AsString( ), doc->Version( ) )
    end if

    doc->MarkSaved( )

    LogInfo( "saved " & DescribeDoc( doc ) )
    srv.SendTrace( "didSave " & UriFileName( uriText ), DescribeDoc( doc ) )
    PublishDocumentDiagnostics( srv, doc )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------
''  textDocument/didClose
''
''  After this the file on disk becomes the truth again, and everything the
''  server cached for this buffer is released.
'' ----------------------------------------------------------------------------
private function OnDidClose( byref srv as Server, _
                             byref req as RpcMessage, _
                             byref rb as JsonBuilder, _
                             byref err_ as RpcError ) as JsonNode

    dim as string uriText = ParamUri( req )

    if( srv.Documents.Close( uriText ) = false ) then
        LogWarn( "didClose for a document that is not open: " & uriText )
        return JsonNode( )
    end if

    '' The buffer is gone, so the index goes back to what is on disk. If the
    '' file is not there -- an untitled document, or one that was deleted --
    '' it leaves the index entirely.
    if( srv.Index->IndexOfUri( uriText ) >= 0 ) then
        dim as string path_ = UriToPath( uriText )
        dim as boolean reread = false
        if( len(path_) > 0 ) then reread = srv.Index->IndexPath( path_ )
        if( reread = false ) then srv.Index->Remove( uriText )
        srv.Index->ResolveIncludes( )
    end if

    LogInfo( "closed " & UriFileName( uriText ) & ", " & srv.Documents.Count( ) & " still open" )
    srv.SendTrace( "didClose " & UriFileName( uriText ), _
                   srv.Documents.Count( ) & " document(s) still open" )

    '' An empty list is what clears the editor's squiggles. Without it they
    '' stay on screen for a file that is no longer open.
    ClearDocumentDiagnostics( srv, uriText )
    return JsonNode( )
end function

'' ----------------------------------------------------------------------------

sub RegisterTextDocumentHandlers( )
    RegisterHandler( LSP_DID_OPEN,   @OnDidOpen )
    RegisterHandler( LSP_DID_CHANGE, @OnDidChange )
    RegisterHandler( LSP_DID_SAVE,   @OnDidSave )
    RegisterHandler( LSP_DID_CLOSE,  @OnDidClose )
end sub
