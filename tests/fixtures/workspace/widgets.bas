'' A widget factory, for the workspace-index test.
#include once "shared.bi"

function MakeWidget( byref label_ as string ) as Widget
    dim as Widget w
    w.Label_ = label_
    return w
end function
