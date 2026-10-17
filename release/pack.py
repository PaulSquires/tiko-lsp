"""Pack one release archive into dist/.

    python3 release/pack.py windows <tiko-lsp.exe> <toolchain-licences-dir> <yyjson-dir>
    python3 release/pack.py linux   <tiko-lsp>     <toolchain-licences-dir> <yyjson-dir>

Writes dist/tiko-lsp-windows-x86_64.zip or dist/tiko-lsp-linux-x86_64.tar.gz.
The names carry no version on purpose: releases/latest/download/<name> is then
a stable URL for every client that downloads the server (docs/deployment.md,
P1-D3). Members sit at the archive root:

    tiko-lsp[.exe]            the server (mode 0755 in the tarball)
    LICENSE                   tiko-lsp's own licence (MIT)
    THIRD-PARTY-NOTICES.txt   what is linked into the binary, and its terms

THIRD-PARTY-NOTICES.txt is assembled here from the licence files themselves --
yyjson's two, and tiko-rt's from the toolchain that built the binary -- so it
cannot drift from what was actually linked.
"""
import io
import sys
import tarfile
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"

HEADER = """\
THIRD-PARTY NOTICES for tiko-lsp

tiko-lsp is licensed under the MIT licence (see LICENSE). The binary also
contains the following software, linked statically, under the terms below.

  1. yyjson                       MIT        JSON reading and writing
  2. yyjson FreeBASIC bindings    MIT        the wrappers tiko-lsp calls yyjson through
  3. tiko-rt                      LGPL-2.1+  the tiko runtime library, with the
                                             static-linking exception quoted in it
"""


def section(n, title, path):
    text = Path(path).read_text(encoding="utf-8").strip()
    rule = "=" * 78
    return "\n%s\n%d. %s\n%s\n\n%s\n" % (rule, n, title, rule, text)


def notices(licences, yyjson):
    return (HEADER
            + section(1, "yyjson (github.com/ibireme/yyjson)",Path(yyjson) / "LICENSE-yyjson")
            + section(2, "yyjson FreeBASIC bindings", Path(yyjson) / "LICENSE")
            + section(3, "tiko-rt", Path(licences) / "LICENSE-tiko-rt"))


def text_bytes(text, crlf):
    text = text.replace("\r\n", "\n")
    if crlf:
        text = text.replace("\n", "\r\n")
    return text.encode("utf-8")


def main(argv):
    if len(argv) != 5 or argv[1] not in ("windows", "linux"):
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    plat, binary, licences, yyjson = argv[1], Path(argv[2]), argv[3], argv[4]
    if not binary.is_file():
        print("no such binary: %s" % binary, file=sys.stderr)
        return 1

    crlf = plat == "windows"
    members = [
        ("tiko-lsp.exe" if plat == "windows" else "tiko-lsp", binary.read_bytes(), 0o755),
        ("LICENSE", text_bytes((ROOT / "LICENSE").read_text(encoding="utf-8"), crlf), 0o644),
        ("THIRD-PARTY-NOTICES.txt", text_bytes(notices(licences, yyjson), crlf), 0o644),
    ]

    DIST.mkdir(exist_ok=True)
    now = time.time()
    if plat == "windows":
        out = DIST / "tiko-lsp-windows-x86_64.zip"
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
            for name, data, _ in members:
                z.writestr(zipfile.ZipInfo(name, time.localtime(now)[:6]), data, zipfile.ZIP_DEFLATED)
    else:
        out = DIST / "tiko-lsp-linux-x86_64.tar.gz"
        with tarfile.open(out, "w:gz") as t:
            for name, data, mode in members:
                info = tarfile.TarInfo(name)
                info.size, info.mode, info.mtime = len(data), mode, int(now)
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                t.addfile(info, io.BytesIO(data))

    print("packed %s (%d bytes)" % (out.relative_to(ROOT), out.stat().st_size))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
