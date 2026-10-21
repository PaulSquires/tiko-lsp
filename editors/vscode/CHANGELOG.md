# Changelog

The extension's version is the version of the tiko-lsp server it includes.

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
