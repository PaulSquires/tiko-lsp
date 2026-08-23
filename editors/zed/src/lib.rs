//! A Zed extension that runs tiko-lsp for FreeBASIC files.
//!
//! The extension does almost nothing, and that is the point: Zed speaks LSP,
//! tiko-lsp speaks LSP, and all that is missing between them is a language
//! called FreeBASIC and the path to a binary. Everything a user sees --
//! diagnostics, completion, hover, rename, formatting, colour -- comes from the
//! server over the wire, not from here.
//!
//! WHERE THE BINARY COMES FROM, in order:
//!
//!   1. `lsp.tiko-lsp.binary.path` in Zed's settings, which is the escape hatch
//!      for anyone whose build lives somewhere unusual;
//!   2. `tiko-lsp` on the PATH;
//!   3. `bin/tiko-lsp` inside the worktree, so that opening the tiko-lsp
//!      repository itself just works after a build.
//!
//! If none of those finds it, the error says exactly what to do -- an editor
//! that silently offers no completions is the worst outcome here, and the one
//! most easily produced by returning a command that does not exist.

use zed_extension_api::{
    self as zed, settings::LspSettings, Command, LanguageServerId, Result, Worktree,
};

struct TikoLspExtension;

/// The name a user writes in `settings.json` under `lsp`, and the name the
/// binary has on disk.
const SERVER_NAME: &str = "tiko-lsp";

/// `--stdio` is the transport tiko-lsp is written for, and the only one it has.
/// It is passed explicitly rather than relied on as a default, because a
/// command line that says what it means survives a change of defaults.
const DEFAULT_ARGS: &[&str] = &["--stdio"];

impl TikoLspExtension {
    /// The binary a worktree should use, or `None` if nothing plausible exists.
    fn find_binary(&self, worktree: &Worktree) -> Option<String> {
        if let Some(path) = worktree.which(SERVER_NAME) {
            return Some(path);
        }

        // A built copy inside the project being edited. This is what makes the
        // extension work while developing the server itself: build it, and the
        // window you built it in picks it up.
        let root = worktree.root_path();
        for candidate in [
            format!("{root}/bin/{SERVER_NAME}.exe"),
            format!("{root}/bin/{SERVER_NAME}"),
        ] {
            if worktree.read_text_file(&candidate).is_ok() {
                return Some(candidate);
            }
        }

        None
    }
}

impl zed::Extension for TikoLspExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        worktree: &Worktree,
    ) -> Result<Command> {
        // Settings win outright: if a user named a path, that path is used even
        // when it is wrong, because guessing past an explicit instruction is
        // how a tool becomes impossible to point somewhere.
        let settings = LspSettings::for_worktree(language_server_id.as_ref(), worktree).ok();
        let binary_settings = settings.and_then(|settings| settings.binary);

        let configured_path = binary_settings
            .as_ref()
            .and_then(|binary| binary.path.clone());
        let configured_args = binary_settings
            .as_ref()
            .and_then(|binary| binary.arguments.clone());

        let command = match configured_path {
            Some(path) => path,
            None => self.find_binary(worktree).ok_or_else(|| {
                format!(
                    "tiko-lsp was not found. Put it on your PATH, or set it in Zed's \
                     settings:\n\n  \"lsp\": {{ \"{SERVER_NAME}\": {{ \"binary\": {{ \
                     \"path\": \"C:/path/to/{SERVER_NAME}.exe\" }} }} }}\n\n\
                     On Windows, yyjson64.dll must sit beside the executable."
                )
            })?,
        };

        Ok(Command {
            command,
            args: configured_args
                .unwrap_or_else(|| DEFAULT_ARGS.iter().map(|arg| arg.to_string()).collect()),

            // The server reads no environment of its own; it is given the
            // editor's so that a PATH-relative DLL beside the binary resolves
            // the way it would from a shell.
            env: worktree.shell_env(),
        })
    }
}

zed::register_extension!(TikoLspExtension);
