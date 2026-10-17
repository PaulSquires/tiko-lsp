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
"$TIKO" -w all -mt $INC "$ROOT/tests/test_framing.bas" \
    "$ROOT/src/rpc/transport.bas" "$ROOT/src/utils/logging.bas" \
    -x "$ROOT/bin/test_framing"
"$ROOT/bin/test_framing" || FAILED=1

echo "[3/13] json and json-rpc tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_json.bas" \
    "$ROOT/src/json/json.bas" "$ROOT/src/rpc/jsonrpc.bas" "$ROOT/src/utils/logging.bas" \
    -x "$ROOT/bin/test_json"
"$ROOT/bin/test_json" || FAILED=1

echo "[4/13] position tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_position.bas" \
    "$ROOT/src/utils/position.bas" \
    -x "$ROOT/bin/test_position"
"$ROOT/bin/test_position" || FAILED=1

echo "[5/13] uri and document tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_document.bas" \
    "$ROOT/src/document/document.bas" "$ROOT/src/document/document_manager.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/completion.bas" \
    "$ROOT/src/analysis/diagnostics.bas" \
    "$ROOT/src/utils/position.bas" "$ROOT/src/utils/uri.bas" "$ROOT/src/utils/logging.bas" \
    -x "$ROOT/bin/test_document"
"$ROOT/bin/test_document" || FAILED=1

echo "[6/13] lexer and parser tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_analysis.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/completion.bas" \
    "$ROOT/src/analysis/diagnostics.bas" \
    -x "$ROOT/bin/test_analysis"
# The project root is passed so the suite can analyse this project's OWN
# source and require zero diagnostics from it.
"$ROOT/bin/test_analysis" "$ROOT" || FAILED=1

echo "[7/13] symbol tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_symbols.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/completion.bas" \
    "$ROOT/src/analysis/diagnostics.bas" \
    -x "$ROOT/bin/test_symbols"
"$ROOT/bin/test_symbols" || FAILED=1

echo "[8/13] completion tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_completion.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/completion.bas" \
    "$ROOT/src/analysis/diagnostics.bas" \
    -x "$ROOT/bin/test_completion"
"$ROOT/bin/test_completion" || FAILED=1

echo "[9/13] workspace tests"
# tests/fake_tiko stands in for `tiko metadata`.
"$TIKO" -w all "$ROOT/tests/fake_tiko.bas" -x "$ROOT/bin/fake_tiko"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_workspace.bas" \
    "$ROOT/src/workspace/workspace.bas" "$ROOT/src/workspace/symbol_index.bas" "$ROOT/src/workspace/modules.bas" "$ROOT/src/analysis/includes.bas" \
    "$ROOT/src/workspace/index_builder.bas" "$ROOT/src/workspace/metadata.bas" "$ROOT/src/workspace/cincludes.bas" \
    "$ROOT/src/utils/process.bas" "$ROOT/src/json/json.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/diagnostics.bas" \
    "$ROOT/src/utils/position.bas" "$ROOT/src/utils/uri.bas" "$ROOT/src/utils/logging.bas" \
    -x "$ROOT/bin/test_workspace"
"$ROOT/bin/test_workspace" "$ROOT" || FAILED=1

echo "[10/13] signature tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_signature.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/signature.bas" \
    "$ROOT/src/analysis/diagnostics.bas" "$ROOT/src/utils/position.bas" \
    -x "$ROOT/bin/test_signature"
"$ROOT/bin/test_signature" || FAILED=1

echo "[11/13] semantic token tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_semantic.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/semantic.bas" \
    "$ROOT/src/analysis/diagnostics.bas" "$ROOT/src/utils/position.bas" \
    -x "$ROOT/bin/test_semantic"
"$ROOT/bin/test_semantic" || FAILED=1

echo "[12/13] formatting tests"
"$TIKO" -w all -mt $INC "$ROOT/tests/test_format.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/format.bas" \
    "$ROOT/src/analysis/diagnostics.bas" "$ROOT/src/utils/position.bas" \
    -x "$ROOT/bin/test_format"
"$ROOT/bin/test_format" || FAILED=1

echo "[13/13] piped session against the real server"
"$TIKO" -w all -mt $INC "$ROOT/tests/session_tool.bas" \
    "$ROOT/src/json/json.bas" "$ROOT/src/rpc/transport.bas" "$ROOT/src/rpc/jsonrpc.bas" \
    "$ROOT/src/lsp/protocol.bas" "$ROOT/src/analysis/semantic.bas" \
    "$ROOT/src/analysis/lexer.bas" "$ROOT/src/analysis/parser.bas" \
    "$ROOT/src/analysis/symbols.bas" "$ROOT/src/analysis/diagnostics.bas" \
    "$ROOT/src/utils/position.bas" "$ROOT/src/utils/logging.bas" \
    "$ROOT/src/utils/uri.bas" \
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
