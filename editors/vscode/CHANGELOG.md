# Changelog

The extension's version is the version of the tiko-lsp server it includes.

## Unreleased

- **`match`** (tiko after 0.1.6): a match statement (`case` arms) and a match used as a value
  (`pattern => value` arms) open a block closed by `end match`, so their arms are no longer
  "case outside a select" errors, format like `select case`, and `Foo( match x` … `end match )`
  balances. `match` and `starts` colour as keywords only there -- a variable, sub or function
  called `match` stays a name, and `end match` outside a match is still END -- and the names a
  pattern binds (`Point( x, y )`, `c as Circle`, `starts "load " rest`) hover and complete as
  locals. Completion offers `match`.

## 0.1.6

- **Linux on arm64**: a `linux-arm64` extension and server, for tiko's new aarch64 Linux
  toolchain (Ubuntu 22.04 and later).
- **`int128` and `uint128`** complete, colour and hover as built-in types (16 bytes).
- **A `var` takes its initializer's type**: after `var v = GetCustomer( )`, `v.` completes
  `Customer`'s members, and hovering `v` shows the type, also through `new` and `@`.
- **Array slices**: `span( of T )` highlights as a type -- only before
  its `( of`, so a variable called `span` stays a name -- is offered by completion with the
  slice types, and hovers with its element. `v( i ).` completes the element type's members,
  as an array element does.

## 0.1.5

- **The version follows tiko's.** The extension, the server and the tiko toolchain now
  share one version number: this is the server shipped with tiko 0.1.5 (there is no 0.1.4
  of the extension).
- **The extension is `PaulSquires.tiko-lang`**, shown as **tiko-lang**. Commands are under
  **tiko:** in the Command Palette (**tiko: Run**, **tiko: Build**, **tiko: Locate
  Toolchain...**), and the output channel is **tiko Language Server**.
- **Newer tiko syntax understood:** `partial type` and `partial class` (with `partial` as a
  modifier); string slices -- `type X as view` blocks and the `slice`, `uslice` and `wslice`
  types, which highlight as types; interfaces and classes; a property's `set` / `end set`.
- Completion offers the types after a generic's `( of ` and after each comma in its list.
- No parameter-name inlay hints on an out-of-line method's own header
  (`function Task.IsDueOn( ...`).
- The server reads `TIKO_PKG` and `TIKO_INCLUDE`, as tiko does.
- On Linux and macOS the server no longer crashes while it indexes the workspace in the
  background (its index threads now ask for a 1 MiB stack, as Windows gives by default).

## 0.1.3

- **The toolchain is found for you.** The server looks for the `tiko-lang` folder in your
  home folder, in Downloads (also one level down, where Windows' Extract All puts it), at
  `C:\tiko-lang`, `/opt/tiko-lang` or `~/.local/tiko-lang`, and for a `tiko` on the `PATH`.
  `std/` and `windows.bi` names then complete with no setting.
- New setting `tiko.toolchainPath`: the `tiko-lang` folder. The headers, the packages and
  the compiler are all taken from it; `tiko.includePaths`, `tiko.packagePaths` and
  `tiko.compilerPath` still override them one by one.
- New command **Tiko: Locate Toolchain...**: choose the folder, and the extension checks
  it, saves it and restarts the server. When no toolchain is found, the extension offers
  it once per window, with **Don't Ask Again**.
- The output channel shows the toolchain the server used.
- The server uses the toolchain it is installed in: a tiko release carries tiko-lsp
  beside the compiler, for the editors other than VS Code.
- **Build and run.** **Tiko: Run** (`Ctrl+F5`, or the ▶ button on a tiko editor), **Tiko:
  Build** (also under `Ctrl+Shift+B`) and **Tiko: Check (no build)** run `tiko run`,
  `tiko build` and `tiko check` in the terminal. A project is built when a `tiko.toml` is
  at or above the file; otherwise the file itself is built. Compiler errors go to the
  Problems view, through the new `$tiko` problem matcher.
- New task type `tiko` for `.vscode/tasks.json` (`command`, `file`, `args`, `runArgs`),
  and settings `tiko.build.arguments` and `tiko.run.arguments`.
- `tiko-lsp --version` names the tiko compiler it was built with, not FreeBASIC.
- **Built-ins have codetips.** `left(`, `mid(`, `instr(` and about 190 other built-in
  procedures show their parameters while you type a call, show their codetip on hover,
  and are offered by completion as functions. The codetips are tkEdit's own.
- Typing `dim x as` at the end of a file no longer stops the server. It read one token
  past the end of the statement before the type was typed.
- **Completion knows where a type goes.** After `as ` it offers types only -- your own,
  typedefs and the built-in ones. After `->` it offers members, as after `.`.
- **F5 and Ctrl+F5 run the program**, with no `launch.json`: both build and run it
  through `tiko run`, instead of asking for a debugger from the Marketplace.
- **A project with several programs**: when `tiko.toml` names more than one exe target,
  **Tiko: Run** runs the one whose sources hold the file you are in, or asks once and
  remembers. New command **Tiko: Select Run Target...**, and a `target` property for
  `tiko` tasks and launch configurations.
- A type, union or enum named after a reserved word -- `type Point`, `union Color`,
  `enum Line` -- is a symbol: it is in the outline, and hover, completion and go to
  definition find it.
- A typed enum -- `enum Small as uint8` -- is no longer an error.
- `ustring` is coloured as a built-in type, and `select channel` as one statement.

## 0.1.2

- **macOS on Apple silicon** (macOS 13 or later): the server is included, as it is
  for Windows x64 and Linux x64.
- A long editing session stays fast. Opening, editing and closing a file used to get
  slower with every file the session had seen, until each took several hundred
  milliseconds; it now stays flat (about 25-40 ms per file over 1,200 files).
- Files opened after the first eight are no longer lost by the server: their edits,
  closes and diagnostics are tracked again. (The fault was in the tiko toolchain's
  `std/containers` Map, which the server is now built with fixed.)
- An anonymous nested `type` (a bare `type` line inside a `union`) no longer stops the
  server.
- The server's JSON is now cJSON, from the tiko toolchain, in place of yyjson. The
  server is smaller (about 865 KB on Windows) and builds from the toolchain alone.

## 0.1.1

- The extension's icon is the tiko mascot.
- The server reads tiko-lang's newer code without false errors:
  - `select channel` (std/tasks): its `case receive ... from`, `case send ... to`,
    `case timeout` and `case else` arms are inside the SELECT, and format like
    `select case`.
  - Fields named after keywords, as C bindings made by `#cinclude` keep them:
    `next as cJSON ptr`, `function as const zstring ptr`.
  - A `#define` or `#macro` body is not checked until it is used, so a malformed
    number there (SDL3's `_asm ( long 0x03 )`) is no longer an error.
  - `sys/` is reserved for the toolchain, like `std/` and `vendor/`.

## 0.1.0

First Marketplace release.

- The tiko-lsp server is included, for Windows x64 and Linux x64.
- Files: `.tiko`, `.tko`, `.ti`. Legacy `.bas`, `.bi` and `.inc` are opt-in through
  `files.associations`.
- Diagnostics, completion, hover, go to definition, references, rename, signature
  help, semantic tokens, inlay hints, formatting and quick fixes.
- Settings: `tiko.includePaths`, `tiko.packagePaths`, `tiko.compilerPath`,
  `tiko.server.path`, `tiko.server.arguments`, `tiko.trace.server`.
