' A stand-in toolchain PACKAGE beside tests/fixtures/toolinc -- found as <inc>/../pkg with no
' packagePaths configured. A facade, as tiko-lang's std modules are (RFC-0009): a header
' included and a name re-exported, plus a public function. Read by tests/session_tool.bas.
#module "demo"
#include once "win/fakeuser.bi"
#define Shout FB.Shout
#export Shout

public function Twice( byval n as long, byval scale as long = 2 ) as long
    return n * scale
end function
