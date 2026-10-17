#!/bin/sh
# ============================================================================
#  Build bin/tiko-lsp (Linux x64).
#
#  Requires:
#    tiko         $TIKO_LSP_TIKO or ../tiko-lang/toolchains/tiko-linux/bin/tiko
#    yyjson       $YYJSON with lib/linux64/libyyjson64.a
#                 (build it once with build/_build_yyjson_linux.sh)
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TIKO=${TIKO_LSP_TIKO:-"$ROOT/../tiko-lang/toolchains/tiko-linux/bin/tiko"}
YYJSON=${TIKO_LSP_YYJSON:-"$ROOT/../yyjson"}

[ -x "$TIKO" ] || TIKO=$(command -v tiko || true)
if [ -z "$TIKO" ] || [ ! -x "$TIKO" ]; then
    echo "tiko not found -- set TIKO_LSP_TIKO to the tiko compiler." >&2
    exit 1
fi

if [ ! -f "$YYJSON/lib/linux64/libyyjson64.a" ]; then
    echo "libyyjson64.a missing -- run build/_build_yyjson_linux.sh first." >&2
    exit 1
fi

mkdir -p "$ROOT/bin"

echo "Building tiko-lsp"
"$TIKO" -w all -mt \
    -i "$YYJSON/inc" -p "$YYJSON/lib/linux64" \
    "$ROOT/src/main.tiko" \
    "$ROOT/src/json/json.tiko" \
    "$ROOT/src/rpc/transport.tiko" \
    "$ROOT/src/rpc/jsonrpc.tiko" \
    "$ROOT/src/lsp/protocol.tiko" \
    "$ROOT/src/lsp/dispatcher.tiko" \
    "$ROOT/src/lsp/publish.tiko" \
    "$ROOT/src/handlers/lifecycle.tiko" \
    "$ROOT/src/handlers/text_document.tiko" \
    "$ROOT/src/handlers/document_symbols.tiko" \
    "$ROOT/src/handlers/hover.tiko" \
    "$ROOT/src/handlers/definition.tiko" \
    "$ROOT/src/handlers/completion.tiko" \
    "$ROOT/src/handlers/workspace_symbols.tiko" \
    "$ROOT/src/handlers/references.tiko" \
    "$ROOT/src/handlers/rename.tiko" \
    "$ROOT/src/handlers/signature_help.tiko" \
    "$ROOT/src/handlers/semantic_tokens.tiko" \
    "$ROOT/src/handlers/inlay_hints.tiko" \
    "$ROOT/src/handlers/formatting.tiko" \
    "$ROOT/src/handlers/code_action.tiko" \
    "$ROOT/src/handlers/watched_files.tiko" \
    "$ROOT/src/handlers/tiko_metadata.tiko" \
    "$ROOT/src/document/document.tiko" \
    "$ROOT/src/document/document_manager.tiko" \
    "$ROOT/src/analysis/lexer.tiko" \
    "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" \
    "$ROOT/src/analysis/completion.tiko" \
    "$ROOT/src/analysis/includes.tiko" \
    "$ROOT/src/analysis/signature.tiko" \
    "$ROOT/src/analysis/semantic.tiko" \
    "$ROOT/src/analysis/format.tiko" \
    "$ROOT/src/workspace/workspace.tiko" \
    "$ROOT/src/workspace/symbol_index.tiko" \
    "$ROOT/src/workspace/modules.tiko" \
    "$ROOT/src/workspace/index_builder.tiko" \
    "$ROOT/src/workspace/metadata.tiko" \
    "$ROOT/src/workspace/cincludes.tiko" \
    "$ROOT/src/utils/process.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" \
    "$ROOT/src/utils/logging.tiko" \
    "$ROOT/src/utils/position.tiko" \
    "$ROOT/src/utils/uri.tiko" \
    -x "$ROOT/bin/tiko-lsp"

echo "Built $ROOT/bin/tiko-lsp"
