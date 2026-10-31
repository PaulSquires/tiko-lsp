# Tiko for VS Code

Language support for **tiko**, the FreeBASIC-compatible language: diagnostics,
completion, hover, go to definition, find references, rename, signature help,
semantic colouring, inlay hints, formatting and quick fixes.

All of it comes from [tiko-lsp](https://github.com/PaulSquires/tiko-lsp), a
language server written in tiko. **The server is included**: install the
extension, open a `.tiko` file, and it starts. There is nothing else to download
and no setting to change.

- Platforms: **Windows x64**, **Linux x64** and **macOS on Apple silicon** (macOS 13
  or later). VS Code installs the build for your platform automatically.
- Files: `.tiko`, `.tko`, `.ti`.

## Getting started

1. Install **Tiko** from the Extensions view (search for `tiko`).
2. Open a folder containing tiko sources, then open a `.tiko` file.
3. To see the server's own messages, run **Tiko: Show Language Server Output**.

### Win32, runtime and `std` names

For `#import "std/strings"`, `windows.bi` and the runtime's names to complete, hover
and show signatures, the server needs the tiko toolchain
([download it](https://tiko-lang.net/#install) if you don't have it yet).

**Usually there is nothing to do.** The server finds the `tiko-lang` folder in your home
folder, in Downloads (also one level down, where Windows' *Extract All* puts it), at
`C:\tiko-lang`, `/opt/tiko-lang` or `~/.local/tiko-lang`, or through a `tiko` on your
`PATH`.

If it finds none, the extension says so once per window and offers **Locate
Toolchain…**. Choose your `tiko-lang` folder; the extension saves it and restarts the
server. You can run **Tiko: Locate Toolchain…** from the Command Palette at any time,
or set the folder yourself:

```jsonc
{
  "tiko.toolchainPath": "D:/tools/tiko-lang"
}
```

**Tiko: Show Language Server Output** shows the toolchain the server used.

### Build and run

- **Run:** the **▶** button at the top right of a tiko editor, `Ctrl+F5` (`Cmd+F5` on a
  Mac), **Run ▸ Run Without Debugging**, or **Tiko: Run**.
- **Build:** `Ctrl+Shift+B`, then **tiko: build …**, or **Tiko: Build**.
- **Check** (every error, nothing written): **Tiko: Check (no build)**.

When a `tiko.toml` is at or above the file, the project is built (`tiko build`,
`tiko run`). Otherwise the file itself is built, and the program is written next to it.
Both run in the terminal, so the program can read input. Compiler errors, including
the ones only the compiler finds, go to the **Problems** view.

`tiko run` runs one target. When the `tiko.toml` has more than one exe target, the one
whose `main` or `sources` hold the open file runs; if that does not decide it, you are
asked once per project, and **Tiko: Select Run Target...** changes the answer.

`tiko.build.arguments` adds compiler options (`-g`, `-exx`), and `tiko.run.arguments`
passes arguments to the program. Tasks of type `tiko` in `.vscode/tasks.json` take
`command` (`build`, `run` or `check`), `file`, `target`, `args` and `runArgs`; a
`tiko` entry in `.vscode/launch.json` takes `file`, `target`, `args` and `runArgs`.

### Legacy FreeBASIC files

Older tiko projects use FreeBASIC's `.bas`, `.bi` and `.inc` extensions. Other
languages use those too, so this extension does not claim them by default. To
treat them as tiko, add:

```jsonc
{
  "files.associations": {
    "*.bas": "tiko",
    "*.bi": "tiko",
    "*.inc": "tiko"
  }
}
```

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `tiko.toolchainPath` | `""` | The `tiko-lang` folder you unpacked. Leave it empty to have it found automatically. **Tiko: Locate Toolchain…** sets it. |
| `tiko.includePaths` | `[]` | Override: the toolchain's `inc` folders, for an unusual layout. |
| `tiko.packagePaths` | `[]` | Where `#import` packages are found, if not in the `pkg` folder beside an include path. |
| `tiko.compilerPath` | `""` | A `tiko` compiler the server may ask about each folder's `tiko.toml` (`tiko metadata`), so imports resolve exactly as the compiler resolves them. Never run for diagnostics. Empty: the compiler in the toolchain folder, else a `tiko` on the `PATH`. |
| `tiko.build.arguments` | `[]` | Compiler options for Build and Run, such as `-g` or `-exx`. |
| `tiko.run.arguments` | `[]` | Arguments **Tiko: Run** passes to the program. |
| `tiko.server.path` | `""` | Use a different `tiko-lsp` executable instead of the included one. |
| `tiko.server.arguments` | `["--stdio"]` | Server arguments. Add `"--log-level", "debug", "--log-file", "C:/temp/tiko-lsp.log"` to see what the server is doing. |
| `tiko.trace.server` | `"off"` | Log the LSP traffic in the **Tiko Language Server** output channel. |

**Tiko: Locate Toolchain…** chooses the toolchain folder. **Tiko: Restart Language
Server** restarts the server by hand.

## Which server runs

In order:

1. `tiko.server.path`, if set;
2. the server included with the extension;
3. `tiko-lsp` on your `PATH`;
4. `bin/tiko-lsp(.exe)` inside a workspace folder.

The output channel's first line names the binary and where it was found. If none
is found (on a platform the extension has no build for), the extension says so
and offers to open the setting.

## Workspace trust

The extension does not run in Restricted Mode, because starting the server means
running an executable.

## Colour

Before the server is up, colour comes from a TextMate grammar. Once it is
running, the server's semantic tokens refine it.

## Building from source

The extension is plain JavaScript (`extension.js`), so there is no compile step.
From `editors/vscode` in the tiko-lsp repository:

```bash
npm install
npm run package
code --install-extension tiko.vsix
```

That development package includes no server. It finds one through
`tiko.server.path`, the `PATH`, or `bin/` in the workspace. The platform packages
that are published are built by `release/vscode/package.sh`.

## Licence

MIT. The included server's third-party notices are in
`server/THIRD-PARTY-NOTICES.txt` inside the installed extension.
