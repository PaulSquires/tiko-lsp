'' ############################################################################
''  handlers/tiko_metadata.bas -- `tiko/metadata`. See tiko_metadata.bi.
'' ############################################################################

#include once "tiko_metadata.bi"
#include once "workspace_symbols.bi"
#include once "../workspace/metadata.bi"
#include once "../utils/uri.bi"

private function OnTikoMetadata( byref srv as Server, _
                                 byref req as RpcMessage, _
                                 byref rb as JsonBuilder, _
                                 byref err_ as RpcError ) as JsonNode

    dim as string uriText = req.Params( ).Member( "textDocument" ).Member( "uri" ).AsString( "" )
    dim as string path_ = ""
    if( len(uriText) > 0 ) then
        path_ = UriToPath( uriText )
        if( len(path_) = 0 ) then return rb.NewNull( )
    end if

    '' The answer is read on the index worker, ahead of its scan: a scan still running
    '' is waited for, as every cross-file request waits for it.
    EnsureWorkspaceIndex( srv )

    dim as string md, js
    if( MetadataFor( path_, md, js ) = false ) then return rb.NewNull( )
    dim as JsonDoc doc
    if( doc.Parse( js ) = false ) then return rb.NewNull( )

    dim as JsonNode result_ = rb.NewObject( )
#ifdef __FB_WIN32__
    rb.SetStr( result_, "manifest", PathToUri( md & "\tiko.toml" ) )
#else
    rb.SetStr( result_, "manifest", PathToUri( md & "/tiko.toml" ) )
#endif
    rb.SetNode( result_, "metadata", rb.CopyOf( doc.Root( ) ) )
    return result_
end function

sub RegisterTikoMetadataHandlers( )
    RegisterHandler( LSP_TIKO_METADATA, @OnTikoMetadata )
end sub
