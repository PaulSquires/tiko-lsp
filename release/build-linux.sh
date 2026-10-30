#!/bin/bash
# ============================================================================
#  Release build, Linux x64: dist/tiko-lsp-linux-x86_64.tar.gz
#
#  Run from Git Bash on Windows, through WSL:
#
#      wsl -d Ubuntu-22.04 -- bash release/build-linux.sh
#
#  or directly on any Linux host with the tree mounted. The distro that runs it
#  decides the glibc the binary needs, so it is the OLDEST supported one --
#  Ubuntu 22.04, glibc 2.35 (docs/deployment.md, P1-D1). A Fedora build needed
#  GLIBC_2.42 and would not start on Ubuntu 24.04.
#
#    1. copy the tree to $HOME -- never build on /mnt/c
#    2. the server AND the whole suite   (build/_run_tests.sh)
#    3. strip a copy of the server, then gates -- each one stops the release:
#         - no versioned glibc symbol newer than $TIKO_LSP_GLIBC_MAX (2.35);
#         - NEEDED libraries only from the allowed list below;
#    4. release/smoke.py: --version and one LSP session show this version
#    5. release/pack.py: the tarball, into the source tree's dist/
#
#    TIKO_LSP_TIKO        tiko   (default <tree>/../tiko-lang/toolchains/tiko-linux/bin/tiko)
#    TIKO_LSP_GLIBC_MAX   newest glibc symbol version allowed (default 2.35)
# ============================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TIKO=${TIKO_LSP_TIKO:-"$ROOT/../tiko-lang/toolchains/tiko-linux/bin/tiko"}
GLIBC_MAX=${TIKO_LSP_GLIBC_MAX:-2.35}
ALLOWED_NEEDED="ld-linux-x86-64.so.2 libc.so.6 libdl.so.2 libm.so.6 libpthread.so.0 libtinfo.so.6"

W=$HOME/tklsp-release
LOG=$HOME/tklsp-release-suite.log

VERSION=$(sed -n 's/^const LSP_SERVER_VERSION = "\([0-9.]*\)".*/\1/p' "$ROOT/src/lsp/protocol.ti")
[ -n "$VERSION" ] || { echo "no LSP_SERVER_VERSION in src/lsp/protocol.ti" >&2; exit 1; }
for tool in python3 strip objdump tar; do
    command -v $tool > /dev/null || { echo "$tool is not installed" >&2; exit 1; }
done
[ -x "$TIKO" ] || { echo "tiko not found: $TIKO -- set TIKO_LSP_TIKO" >&2; exit 1; }

echo "== tiko-lsp $VERSION -- Linux x64 release build on $(. /etc/os-release; echo "$PRETTY_NAME"), $(ldd --version | head -1)"

echo "== [1/5] copy to $W"
rm -rf "$W"
mkdir -p "$W"
(cd "$ROOT" && tar cf - --exclude=.git --exclude=./bin --exclude=./obj --exclude=./dist --exclude=./editors .) | (cd "$W" && tar xf -)

# The toolchain finds its own inc/ and pkg/; a developer's TKO_* overrides
# would build against something no user has.
unset TKO_INCLUDE TKO_LIBPATH TKO_PKG
export TIKO_LSP_TIKO=$TIKO

echo "== [2/5] server + suite (log: $LOG)"
set +e
sh "$W/build/_run_tests.sh" > "$LOG" 2>&1
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

echo "== [3/5] strip + gates"
mkdir -p "$W/stage"
cp "$W/bin/tiko-lsp" "$W/stage/tiko-lsp"
strip "$W/stage/tiko-lsp"
chmod 0755 "$W/stage/tiko-lsp"

NEWEST=$(objdump -T "$W/stage/tiko-lsp" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1)
if [ "$(printf '%s\n%s\n' "$NEWEST" "$GLIBC_MAX" | sort -V | tail -1)" != "$GLIBC_MAX" ]; then
    echo "GATE: tiko-lsp needs GLIBC_$NEWEST, newer than the allowed $GLIBC_MAX -- build on an older distro" >&2
    exit 1
fi
NEEDED=$(objdump -p "$W/stage/tiko-lsp" | awk '/NEEDED/ { print $2 }' | sort | tr '\n' ' ')
for lib in $NEEDED; do
    case " $ALLOWED_NEEDED " in
        *" $lib "*) ;;
        *) echo "GATE: tiko-lsp needs $lib, which is not on the allowed list" >&2; exit 1 ;;
    esac
done
echo "   newest glibc symbol: GLIBC_$NEWEST (allowed <= $GLIBC_MAX); NEEDED: $NEEDED"
echo "   size: $(stat -c %s "$W/stage/tiko-lsp") bytes stripped"

echo "== [4/5] smoke"
python3 "$ROOT/release/smoke.py" "$W/stage/tiko-lsp" "$VERSION"

echo "== [5/5] pack"
python3 "$ROOT/release/pack.py" linux "$W/stage/tiko-lsp" "$(dirname "$(dirname "$TIKO")")"

echo "== done: dist/tiko-lsp-linux-x86_64.tar.gz ($VERSION, GLIBC_$NEWEST)"
