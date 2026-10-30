#!/bin/bash
# ============================================================================
#  Release build, macOS arm64 (Apple silicon): dist/tiko-lsp-macos-arm64.tar.gz
#
#  Run ON THE MAC, from the tree:   bash release/build-macos.sh
#  (from Windows: sync the tree, then `ssh mac zsh -l <script that runs it>`, and
#  copy dist/tiko-lsp-macos-arm64.tar.gz back -- docs/deployment.md, Phase 1)
#
#    1. the server AND the whole suite   (build/_run_tests.sh)
#    2. strip a copy, re-sign it ad hoc, then gates -- each one stops the release:
#         - it links only macOS's own libraries (/usr/lib/libSystem, /usr/lib/libncurses)
#           -- cJSON is static, nothing from Homebrew;
#         - its minimum macOS is no later than $TIKO_LSP_MACOS_MIN (13.0, the
#           toolchain's own floor);
#         - its code signature verifies (arm64 refuses to run an unsigned binary);
#    3. release/smoke.py: --version and one LSP session show this version
#    4. release/pack.py: the tarball, into dist/
#
#    TIKO_LSP_TIKO        tiko   (default <tree>/../tiko-lang/toolchains/tiko-macos/bin/tiko)
#    TIKO_LSP_MACOS_MIN   newest minimum macOS allowed (default 13.0)
# ============================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TIKO=${TIKO_LSP_TIKO:-"$ROOT/../tiko-lang/toolchains/tiko-macos/bin/tiko"}
MACOS_MIN=${TIKO_LSP_MACOS_MIN:-13.0}
LOG="$ROOT/obj/release-macos-suite.log"
STAGE="$ROOT/obj/stage-macos"

VERSION=$(sed -n 's/^const LSP_SERVER_VERSION = "\([0-9.]*\)".*/\1/p' "$ROOT/src/lsp/protocol.ti")
[ -n "$VERSION" ] || { echo "no LSP_SERVER_VERSION in src/lsp/protocol.ti" >&2; exit 1; }
[ "$(uname -s)" = "Darwin" ] || { echo "run this on the Mac" >&2; exit 1; }
[ -x "$TIKO" ] || { echo "tiko not found: $TIKO -- set TIKO_LSP_TIKO" >&2; exit 1; }
for tool in python3 strip otool codesign; do
    command -v $tool > /dev/null || { echo "$tool is not installed" >&2; exit 1; }
done

echo "== tiko-lsp $VERSION -- macOS arm64 release build on macOS $(sw_vers -productVersion)"

# The toolchain finds its own inc/ and pkg/; a developer's TKO_* overrides would
# build against something no user has.
unset TKO_INCLUDE TKO_LIBPATH TKO_PKG
export TIKO_LSP_TIKO=$TIKO

echo "== [1/4] server + suite (log: obj/release-macos-suite.log)"
mkdir -p "$ROOT/obj"
set +e
sh "$ROOT/build/_run_tests.sh" > "$LOG" 2>&1
rc=$?
set -e
tail -3 "$LOG"
if [ $rc -ne 0 ] || ! grep -q "ALL SUITES PASSED" "$LOG"; then
    echo "SUITE FAILED (rc $rc) -- see $LOG" >&2
    exit 1
fi
if grep -qi "warning" "$LOG"; then
    echo "SUITE LOG HAS WARNINGS -- see $LOG" >&2
    grep -i "warning" "$LOG" | head -5 >&2
    exit 1
fi

echo "== [2/4] strip, sign + gates"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ROOT/bin/tiko-lsp" "$STAGE/tiko-lsp"
strip -x "$STAGE/tiko-lsp"
codesign --force --sign - "$STAGE/tiko-lsp" 2> /dev/null
chmod 0755 "$STAGE/tiko-lsp"

ARCH=$(lipo -archs "$STAGE/tiko-lsp")
[ "$ARCH" = "arm64" ] || { echo "GATE: tiko-lsp is '$ARCH', expected arm64" >&2; exit 1; }

LIBS=$(otool -L "$STAGE/tiko-lsp" | tail -n +2 | awk '{ print $1 }')
for lib in $LIBS; do
    case "$lib" in
        /usr/lib/libSystem.B.dylib|/usr/lib/libncurses.*.dylib) ;;
        *) echo "GATE: tiko-lsp links $lib, which is not part of macOS" >&2; exit 1 ;;
    esac
done

MINOS=$(otool -l "$STAGE/tiko-lsp" | awk '/LC_BUILD_VERSION/ { f = 1 } f && $1 == "minos" { print $2; exit }')
[ -n "$MINOS" ] || { echo "GATE: no LC_BUILD_VERSION minos in tiko-lsp" >&2; exit 1; }
if [ "$(printf '%s\n%s\n' "$MINOS" "$MACOS_MIN" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
    echo "GATE: tiko-lsp needs macOS $MINOS, later than the allowed $MACOS_MIN" >&2
    exit 1
fi

codesign --verify --strict "$STAGE/tiko-lsp" || { echo "GATE: the signature does not verify" >&2; exit 1; }
echo "   arch arm64; links $(echo $LIBS | tr '\n' ' '); minimum macOS $MINOS (allowed <= $MACOS_MIN); signature ok"
echo "   size: $(stat -f %z "$STAGE/tiko-lsp") bytes stripped"

echo "== [3/4] smoke"
python3 "$ROOT/release/smoke.py" "$STAGE/tiko-lsp" "$VERSION"

echo "== [4/4] pack"
python3 "$ROOT/release/pack.py" macos "$STAGE/tiko-lsp" "$(dirname "$(dirname "$TIKO")")"

echo "== done: dist/tiko-lsp-macos-arm64.tar.gz ($VERSION, macOS $MINOS+)"
