#!/bin/sh
# ============================================================================
#  Smoke-test a Linux or macOS release tarball on THIS machine.
#
#      sh release/smoke-linux.sh [dist/tiko-lsp-linux-x86_64.tar.gz]
#
#  Extracts the tarball into a fresh temporary directory -- exactly what a user
#  or an editor extension gets -- and runs release/smoke.py on it. Needs only
#  sh, tar and python3, so it runs on any test host (Fedora, Ubuntu, ...).
#  The version expected is the one in src/lsp/protocol.ti.
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "$(uname -s)" = "Darwin" ]; then
    TARBALL=${1:-"$ROOT/dist/tiko-lsp-macos-arm64.tar.gz"}
else
    TARBALL=${1:-"$ROOT/dist/tiko-lsp-linux-x86_64.tar.gz"}
fi
VERSION=$(sed -n 's/^const LSP_SERVER_VERSION = "\([0-9.]*\)".*/\1/p' "$ROOT/src/lsp/protocol.ti")

[ -f "$TARBALL" ] || { echo "no tarball: $TARBALL" >&2; exit 1; }

DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT
tar -xzf "$TARBALL" -C "$DIR"

if [ "$(uname -s)" = "Darwin" ]; then
    echo "host: macOS $(sw_vers -productVersion), $(uname -m)"
else
    echo "host: $(. /etc/os-release; echo "$PRETTY_NAME"), $(ldd --version | head -1)"
fi
ls -l "$DIR"
[ -x "$DIR/tiko-lsp" ] || { echo "SMOKE FAILED: tiko-lsp is not executable after extraction" >&2; exit 1; }
python3 "$ROOT/release/smoke.py" "$DIR/tiko-lsp" "$VERSION"
