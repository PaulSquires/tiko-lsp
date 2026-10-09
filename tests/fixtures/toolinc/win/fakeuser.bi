'' A stand-in for win/winuser.bi.

'' Shows a message box.
declare function MessageBoxW( byval hWnd as any ptr, byval lpText as const wstring ptr, _
                              byval lpCaption as const wstring ptr, byval uType as ulong ) as long

declare function OnlyInTheToolchain( ) as long
