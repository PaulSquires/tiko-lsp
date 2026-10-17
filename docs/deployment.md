# tiko-lsp: packaging and deployment plan

Status: **plan, nothing executed.** Written 2026-10-16 and revised the same day to put **VS
Code first**. Store rules were read on that date (sources at the end); re-check them
before each first publish, because they change.

## Goal

A new user starts their editor, opens its extension store, types **tiko**, installs one
thing, opens a `.tiko` file and has a running server. They never download a binary, edit a
setting or install a dependency by hand. Windows x86-64 and Linux x86-64 only.

## How the plan is shaped

```
Phase 1  Server release builds ─────────────── shared, done once, needed by every track
   │
   ├── Track A  VS Code (+ Open VSX) ────────── FIRST. Nothing else starts until A is DONE (§A.8)
   │
   └── Phase 2  GitHub Releases foundation ──── done once, needed only by download-based tracks
          ├── Track B  Zed
          ├── Track C  Sublime Text            any order, each on its own,
          └── Track D  Neovim                  none depends on another
```

**Rules that keep the tracks independent:**

- A track depends only on Phase 1 and, for B–D, Phase 2. It never depends on another
  track.
- A track touches only its own `editors/<name>/` directory, its own `release/<name>/`
  scripts and its own rows in the runbook. Shared files (`release/bump.py`, the build
  scripts) are extended by **adding a line**, never by reworking what an earlier track
  did.
- Each track has a **Definition of done**. A track is not "partly published": either it
  meets the definition or its store listing does not exist yet.
- Client versions are independent of the server version and of each other. The exception
  is VS Code, which bundles the server and so releases in lockstep with it (A-D4).

| Track | Store the user sees | How the binary arrives | Needs Phase 2? |
| --- | --- | --- | --- |
| A | VS Code Marketplace, then Open VSX (VSCodium, Cursor, Windsurf, Kiro) | **bundled** in a platform-specific VSIX | **no** |
| B | Zed extension registry | downloaded from GitHub Releases (Zed forbids bundling) | yes |
| C | Package Control (`LSP-tiko`) | downloaded into `Package Storage` | yes |
| D | none at first: plugin repo `tiko.nvim`; later Mason | downloaded into `stdpath('data')`; later Mason | yes |

Because Track A bundles the binary, it **does not need the repos public or a GitHub
release**. That is one more reason it goes first: it is the shortest path to a listing.
Its listing links to the repository, though, so a private repo means a dead "Repository"
link (A-D5).

## Findings (measured 2026-10-16)

| # | Finding | Hits |
| --- | --- | --- |
| F1 | `tiko-lsp`, `tree-sitter-tiko` and `tiko-lang` are **PRIVATE** on GitHub. | Phase 2 blocker (B, C, D). A only loses its repository link. |
| F2 | `bin/tiko-lsp` built on Fedora needs **GLIBC_2.42**, and fails on Ubuntu 24.04 (glibc 2.39): `version 'GLIBC_2.42' not found`. | Phase 1: Fedora cannot be the Linux release host. |
| F3 | `toolchains/tiko-linux/bin/tiko` needs only **GLIBC_2.34**. | Phase 1: any distro whose build passes the glibc gate can be the host. |
| F4 | The Linux binary links `libtinfo.so.6`, libm and libc, and carries debug info (3.9 MB). | Phase 1: strip it; tinfo is open item O3. |
| F5 | `tiko-lsp.exe` imports `yyjson64.dll`, `KERNEL32.dll` and `ucrtbase.dll` (814 KB). | Phase 1: link yyjson statically, or ship the DLL (P1-D2). |
| F6 | Every client finds the server through settings → PATH → `<workspace>/bin`. None can obtain it itself. | Every track. |
| F7 | `editors/zed`, `editors/neovim` and `tree-sitter-tiko` have no LICENSE. | B, D. |
| F8 | The Zed grammar is loaded from `file:///C:/dev/tree-sitter-tiko`. Zed language-extension IDs should equal the language name; the current ID is `tiko-lsp`. | B. |
| F9 | Sublime's default channel sends LSP packages to `sublimelsp/repository`. Package Control installs one package per repo, from the repo root, by semver tag. | C. |
| F10 | nvim-lspconfig and mason-registry are gated on ≥100 stars, or evidence such as 5,000 VS Code Marketplace downloads. | D: Track A's download count can open this gate. |
| F11 | VS Code Marketplace: **global Azure DevOps PATs retire on 2026-12-01**; Microsoft Entra ID (`--azure-credential`) replaces them. | A: deadline. |
| F12 | Names are free: Marketplace display name "Tiko" (only a *publisher* uses it), Zed `tiko`, Sublime `LSP-tiko`. | A, B, C. |
| F13 | `LSP_SERVER_VERSION = "0.1.0"`; `--version` exists; no tags, no releases. | Phase 1. |

