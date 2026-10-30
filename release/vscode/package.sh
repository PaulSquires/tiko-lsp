#!/bin/sh
# ============================================================================
#  Track A: package the platform-specific VS Code extensions.
#
#      bash release/vscode/package.sh
#
#  Needs the Phase 1 archives in dist/ (release/build-windows.sh and
#  release/build-linux.sh). For each target it fills editors/vscode/server/
#  from THE RELEASE ARCHIVE -- so the bundled binary is byte-for-byte the one
#  that passed the release gates -- and runs `vsce package --target`:
#
#      dist/tiko-win32-x64.vsix   <- dist/tiko-lsp-windows-x86_64.zip
#      dist/tiko-linux-x64.vsix   <- dist/tiko-lsp-linux-x86_64.tar.gz
#      dist/tiko-darwin-arm64.vsix <- dist/tiko-lsp-macos-arm64.tar.gz  (built on the Mac by
#                                    release/build-macos.sh and copied back)
#
#  Gates, each one stops the packaging:
#    - editors/vscode/package.json's version equals the server's (lockstep, A-D4);
#    - each .vsix declares its TargetPlatform, holds exactly one server binary --
#      the right one, identical to the archive's -- plus LICENSE and
#      THIRD-PARTY-NOTICES.txt beside it, and no server/ file of the other target.
# ============================================================================
set -e

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
EXT="$ROOT/editors/vscode"
DIST="$ROOT/dist"
cd "$EXT"

SERVER_VERSION=$(sed -n 's/^const LSP_SERVER_VERSION = "\([0-9.]*\)".*/\1/p' "$ROOT/src/lsp/protocol.ti")
EXT_VERSION=$(python -c "import json; print(json.load(open('package.json'))['version'])")
if [ "$SERVER_VERSION" != "$EXT_VERSION" ]; then
    echo "GATE: extension $EXT_VERSION != server $SERVER_VERSION -- run release/bump.py" >&2
    exit 1
fi
echo "== Tiko for VS Code $EXT_VERSION"

[ -d node_modules ] || npm ci

package_one() {   # <vsce target> <archive> <binary name>
    target=$1; archive=$2; bin=$3
    out="$DIST/tiko-$target.vsix"
    [ -f "$DIST/$archive" ] || { echo "missing $DIST/$archive -- run the Phase 1 build" >&2; exit 1; }

    echo "== $target <- $archive"
    rm -rf server
    mkdir server
    python - "$DIST/$archive" server <<'EOF'
import sys, tarfile, zipfile
src, dst = sys.argv[1], sys.argv[2]
if src.endswith(".zip"):
    zipfile.ZipFile(src).extractall(dst)
else:
    # Our own archive, but extracted as untrusted anyway: regular files only,
    # by base name (no paths, links or devices), on any Python 3.
    import os
    with tarfile.open(src) as t:
        for m in t.getmembers():
            if m.isreg():
                with open(os.path.join(dst, os.path.basename(m.name)), "wb") as f:
                    f.write(t.extractfile(m).read())
EOF
    rm -f "$out"
    npx vsce package --target "$target" --out "$out"

    python - "$out" "$target" "$bin" server/"$bin" <<'EOF'
import hashlib, re, sys, zipfile
vsix, target, binname, local = sys.argv[1:5]
z = zipfile.ZipFile(vsix)
names = z.namelist()
srv = sorted(n for n in names if n.startswith("extension/server/"))
want = sorted("extension/server/" + n for n in (binname, "LICENSE", "THIRD-PARTY-NOTICES.txt"))
if srv != want:
    sys.exit("GATE: %s server/ holds %s, expected %s" % (vsix, srv, want))
manifest = z.read("extension.vsixmanifest").decode("utf-8")
m = re.search(r'TargetPlatform="([^"]+)"', manifest)
if not m or m.group(1) != target:
    sys.exit("GATE: %s declares TargetPlatform %s, expected %s" % (vsix, m and m.group(1), target))
inside = hashlib.sha256(z.read("extension/server/" + binname)).hexdigest()
staged = hashlib.sha256(open(local, "rb").read()).hexdigest()
if inside != staged:
    sys.exit("GATE: %s's server differs from the release archive's" % vsix)
print("   %s: %d files, TargetPlatform=%s, server sha256 %s..." % (vsix.split("/")[-1], len(names), target, inside[:16]))
EOF
}

package_one win32-x64 tiko-lsp-windows-x86_64.zip    tiko-lsp.exe
package_one linux-x64 tiko-lsp-linux-x86_64.tar.gz   tiko-lsp
package_one darwin-arm64 tiko-lsp-macos-arm64.tar.gz tiko-lsp

rm -rf server
echo "== done: dist/tiko-win32-x64.vsix, dist/tiko-linux-x64.vsix, dist/tiko-darwin-arm64.vsix ($EXT_VERSION)"
