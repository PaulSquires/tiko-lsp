'' ############################################################################
''  utils/process.bas -- running a tool and keeping what it says. See process.bi.
'' ############################################################################

#include once "process.bi"

#ifdef __FB_WIN32__

#include once "windows.bi"

'' One argument as CommandLineToArgvW reads it back: bare when it can be, else quoted,
'' with the backslashes before a quote -- and before the closing one -- doubled.
private function QuoteArg( byref a as string ) as string
    if( len(a) > 0 andalso instr( a, any " " & chr(9) & chr(34) ) = 0 ) then return a
    dim as string r = chr(34)
    dim as long slashes = 0
    for i as long = 0 to len(a) - 1
        dim as ubyte c = a[i]
        if( c = asc( "\" ) ) then
            slashes += 1
            continue for
        end if
        if( c = 34 ) then
            r &= string( slashes * 2 + 1, "\" ) & chr(34)
        else
            r &= string( slashes, "\" ) & chr(c)
        end if
        slashes = 0
    next
    return r & string( slashes * 2, "\" ) & chr(34)
end function

private function Utf8ToWide( byref s as string ) as wstring ptr
    dim as long n = MultiByteToWideChar( CP_UTF8, 0, strptr( s ), len(s), 0, 0 )
    dim as wstring ptr w = callocate( (n + 1) * sizeof( wstring ) )
    if( n > 0 ) then MultiByteToWideChar( CP_UTF8, 0, strptr( s ), len(s), w, n )
    return w
end function

'' Whatever the pipe holds now, appended to `acc`, without blocking. False once the
'' writing end is closed and nothing is left: the child has exited or closed it.
private function DrainPipe( byval h as HANDLE, byref acc as string ) as boolean
    dim as DWORD avail = 0
    if( PeekNamedPipe( h, 0, 0, 0, @avail, 0 ) = 0 ) then return false
    while( avail > 0 )
        dim as string buf = space( iif( avail > 65536, 65536, avail ) )
        dim as DWORD got = 0
        if( ReadFile( h, strptr( buf ), len(buf), @got, 0 ) = 0 ) then return false
        acc &= left( buf, got )
        avail -= got
    wend
    return true
end function

function RunCaptured( byref exe as string, byref args as FB.Array( of string ), _
                      byref cwd as string, byval timeoutMs as long ) as ProcessResult
    dim as ProcessResult r

    dim as SECURITY_ATTRIBUTES sa
    sa.nLength = sizeof( sa )
    sa.bInheritHandle = TRUE

    dim as HANDLE outR, outW, errR, errW
    if( CreatePipe( @outR, @outW, @sa, 0 ) = 0 ) then return r
    if( CreatePipe( @errR, @errW, @sa, 0 ) = 0 ) then
        CloseHandle( outR )
        CloseHandle( outW )
        return r
    end if
    '' The parent's ends are not inherited: a child holding a copy of the read end would
    '' keep it open, and the write ends would never report the child's exit.
    SetHandleInformation( outR, HANDLE_FLAG_INHERIT, 0 )
    SetHandleInformation( errR, HANDLE_FLAG_INHERIT, 0 )
    dim as wstring * 4 nulName = "NUL"
    dim as HANDLE nul = CreateFileW( @nulName, GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE, _
                                     @sa, OPEN_EXISTING, 0, 0 )

    dim as STARTUPINFOW si
    si.cb = sizeof( si )
    si.dwFlags = STARTF_USESTDHANDLES
    si.hStdInput  = nul
    si.hStdOutput = outW
    si.hStdError  = errW

    dim as string cmd = QuoteArg( exe )
    for i as long = 0 to args.Count( ) - 1
        cmd &= " " & QuoteArg( args[i] )
    next
    dim as wstring ptr wexe = Utf8ToWide( exe )
    dim as wstring ptr wcmd = Utf8ToWide( cmd )
    dim as wstring ptr wcwd = iif( len(cwd) > 0, Utf8ToWide( cwd ), 0 )

    dim as PROCESS_INFORMATION pi
    dim as BOOL ok = CreateProcessW( wexe, wcmd, 0, 0, TRUE, CREATE_NO_WINDOW, 0, wcwd, @si, @pi )
    deallocate( wexe )
    deallocate( wcmd )
    if( wcwd <> 0 ) then deallocate( wcwd )
    CloseHandle( outW )
    CloseHandle( errW )
    if( nul <> INVALID_HANDLE_VALUE ) then CloseHandle( nul )
    if( ok = 0 ) then
        CloseHandle( outR )
        CloseHandle( errR )
        return r
    end if
    r.Started = true

    '' Both pipes are drained while the child runs: one read to the end before the other
    '' would deadlock a child that fills the second pipe's buffer first.
    dim as double deadline = timer( ) + timeoutMs / 1000
    dim as boolean outOpen = true, errOpen = true
    while( outOpen orelse errOpen )
        dim as long before = len(r.Stdout_) + len(r.Stderr_)
        if( outOpen ) then outOpen = DrainPipe( outR, r.Stdout_ )
        if( errOpen ) then errOpen = DrainPipe( errR, r.Stderr_ )
        if( timer( ) > deadline ) then
            TerminateProcess( pi.hProcess, 1 )
            r.TimedOut = true
            exit while
        end if
        if( len(r.Stdout_) + len(r.Stderr_) = before ) then Sleep_( 5 )
    wend

    WaitForSingleObject( pi.hProcess, 5000 )
    dim as DWORD code = 0
    GetExitCodeProcess( pi.hProcess, @code )
    r.Exit_ = clng( code )
    CloseHandle( pi.hProcess )
    CloseHandle( pi.hThread )
    CloseHandle( outR )
    CloseHandle( errR )
    return r
end function

#else

'' Declared here under names of their own, not through crt/linux/*.bi: two of these
'' collide with names the runtime headers already give something else.
type PrPollFd
    fd      as long
    events  as short
    revents as short
end type

extern "C"
    declare function pr_pipe_   alias "pipe"    ( byval fds as long ptr ) as long
    declare function pr_fork_   alias "fork"    ( ) as long
    declare function pr_dup2_   alias "dup2"    ( byval a as long, byval b as long ) as long
    declare function pr_close_  alias "close"   ( byval fd as long ) as long
    declare function pr_read_   alias "read"    ( byval fd as long, byval buf as any ptr, byval n as uinteger ) as integer
    declare function pr_open_   alias "open"    ( byval path as const zstring ptr, byval flags as long, ... ) as long
    declare function pr_execv_  alias "execv"   ( byval path as const zstring ptr, byval argv as zstring ptr ptr ) as long
    declare function pr_chdir_  alias "chdir"   ( byval path as const zstring ptr ) as long
    declare sub      pr_exit_   alias "_exit"   ( byval code as long )
    declare function pr_wait_   alias "waitpid" ( byval pid as long, byval status as long ptr, byval opts as long ) as long
    declare function pr_kill_   alias "kill"    ( byval pid as long, byval sig as long ) as long
    declare function pr_poll_   alias "poll"    ( byval fds as PrPollFd ptr, byval n as ulong, byval ms as long ) as long
end extern

'' What one ready descriptor holds, appended to `acc`. False at end of file.
private function DrainFd( byval fd as long, byref acc as string ) as boolean
    dim as string buf = space( 65536 )
    dim as integer got = pr_read_( fd, strptr( buf ), len(buf) )
    if( got <= 0 ) then return false
    acc &= left( buf, got )
    return true
end function

function RunCaptured( byref exe as string, byref args as FB.Array( of string ), _
                      byref cwd as string, byval timeoutMs as long ) as ProcessResult
    dim as ProcessResult r
    dim as long po(0 to 1), pe(0 to 1)
    if( pr_pipe_( @po(0) ) <> 0 ) then return r
    if( pr_pipe_( @pe(0) ) <> 0 ) then
        pr_close_( po(0) )
        pr_close_( po(1) )
        return r
    end if

    '' argv is built BEFORE the fork: the child may only call what is async-signal-safe.
    dim as long n = args.Count( )
    dim as zstring ptr ptr argv = callocate( (n + 2) * sizeof( zstring ptr ) )
    dim as string keep( 0 to n )
    keep(0) = exe
    for i as long = 0 to n - 1
        keep(i + 1) = args[i]
    next
    for i as long = 0 to n
        argv[i] = strptr( keep(i) )
    next
    dim as string devnull = "/dev/null"

    dim as long pid = pr_fork_( )
    if( pid = 0 ) then
        dim as long nfd = pr_open_( strptr( devnull ), 0 )
        if( nfd >= 0 ) then pr_dup2_( nfd, 0 )
        pr_dup2_( po(1), 1 )
        pr_dup2_( pe(1), 2 )
        pr_close_( po(0) )
        pr_close_( pe(0) )
        if( len(cwd) > 0 ) then
            if( pr_chdir_( strptr( cwd ) ) <> 0 ) then pr_exit_( 127 )
        end if
        pr_execv_( strptr( keep(0) ), argv )
        pr_exit_( 127 )
    end if
    deallocate( argv )
    pr_close_( po(1) )
    pr_close_( pe(1) )
    if( pid < 0 ) then
        pr_close_( po(0) )
        pr_close_( pe(0) )
        return r
    end if
    r.Started = true

    dim as double deadline = timer( ) + timeoutMs / 1000
    dim as boolean outOpen = true, errOpen = true
    while( outOpen orelse errOpen )
        dim as PrPollFd fds(0 to 1)
        dim as long nf = 0
        if( outOpen ) then
            fds(nf).fd = po(0)
            fds(nf).events = 1           '' POLLIN
            nf += 1
        end if
        if( errOpen ) then
            fds(nf).fd = pe(0)
            fds(nf).events = 1
            nf += 1
        end if
        dim as long left_ = clng( (deadline - timer( )) * 1000 )
        if( left_ <= 0 ) then
            pr_kill_( pid, 9 )
            r.TimedOut = true
            exit while
        end if
        if( pr_poll_( @fds(0), nf, left_ ) <= 0 ) then continue while
        for k as long = 0 to nf - 1
            if( fds(k).revents = 0 ) then continue for
            if( fds(k).fd = po(0) ) then
                outOpen = DrainFd( po(0), r.Stdout_ )
            else
                errOpen = DrainFd( pe(0), r.Stderr_ )
            end if
        next
    wend
    pr_close_( po(0) )
    pr_close_( pe(0) )

    dim as long status = 0
    pr_wait_( pid, @status, 0 )
    if( (status and &h7F) = 0 ) then r.Exit_ = (status shr 8) and &hFF else r.Exit_ = -1
    return r
end function

#endif