---

## Phase 1: server release builds (shared, done once)

**Goal:** two tested, portable server binaries produced by one command per platform, in
`dist/`. Nothing in this phase is published.

**Status (2026-10-17): built and run.** Both archives were produced and every gate is
green. Still owed: the tarball smoke test on **Fedora 44**
(`sh release/smoke-linux.sh` on that machine).

### Decisions

- **P1-D1. The glibc gate is the rule; the build host is WSL Ubuntu 24.04.** Built
  there, the stripped server needs only **GLIBC_2.34** (measured 2026-10-17), so it runs
  on Ubuntu 22.04 (2.35) and RHEL 9 (2.34). The Fedora build's GLIBC_2.42 (F2) was a
  property of that host, not of the code. If the gate (≤ 2.35) ever trips on 24.04, build
  on an older distro instead (`wsl --install -d Ubuntu-22.04`). Fedora 44 stays a test
  host.
- **P1-D2. yyjson is linked statically on Windows: DONE.** `build/_build_yyjson_static.sh`
  compiles yyjson.c and the shim with `clang -target x86_64-pc-windows-msvc` into
  `obj/yyjson-static/libyyjson64.a`. The shim is first copied with `__declspec(dllexport)`
  removed, otherwise the exe would get an export table and a stray `.lib/.exp`. Setting
  `TIKO_LSP_YYJSON_LIB` points `_compile.bat` and `_run_tests.bat` at it. The result is
  1.1 MB and imports only `KERNEL32` and `ucrtbase`. The default dev build is unchanged
  and still uses the DLL.
- **P1-D3. Archive names carry no version**, so `releases/latest/download/<asset>` stays a
  stable URL for Phase 2 downloaders. The version lives in the tag and in a `VERSION`
  file.
- **P1-D4. Zero-config toolchain discovery (optional server feature, your call).** When
  `initialize` brings no `includePaths` and no `compilerPath`, the server looks for `tiko`
  on PATH and uses `<tiko>/../inc`, `<tiko>/../pkg` and `compilerPath = tiko`. Without it,
  a new user gets diagnostics and symbols but no Win32 or std completions until they edit
  a setting. It sits in Phase 1 because every track benefits.

### Work

