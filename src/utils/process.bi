'' ############################################################################
''  utils/process.bi -- running a tool and keeping what it says
''
''  ONE USE, so far: `tiko metadata` (workspace/metadata.bi). The rule it is
''  built around is the server's own: STDOUT CARRIES THE PROTOCOL. A child that
''  inherited it would write into the client's message stream, so neither of
''  the child's output streams is ever the server's -- both are pipes, read
''  here, and stdin is the null device. On Windows the child gets no console
''  window either: the server usually has none, and a console program started
''  without one would open its own.
'' ############################################################################

#pragma once


'' What came back. `Exit_` is the child's exit code; `Started` is false when it
'' could not be run at all, and `TimedOut` true when it was killed for taking
'' longer than it was given.
type ProcessResult
    Started  as boolean
    TimedOut as boolean
    Exit_    as long
    Stdout_  as string
    Stderr_  as string
end type

'' Runs `exe` with `args` -- each passed as ONE argument, quoted here as the
'' platform needs -- in the directory `cwd` ("" = the server's own), and waits for
'' it, at most `timeoutMs`. Paths are UTF-8.
declare function RunCaptured( byref exe as string, byref args as containers.Array( of string ), _
                              byref cwd as string, byval timeoutMs as long ) as ProcessResult
