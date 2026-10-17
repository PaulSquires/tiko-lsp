'' ############################################################################
''  handlers/formatting.bas -- textDocument/formatting and rangeFormatting
''
''  Both requests are the same engine; the range one just narrows which lines
''  produce edits. The structure is always computed from the whole document --
''  a range has no way of knowing how deep it already is.
''
''  A REFUSAL IS AN EMPTY EDIT LIST, NOT AN ERROR. When the parser reported a
''  structural problem the indentation is unknown, and an editor that formats
''  on save must not get an error dialog for it: it gets no edits, the file is
''  saved unchanged, and the reason goes to the log.
'' ############################################################################

#import "std/containers"
#include once "formatting.bi"
#include once "../analysis/format.bi"
#include once "../utils/logging.bi"

'' Reads LSP's FormattingOptions, which carries the user's editor settings.
private function ReadOptions( byref opts as JsonValue ) as FormatOptions
    dim as FormatOptions o = DefaultFormatOptions( )

    if( opts.IsObject( ) = false ) then return o

    dim as longint tabs = opts.Member( "tabSize" ).AsLongInt( 4 )
    if( tabs >= 1 andalso tabs <= 16 ) then o.TabSize = clng( tabs )

    o.InsertSpaces           = opts.Member( "insertSpaces"           ).AsBoolean( true )
    o.TrimTrailingWhitespace = opts.Member( "trimTrailingWhitespace" ).AsBoolean( true )
    o.InsertFinalNewline     = opts.Member( "insertFinalNewline"     ).AsBoolean( false )
    o.TrimFinalNewlines      = opts.Member( "trimFinalNewlines"      ).AsBoolean( false )
    return o
end function

private function BuildEdits( byref rb as JsonBuilder, byref edits as TextEditArray ) as JsonNode
    dim as JsonNode arr = rb.NewArray( )

    for i as long = 0 to edits.Count( ) - 1
        dim as JsonNode start_ = rb.NewObject( )
        rb.SetInt( start_, "line", edits[i].StartLine )
        rb.SetInt( start_, "character", edits[i].StartChar )

        dim as JsonNode end_ = rb.NewObject( )
        rb.SetInt( end_, "line", edits[i].EndLine )
        rb.SetInt( end_, "character", edits[i].EndChar )

        dim as JsonNode range_ = rb.NewObject( )
        rb.SetNode( range_, "start", start_ )
        rb.SetNode( range_, "end", end_ )

        dim as JsonNode e = rb.NewObject( )
        rb.SetNode( e, "range", range_ )
        rb.SetStr ( e, "newText", edits[i].NewText )

        rb.PushNode( arr, e )
    next

    return arr
end function

private function FormatLines( byref srv as Server, byref req as RpcMessage, _
                              byref rb as JsonBuilder, _
                              byval firstLine as long, byval lastLine as long ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as TextDocumentPtr doc = srv.Documents.Find( uriText )
    if( doc = 0 ) then return rb.NewArray( )

    dim as FormatOptions opts = ReadOptions( req.Params( ).Member( "options" ) )

    dim edits as TextEditArray
    dim as string reason
    dim as double started = timer( )

    if( ComputeFormatEdits( doc->Text( ), doc->Index( ), opts, firstLine, lastLine, edits, reason ) = false ) then
        LogInfo( "formatting refused for " & uriText & ": " & reason )
        return rb.NewArray( )
    end if

    LogDebug( "formatting: " & edits.Count( ) & " edit(s), " & _
              int( (timer( ) - started) * 1000 ) & " ms" )
    return BuildEdits( rb, edits )
end function

private function OnFormatting( byref srv as Server, _
                               byref req as RpcMessage, _
                               byref rb as JsonBuilder, _
                               byref err_ as RpcError ) as JsonNode
    return FormatLines( srv, req, rb, 0, -1 )
end function

private function OnRangeFormatting( byref srv as Server, _
                                    byref req as RpcMessage, _
                                    byref rb as JsonBuilder, _
                                    byref err_ as RpcError ) as JsonNode

    dim as JsonValue rangeVal = req.Params( ).Member( "range" )
    dim as long fromLine = clng( rangeVal.Member( "start" ).Member( "line" ).AsLongInt( 0 ) )
    dim as long toLine   = clng( rangeVal.Member( "end"   ).Member( "line" ).AsLongInt( 0 ) )

    '' A selection that ends at character 0 of a line does not include that
    '' line, and reformatting it would move a line the user did not select.
    if( rangeVal.Member( "end" ).Member( "character" ).AsLongInt( 0 ) = 0 andalso toLine > fromLine ) then
        toLine -= 1
    end if

    return FormatLines( srv, req, rb, fromLine, toLine )
end function

sub RegisterFormattingHandlers( )
    RegisterHandler( LSP_FORMATTING,       @OnFormatting )
    RegisterHandler( LSP_RANGE_FORMATTING, @OnRangeFormatting )
end sub
