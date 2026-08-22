#!/bin/sh
# ============================================================================
#  Build bin/tiko-lsp (Linux x64).
#
#  Requires:
#    fbc-modern   $FBC or ../fbc-modern/toolchains/fbc-modern-linux/bin/fbc
#    yyjson       $YYJSON with lib/linux64/libyyjson64.a
#                 (build it once with build/_build_yyjson_linux.sh)
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FBC=${TIKO_LSP_FBC:-"$ROOT/../fbc-modern/toolchains/fbc-modern-linux/bin/fbc"}
YYJSON=${TIKO_LSP_YYJSON:-"$ROOT/../yyjson"}

[ -x "$FBC" ] || FBC=$(command -v fbc || true)
if [ -z "$FBC" ] || [ ! -x "$FBC" ]; then
    echo "fbc not found -- set TIKO_LSP_FBC to the fbc-modern compiler." >&2
    exit 1
fi

if [ ! -f "$YYJSON/lib/linux64/libyyjson64.a" ]; then
    echo "libyyjson64.a missing -- run build/_build_yyjson_linux.sh first." >&2
    exit 1
fi

mkdir -p "$ROOT/bin"

echo "Building tiko-lsp"
"$FBC" -w all \
    -i "$YYJSON/inc" -p "$YYJSON/lib/linux64" \
    "$ROOT/src/main.bas" \
    "$ROOT/src/json/json.bas" \
    "$ROOT/src/rpc/transport.bas" \
    "$ROOT/src/rpc/jsonrpc.bas" \
    "$ROOT/src/lsp/protocol.bas" \
    "$ROOT/src/lsp/dispatcher.bas" \
    "$ROOT/src/handlers/lifecycle.bas" \
    "$ROOT/src/handlers/text_document.bas" \
    "$ROOT/src/document/document.bas" \
    "$ROOT/src/document/document_manager.bas" \
    "$ROOT/src/utils/logging.bas" \
    "$ROOT/src/utils/position.bas" \
    "$ROOT/src/utils/uri.bas" \
    -x "$ROOT/bin/tiko-lsp"

echo "Built $ROOT/bin/tiko-lsp"
