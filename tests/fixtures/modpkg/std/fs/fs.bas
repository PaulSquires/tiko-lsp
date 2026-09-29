' A FACADE, as tiko-lang's std modules are (RFC-0009): a header included, and its names
' re-exported as macros -- the importer writes fs.PathJoin. Read by tests/test_workspace.bas.
#module "fs"
#include once "fb/fakefs.bi"
#define PathJoin FB.PathJoin
#define IsDir FB.IsDir
#define Hidden FB.Hidden
#define Twice( x ) ( ( x ) * 2 )
#export PathJoin, IsDir, Twice

public function Version( ) as long
    return 1
end function
