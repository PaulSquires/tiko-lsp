# Tiko for VS Code

Language support for **tiko** -- the FreeBASIC-compatible language of tiko-lang
-- served by [tiko-lsp](../../README.md). The VS Code twin of the
[Zed extension](../zed): a language called Tiko, the path to a binary, and the
toolchain settings the server needs. Everything else -- diagnostics,
completion, hover, go to definition, references, rename, signature help,
semantic tokens, inlay hints, formatting and quick fixes -- comes from the
server.

Files: `.tiko`, `.tko`, `.ti`, and the legacy `.bas`, `.bi`, `.inc`.

## Build and install

```bash
cd editors/vscode
npm install
npm run package
code --install-extension tiko-lsp.vsix
```

`npm run package` writes `tiko-lsp.vsix`. The extension is plain JavaScript
(`extension.js`), so there is no compile step.

## Where it looks for the server

In order:

1. `tiko.server.path` in your settings;
2. `tiko-lsp` on your `PATH`;
3. `bin/tiko-lsp.exe` inside a workspace folder -- so opening the tiko-lsp
   repository itself works after a build.

If none of those finds it, the extension says so and offers to open the
setting. On Windows, `yyjson64.dll` must sit beside the executable (the build
puts it there).

## Settings

```jsonc
{
  "tiko.server.path": "C:/dev/tiko-lsp/bin/tiko-lsp.exe",

  // The toolchain's inc: Win32, AfxNova and runtime names complete, hover and
  // show signatures. Its sibling pkg -- what #import "std/strings" names -- is
  // found on its own.
  "tiko.includePaths": ["C:/dev/tiko-editor-tiko/toolchains/tiko-windows/inc"],

  // Only if pkg is not beside an include path.
  "tiko.packagePaths": [],

  // Server arguments. Add "--log-level", "debug", "--log-file", "C:/temp/tiko-lsp.log"
  // to see what the server is doing; it never writes to stdout.
  "tiko.server.arguments": ["--stdio"],

  // The LSP traffic, in the "Tiko Language Server" output channel.
  "tiko.trace.server": "off"
}
```

`includePaths` and `packagePaths` are sent as `initializationOptions`, which a
server reads once: changing them, the path or the arguments offers a restart.
**Tiko: Restart Language Server** does it by hand.

## Colour

VS Code does not load tree-sitter grammars, so colour before the server is up
comes from a TextMate grammar, `syntaxes/tiko.tmLanguage.json`. Its word lists
are generated from the Zed highlights query (`python
syntaxes/gen_tmlanguage.py`), so both editors colour the same words. Once the
server is running, its semantic tokens refine it.

## Workspace trust

The extension does not run in Restricted Mode: starting the server means
running an executable named in settings or found in the workspace.

## What is verified

See the commit that added this directory for what was measured against a real
VS Code. In short: the extension installs from the `.vsix`, activates on a
`.bas` file, starts the server with the configured arguments and
`initializationOptions`, and the server answers VS Code's requests.
