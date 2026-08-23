'' ############################################################################
''  main.bas -- tiko-lsp, a Language Server Protocol server for fbc-modern
''
''  Phases 1-6: transport, JSON-RPC, dispatcher, lifecycle, document sync,
''  analysis, the language features built on it, and the workspace index.
''
''  The whole program is one thread and one loop: read a framed message,
''  dispatch it, write the response. Analysis work moves off this loop in a
''  later phase; until then the simplest correct thing is also the fastest.
''
''  STDOUT BELONGS TO THE PROTOCOL. Nothing in this program prints to it.
'' ############################################################################

#include once "crt.bi"
#include once "fb/string.bi"

#include once "utils/logging.bi"
#include once "json/json.bi"
#include once "rpc/transport.bi"
#include once "rpc/jsonrpc.bi"
#include once "lsp/protocol.bi"
#include once "lsp/dispatcher.bi"
#include once "handlers/lifecycle.bi"
#include once "handlers/text_document.bi"
#include once "handlers/document_symbols.bi"
#include once "handlers/hover.bi"
#include once "handlers/definition.bi"
#include once "handlers/completion.bi"
#include once "handlers/workspace_symbols.bi"
#include once "handlers/references.bi"
#include once "handlers/rename.bi"
#include once "handlers/signature_help.bi"
#include once "handlers/semantic_tokens.bi"
#include once "handlers/inlay_hints.bi"
#include once "handlers/formatting.bi"
#include once "handlers/code_action.bi"
#include once "workspace/index_builder.bi"

using FB

'' ----------------------------------------------------------------------------
''  Command line
'' ----------------------------------------------------------------------------
type CmdOptions
    LogLevel  as LspLogLevel
    LogPath   as string
    ShowHelp  as boolean
    ShowVers  as boolean
    BadOption as string
end type

'' Usage goes to stderr, not stdout: an editor that launches the server with a
'' bad argument would otherwise receive the help text as protocol data.
private sub PrintUsage( )
    fprintf( stderr, !"%s %s -- Language Server Protocol server for fbc-modern\n\n", _
             LSP_SERVER_NAME, LSP_SERVER_VERSION )
    fprintf( stderr, !"Usage: tiko-lsp [options]\n\n" )
    fprintf( stderr, !"  --stdio                 communicate over stdin/stdout (default)\n" )
    fprintf( stderr, !"  --log-level <level>     off|error|warn|info|debug|trace (default: error)\n" )
    fprintf( stderr, !"  --log-file <path>       append diagnostics to this file as well as stderr\n" )
    fprintf( stderr, !"  --version               print the version and exit\n" )
    fprintf( stderr, !"  --help                  print this text and exit\n\n" )
    fprintf( stderr, !"Environment: TIKO_LSP_LOG_LEVEL, TIKO_LSP_LOG_FILE (overridden by the flags)\n" )
end sub

private function ParseCommandLine( ) as CmdOptions
    dim as CmdOptions opts

    '' Environment first, so an explicit flag always wins.
    dim as string envLevel = environ( "TIKO_LSP_LOG_LEVEL" )
    opts.LogLevel = iif( len(envLevel) > 0, LogLevelFromName( envLevel ), LSPLOG_ERROR )
    opts.LogPath  = environ( "TIKO_LSP_LOG_FILE" )

    dim as long i = 1
    do
        dim as string arg = command( i )
        if( len(arg) = 0 ) then exit do

        dim as string key_ = arg
        dim as string inlineVal = ""
        dim as long eqAt = instr( arg, "=" )
        if( eqAt > 0 ) then
            key_      = left( arg, eqAt - 1 )
            inlineVal = mid( arg, eqAt + 1 )
        end if

        select case lcase( key_ )
            case "--stdio"
                '' Accepted for compatibility with editor configurations that
                '' always pass it. stdio is the only transport this server has.

            case "--log-level"
                if( len(inlineVal) = 0 ) then
                    i += 1
                    inlineVal = command( i )
                end if
                opts.LogLevel = LogLevelFromName( inlineVal )

            case "--log-file"
                if( len(inlineVal) = 0 ) then
                    i += 1
                    inlineVal = command( i )
                end if
                opts.LogPath = inlineVal

            case "--version", "-v"
                opts.ShowVers = true

            case "--help", "-h", "-?", "/?"
                opts.ShowHelp = true

            case else
                opts.BadOption = arg
        end select

        i += 1
    loop

    return opts
