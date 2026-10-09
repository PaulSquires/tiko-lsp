'' A stand-in for win/winuser.bi.

'' Shows a message box.
declare function MessageBoxW( byval hWnd as any ptr, byval lpText as const wstring ptr, _
                              byval lpCaption as const wstring ptr, byval uType as ulong ) as long

declare function OnlyInTheToolchain( ) as long

'' A generic type in a namespace, the shape of fb/result.bi's FB.Result.
namespace FB
type Box( of T )
    declare function Get( ) as T
    declare function IsEmpty( ) as boolean
end type

'' Declared the way fb/*.bi declares: modifiers BEFORE the parameter list.
declare function Shout overload alias "fb_Shout" ( byref s as const string, byval times as long ) as string

'' A type behind a FORWARD ALIAS, the shape of fb/logger.bi's `type Logger as Logger_`.
type Gadget as Gadget_
type Gadget_
    Speed as long
    declare constructor( )
    declare destructor( )
    declare sub Spin( )
    declare operator let( byref other as Gadget_ )
end type
end namespace
