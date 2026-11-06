' A stand-in for a toolchain header (inc/fb/...), found through TIKO_INCLUDE.
namespace FB

'' Joins two paths.
declare function PathJoin( byref a as string, byref b as string ) as string

declare function Hidden( ) as long

end namespace
