#!/bin/sh
# ============================================================================
#  Build a static libyyjson64.a for Windows x64 (the windows-x86_64 target,
#  MSVC ABI), so tiko-lsp.exe links yyjson in and needs no yyjson64.dll.
#
#  Run from Git Bash. Writes obj/yyjson-static/libyyjson64.a; point the build
#  at that directory with TIKO_LSP_YYJSON_LIB (see build/_compile.bat).
#
#  The objects come from the same two C files as the DLL, compiled by the
#  clang tiko itself links with, so the archive is COFF and calls the C library
#  the program already imports from ucrtbase.dll. Two details matter:
#
#    - yyjson_fb.c marks every wrapper __declspec(dllexport). Linked into an
#      exe that would give tiko-lsp.exe an export table, and lld-link would
#      write a tiko-lsp.lib/.exp beside it. A copy with the attribute removed
#      is compiled instead; the source is a generated file, so it is never
#      edited in place.
#    - clang -c leaves no /DEFAULTLIB directive in the objects, so nothing
#      drags in a second C runtime (libcmt) beside ucrtbase. The release build
#      checks the exe's imports to keep it that way.
#
#    YYJSON     path to the yyjson checkout     (default: ../../yyjson)
#    TKO_CLANG  clang.exe                       (default: C:/Program Files/LLVM/bin/clang.exe)
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
YYJSON=${YYJSON:-${TIKO_LSP_YYJSON:-$(cd "$ROOT/../yyjson" 2>/dev/null && pwd)}}
CLANG=${TKO_CLANG:-"C:/Program Files/LLVM/bin/clang.exe"}
AR="$(dirname "$CLANG")/llvm-ar.exe"

if [ ! -f "$YYJSON/src/yyjson.c" ]; then
    echo "yyjson sources not found under '$YYJSON' -- set YYJSON to the checkout." >&2
    exit 1
fi
if [ ! -x "$CLANG" ] || [ ! -x "$AR" ]; then
    echo "clang or llvm-ar not found beside '$CLANG' -- set TKO_CLANG." >&2
    exit 1
fi

OUT="$ROOT/obj/yyjson-static"
mkdir -p "$OUT"

CFLAGS="-target x86_64-pc-windows-msvc -O2 -I$YYJSON/src"

echo "[1/3] compiling yyjson.c"
"$CLANG" $CFLAGS -c "$YYJSON/src/yyjson.c" -o "$OUT/yyjson.o"

echo "[2/3] compiling yyjson_fb.c without dllexport"
sed 's/__declspec(dllexport)//' "$YYJSON/src/yyjson_fb.c" > "$OUT/yyjson_fb_static.c"
if grep -q dllexport "$OUT/yyjson_fb_static.c"; then
    echo "dllexport survived the rewrite of yyjson_fb.c" >&2
    exit 1
fi
"$CLANG" $CFLAGS -c "$OUT/yyjson_fb_static.c" -o "$OUT/yyjson_fb.o"

echo "[3/3] archiving libyyjson64.a"
rm -f "$OUT/libyyjson64.a"
"$AR" rcs "$OUT/libyyjson64.a" "$OUT/yyjson.o" "$OUT/yyjson_fb.o"

echo "Built $OUT/libyyjson64.a"