end function

'' ----------------------------------------------------------------------------
''  The message loop
'' ----------------------------------------------------------------------------
private function RunServer( ) as long
    dim as StdioTransport tp
    dim as Server srv

    srv.Attach( @tp )
    RegisterLifecycleHandlers( )
    RegisterTextDocumentHandlers( )
    RegisterDocumentSymbolHandlers( )
    RegisterHoverHandlers( )
    RegisterDefinitionHandlers( )
    RegisterCompletionHandlers( )
    RegisterWorkspaceHandlers( )
    RegisterReferencesHandlers( )
    RegisterRenameHandlers( )
    RegisterSignatureHelpHandlers( )
    RegisterSemanticTokensHandlers( )
    RegisterInlayHintHandlers( )
    RegisterFormattingHandlers( )
    RegisterCodeActionHandlers( )
    LogDebug( RegisteredCount( ) & " methods registered" )

    dim as string payload

    do while srv.IsRunning( )
        dim as TransportStatus st = tp.ReadMessage( payload )

        select case st
            case TRANSPORT_OK
                '' One message is handled to completion before the next is
                '' read: the protocol requires notifications to be applied in
                '' order, and every answer depends on the buffer as the
                '' previous message left it.
                ''
                '' The ONE thing that does not happen here is the workspace
                '' scan -- it runs on its own thread, and only the handful of
                '' requests that need cross-file knowledge ever wait for it.
                '' See workspace/index_builder.bi.
                srv.HandleMessage( payload )

            case TRANSPORT_EOF
                '' The editor closed the pipe without saying `exit`. That is
                '' how a crashed or killed client looks, and the specification
                '' treats it as an error exit.
                LogWarn( "stdin closed without an exit notification" )
                ShutdownIndexBuilder( )
                if( srv.ShutdownReceived( ) ) then return 0
                return 1

            case TRANSPORT_ERROR
                '' A framing error means the byte stream is no longer aligned
                '' to a message boundary; there is nothing to resynchronise
                '' to, so the only honest response is to stop.
                LogError( "transport error: " & tp.ErrorText( ) )
                ShutdownIndexBuilder( )
                return 1
        end select
    loop

    '' EVERY path out of this function stops the worker first. A thread still
    '' walking a directory when the process tears down is how an orderly
    '' shutdown turns into a crash report -- and it would be one the user sees
    '' AFTER asking the editor to quit, which is the worst time to see one.
    ShutdownIndexBuilder( )
    return srv.ExitCode( )
end function

'' ----------------------------------------------------------------------------
''  Entry point
'' ----------------------------------------------------------------------------
dim as CmdOptions opts = ParseCommandLine( )

if( len(opts.BadOption) > 0 ) then
    fprintf( stderr, !"tiko-lsp: unknown option '%s'\n\n", strptr(opts.BadOption) )
    PrintUsage( )
    end 2
end if

if( opts.ShowHelp ) then
    PrintUsage( )
    end 0
end if

if( opts.ShowVers ) then
    fprintf( stderr, !"%s %s (LSP %s, built with FreeBASIC %s)\n", _
             LSP_SERVER_NAME, LSP_SERVER_VERSION, LSP_SPEC_VERSION, __FB_VERSION__ )
    end 0
end if

LogInit( opts.LogLevel, opts.LogPath )
LogInfo( LSP_SERVER_NAME & " " & LSP_SERVER_VERSION & " starting (log level " & _
         LogLevelName( opts.LogLevel ) & ")" )

dim as long code_ = RunServer( )

LogInfo( "exiting with code " & code_ )
LogClose( )

end code_
