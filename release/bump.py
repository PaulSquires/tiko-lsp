"""Write a release version into every place that carries it.

    python release/bump.py X.Y.Z

Each SITE is a file and a pattern that must match EXACTLY ONCE; a site that
matches zero or two times stops the bump before anything is written, because a
version that reaches only some of its places is a release that lies about
itself. Line endings are kept as they are (newline='').

A track that ships its own version adds its sites here -- one line each -- and
changes nothing else (docs/deployment.md, "Rules that keep the tracks
independent").
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (file relative to the repo root, regex with one group around the version)
SITES = [
    ("src/lsp/protocol.ti", r'^const LSP_SERVER_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)"'),
    # Track A: the VS Code extension is versioned in lockstep with the server it bundles.
    ("editors/vscode/package.json", r'^  "version": "([0-9]+\.[0-9]+\.[0-9]+)"'),
    ("editors/vscode/package-lock.json", r'\A\{\s*"name": "tiko",\s*"version": "([0-9]+\.[0-9]+\.[0-9]+)"'),
    ("editors/vscode/package-lock.json", r'"": \{\s*"name": "tiko",\s*"version": "([0-9]+\.[0-9]+\.[0-9]+)"'),
]


def main(argv):
    if len(argv) != 2 or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", argv[1]):
        print("usage: python release/bump.py X.Y.Z", file=sys.stderr)
        return 2
    version = argv[1]

    # Every site is applied in memory first -- a file may hold several -- and
    # nothing is written until all of them matched.
    texts = {}
    report = []
    for rel, pattern in SITES:
        if rel not in texts:
            with open(ROOT / rel, encoding="utf-8", newline="") as f:
                texts[rel] = f.read()
        text = texts[rel]
        hits = list(re.finditer(pattern, text, re.MULTILINE))
        if len(hits) != 1:
            print(f"{rel}: pattern matched {len(hits)} times, expected 1", file=sys.stderr)
            return 1
        m = hits[0]
        texts[rel] = text[: m.start(1)] + version + text[m.end(1):]
        report.append(f"{rel}: {m.group(1)} -> {version}")

    for rel, text in texts.items():
        with open(ROOT / rel, "w", encoding="utf-8", newline="") as f:
            f.write(text)
    print("\n".join(report))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
