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
end namespace
