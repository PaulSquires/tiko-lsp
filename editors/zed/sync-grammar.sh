#!/usr/bin/env bash
# Push the grammar into the repository Zed loads it from, and pin the new rev.
#
# WHY A SECOND REPOSITORY AT ALL: a Zed extension names a grammar by REPOSITORY
# AND REVISION, never by a path, and the repository root is where it looks for
# `src/parser.c`. The grammar is developed at tiko-lsp/grammar, which is not a
# repository root -- so it is mirrored to one. A `file://` URL keeps that local
# until the grammar is published.
#
# Run this after every grammar change, then reload extensions in Zed.
set -e

SRC="$(cd "$(dirname "$0")/../../grammar" && pwd)"
DST="${TIKO_GRAMMAR_REPO:-/c/dev/tree-sitter-tiko}"
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
