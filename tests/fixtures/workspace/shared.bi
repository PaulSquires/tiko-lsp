'' Types shared across the fixture workspace.
type Widget
    Label_ as string
    Size_ as long
end type

declare function MakeWidget( byref label_ as string ) as Widget
const WIDGET_LIMIT = 32
