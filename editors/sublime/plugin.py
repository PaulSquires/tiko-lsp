"""LSP-tiko: runs tiko-lsp for tiko files in Sublime Text, through the LSP package.

The package does almost nothing, and that is the point: Sublime's LSP package
speaks LSP, tiko-lsp speaks LSP, and all that is missing between them is a
syntax called Tiko and the path to a binary. Everything a user sees --
diagnostics, completion, hover, rename, formatting, colour -- comes from the
server over the wire, not from here. It is the Sublime twin of ../zed and
../vscode, and finds the server the same way.

WHERE THE BINARY COMES FROM, in order:

  1. `server_path` in LSP-tiko.sublime-settings -- the escape hatch for anyone
     whose build lives somewhere unusual;
  2. `tiko-lsp` on the PATH;
  3. `bin/tiko-lsp(.exe)` inside a workspace folder, so that opening the
     tiko-lsp repository itself just works after a build.

If none of those finds it, starting fails with a message that says what to set
-- an editor that silently offers no completions is the worst outcome here,
and the one most easily produced by starting a command that does not exist.
"""
import os
import shutil

import sublime
from LSP.plugin import AbstractPlugin, ClientConfig, WorkspaceFolder, register_plugin, unregister_plugin
from LSP.plugin.core.typing import List, Optional

SESSION_NAME = "tiko"
SETTINGS_FILENAME = "LSP-tiko.sublime-settings"
SERVER_NAME = "tiko-lsp"


def _exe() -> str:
    return SERVER_NAME + ".exe" if sublime.platform() == "windows" else SERVER_NAME


def _settings() -> sublime.Settings:
    return sublime.load_settings(SETTINGS_FILENAME)


def find_server(workspace_folders: List[WorkspaceFolder]) -> Optional[str]:
    """The server binary, or None -- see the order at the top of the file."""
    configured = _settings().get("server_path") or ""
    # Settings win outright: a path a user named is used even when it is
    # wrong, because guessing past an explicit instruction is how a tool
    # becomes impossible to point somewhere. The caller checks it exists.
    if configured:
        return os.path.expandvars(os.path.expanduser(configured))

    on_path = shutil.which(SERVER_NAME)
    if on_path:
        return on_path

    for folder in workspace_folders:
        candidate = os.path.join(folder.path, "bin", _exe())
        if os.path.isfile(candidate):
            return candidate
    return None


class Tiko(AbstractPlugin):
    @classmethod
    def name(cls) -> str:
        return SESSION_NAME

    @classmethod
    def on_pre_start(
        cls,
        window: sublime.Window,
        initiating_view: sublime.View,
        workspace_folders: List[WorkspaceFolder],
        configuration: ClientConfig,
    ) -> Optional[str]:
        path = find_server(workspace_folders)
        if not path:
            raise ValueError(
                "tiko-lsp was not found. Put it on your PATH, or set \"server_path\" in "
                "Preferences > Package Settings > LSP > Servers > LSP-tiko."
            )
        if not os.path.isfile(path):
            raise ValueError("LSP-tiko: server_path names a file that does not exist: {}".format(path))

        # The configuration persists between starts: the command is rebuilt
        # from scratch every time, or a restart would append the arguments twice.
        arguments = _settings().get("server_arguments") or ["--stdio"]
        configuration.command = [path] + list(arguments)
        return None


def plugin_loaded() -> None:
    register_plugin(Tiko)


def plugin_unloaded() -> None:
    unregister_plugin(Tiko)
