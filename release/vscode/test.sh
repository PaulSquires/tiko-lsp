#!/bin/bash
# ============================================================================
#  Track A, A.4: test a packaged .vsix in a CLEAN VS Code profile.
#
#      bash release/vscode/test.sh [dist/tiko-win32-x64.vsix]      (Git Bash, Windows)
#      bash release/vscode/test.sh dist/tiko-linux-x64.vsix         (Linux, with a display)
#
#  1. a fresh user-data dir and extensions dir under
#     editors/vscode/test-results/<target>/ -- no settings, no other extensions;
#  2. `code --install-extension <vsix>` into that extensions dir, as a user would;
#  3. VS Code opened on editors/vscode/test/fixture/ws with
#     editors/vscode/test/harness as the development extension, which runs
#     suite.js against the INSTALLED Tiko: bundled server present and used,
#     hover, completion, definition, a diagnostic, formatting, and .bas left
#     alone (see suite.js for each check);
#  4. results.json printed, one line per check; the exit code is VS Code's.
#
#  Workspace trust is switched off for the run (--disable-workspace-trust),
#  because the extension -- by design -- does nothing in Restricted Mode, and a
#  fresh profile would start there. A VS Code window opens for ~10-60 s.
#
#    CODE_EXE  the VS Code executable (default: the per-user Windows install, or
#              `code` on Linux)
# ============================================================================
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VSIX=${1:-"$ROOT/dist/tiko-win32-x64.vsix"}
[ -f "$VSIX" ] || { echo "no such .vsix: $VSIX" >&2; exit 1; }
TARGET=$(basename "$VSIX" .vsix)

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        WIN=1
        CODE_EXE=${CODE_EXE:-"$LOCALAPPDATA/Programs/Microsoft VS Code/Code.exe"}
        CODE_CLI="$(dirname "$CODE_EXE")/bin/code"
        native() { cygpath -w "$1"; }
        ;;
    *)
        WIN=0
        CODE_EXE=${CODE_EXE:-$(command -v code || true)}
        CODE_CLI=$CODE_EXE
        native() { printf '%s' "$1"; }
        ;;
esac
[ -n "$CODE_EXE" ] && [ -e "$CODE_EXE" ] || { echo "VS Code not found -- set CODE_EXE" >&2; exit 1; }

WORK="$ROOT/editors/vscode/test-results/$TARGET"
rm -rf "$WORK"
mkdir -p "$WORK/profile" "$WORK/extensions"
RESULTS="$WORK/results.json"

echo "== $TARGET: install into a clean profile"
"$CODE_CLI" --user-data-dir "$(native "$WORK/profile")" --extensions-dir "$(native "$WORK/extensions")" \
    --install-extension "$(native "$VSIX")" --force

echo "== $TARGET: run the harness (VS Code $("$CODE_CLI" --version | head -1))"
# A new user has no tiko-lsp on the PATH, and a developer's machine often does
# (bin/ of this repository). Drop every PATH directory holding one, so the run
# is the new user's -- the harness checks that the bundled server is the one
# that actually runs.
CLEAN_PATH=
IFS=: read -r -a PATH_DIRS <<< "$PATH"
for d in "${PATH_DIRS[@]}"; do
    if [ -n "$d" ] && { [ -e "$d/tiko-lsp.exe" ] || [ -e "$d/tiko-lsp" ]; }; then
        echo "   leaving $d off the PATH (it holds a tiko-lsp)"
        continue
    fi
    CLEAN_PATH=${CLEAN_PATH:+$CLEAN_PATH:}$d
done
export PATH=$CLEAN_PATH
export TIKO_TEST_RESULTS=$(native "$RESULTS")
export TIKO_TEST_EXTENSIONS_DIR=$(native "$WORK/extensions")
unset ELECTRON_RUN_AS_NODE
set +e
timeout 300 "$CODE_EXE" \
    --user-data-dir "$(native "$WORK/profile")" \
    --extensions-dir "$(native "$WORK/extensions")" \
    --disable-workspace-trust --skip-welcome --skip-release-notes --disable-telemetry --new-window \
    --extensionDevelopmentPath="$(native "$ROOT/editors/vscode/test/harness")" \
    --extensionTestsPath="$(native "$ROOT/editors/vscode/test/harness/suite.js")" \
    "$(native "$ROOT/editors/vscode/test/fixture/ws")" > "$WORK/vscode.log" 2>&1
rc=$?
set -e

if [ ! -f "$RESULTS" ]; then
    echo "NO RESULTS (VS Code exit $rc) -- see $WORK/vscode.log" >&2
    tail -20 "$WORK/vscode.log" >&2
    exit 1
fi
if [ $WIN -eq 1 ]; then PY=python; else PY=python3; fi
"$PY" - "$RESULTS" <<'EOF'
import json, sys
r = json.load(open(sys.argv[1]))
print("   VS Code %s on %s" % (r["vscode"], r["platform"]))
for c in r["results"]:
    print("   %s  %-44s %s" % ("PASS" if c["ok"] else "FAIL", c["name"], c["detail"][:110].replace("\n", " ")))
EOF
if [ $rc -ne 0 ]; then
    echo "== $TARGET: FAILED (VS Code exit $rc)" >&2
    exit 1
fi
echo "== $TARGET: all checks passed"
