'' ############################################################################
''  utils/logging.bas -- implementation of the logging facade
'' ############################################################################

#import "std/containers"
#import "std/strings"
#include once "crt.bi"
#include once "logging.bi"

using strings

'' ----------------------------------------------------------------------------
''  Module state.
''
''  A logger is one of the few places a global is the right answer: every
''  module logs, and threading a logger through every call signature would buy
''  nothing. It is initialised exactly once, from main, before anything else
''  runs.
'' ----------------------------------------------------------------------------
dim shared as LspLogLevel g_LogLevel = LSPLOG_ERROR
dim shared as FILE ptr    g_LogFile              '' CRT stream, NULL = none
dim shared as string      g_LogPath

private function TimeStamp( ) as string
    '' Local date and time with milliseconds. TIMER is seconds-since-midnight
    '' as a double on every target, which is where the sub-second part comes
    '' from -- FreeBASIC's TIME$ has one-second resolution.
    dim as double t = timer( )
    dim as long ms = culng( (t - int(t)) * 1000.0 ) mod 1000
    return date( ) & " " & time( ) & "." & PadLeft( str(ms), 3, "0" )
end function

sub LogInit( byval level as LspLogLevel, byref filePath as string = "" )
    LogClose( )

    g_LogLevel = level
    if( len(filePath) = 0 orelse level = LSPLOG_OFF ) then exit sub

    '' "a", not "w": several editor windows may launch several servers against
    '' the same configured path, and truncating loses the other one.
    g_LogFile = fopen( strptr(filePath), "a" )
    if( g_LogFile <> NULL ) then
        g_LogPath = filePath
    else
        '' Losing the file is not fatal -- stderr still works. Say so there.
        fprintf( stderr, !"[fblsp] cannot open log file: %s\n", strptr(filePath) )
    end if
end sub

sub LogClose( )
    if( g_LogFile <> NULL ) then
        fclose( g_LogFile )
        g_LogFile = NULL
    end if
    g_LogPath = ""
end sub

function LogLevelFromName( byref levelName as string ) as LspLogLevel
    select case lcase( trim(levelName) )
        case "off", "none"      : return LSPLOG_OFF
        case "error"            : return LSPLOG_ERROR
        case "warn", "warning"  : return LSPLOG_WARN
        case "info"             : return LSPLOG_INFO
        case "debug"            : return LSPLOG_DEBUG
        case "trace", "verbose" : return LSPLOG_TRACE
    end select
    return LSPLOG_ERROR
end function

function LogLevelName( byval level as LspLogLevel ) as string
    select case level
        case LSPLOG_OFF   : return "OFF"
        case LSPLOG_ERROR : return "ERROR"
        case LSPLOG_WARN  : return "WARN"
        case LSPLOG_INFO  : return "INFO"
        case LSPLOG_DEBUG : return "DEBUG"
        case LSPLOG_TRACE : return "TRACE"
    end select
    return "?"
end function

function LogIsEnabled( byval level as LspLogLevel ) as boolean
    return (level <> LSPLOG_OFF) andalso (level <= g_LogLevel)
end function

function LogFilePath( ) as string
    return g_LogPath
end function

sub LogWrite( byval level as LspLogLevel, byref msg as string )
    if( LogIsEnabled( level ) = false ) then exit sub

    dim as string line_ = TimeStamp( ) & "  " & PadRight( LogLevelName(level), 5 ) & "  " & msg

    '' stderr always: editors surface it, and it needs no configuration.
    fprintf( stderr, !"%s\n", strptr(line_) )

    if( g_LogFile <> NULL ) then
        fprintf( g_LogFile, !"%s\n", strptr(line_) )
        '' Flushed per record on purpose. A language server that crashes is
        '' exactly when the log matters, and buffered lines would be lost.
        fflush( g_LogFile )
    end if
end sub

sub LogError( byref msg as string ) : LogWrite( LSPLOG_ERROR, msg ) : end sub
sub LogWarn ( byref msg as string ) : LogWrite( LSPLOG_WARN,  msg ) : end sub
sub LogInfo ( byref msg as string ) : LogWrite( LSPLOG_INFO,  msg ) : end sub
sub LogDebug( byref msg as string ) : LogWrite( LSPLOG_DEBUG, msg ) : end sub
sub LogTrace( byref msg as string ) : LogWrite( LSPLOG_TRACE, msg ) : end sub
