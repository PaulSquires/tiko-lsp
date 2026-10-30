# tiko-lsp

**Editor support for the [tiko](https://tiko-lang.net/) programming language.**

tiko-lsp is a *language server*: a small program your editor runs in the background
to understand tiko code. It gives you red underlines for mistakes as you type,
completion, hover help, go to definition, find references, rename, formatting and more.
One server works in every editor that speaks the Language Server Protocol (LSP).

- **Installed tiko?** Then you already have the server: it comes with the toolchain,
  beside the compiler. See [Where the server is](#where-the-server-is).
- **VS Code users:** install the **Tiko** extension and you are done. The extension
  carries its own copy of the server. See [Quick start](#quick-start-vs-code).
- **Other editors:** see [Other editors](#other-editors).

tiko is FreeBASIC-compatible, so the server also reads FreeBASIC-style code.

---

## Contents

- [What you get](#what-you-get)
- [What is available](#what-is-available)
- [Where the server is](#where-the-server-is)
- [Quick start (VS Code)](#quick-start-vs-code)
- [Connect the tiko toolchain](#connect-the-tiko-toolchain)
- [Build and run (VS Code)](#build-and-run-vs-code)
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
| **Signature help** | Shows the parameter list while you type a call, with the current parameter highlighted. It covers the built-ins too, such as `left`, `mid` and `instr`. |
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

| Editor | How you install it | Where the server comes from | Status |
| --- | --- | --- | --- |
| **VS Code** | Extensions view: search **tiko**, install **Tiko** by Paul Squires | The extension | Available |
| **VSCodium**, Cursor, Windsurf and other VS Code-based editors | Their Extensions view (Open VSX): search **tiko** | The extension | Available |
| **Zed** | Dev extension, from this repository | The tiko toolchain | Manual install; store listing planned |
| **Neovim** 0.10+ | Plugin, from this repository | The tiko toolchain | Manual install; plugin repository planned |
| **Sublime Text** 4 | `LSP-tiko`, from this repository | The tiko toolchain | Manual install; Package Control listing planned |
| **Helix** and any other LSP editor | A few lines of configuration | The tiko toolchain | Works today |

### Platforms

| System | VS Code extension | In the tiko toolchain |
| --- | --- | --- |
| Windows 10/11, x64 | Yes | Yes |
| Linux x64 (glibc 2.34 or newer: Ubuntu 22.04+, Debian 12+, Fedora 36+, RHEL 9+) | Yes | Yes |
| macOS 13+ on Apple silicon (M1 or newer) | Yes | Yes |
| Intel Macs, Windows on ARM, Linux on ARM | No | No |

On a platform that is not listed, the VS Code extension shows "not available for your
platform". That is expected: there is no server build for that platform yet.

---

## Where the server is

The server is one program with no dependencies. Every tiko release carries it, next
to the compiler:

| System | The server | The compiler |
| --- | --- | --- |
| Windows | `tiko-lang\tiko-lsp.exe` | `tiko-lang\tiko.exe` |
| Linux, macOS | `tiko-lang/bin/tiko-lsp` | `tiko-lang/bin/tiko` |

So if `tiko` is on your `PATH`, `tiko-lsp` is too, and most editors find it with no
setting. If it isn't, name the `tiko-lang` folder in your editor's settings, as
[Other editors](#other-editors) shows. The server then also uses that toolchain's
headers and packages, so `std/` and `windows.bi` names complete.

Check the version you have:

```bash
tiko-lsp --version
```

It prints to *stderr*, which every terminal shows. The server and the compiler come from
the same release, so they always match.

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

## Build and run (VS Code)

The extension builds and runs with the tiko compiler from the toolchain it found
(see [Connect the tiko toolchain](#connect-the-tiko-toolchain)). It needs clang, as tiko
itself does; the [install steps](https://tiko-lang.net/#install) cover it.

| To | Do |
| --- | --- |
| **Run** the program | Click **▶** at the top right of a tiko editor, press `Ctrl+F5` (`Cmd+F5` on a Mac), or run **Tiko: Run**. |
| **Build** without running | `Ctrl+Shift+B` and choose **tiko: build …**, or run **Tiko: Build**. |
| **Check** for errors without building | **Tiko: Check (no build)**. |

What gets built:

- **A project:** when a `tiko.toml` is in the file's folder or a folder above it, that
  project is built (`tiko build`, `tiko run`). Its profiles and targets apply.
- **A single file:** otherwise, the file you are editing. The program is written next to
  it (`hello.exe` on Windows, `hello` elsewhere).

The build runs in VS Code's terminal, and the program runs there too, so it can read
input. The compiler's errors and warnings go to the **Problems** view (`Ctrl+Shift+M`),
including the ones only the compiler can find, such as an undeclared name. Click one to
jump to it. Open files are saved first.

Options:

```jsonc
"tiko.build.arguments": ["-g", "-exx"],    // compiler options: debug info, runtime checks
"tiko.run.arguments": ["input.txt"]         // passed to your program
```

For more control, add tasks of type `tiko` to `.vscode/tasks.json`. VS Code completes
their fields:

```jsonc
{
  "version": "2.0.0",
  "tasks": [
    {
      "type": "tiko",
      "command": "run",                  // build | run | check
      "file": "tools/gen.tiko",          // optional: this root file instead of the project
      "args": ["-O2"],
      "runArgs": ["--verbose"],
      "label": "run the generator"
    }
  ]
}
```

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

### Other editors: update tiko

The server in your other editors is the one in the tiko toolchain, so **installing a
newer tiko updates it**. Unpack the new release over the old `tiko-lang` folder (or in
its place), then restart the server from your editor, or restart the editor.

VS Code keeps using the server inside its extension, which updates with the extension.
After a new tiko, run **Tiko: Restart Language Server**, so the server reads the new
toolchain's headers and packages.

On macOS, download tiko with `curl` as tiko-lang.net shows. An archive a browser
downloaded is quarantined, and macOS refuses to run the programs in it until you clear
the flag:

```bash
xattr -dr com.apple.quarantine tiko-lang
```

---

## Other editors

Every editor below runs the same server: the one in your tiko toolchain
([where it is](#where-the-server-is)). Each one needs:

1. the server program. The Zed, Neovim and Sublime packages in this repository find it
   by themselves: in the `tiko-lang` folder you name in their settings, then on your
   `PATH`, then (Neovim and Sublime) in a `tiko-lang` folder in your home or Downloads
   folder. Any other editor: give it the full path, or put `tiko-lang` (on Linux and
   macOS, `tiko-lang/bin`) on your `PATH`;
2. the file extensions `.tiko`, `.ti` and `.tko` mapped to the language `tiko`;
3. optionally, the toolchain: send `toolchainPath` (the `tiko-lang` folder) as an LSP
   *initialization option*. Without it, the server uses the toolchain it is installed in,
   then looks in the [usual places](#usually-nothing-to-do). The server also accepts
   `includePaths`, `packagePaths` and `compilerPath`, which mean the same as the
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
| `tiko.build.arguments` | `[]` | Compiler options for Build and Run, such as `-g` or `-exx`. |
| `tiko.run.arguments` | `[]` | Arguments that **Tiko: Run** passes to your program. |
| `tiko.server.path` | `""` | Use a different `tiko-lsp` program instead of the one included with the extension. |
| `tiko.server.arguments` | `["--stdio"]` | Arguments for the server. See [Troubleshooting](#troubleshooting) for logging. |
| `tiko.trace.server` | `"off"` | `messages` or `verbose` logs the editor ↔ server traffic in the output channel. |

Commands (Command Palette, `Ctrl+Shift+P`):

- **Tiko: Run** (`Ctrl+F5`), **Tiko: Build**, **Tiko: Check (no build)**
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
In VS Code: your platform has no included server (see [Platforms](#platforms)), or you
built the extension yourself. Set `tiko.server.path` to the `tiko-lsp` in your tiko
toolchain. In other editors: name your `tiko-lang` folder in the editor's settings, or
put it (on Linux and macOS, its `bin`) on your `PATH`. See
[Where the server is](#where-the-server-is).

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
- No debugger in VS Code yet. **Tiko: Run** builds and runs; `tiko.build.arguments`
  with `-exx` adds runtime checks that report the failing line.

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
- **Other editors:** the server goes with the tiko toolchain. Remove the editor's tiko
  package or settings to stop it starting.

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
