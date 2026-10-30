# tiko-lsp

**Editor support for the [tiko](https://tiko-lang.net/) programming language.**

tiko-lsp is a *language server*: a small program your editor runs in the background
to understand tiko code. It gives you red underlines for mistakes as you type,
completion, hover help, go to definition, find references, rename, formatting and more.
One server works in every editor that speaks the Language Server Protocol (LSP).

- **VS Code users:** install the **Tiko** extension and you are done. The server is
  included. See [Quick start](#quick-start-vs-code).
- **Other editors:** see [Other editors](#other-editors).

tiko is FreeBASIC-compatible, so the server also reads FreeBASIC-style code.

---

## Contents

- [What you get](#what-you-get)
- [What is available](#what-is-available)
- [Quick start (VS Code)](#quick-start-vs-code)
- [Connect the tiko toolchain](#connect-the-tiko-toolchain)
- [Updating](#updating)
- [Other editors](#other-editors)
- [Settings (VS Code)](#settings-vs-code)
- [Troubleshooting](#troubleshooting)
- [Known limitations](#known-limitations)
- [Reporting a problem](#reporting-a-problem)
- [Uninstalling](#uninstalling)
- [For contributors](#for-contributors)
- [Licence](#licence)

---

## What you get

| Feature | What it does |
| --- | --- |
| **Diagnostics** | Underlines structural mistakes as you type, such as an `if` with no `end if` or an unclosed string. |
| **Completion** | Suggests variables, procedures, types, fields after `.`, and module exports after `strings.`. |
| **Hover** | Shows the declaration and signature of the name under the mouse. |
| **Go to definition** | `F12` jumps to where a name is declared. It works across files, into `#include`d headers and into `#import`ed modules. |
| **Find references** | `Shift+F12` lists every use of a name in the workspace. |
| **Rename** | `F2` renames a name everywhere it is used. A rename it cannot do safely is refused, with the reason. |
| **Signature help** | Shows the parameter list while you type a call, with the current parameter highlighted. |
| **Inlay hints** | Shows parameter names at call sites, for example `Move(x: 10, y: 20)`. |
| **Semantic colouring** | Colours types, procedures, variables and constants by what they are, not only by how they look. |
| **Formatting** | Re-indents a file or a selection. It never touches code that has errors. |
| **Quick fixes** | One-click fixes for simple mistakes, such as a missing closing quote. |
| **Outline** | Lists the file's procedures, types and constants, in the Outline view and in breadcrumbs. |
| **Workspace symbols** | `Ctrl+T` finds any procedure or type in the project by name. |

The server reads your code itself. It does not need to compile anything to give you
these features, so it stays fast: about 1 ms to check a 900-line file.

---

## What is available

### Editors

| Editor | How you install it | Server included? | Status |
| --- | --- | --- | --- |
| **VS Code** | Extensions view: search **tiko**, install **Tiko** by Paul Squires | Yes | Available |
| **VSCodium**, Cursor, Windsurf and other VS Code-based editors | Their Extensions view (Open VSX): search **tiko** | Yes | Available |
| **Zed** | Dev extension, from this repository | No: [download it](#the-server-on-its-own) | Manual install; store listing planned |
| **Neovim** 0.10+ | Plugin, from this repository | No | Manual install; plugin repository planned |
| **Sublime Text** 4 | `LSP-tiko`, from this repository | No | Manual install; Package Control listing planned |
| **Helix** and any other LSP editor | A few lines of configuration | No | Works today |

### Platforms

| System | VS Code extension | Server download |
| --- | --- | --- |
| Windows 10/11, x64 | Yes | `tiko-lsp-windows-x86_64.zip` |
| Linux x64 (glibc 2.34 or newer: Ubuntu 22.04+, Debian 12+, Fedora 36+, RHEL 9+) | Yes | `tiko-lsp-linux-x86_64.tar.gz` |
| macOS 13+ on Apple silicon (M1 or newer) | Yes | `tiko-lsp-macos-arm64.tar.gz` |
| Intel Macs, Windows on ARM, Linux on ARM | No | No |

On a platform that is not listed, the VS Code extension shows "not available for your
platform". That is expected: there is no server build for that platform yet.

---

## Quick start (VS Code)

1. **Install the extension.** In VS Code, open the Extensions view (`Ctrl+Shift+X`, or
   `Cmd+Shift+X` on a Mac), search for `tiko` and install **Tiko** by *Paul Squires*.
2. **Open a folder.** Use *File → Open Folder…* and choose your project folder. The
   server indexes the whole folder, so opening a single file gives you less.
3. **Open a `.tiko` file.** Colouring appears at once. The server starts within a second.
   Type a mistake, such as `if x then` with no `end if`, and it is underlined.
4. **The tiko toolchain** is found automatically if you unpacked it in your home or
   Downloads folder. If it isn't found, VS Code offers **Locate Toolchain…** once:
   choose your `tiko-lang` folder. See
   [Connect the tiko toolchain](#connect-the-tiko-toolchain).

If VS Code asks whether you trust the folder's authors, choose **Trust**. The extension
does not run in Restricted Mode, because starting the server means running a program.

To check that the server is running, run **Tiko: Show Language Server Output** from the
Command Palette (`Ctrl+Shift+P`). Its first line names the server it started and where
that server came from.

### Files the extension handles

`.tiko` (source), `.ti` (header) and `.tko` (older source) are tiko files.

Older projects use FreeBASIC's `.bas`, `.bi` and `.inc`. Other languages use those
extensions too, so the extension does not take them over unless you ask it to. To
treat them as tiko, add this to your settings (`Ctrl+,`, then the `{}` icon at the top
right):

```jsonc
"files.associations": {
  "*.bas": "tiko",
  "*.bi": "tiko",
  "*.inc": "tiko"
}
```

Put it in the folder's settings (`.vscode/settings.json`) instead of your user settings
if you also edit other BASIC dialects.

---

## Connect the tiko toolchain

The editor features above work on your own code with no setup. To also complete,
hover and show signatures for the **standard library** (`#import "std/strings"`) and
the **system headers** (`#include "windows.bi"`), the server needs the tiko toolchain.

Don't have tiko yet? Download it from **<https://tiko-lang.net/#install>** and unpack
it. You get one folder, `tiko-lang`.

### Usually, nothing to do

The server finds the toolchain by itself when you unpacked it in one of these places:

| Where | Example |
| --- | --- |
| Your home folder | `C:\Users\you\tiko-lang`, `/home/you/tiko-lang`, `/Users/you/tiko-lang` |
| Your Downloads folder | `Downloads\tiko-lang` |
| A folder inside Downloads named after the archive (what Windows' *Extract All* makes) | `Downloads\tiko-windows-x86_64-6828165b\tiko-lang` |
| Windows: the top of the system drive | `C:\tiko-lang` |
| Linux and macOS | `/opt/tiko-lang`, `~/.local/tiko-lang` |

The server also uses a `tiko` on your `PATH`. If you want to run `tiko` from any
terminal, add `...\tiko-lang` (Windows) or `.../tiko-lang/bin` (Linux, macOS) to your
`PATH`, then restart your editor.

**Tiko: Show Language Server Output** shows what was found, for example:

```
toolchain: C:\Users\you\tiko-lang  (found automatically)
  headers   C:\Users\you\tiko-lang\inc
  packages  C:\Users\you\tiko-lang\pkg
  compiler  C:\Users\you\tiko-lang\tiko.exe
```

### Somewhere else: Tiko: Locate Toolchain…

If no toolchain is found, VS Code tells you, once per window, with a **Locate Toolchain…**
button (and a **Don't Ask Again** button).
You can also run **Tiko: Locate Toolchain…** from the Command Palette at any time.
Choose the `tiko-lang` folder. The extension checks that it is a toolchain, saves it as
**Tiko: Toolchain Path**, and restarts the server.

Or set it yourself:

```jsonc
"tiko.toolchainPath": "D:/tools/tiko-lang"
```

From that one folder the server takes three things:

- the headers, from `inc`;
- the packages, from `pkg`;
- the compiler, `tiko.exe` (Windows) or `bin/tiko` (Linux, macOS).

With the compiler, the server also asks `tiko` how a `tiko.toml` package's modules and
`#cinclude` C headers resolve, so names from `#cinclude "raylib.h"` complete too. The
server never runs the compiler to check your code.

### Advanced: separate settings

For unusual layouts, `tiko.includePaths`, `tiko.packagePaths` and `tiko.compilerPath`
override the parts of the toolchain one at a time. Whatever you set there wins over
`tiko.toolchainPath`.

---

## Updating

### VS Code and VSCodium

**Updates are automatic.** By default VS Code checks for extension updates and installs
them, and each update includes the matching server. You never update the server
separately.

- **Which version am I running?** In the Extensions view, select **Tiko**: the version
  is under the name. *Tiko: Show Language Server Output* also shows the server version.
- **Update now:** Extensions view → `...` menu → *Check for Extension Updates*.
- **Automatic updates turned off?** Select **Tiko** in the Extensions view and click
  **Update** when it appears.
- **Go back to an older version:** right-click **Tiko** → *Install Specific Version…*.
  VS Code then stops auto-updating Tiko until you install the latest version again.
- **Try new features early:** click **Switch to Pre-Release Version** on the extension's
  page, if one is offered.

What changed in each version is in the extension's **Changelog** tab, and in
[editors/vscode/CHANGELOG.md](editors/vscode/CHANGELOG.md).

### Updating the tiko toolchain

The server reads the toolchain's headers and packages when it starts. After you
install a newer tiko, run **Tiko: Restart Language Server**, or restart the editor.
If you replaced the folder in place, nothing else needs to change.

### The server on its own (other editors)

For editors other than VS Code, the server is a single program with no dependencies.

1. Download the archive for your system from the
   [Releases page](https://github.com/PaulSquires/tiko-lsp/releases/latest).
2. Unpack it to a folder of your choice: for example `C:\tools\tiko-lsp` on Windows, or
   `~/.local/bin` on Linux and macOS.
3. Point your editor at `tiko-lsp` (`tiko-lsp.exe` on Windows), or put that folder on
   your `PATH`.

To update, download the newer archive and replace the file. Then restart the server
from your editor, or restart the editor.

Check the version you have:

```bash
tiko-lsp --version
```

It prints to *stderr*, which every terminal shows.

On macOS, if you downloaded the archive with a browser, clear the quarantine flag once,
or macOS refuses to run the program:

```bash
xattr -d com.apple.quarantine tiko-lsp
```

---

## Other editors

Every editor below runs the same server. Each one needs:

1. the server program ([download](#the-server-on-its-own));
2. the file extensions `.tiko`, `.ti` and `.tko` mapped to the language `tiko`;
3. optionally, the toolchain: send `toolchainPath` (the `tiko-lang` folder) as an LSP
   *initialization option*. Without it, the server looks in the
   [usual places](#usually-nothing-to-do). The server also accepts `includePaths`,
   `packagePaths` and `compilerPath`, which mean the same as the
   [VS Code settings](#settings-vs-code). To turn the search off, send an empty string
   for `toolchainPath` or `compilerPath`.

| Editor | Instructions |
| --- | --- |
| Zed | [editors/zed/README.md](editors/zed/README.md) |
| Neovim | [editors/neovim/README.md](editors/neovim/README.md) (`tiko.nvim`, with `:TikoInfo` and `:TikoRestart`) |
| Sublime Text | [editors/sublime/README.md](editors/sublime/README.md) (`LSP-tiko`, for the LSP package) |

**Helix** (`languages.toml`):

```toml
[language-server.tiko-lsp]
command = "tiko-lsp"
args = ["--stdio"]
config = { toolchainPath = "/home/you/tiko-lang" }

[[language]]
name = "tiko"
scope = "source.tiko"
file-types = ["tiko", "ti", "tko"]
roots = ["tiko.toml", ".git"]
comment-token = "'"
language-servers = ["tiko-lsp"]
```

**Neovim without a plugin** (0.11+):

```lua
vim.filetype.add({ extension = { tiko = 'tiko', ti = 'tiko', tko = 'tiko' } })
vim.lsp.config.tiko_lsp = {
  cmd = { 'tiko-lsp', '--stdio' },
  filetypes = { 'tiko' },
  root_markers = { 'tiko.toml', '.git' },
  init_options = { toolchainPath = '/home/you/tiko-lang' },
}
vim.lsp.enable('tiko_lsp')
```

### Server command line

Editors start the server for you. These options are for configuring it, and for
troubleshooting:

| Option | Meaning |
| --- | --- |
| `--stdio` | Talk over standard input and output. This is the only mode, and the default. |
| `--log-level <level>` | `off`, `error` (default), `warn`, `info`, `debug` or `trace` (logs every message). |
| `--log-file <path>` | Also append the log to a file. |
| `--version`, `--help` | Print to stderr and exit. |

The environment variables `TIKO_LSP_LOG_LEVEL` and `TIKO_LSP_LOG_FILE` do the same as
the flags. The flags win when both are set.

---

## Settings (VS Code)

| Setting | Default | What it does |
| --- | --- | --- |
| `tiko.toolchainPath` | `""` | The `tiko-lang` folder. Leave it empty to have it found automatically. See [Connect the tiko toolchain](#connect-the-tiko-toolchain). |
| `tiko.includePaths` | `[]` | Override: the toolchain's `inc` folder or folders. |
| `tiko.packagePaths` | `[]` | Override: where `#import` packages live. |
| `tiko.compilerPath` | `""` | Override: the `tiko` compiler that the server may ask about `tiko.toml` packages and `#cinclude`. The server never uses it to check your code. |
| `tiko.server.path` | `""` | Use a different `tiko-lsp` program instead of the one included with the extension. |
| `tiko.server.arguments` | `["--stdio"]` | Arguments for the server. See [Troubleshooting](#troubleshooting) for logging. |
| `tiko.trace.server` | `"off"` | `messages` or `verbose` logs the editor ↔ server traffic in the output channel. |

Commands (Command Palette, `Ctrl+Shift+P`):

- **Tiko: Locate Toolchain…**
- **Tiko: Restart Language Server**
- **Tiko: Show Language Server Output**

---

## Troubleshooting

**Nothing happens when I open a `.tiko` file.**
Check the language mode at the bottom right of the window. It should say **Tiko**. If
VS Code shows "Restricted Mode" at the bottom left, the folder is not trusted. Click it
and choose **Trust**.

**"tiko-lsp was not found".**
Your platform has no included server (see [Platforms](#platforms)), or you built the
extension yourself. Put `tiko-lsp` on your `PATH`, or set `tiko.server.path`.

**`std` or `windows.bi` names do not complete, and go to definition does nothing on them.**
The server cannot find the toolchain. Run **Tiko: Locate Toolchain…** and choose your
`tiko-lang` folder. To see what the server found, run **Tiko: Show Language Server
Output** and look at the `toolchain:` line.

**Completion is slow in a project that uses `windows.bi`.**
The Win32 headers declare about 190,000 names. The first full index takes a few seconds
on a background thread. After that, completion costs tens of milliseconds a keystroke.

**A red underline on code that compiles.**
That is a bug in the server. False errors matter most to us, so please
[report it](#reporting-a-problem) with the smallest piece of code that shows it.

**Formatting does nothing.**
The formatter refuses to touch a file that has errors. Fix the underlined problems
first.

**I need to see what the server is doing.**
Set `tiko.server.arguments` to

```jsonc
["--stdio", "--log-level", "debug", "--log-file", "C:/temp/tiko-lsp.log"]
```

then restart the server and read that file. To see the messages themselves, set
`tiko.trace.server` to `verbose` and open **Tiko: Show Language Server Output**.

**The server stopped and VS Code says it will not restart it.**
Run **Tiko: Restart Language Server**. If it keeps stopping, please report it with the
log file and the file you had open.

---

## Known limitations

- **`#if` is not evaluated.** Both branches of `#ifdef UNICODE` are read, so
  completion offers both `MessageBoxA` and `MessageBoxW`.
- **`#define` macros are not indexed.** Object-like macros, such as raylib's colour
  constants, do not complete.
- **No type inference.** After `GetCustomer().` completion offers every known member,
  not only the members of the type that `GetCustomer` returns.
- **References and rename match by name.** They follow the include graph, but two
  unrelated symbols with the same name in files that can see each other are treated as
  one. Rename refuses the cases where that would be unsafe.
- A header that you start `#include`-ing is read at the next full index, not as you type.
  Save the file, or restart the server, to pick it up at once.
- No debugger. Build and run with `tiko` in a terminal, or use tkEdit, which ships with
  the toolchain.

---

## Reporting a problem

Open an issue at <https://github.com/PaulSquires/tiko-lsp/issues>. Include:

1. the extension version, or the output of `tiko-lsp --version`;
2. your operating system and editor version;
3. the smallest piece of tiko code that shows the problem;
4. if the server crashed or misbehaved, the `--log-level debug` log
   ([how](#troubleshooting)).

---

## Uninstalling

- **VS Code / VSCodium:** Extensions view → **Tiko** → **Uninstall**. The server goes
  with it.
- **The server on its own:** delete the `tiko-lsp` program, and remove its folder from
  your `PATH` if you added it.

The server writes nothing to disk except a log file that you asked for. With
`tiko.compilerPath` set, `tiko` keeps its usual build cache.

---

## For contributors

Building the server from source, its architecture, the test suites and the release
process are in [docs/development.md](docs/development.md),
[docs/architecture.md](docs/architecture.md) and [docs/deployment.md](docs/deployment.md).

In short: the server is written in tiko and built with the tiko toolchain:

```bash
build\_compile.bat          # Windows
sh build/_compile.sh        # Linux, macOS
build\_run_tests.bat        # or: sh build/_run_tests.sh
```

---

## Licence

MIT, © 2026 Paul Squires. See [LICENSE](LICENSE).

The server links [cJSON](https://github.com/DaveGamble/cJSON) (MIT) statically. Every
release archive, and the VS Code extension's `server/` folder, includes
`THIRD-PARTY-NOTICES.txt`.
