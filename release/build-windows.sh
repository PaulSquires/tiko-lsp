#!/bin/sh
# ============================================================================
#  Release build, Windows x64: dist/tiko-lsp-windows-x86_64.zip
#
#  Run from Git Bash on Windows:   bash release/build-windows.sh
#
#    1. the server AND the whole suite (build/_run_tests.bat); JSON is the
#       toolchain's vendor/cJSON, linked statically
#    2. gates on bin/tiko-lsp.exe -- each one stops the release:
#         - it imports KERNEL32.dll and ucrtbase.dll and NOTHING else
#           (no cJSON.dll, no second C runtime);
#         - it has no export table (cJSON's static archive hides its symbols);
#    3. release/smoke.py: --version and one LSP session show this version
#    4. release/pack.py: the zip, with LICENSE and THIRD-PARTY-NOTICES.txt
#
#  The version is read from src/lsp/protocol.ti; set it with release/bump.py.
#
#    TIKO_LSP_TIKO    tiko.exe   (default C:/dev/tiko-lang/toolchains/tiko-windows/tiko.exe)
#    TIKO_CLANG        clang.exe  (default C:/Program Files/LLVM/bin/clang.exe) -- its
#                     llvm-objdump reads the gates
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

TIKO=${TIKO_LSP_TIKO:-"C:/dev/tiko-lang/toolchains/tiko-windows/tiko.exe"}
CLANG=${TIKO_CLANG:-"C:/Program Files/LLVM/bin/clang.exe"}
OBJDUMP="$(dirname "$CLANG")/llvm-objdump.exe"
EXE="$ROOT/bin/tiko-lsp.exe"

VERSION=$(sed -n 's/^const LSP_SERVER_VERSION = "\([0-9.]*\)".*/\1/p' src/lsp/protocol.ti)
[ -n "$VERSION" ] || { echo "no LSP_SERVER_VERSION in src/lsp/protocol.ti" >&2; exit 1; }

echo "== tiko-lsp $VERSION -- Windows x64 release build"
if [ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    echo "   NOTE: the working tree has uncommitted changes -- fine for a trial, not for a release."
fi

echo "== [1/4] server + suite (log: obj/release-windows-suite.log)"
mkdir -p obj
rm -f "$EXE"
set +e
cmd.exe //c "build\\_run_tests.bat" > obj/release-windows-suite.log 2>&1
rc=$?
set -e
tail -3 obj/release-windows-suite.log
if [ $rc -ne 0 ] || ! grep -q "ALL SUITES PASSED" obj/release-windows-suite.log; then
    echo "SUITE FAILED (rc $rc) -- see obj/release-windows-suite.log" >&2
    exit 1
fi

echo "== [2/4] gates"
IMPORTS=$("$OBJDUMP" -p "$EXE" | sed -n 's/.*DLL Name: *//p' | tr -d '\r' | tr 'A-Z' 'a-z' | sort | tr '\n' ' ')
if [ "$IMPORTS" != "kernel32.dll ucrtbase.dll " ]; then
    echo "GATE: tiko-lsp.exe imports [$IMPORTS], expected [kernel32.dll ucrtbase.dll]" >&2
    exit 1
fi
if "$OBJDUMP" -p "$EXE" | grep -q "^Export Table:"; then
    echo "GATE: tiko-lsp.exe has an export table -- a dllexport reached the link" >&2
    exit 1
fi
echo "   imports: $IMPORTS; no exports"

echo "== [3/4] smoke"
python release/smoke.py "$EXE" "$VERSION"

echo "== [4/4] pack"
python release/pack.py windows "$EXE" "$(dirname "$TIKO")"

echo "== done: dist/tiko-lsp-windows-x86_64.zip ($VERSION)"
