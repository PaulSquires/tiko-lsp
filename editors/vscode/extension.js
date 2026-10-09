// A VS Code extension that runs tiko-lsp for tiko files.
//
// The extension does almost nothing, and that is the point: VS Code speaks
// LSP, tiko-lsp speaks LSP, and all that is missing between them is a language
// called Tiko and the path to a binary. Everything a user sees -- diagnostics,
// completion, hover, rename, formatting, colour -- comes from the server over
// the wire, not from here. It is the VS Code twin of ../zed, and finds the
// server the same way.
//
// WHERE THE BINARY COMES FROM, in order:
//
//   1. `tiko.server.path` in the settings -- the escape hatch for anyone whose
//      build lives somewhere unusual;
//   2. `tiko-lsp` on the PATH;
//   3. `bin/tiko-lsp(.exe)` inside a workspace folder, so that opening the
//      tiko-lsp repository itself just works after a build.
//
// If none of those finds it, the error says exactly what to do -- an editor
// that silently offers no completions is the worst outcome here, and the one
// most easily produced by starting a command that does not exist.

'use strict';

const fs = require('fs');
const path = require('path');
const vscode = require('vscode');
const { LanguageClient } = require('vscode-languageclient/node');

const SERVER_NAME = 'tiko-lsp';
const EXE = process.platform === 'win32' ? SERVER_NAME + '.exe' : SERVER_NAME;

/** @type {LanguageClient | undefined} */
let client;
/** @type {vscode.OutputChannel | undefined} */
let output;

function isFile(p) {
    try {
        return fs.statSync(p).isFile();
    } catch {
        return false;
    }
}

/** `tiko-lsp` on the PATH, without running anything. */
function onPath() {
    const dirs = (process.env.PATH || '').split(path.delimiter);
    for (const d of dirs) {
        if (!d) continue;
        const cand = path.join(d.replace(/^"|"$/g, ''), EXE);
        if (isFile(cand)) return cand;
    }
    return undefined;
}

/** The server binary, or undefined -- see the order at the top of the file. */
function findServer() {
    const configured = vscode.workspace.getConfiguration('tiko').get('server.path', '');
    // Settings win outright: a path a user named is used even when it is
    // wrong, because guessing past an explicit instruction is how a tool
    // becomes impossible to point somewhere. The error then names that path.
    if (configured) return { path: configured, configured: true };

    const fromPath = onPath();
    if (fromPath) return { path: fromPath, configured: false };

    for (const folder of vscode.workspace.workspaceFolders || []) {
        const cand = path.join(folder.uri.fsPath, 'bin', EXE);
        if (isFile(cand)) return { path: cand, configured: false };
    }
    return undefined;
}

function notFound(message) {
    vscode.window.showErrorMessage(message, 'Open Settings').then((choice) => {
        if (choice === 'Open Settings') {
            vscode.commands.executeCommand('workbench.action.openSettings', 'tiko.server.path');
        }
    });
}

async function start(context) {
    const found = findServer();
    if (!found) {
        notFound(
            `${SERVER_NAME} was not found. Put it on your PATH, or set "tiko.server.path" ` +
            `to the executable. On Windows, yyjson64.dll must sit beside it.`
        );
        return;
    }
    if (found.configured && !isFile(found.path)) {
        notFound(`tiko.server.path names a file that does not exist: ${found.path}`);
        return;
    }

    const cfg = vscode.workspace.getConfiguration('tiko');
    const args = cfg.get('server.arguments', ['--stdio']);

    // The server reads no configuration of its own: what it needs to know
    // about the toolchain arrives here, in `initialize`.
    const initializationOptions = {};
    const includePaths = cfg.get('includePaths', []);
    const packagePaths = cfg.get('packagePaths', []);
    if (includePaths.length > 0) initializationOptions.includePaths = includePaths;
    if (packagePaths.length > 0) initializationOptions.packagePaths = packagePaths;

    // stdio, with the arguments exactly as configured. No `transport` field:
    // the client library would append its own `--stdio` to the command line.
    const serverOptions = {
        run: { command: found.path, args },
        debug: { command: found.path, args },
    };

    const clientOptions = {
        documentSelector: [{ language: 'tiko' }],
        initializationOptions,
        outputChannel: output,
        // The server registers its own file watchers once it is initialized
        // (workspace/didChangeWatchedFiles), so none are configured here.
    };

    client = new LanguageClient('tiko', 'Tiko Language Server', serverOptions, clientOptions);
    output.appendLine(`starting ${found.path} ${args.join(' ')}`);
    try {
        await client.start();
    } catch (err) {
        output.appendLine(`failed to start: ${err && err.message ? err.message : err}`);
        vscode.window.showErrorMessage(`tiko-lsp failed to start: ${err && err.message ? err.message : err}`);
        client = undefined;
    }
}

async function stop() {
    if (!client) return;
    const c = client;
    client = undefined;
    try {
        await c.stop();
    } catch {
        // A server that already exited has nothing left to stop.
    }
}

async function restart(context) {
    await stop();
    await start(context);
}

async function activate(context) {
    output = vscode.window.createOutputChannel('Tiko Language Server');
    context.subscriptions.push(output);

    context.subscriptions.push(
        vscode.commands.registerCommand('tiko.restartServer', () => restart(context)),
        vscode.commands.registerCommand('tiko.showOutput', () => output.show(true)),

        // initializationOptions are read once, at `initialize`: a change to
        // anything the server is started with needs a restart to take effect.
        vscode.workspace.onDidChangeConfiguration((e) => {
            const affected = ['tiko.server.path', 'tiko.server.arguments', 'tiko.includePaths', 'tiko.packagePaths']
                .some((key) => e.affectsConfiguration(key));
            if (!affected) return;
            vscode.window
                .showInformationMessage('Tiko settings changed. Restart the language server?', 'Restart')
                .then((choice) => {
                    if (choice === 'Restart') restart(context);
                });
        })
    );

    await start(context);
}

function deactivate() {
    return stop();
}

module.exports = { activate, deactivate };
