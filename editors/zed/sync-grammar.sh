#!/usr/bin/env bash
# Push the grammar into the repository Zed loads it from, and pin the new rev.
#
# WHY A SECOND REPOSITORY AT ALL: a Zed extension names a grammar by REPOSITORY
# AND REVISION, never by a path, and the repository root is where it looks for
# `src/parser.c`. The grammar is developed at tiko-lsp/grammar, which is not a
# repository root -- so it is mirrored to one. Zed loads that mirror through a
# `file://` URL, and the mirror is ALSO published at
# github.com/PaulSquires/tiko-tree-sitter, so the push below keeps the two from
# drifting. The push is not what Zed reads: a failed push leaves the local
# reload working, and says so.
#
# Run this after every grammar change, then reload extensions in Zed.
set -e

SRC="$(cd "$(dirname "$0")/../../grammar" && pwd)"
DST="${TIKO_GRAMMAR_REPO:-/c/dev/tiko-tree-sitter}"
HERE="$(cd "$(dirname "$0")" && pwd)"

[ -d "$DST/.git" ] || { echo "not a git repository: $DST" >&2; exit 1; }

# The generated parser is committed, so regenerate before mirroring -- a stale
# parser.c mirrors cleanly and gives Zed a grammar that is a revision behind.
( cd "$SRC" && ./node_modules/.bin/tree-sitter generate >/dev/null 2>&1 )

find "$DST" -mindepth 1 -maxdepth 1 -not -name .git -exec rm -rf {} +
( cd "$SRC" && tar -cf - --exclude=node_modules --exclude=package-lock.json . ) | ( cd "$DST" && tar -xf - )

cd "$DST"
git add -A
git commit -q -m "sync from tiko-lsp/grammar" || echo "nothing changed in the grammar"
REV="$(git log --format=%H -1)"

# Publish it. `set -e` is lifted for this one command on purpose: what Zed
# reads is the LOCAL clone, so a network failure must not stop the pin below
# and leave the extension naming a revision that was never written.
if git remote get-url origin >/dev/null 2>&1; then
    set +e
    git push -q origin HEAD
    if [ $? -ne 0 ]; then
        echo "WARNING: the push to origin failed -- the local reload still works," >&2
        echo "         but github is now behind $(echo "$REV" | cut -c1-12)" >&2
    fi
    set -e
else
    echo "no origin on $DST -- nothing published"
fi

cd "$HERE"
python - "$REV" <<'PY'
import io, re, sys
rev = sys.argv[1]
p = 'extension.toml'
s = io.open(p, encoding='utf-8', newline='').read()
s = re.sub(r'(\[grammars\.tiko\][^\[]*?rev = ")[0-9a-f]{40}(")', r'\g<1>' + rev + r'\g<2>', s, count=1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('pinned', rev[:12])
PY

echo "now run 'zed: reload extensions' in Zed (or restart it)"
