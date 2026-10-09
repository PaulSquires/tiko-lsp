'' A workspace header: its sub is called from app.bas, another file.
declare sub Helper( byval count as long, byref label as string )

'' A workspace alias of a toolchain generic: `b.` must reach FB.Box's members.
type IntBox as FB.Box( of long )
