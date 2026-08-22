#!/bin/sh
# ============================================================================
#  Build a static libyyjson64.a for Linux.
#
#  The yyjson repository ships a Windows DLL and its import library only. The
#  FreeBASIC bindings say `#inclib "yyjson64"`, so on Linux fbc looks for
#  libyyjson64.a on the library path -- this script produces exactly that from
#  the same two C files the Windows DLL is built from.
#
#  Run once, then build\_compile.sh will find it.
#
#    YYJSON   path to the yyjson checkout   (default: ../../yyjson)
#    CC       C compiler                    (default: cc)
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
YYJSON=${YYJSON:-$(cd "$ROOT/../yyjson" 2>/dev/null && pwd)}
CC=${CC:-cc}

if [ ! -f "$YYJSON/src/yyjson.c" ]; then
    echo "yyjson sources not found under '$YYJSON' -- set YYJSON to the checkout." >&2
    exit 1
fi

OUT="$YYJSON/lib/linux64"
OBJ="$YYJSON/obj/linux64"
mkdir -p "$OUT" "$OBJ"

CFLAGS="-O2 -fPIC -Wall -Wextra -I$YYJSON/src"

echo "[1/3] compiling yyjson.c"
$CC -c $CFLAGS "$YYJSON/src/yyjson.c" -o "$OBJ/yyjson.o"

# The shim exports yyjson's `static inline` API under fby_ names, which is what
# the FreeBASIC `alias` clauses call. Without it most of the API is missing.
echo "[2/3] compiling yyjson_fb.c (export shim)"
$CC -c $CFLAGS "$YYJSON/src/yyjson_fb.c" -o "$OBJ/yyjson_fb.o"

echo "[3/3] archiving libyyjson64.a"
rm -f "$OUT/libyyjson64.a"
ar rcs "$OUT/libyyjson64.a" "$OBJ/yyjson.o" "$OBJ/yyjson_fb.o"

echo "Built $OUT/libyyjson64.a"
