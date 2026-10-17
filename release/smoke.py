"""Smoke-test a release binary: one real LSP session over a pipe.

    python3 release/smoke.py <path-to-tiko-lsp> <expected-version>

Checks, in order: `--version` names the expected version; `initialize` answers
with serverInfo.name "tiko-lsp" and serverInfo.version = the expected version;
`shutdown` answers null; `exit` ends the process with code 0 within the
deadline. Runs the same on Windows and Linux -- standard library only, so it
works on a bare distro with python3.

This is the release gate's question -- "does the packaged binary start and
speak the protocol on THIS machine" -- not a test of the server's features;
build/_run_tests.* answer that.
"""
import json
import subprocess
import sys

DEADLINE = 30  # seconds; a hang is the failure mode on a pipe, not a wrong answer


def frame(obj):
    body = json.dumps(obj).encode("utf-8")
    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body


def unframe(data):
    """Every message in a captured stdout stream, in order."""
    out = []
    while data:
        head, sep, rest = data.partition(b"\r\n\r\n")
        if not sep:
            raise ValueError("truncated header: %r" % head[:80])
        length = None
        for line in head.split(b"\r\n"):
            name, _, value = line.partition(b":")
            if name.strip().lower() == b"content-length":
                length = int(value.strip())
        if length is None or len(rest) < length:
            raise ValueError("bad or truncated message after %d messages" % len(out))
        out.append(json.loads(rest[:length].decode("utf-8")))
        data = rest[length:]
    return out


def fail(msg):
    print("SMOKE FAILED: " + msg)
    return 1


def main(argv):
    if len(argv) != 3:
        print("usage: python3 release/smoke.py <tiko-lsp> <version>", file=sys.stderr)
        return 2
    exe, want = argv[1], argv[2]

    v = subprocess.run([exe, "--version"], capture_output=True, timeout=DEADLINE)
    text = (v.stdout + v.stderr).decode("utf-8", "replace").strip()
    if v.returncode != 0 or ("tiko-lsp " + want) not in text:
        return fail("--version printed %r (rc %d), expected 'tiko-lsp %s'" % (text, v.returncode, want))

    session = b"".join([
        frame({"jsonrpc": "2.0", "id": 1, "method": "initialize",
               "params": {"processId": None, "rootUri": None, "capabilities": {},
                          "clientInfo": {"name": "release-smoke", "version": want}}}),
        frame({"jsonrpc": "2.0", "method": "initialized", "params": {}}),
        frame({"jsonrpc": "2.0", "id": 2, "method": "shutdown"}),
        frame({"jsonrpc": "2.0", "method": "exit"}),
    ])
    try:
        p = subprocess.run([exe, "--stdio"], input=session, capture_output=True, timeout=DEADLINE)
    except subprocess.TimeoutExpired:
        return fail("no exit within %d s" % DEADLINE)
    if p.returncode != 0:
        return fail("exit code %d; stderr: %s" % (p.returncode, p.stderr.decode("utf-8", "replace")[-400:]))

    try:
        msgs = unframe(p.stdout)
    except ValueError as e:
        return fail("stdout is not clean LSP framing (%s)" % e)
    by_id = {m.get("id"): m for m in msgs if "id" in m and "method" not in m}

    init = by_id.get(1)
    if not init or "result" not in init:
        return fail("no initialize result: %r" % init)
    info = init["result"].get("serverInfo", {})
    if info.get("name") != "tiko-lsp" or info.get("version") != want:
        return fail("serverInfo is %r, expected tiko-lsp %s" % (info, want))
    if "capabilities" not in init["result"]:
        return fail("initialize result has no capabilities")

    shut = by_id.get(2)
    if not shut or "result" not in shut or shut["result"] is not None:
        return fail("shutdown answered %r, expected a null result" % shut)

    print("smoke ok: %s -- %s, %d messages, exit 0" % (exe, text, len(msgs)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
