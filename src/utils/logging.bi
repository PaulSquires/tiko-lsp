'' ############################################################################
''  utils/logging.bi -- diagnostic logging for the language server
''
''  THE ONE RULE: nothing here may ever write to stdout. stdout carries the
''  LSP wire protocol, and a single stray PRINT desynchronises the framing so
''  the editor drops the connection with no useful error. Every sink here is
''  either stderr or a log file the user asked for.
'' ############################################################################

#pragma once

'' Ordered by increasing verbosity, so `level <= g_LogLevel` is the filter.
enum LspLogLevel
    LSPLOG_OFF   = 0
    LSPLOG_ERROR = 1
    LSPLOG_WARN  = 2
    LSPLOG_INFO  = 3
    LSPLOG_DEBUG = 4
    LSPLOG_TRACE = 5
end enum

declare sub LogInit( byval level as LspLogLevel, byref filePath as string = "" )
declare sub LogClose( )

declare function LogLevelFromName( byref levelName as string ) as LspLogLevel
declare function LogLevelName( byval level as LspLogLevel ) as string
declare function LogIsEnabled( byval level as LspLogLevel ) as boolean
declare function LogFilePath( ) as string

declare sub LogWrite( byval level as LspLogLevel, byref msg as string )

declare sub LogError( byref msg as string )
declare sub LogWarn( byref msg as string )
declare sub LogInfo( byref msg as string )
declare sub LogDebug( byref msg as string )
declare sub LogTrace( byref msg as string )