| File | Does |
| --- | --- |
| `release/bump.py X.Y.Z` | Writes the version into every registered site. Phase 1 has one site, `src/lsp/protocol.ti`; each track **adds** its own lines to `SITES`. A site matching zero or two times stops the bump before anything is written, and line endings are kept. |
| `build/_build_yyjson_static.sh` | The static COFF `libyyjson64.a` (P1-D2) |
| `release/build-windows.sh` | Git Bash: static yyjson → `build\_run_tests.bat` (the server and the whole suite, linked statically) → gates → smoke → `dist/tiko-lsp-windows-x86_64.zip`. About 14 s. |
| `release/build-linux.sh` | `wsl -d Ubuntu -- bash release/build-linux.sh`: copies the tree and yyjson to `$HOME` (never builds on `/mnt/c`), static yyjson, `build/_run_tests.sh`, then `strip`, gates, smoke → `dist/tiko-lsp-linux-x86_64.tar.gz`. About 30 s. |
| `release/smoke.py <exe> <ver>` | Standard-library Python, used on both platforms: `--version`, then one LSP session (`initialize` → `initialized` → `shutdown` → `exit`). Requires `serverInfo` = tiko-lsp + the version, a null `shutdown` result, clean framing on stdout, and exit code 0 within 30 s. |
| `release/smoke-linux.sh [tarball]` | For any Linux test host: extracts the tarball into a fresh temp dir, checks the exec bit, runs `smoke.py` |
| `release/pack.py` | Builds the archive. `THIRD-PARTY-NOTICES.txt` is **assembled from the licence files** (yyjson's two, plus `LICENSE-tiko-rt` from the toolchain that built the binary), so it can't drift from what was linked. CRLF in the zip, LF in the tarball. |

```
tiko-lsp-windows-x86_64.zip     tiko-lsp.exe (1.1 MB)                    LICENSE  THIRD-PARTY-NOTICES.txt   425 KB
tiko-lsp-linux-x86_64.tar.gz    tiko-lsp (mode 0755, stripped, 1.1 MB)   LICENSE  THIRD-PARTY-NOTICES.txt   441 KB
```

`dist/` and `obj/` are gitignored.

### Gates (each one stops the build)

- Windows: `llvm-objdump -p` shows imports of exactly `kernel32.dll` and `ucrtbase.dll`,
  and **no export table**. The suite runs linked statically, all of it, and must print
  `ALL SUITES PASSED`.
- Linux: the newest `GLIBC_*` symbol version is ≤ `$TIKO_LSP_GLIBC_MAX` (default 2.35);
  every `NEEDED` library is on an allowed list (`libc`, `libm`, `libdl`, `libpthread`,
  `libtinfo`, `ld-linux`); `ALL SUITES PASSED`, with no "warning" anywhere in the suite
  log.
- Both: `release/smoke.py` passes against the exact binary that gets packed.

Measured 2026-10-17 at 780cab8 plus these scripts:

- Windows: 17 suites, 1,401 assertions, 0 warnings. Imports are `kernel32` and `ucrtbase`
  only. The smoke test passes on the exe extracted from the zip into an empty directory
  (no `yyjson64.dll` anywhere near it).
- Linux (WSL Ubuntu 24.04.5, glibc 2.39): suite passed; newest symbol GLIBC_2.34; NEEDED
  `libc`, `libm`, `libtinfo`. `smoke-linux.sh` on the extracted tarball passes.

### Definition of done

Both scripts produce both archives, every gate is green, and the tarball smoke test passes
on Ubuntu 24.04 and **Fedora 44**. Ubuntu 22.04 isn't installed, so it stays covered only
by the glibc gate. Nothing is tagged yet.

---

## Track A: VS Code (first)

**Goal:** search "tiko" in the Extensions view of VS Code (and then VSCodium or Cursor),
click Install, open a `.tiko` file, and have a working server on Windows and Linux,
**including the update path**.

**Depends on:** Phase 1 only.

### A. Decisions

- **A-D1. Extension ID `PaulSquires.tiko`.** Rename `name` from `tiko-lsp`. The ID is
  **permanent** once published. Display name `Tiko`.
- **A-D2. Legacy extensions are opt-in.** `.bas`, `.bi` and `.inc` are not claimed by
  default, so installing Tiko doesn't take those files from FreeBASIC, VB or PHP/asm
  extensions. The README shows the `files.associations` line that turns them on.
- **A-D3. Server lookup order:** `tiko.server.path` → **bundled** `server/` →
  PATH → `<workspace>/bin`. The bundled copy goes before PATH so a stale copy on PATH
  can't shadow it.
- **A-D4. Lockstep versions.** The extension version equals the bundled server version.
  Every server release republishes the extension, which is a scripted, minutes-long job.
- **A-D5. Repository link.** Either make `tiko-lsp` public before the first publish, or
  leave `repository` out of `package.json` until it is. A dead link on a listing looks
  abandoned.
- **A-D6. No universal VSIX.** Only `win32-x64` and `linux-x64` are published. macOS and
  ARM users see "not available for your platform", which is true.
- **A-D7. Open VSX is part of Track A.** It takes the same two VSIX files, so it costs one
  extra command per release, and it covers VSCodium, Cursor, Windsurf and Kiro.

### A.1 One-time accounts (you)

1. **Marketplace publisher.** Sign in at <https://marketplace.visualstudio.com/manage>
   with a Microsoft account and create publisher ID **`PaulSquires`** (permanent; it must
   equal `publisher` in `package.json`), display name `Paul Squires`.
2. **PAT.** Create an Azure DevOps organisation at <https://dev.azure.com> with the same
   account. Then User settings → Personal access tokens → New: Organization **All
   accessible organizations**; Scopes → Custom → **Marketplace: Manage**. Keep it in the
   password manager. Check it with `npx @vscode/vsce login PaulSquires`.
3. **Entra ID route (before 2026-12-01).** Run `az login`, then publish a throwaway
   pre-release with `npx @vscode/vsce publish --pre-release --azure-credential`. If a
   personal Microsoft account isn't accepted, add an Entra identity to the publisher as
   Contributor. **Track A is not done until this works** (A.8).
4. **Open VSX.**
   1. Create an Eclipse Foundation account, with your GitHub username in its profile.
   2. Log in to <https://open-vsx.org> with GitHub, then Profile → *Log in with Eclipse* →
      **sign the Publisher Agreement**.
   3. Settings → Access Tokens → Generate.
   4. `npx ovsx create-namespace PaulSquires -p <token>`.
   5. Claim the namespace through an issue at `github.com/EclipseFdn/open-vsx.org`
      ("Namespace Access" wiki page) to remove the "unverified" warning.

### A.2 Client changes (`editors/vscode`)

- `package.json`:
  - `name` → `tiko` (A-D1);
  - add an `icon` (PNG, at least 128×128; never SVG), `keywords` (`tiko`, `basic`,
    `freebasic`, `lsp`, `language server`; at most 30), `categories` + `Linters` and
    `Formatters`, `galleryBanner`, `bugs` and `homepage` (A-D5);
  - `extensions` → `.tiko`, `.tko`, `.ti` (A-D2).
- `extension.js`:
  - add the bundled lookup, `context.asAbsolutePath('server/tiko-lsp[.exe]')` (A-D3);
  - on Linux, `fs.chmodSync(path, 0o755)` before starting it, because a VSIX packed on
    Windows loses the exec bit;
  - drop the yyjson64.dll sentence from the not-found message (P1-D2 landed).
- `.vscodeignore`: exclude `syntaxes/gen_tmlanguage.py`, `*.vsix`, `node_modules/.bin`.
- `README.md`: "Zero setup" first, then settings and the opt-in legacy extensions. Images
  must be `https` URLs; no SVG except trusted badges.
- `CHANGELOG.md`: new.
- `release/bump.py`: add the `editors/vscode/package.json` version site to `SITES`.

### A.3 Packaging (`release/vscode/package.sh`)

For each target, empty `editors/vscode/server/`, copy **only that target's** binary in
from `dist/`, then:

```bash
npx @vscode/vsce package --target win32-x64 -o dist/tiko-win32-x64.vsix
npx @vscode/vsce package --target linux-x64 -o dist/tiko-linux-x64.vsix
```

Gate: unzip each VSIX and assert it holds exactly one server binary, the right one.

### A.4 Local verification (before any upload)

Clean profiles, nothing on PATH, no settings:
`code --user-data-dir <D> --extensions-dir <E> --install-extension dist/tiko-<t>.vsix`.

| Check | Windows 11 | Ubuntu 24.04 (WSLg) | Fedora 44 (WSLg) |
| --- | --- | --- | --- |
| Output channel shows `tiko-lsp X.Y.Z ready` | ☐ | ☐ | ☐ |
| Hover on a symbol | ☐ | ☐ | ☐ |
| Completion after `.` | ☐ | ☐ | ☐ |
| Diagnostic for an unclosed `if` | ☐ | ☐ | ☐ |
| Format Document | ☐ | ☐ | ☐ |
| `.bas` **not** claimed by default; claimed after adding `files.associations` | ☐ | ☐ | ☐ |
| `tiko.server.path` set to a missing file gives the named error | ☐ | ☐ | ☐ |
| Restricted Mode (untrusted folder): the extension stays off, with no crash | ☐ | ☐ | ☐ |

### A.5 Publish: VS Code Marketplace

```bash
npx @vscode/vsce publish --packagePath dist/tiko-win32-x64.vsix dist/tiko-linux-x64.vsix
```

- After upload the Marketplace runs a virus scan, and the listing appears once it passes
  (usually minutes). Then check
  `https://marketplace.visualstudio.com/items?itemName=PaulSquires.tiko`: both platforms
  should be under Version history.
- **Never `vsce unpublish`.** It is irreversible and reserves the name for good.
- If Defender or the scan flags the exe: submit it to Microsoft's WDSI portal. Code
  signing (Azure Artifact Signing, about US$10 a month, individuals allowed) is the
  lasting fix (O6).

### A.6 Publish: Open VSX

```bash
npx ovsx publish dist/tiko-win32-x64.vsix -p $OVSX_TOKEN
npx ovsx publish dist/tiko-linux-x64.vsix -p $OVSX_TOKEN
```

Each VSIX's manifest carries its target. Check `https://open-vsx.org/extension/PaulSquires/tiko`.

### A.7 Store verification (after upload)

Repeat the A.4 matrix, but install by **searching "tiko" in the Extensions view** of a
clean profile:

- VS Code: Windows 11, Ubuntu 24.04, Fedora 44;
- VSCodium (Open VSX): Windows 11, Ubuntu 24.04.

### A.8 Definition of done (gate for Tracks B–D)

All of these must be true:

1. `PaulSquires.tiko` is live on the Marketplace and on Open VSX for win32-x64 and
   linux-x64.
2. The A.7 store matrix is all green.
3. **The update path is proven.** Release `0.1.1` with the A.9 runbook. A clean profile
   that installed `0.1.0` auto-updates to it, and the output channel then shows the new
   server version.
4. **Entra ID publishing works** (A.1 step 3), so the 2026-12-01 PAT retirement can't
   stop a release.
5. The A.9 runbook was followed **from this document alone**, and anything that turned out
   different was corrected here.
6. The listing has its icon, README, CHANGELOG and a working repository link (A-D5).

### A.9 Track A release runbook (every release)

From Git Bash on Windows 11:

| Step | Command | Check |
| --- | --- | --- |
| 1 | `python release/bump.py X.Y.Z`, then commit `release: X.Y.Z` | every site replaced once |
| 2 | `bash release/build-windows.sh` | Phase 1 gates |
| 3 | `wsl -d Ubuntu -- bash release/build-linux.sh` | glibc ≤ 2.35, suite green |
| 4 | `sh release/smoke-linux.sh` on Fedora 44 (and `wsl -d Ubuntu -- sh release/smoke-linux.sh`) | `smoke ok` |
| 5 | `bash release/vscode/package.sh` | one binary per VSIX |
| 6 | A.4 matrix on at least Windows 11 + one Linux | green |
| 7 | `git tag vX.Y.Z && git push origin main vX.Y.Z` | |
| 8 | A.5, then A.6 | both listings show X.Y.Z for both platforms |

---

## Phase 2: GitHub Releases foundation (after Track A; needed by B, C, D)

**Goal:** a public repo with a release whose assets any client can download anonymously.

1. **Make `PaulSquires/tiko-lsp` public** (F1), unless it already went public for A-D5.
   Before flipping it, check the history: `git log --all --stat`, the `bin/` captures
   (gitignored, but check), absolute `C:\dev` paths in docs.
2. `release/publish-github.sh X.Y.Z`: writes `SHA256SUMS` and `VERSION` into `dist/`, then
   runs `gh release create vX.Y.Z dist/*.zip dist/*.tar.gz dist/SHA256SUMS dist/VERSION`.
3. Add it to the runbook as step 9, after A.9 step 8. From then on, every release also
   publishes the GitHub release.
4. **Definition of done:** anonymous `curl -fsSL` of
   `https://github.com/PaulSquires/tiko-lsp/releases/latest/download/VERSION` returns the
   current version, and both archives match `SHA256SUMS`.

**Shared contract for Tracks B–D** (each implements it in its own language; none shares
code with another):

- Download `releases/latest/download/VERSION`, at most once a day; the timestamp lives in
  the client's own storage directory.
- If no binary is present, or `VERSION` is newer, download the platform archive plus
  `SHA256SUMS`, verify the hash, extract to `<storage>/tiko-lsp-<version>/`, set the exec
  bit on Linux, then delete older version directories.
- Lookup order: user setting → managed copy → PATH → `<workspace>/bin`.
- On anything other than Windows or Linux x86-64: say "tiko-lsp ships for Windows and
  Linux x86-64", once. Never fail silently.
- Legacy `.bas/.bi/.inc` stay opt-in, as in A-D2.

---

## Track B: Zed (independent)

**Depends on:** Phase 1 and Phase 2. **Touches:** `editors/zed/`, `tree-sitter-tiko`,
`release/zed/`.

### B.1 One-time setup

- Make `PaulSquires/tree-sitter-tiko` public and add an MIT `LICENSE` at its root.
- Add a `LICENSE` to `editors/zed/` (Zed checks the extension directory, not the repo
  root) (F7).
- Fork `zed-industries/extensions` into your **personal** account; install `pnpm`.

### B.2 Client changes

- `extension.toml`: `id = "tiko"`, `name = "Tiko"` (F8);
  `repository = "https://github.com/PaulSquires/tree-sitter-tiko"`,
  `rev = <a pushed commit on its main branch>`.
- `src/lib.rs` implements the shared contract with Zed's API:
  - `zed::current_platform()`;
  - `zed::latest_github_release("PaulSquires/tiko-lsp", GithubReleaseOptions { require_assets: true, pre_release: false })`;
  - `zed::download_file(url, "tiko-lsp-<ver>", DownloadedFileType::Zip | GzipTar)`;
  - `zed::make_file_executable`;
  - `set_language_server_installation_status`.

  Zed handles the version check itself, so no `VERSION` file is needed here.
- `languages/tiko/config.toml`: `.tiko`, `.tko`, `.ti` only.
- `sync-grammar.sh`: point it at the GitHub URL.
- `release/bump.py`: add `extension.toml` + `Cargo.toml` as version sites (Zed's own
  version, not the server's).

### B.3 Verify

In a clean profile (`Zed.exe --user-data-dir <D>`), run `zed: install dev extension` on
`editors/zed` **at the exact commit you will submit**, on Windows 11 and on Ubuntu 24.04
(WSLg). Then check: the server downloads, hover, completion, a diagnostic, formatting.
Zed requires this manual test.

### B.4 Publish

```bash
git clone https://github.com/PaulSquires/extensions && cd extensions
git submodule init && git submodule update
git submodule add https://github.com/PaulSquires/tiko-lsp.git extensions/tiko
git -C extensions/tiko checkout <tested commit, which must be on a branch>
```

Then append to `extensions.toml`, run `pnpm sort-extensions`, commit, push, and open a PR
to `zed-industries/extensions`:

```toml
[tiko]
submodule = "extensions/tiko"
path = "editors/zed"
version = "0.1.0"          # must equal extension.toml at that commit
```

PR rules: an HTTPS URL; one extension per PR; at most 3 of your PRs open at once; answer
reviews within 3 weeks or the PR is closed. Once merged, Zed's CI builds and publishes it.

### B.5 Updates

- A server-only release needs **no** Zed PR: the extension downloads the latest release.
- When `editors/zed` changes: bump `extension.toml`'s version, push, move the submodule to
  the new commit in the fork, bump `extensions.toml`, and open a PR.

### B.6 Definition of done

Searching `zed: extensions` → **tiko** installs it. The server downloads with no settings
on Windows 11 and Ubuntu 24.04. A later server release is picked up without a Zed PR.

---

## Track C: Sublime Text (independent)

**Depends on:** Phase 1 and Phase 2. **Touches:** `editors/sublime/`, the
`PaulSquires/LSP-tiko` mirror, `release/sublime/`.

### C.1 One-time setup

Create the public repo `PaulSquires/LSP-tiko` (in the browser). It is a **mirror** of
`editors/sublime`, pushed by `release/sublime/mirror.sh` with
`git subtree split --prefix=editors/sublime`, because Package Control installs from a
repo root (F9). Then fork `sublimelsp/repository`.

### C.2 Client changes

- `plugin.py` implements the shared contract through the LSP package's own hooks, so it
  gets LSP's progress UI for free:
  - `storage_path()/LSP-tiko/`;
  - `needs_update_or_installation()`;
  - `install_or_update()`, which runs on LSP's worker thread and uses `urllib.request`,
    `hashlib`, `zipfile`/`tarfile` (Python 3.8).
- `messages.json` + `messages/install.txt`, shown once after install: install the **LSP**
  package if it is missing, and how to point at the toolchain.
- `Tiko.sublime-syntax`: `tiko`, `tko`, `ti` (regenerate with `gen_sublime.py`).
- The mirror carries only what a user needs. `gen_sublime.py` stays in tiko-lsp. No
  `.pyc` files, no `package-metadata.json`.
- One package, with the syntax inside. Split out a `Tiko` syntax package only if a
  reviewer asks.

### C.3 Verify

Use a clean **portable** Sublime Text 4. Install LSP from Package Control, then add
LSP-tiko with *Package Control: Add Repository* (the mirror's GitHub URL) and install it.
On Windows 11 and Ubuntu 24.04, check: the server downloads, hover, completion, a
diagnostic, formatting.

### C.4 Publish

1. Push the mirror and tag it `0.1.0` (plain semver).
2. In your fork of `sublimelsp/repository`, add to `repository.json` `packages`, in
   alphabetical position:

   ```json
   {
       "details": "https://github.com/PaulSquires/LSP-tiko",
       "name": "LSP-tiko",
       "labels": ["lsp", "tiko", "basic"],
       "platforms": ["windows", "linux"],
       "releases": [{ "sublime_text": ">=4070", "tags": true }]
   }
   ```

3. Run `tox` (the repo's checks), then open the PR. After the merge, the packagecontrol.io
   crawler lists it within hours.

### C.5 Updates

- Server-only release: nothing to do; the plugin updates the server within a day.
- Plugin change: run the mirror script, push a new semver tag on `LSP-tiko`, and Package
  Control picks it up.

### C.6 Definition of done

*Package Control: Install Package* → **LSP-tiko** installs it. The server downloads with
no settings on Windows 11 and Ubuntu 24.04, and a newer server release is picked up.

---

## Track D: Neovim (independent)

**Depends on:** Phase 1 and Phase 2. **Touches:** `editors/neovim/`, the
`PaulSquires/tiko.nvim` mirror, `release/neovim/`.

### D.1 One-time setup

Create the public repo `PaulSquires/tiko.nvim`, a mirror of `editors/neovim` pushed by
`release/neovim/mirror.sh`. Add a `LICENSE` to `editors/neovim` (F7).

### D.2 Client changes

- `lua/tiko/install.lua`: `:TikoInstall` and `:TikoUpdate` implement the shared contract
  with `vim.system` running `curl -fsSL` (built into Windows 10+) and `tar -xf` (bsdtar on
  Windows, which also extracts `.zip`). The server goes to
  `stdpath('data')/tiko-lsp/<version>/`, verified with `vim.fn.sha256`.
- On the first missing binary, offer once through `vim.ui.select`. It never downloads
  silently.
- `doc/tiko.txt`, so `:h tiko` works.

### D.3 Verify

Neovim 0.11 with `NVIM_APPNAME=tiko-clean`, installed through lazy.nvim as
`{ 'PaulSquires/tiko.nvim', lazy = false, opts = {} }`. On Windows 11, Ubuntu 24.04 and
Fedora 44: accept the download prompt, then check hover, completion, a diagnostic,
formatting.

### D.4 Publish (stage 1: no store)

Push the mirror and tag `v0.1.0`. Then:

- add the GitHub topics `neovim`, `neovim-plugin`, `nvim-plugin`, `lsp`, `tiko` (dotfyle.com
  indexes repos by these);
- open a PR to `rockerBOO/awesome-neovim`;
- optionally, publish to LuaRocks with `nvim-neorocks/luarocks-tag-release`.

### D.5 Stage 2: lspconfig + Mason (gated, F10)

Start when tiko-lsp has 100 stars **or** the Marketplace shows 5,000 installs. Track A
feeds that number.

1. Filetype detection for `.tiko`, `.tko` and `.ti`: a PR to `vim/vim`
   `runtime/filetype.vim` (Neovim syncs it) or to Neovim's
   `runtime/lua/vim/filetype.lua`.
2. nvim-lspconfig: a PR adding `lsp/tiko_lsp.lua` with
   `cmd = { 'tiko-lsp', '--stdio' }`, `filetypes = { 'tiko' }`,
   `root_markers = { 'tiko.toml', '.git' }`.
3. mason-registry: a PR adding `packages/tiko-lsp/package.yaml` (check it against the
   schema at the time). Renovate then follows new GitHub releases by itself.

   ```yaml
   name: tiko-lsp
   description: Language server for tiko, a FreeBASIC-compatible language.
   homepage: https://github.com/PaulSquires/tiko-lsp
   licenses: [MIT]
   languages: [Tiko]
   categories: [LSP]
   source:
     id: pkg:github/PaulSquires/tiko-lsp@v0.1.0
     asset:
       - target: win_x64
         file: tiko-lsp-windows-x86_64.zip
         bin: tiko-lsp.exe
       - target: linux_x64_gnu
         file: tiko-lsp-linux-x86_64.tar.gz
         bin: tiko-lsp
   bin:
     tiko-lsp: "{{source.asset.bin}}"
   neovim:
     lspconfig: tiko_lsp
   ```

### D.6 Definition of done

- **Stage 1:** the lazy.nvim one-liner installs it and the server downloads after one
  prompt on all three hosts.
- **Stage 2:** `:MasonInstall tiko-lsp` plus `vim.lsp.enable('tiko_lsp')` works with no
  tiko.nvim at all.

---

## Out of scope for now

- **Helix** (named in the README, not in `editors/`): there is no store. The route is an
  upstream `languages.toml` PR. It would make a fifth independent track later.
- **CI builds:** only once the tiko toolchain is a public release asset a workflow can
  download.

## Open items

| # | Item | Blocks |
| --- | --- | --- |
| O1 | Publish before tiko-lang is public? A new user can install the LSP but cannot get a compiler yet. | the first public listing (A.5) |
| O2 | ~~Can yyjson link statically into a windows-x86_64 tiko build?~~ **Yes**, done 2026-10-17 (P1-D2). | — |
| O3 | `libtinfo.so.6`: what in the runtime pulls it in? Drop it or link it statically. | nothing; until then, document it |
| O4 | Entra ID publishing with a personal Microsoft account. | A.8 item 4; deadline 2026-12-01 |
| O5 | Zero-config toolchain discovery (P1-D4). | the "no setting" goal for Win32/std completions |
| O6 | Code signing for the Windows exe. | nothing, unless a scan flags it |
| O7 | A PNG icon (at least 128×128) for the listings. | A.8 item 6 |
| O8 | `--version` says "built with FreeBASIC 1.20.0" (from `__FB_VERSION__`). In a public listing it should name tiko. Server change: `src/main.tiko`. | nothing; cosmetic |

## Sources (read 2026-10-16)

- VS Code: [Publishing extensions](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)
- Open VSX: [Publishing extensions](https://github.com/eclipse/openvsx/wiki/Publishing-Extensions)
- Zed: [prerequisites](https://zed.dev/docs/extensions/publishing/prerequisites),
  [publishing guide](https://zed.dev/docs/extensions/publishing/publishing-guide),
  [license requirements](https://zed.dev/docs/extensions/publishing/license-requirements),
  [zed_extension_api](https://docs.rs/zed_extension_api)
- Sublime: [Submitting a package](https://packagecontrol.io/docs/submitting_a_package),
  [package_control_channel README](https://github.com/sublimehq/package_control_channel)
  (sends LSP packages to [sublimelsp/repository](https://github.com/sublimelsp/repository)),
  [sublimelsp/LSP plugin/api.py](https://github.com/sublimelsp/LSP/blob/main/plugin/api.py)
- Neovim: [nvim-lspconfig CONTRIBUTING](https://github.com/neovim/nvim-lspconfig/blob/master/CONTRIBUTING.md),
  [mason-registry CONTRIBUTING](https://github.com/mason-org/mason-registry/blob/main/CONTRIBUTING.md)
