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
"$FBC" -w all -mt \
    -i "$YYJSON/inc" -p "$YYJSON/lib/linux64" \
    "$ROOT/src/main.bas" \
    "$ROOT/src/json/json.bas" \
    "$ROOT/src/rpc/transport.bas" \
    "$ROOT/src/rpc/jsonrpc.bas" \
    "$ROOT/src/lsp/protocol.bas" \
    "$ROOT/src/lsp/dispatcher.bas" \
    "$ROOT/src/lsp/publish.bas" \
    "$ROOT/src/handlers/lifecycle.bas" \
    "$ROOT/src/handlers/text_document.bas" \
    "$ROOT/src/handlers/document_symbols.bas" \
    "$ROOT/src/handlers/hover.bas" \
    "$ROOT/src/handlers/definition.bas" \
    "$ROOT/src/handlers/completion.bas" \
    "$ROOT/src/handlers/workspace_symbols.bas" \
    "$ROOT/src/handlers/references.bas" \
    "$ROOT/src/handlers/rename.bas" \
    "$ROOT/src/handlers/signature_help.bas" \
    "$ROOT/src/handlers/semantic_tokens.bas" \
    "$ROOT/src/handlers/inlay_hints.bas" \
    "$ROOT/src/handlers/formatting.bas" \
    "$ROOT/src/handlers/code_action.bas" \
    "$ROOT/src/handlers/watched_files.bas" \
    "$ROOT/src/document/document.bas" \
    "$ROOT/src/document/document_manager.bas" \
    "$ROOT/src/analysis/lexer.bas" \
    "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" \
    "$ROOT/src/analysis/completion.bas" \
    "$ROOT/src/analysis/includes.bas" \
    "$ROOT/src/analysis/signature.bas" \
    "$ROOT/src/analysis/semantic.bas" \
    "$ROOT/src/analysis/format.bas" \
    "$ROOT/src/workspace/workspace.bas" \
    "$ROOT/src/workspace/symbol_index.bas" \
    "$ROOT/src/workspace/modules.bas" \
    "$ROOT/src/workspace/index_builder.bas" \
    "$ROOT/src/analysis/diagnostics.bas" \
    "$ROOT/src/utils/logging.bas" \
    "$ROOT/src/utils/position.bas" \
    "$ROOT/src/utils/uri.bas" \
    -x "$ROOT/bin/tiko-lsp"

echo "Built $ROOT/bin/tiko-lsp"
