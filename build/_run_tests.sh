#!/bin/sh
# ============================================================================
#  Build and run the whole test suite (Linux x64).
#  Mirrors build/_run_tests.bat exactly, including the piped session.
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TIKO=${TIKO_LSP_TIKO:-"$ROOT/../tiko-lang/toolchains/tiko-linux/bin/tiko"}
YYJSON=${TIKO_LSP_YYJSON:-"$ROOT/../yyjson"}

[ -x "$TIKO" ] || TIKO=$(command -v tiko)
INC="-i $YYJSON/inc -p $YYJSON/lib/linux64"
FAILED=0

mkdir -p "$ROOT/bin"

echo "[1/13] building the server"
sh "$ROOT/build/_compile.sh"

echo "[2/13] framing tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_framing.tiko" \
    "$ROOT/src/rpc/transport.tiko" "$ROOT/src/utils/logging.tiko" \
    -x "$ROOT/bin/test_framing"
"$ROOT/bin/test_framing" || FAILED=1

echo "[3/13] json and json-rpc tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_json.tiko" \
    "$ROOT/src/json/json.tiko" "$ROOT/src/rpc/jsonrpc.tiko" "$ROOT/src/utils/logging.tiko" \
    -x "$ROOT/bin/test_json"
"$ROOT/bin/test_json" || FAILED=1

echo "[4/13] position tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_position.tiko" \
    "$ROOT/src/utils/position.tiko" \
    -x "$ROOT/bin/test_position"
"$ROOT/bin/test_position" || FAILED=1

echo "[5/13] uri and document tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_document.tiko" \
    "$ROOT/src/document/document.tiko" "$ROOT/src/document/document_manager.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/completion.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" \
    "$ROOT/src/utils/position.tiko" "$ROOT/src/utils/uri.tiko" "$ROOT/src/utils/logging.tiko" \
    -x "$ROOT/bin/test_document"
"$ROOT/bin/test_document" || FAILED=1

echo "[6/13] lexer and parser tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_analysis.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/completion.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" \
    -x "$ROOT/bin/test_analysis"
# The project root is passed so the suite can analyse this project's OWN
# source and require zero diagnostics from it.
"$ROOT/bin/test_analysis" "$ROOT" || FAILED=1

echo "[7/13] symbol tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_symbols.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/completion.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" \
    -x "$ROOT/bin/test_symbols"
"$ROOT/bin/test_symbols" || FAILED=1

echo "[8/13] completion tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_completion.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/completion.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" \
    -x "$ROOT/bin/test_completion"
"$ROOT/bin/test_completion" || FAILED=1

echo "[9/13] workspace tests"
# tests/fake_tiko stands in for `tiko metadata`.
"$TIKO" -w all "$ROOT/tests/fake_tiko.tiko" -x "$ROOT/bin/fake_tiko"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_workspace.tiko" \
    "$ROOT/src/workspace/workspace.tiko" "$ROOT/src/workspace/symbol_index.tiko" "$ROOT/src/workspace/modules.tiko" "$ROOT/src/analysis/includes.tiko" \
    "$ROOT/src/workspace/index_builder.tiko" "$ROOT/src/workspace/metadata.tiko" "$ROOT/src/workspace/cincludes.tiko" \
    "$ROOT/src/utils/process.tiko" "$ROOT/src/json/json.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/diagnostics.tiko" \
    "$ROOT/src/utils/position.tiko" "$ROOT/src/utils/uri.tiko" "$ROOT/src/utils/logging.tiko" \
    -x "$ROOT/bin/test_workspace"
"$ROOT/bin/test_workspace" "$ROOT" || FAILED=1

echo "[10/13] signature tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_signature.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/signature.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" "$ROOT/src/utils/position.tiko" \
    -x "$ROOT/bin/test_signature"
"$ROOT/bin/test_signature" || FAILED=1

echo "[11/13] semantic token tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_semantic.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/semantic.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" "$ROOT/src/utils/position.tiko" \
    -x "$ROOT/bin/test_semantic"
"$ROOT/bin/test_semantic" || FAILED=1

echo "[12/13] formatting tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_format.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/format.tiko" \
    "$ROOT/src/analysis/diagnostics.tiko" "$ROOT/src/utils/position.tiko" \
    -x "$ROOT/bin/test_format"
"$ROOT/bin/test_format" || FAILED=1

echo "[13/13] piped session against the real server"
"$TIKO" -w all -mt $INC "$ROOT/tests/session_tool.tiko" \
    "$ROOT/src/json/json.tiko" "$ROOT/src/rpc/transport.tiko" "$ROOT/src/rpc/jsonrpc.tiko" \
    "$ROOT/src/lsp/protocol.tiko" "$ROOT/src/analysis/semantic.tiko" \
    "$ROOT/src/analysis/lexer.tiko" "$ROOT/src/analysis/parser.tiko" \
    "$ROOT/src/analysis/symbols.tiko" "$ROOT/src/analysis/diagnostics.tiko" \
    "$ROOT/src/utils/position.tiko" "$ROOT/src/utils/logging.tiko" \
    "$ROOT/src/utils/uri.tiko" \
    -x "$ROOT/bin/session_tool"

"$ROOT/bin/session_tool" --write "$ROOT/bin/session.bin" "$ROOT/tests/fixtures/workspace"

# stderr is redirected only to keep the transcript readable; the server writes
# diagnostics there, never to stdout.
set +e
"$ROOT/bin/tiko-lsp" --log-level info \
    < "$ROOT/bin/session.bin" > "$ROOT/bin/captured.bin" 2> "$ROOT/bin/server.log"
SERVER_EXIT=$?
set -e

if [ "$SERVER_EXIT" -ne 0 ]; then
    echo "   FAIL  the server exited with $SERVER_EXIT, expected 0 after shutdown+exit"
    FAILED=1
else
    echo "   ok    the server exited 0 after shutdown+exit"
fi

"$ROOT/bin/session_tool" --check "$ROOT/bin/captured.bin" || FAILED=1

echo
if [ "$FAILED" -eq 0 ]; then
    echo "ALL SUITES PASSED"
    exit 0
fi
echo "SUITE FAILURES -- see above"
exit 1
