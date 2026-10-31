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
//   2. `server/tiko-lsp(.exe)` inside this extension -- the copy a Marketplace
//      install carries. Each published .vsix is platform-specific and holds
//      exactly one binary (release/vscode/package.sh). It comes BEFORE the
//      PATH so a stale copy there cannot shadow the one installed with the
//      extension; a developer's own build is named with the setting;
//   3. `tiko-lsp` on the PATH;
//   4. `bin/tiko-lsp(.exe)` inside a workspace folder, so that opening the
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

/**
 * The bundled server, executable. A .vsix is a zip, and one packed on Windows
 * carries no Unix mode bits, so on Linux and macOS the binary may arrive as 0644
 * and spawn would fail with EACCES. Set the bits once; if that is impossible (a
 * read-only install), starting it will say so.
 *
 * On macOS, a binary carrying the com.apple.quarantine attribute is held by
 * Gatekeeper when it is run -- the tiko compiler itself blocks in syspolicyd
 * until the attribute is cleared. Whether VS Code marks the files it unpacks
 * from a Marketplace download is not something this extension controls, so
 * the attribute is removed from the server, and only from it, if present.
 */
function bundled(context) {
    const cand = context.asAbsolutePath(path.join('server', EXE));
    if (!isFile(cand)) return undefined;
    if (process.platform !== 'win32') {
        try {
            const mode = fs.statSync(cand).mode;
            if ((mode & 0o111) !== 0o111) fs.chmodSync(cand, mode | 0o755);
        } catch {
            // Reported by the start that follows, with the path in the message.
        }
    }
    if (process.platform === 'darwin') {
        try {
            const { execFileSync } = require('child_process');
            execFileSync('/usr/bin/xattr', ['-d', 'com.apple.quarantine', cand], { stdio: 'ignore' });
        } catch {
            // Not quarantined (xattr exits non-zero when the attribute is absent).
        }
    }
    return cand;
}

/** The server binary, or undefined -- see the order at the top of the file. */
function findServer(context) {
    const configured = vscode.workspace.getConfiguration('tiko').get('server.path', '');
    // Settings win outright: a path a user named is used even when it is
    // wrong, because guessing past an explicit instruction is how a tool
    // becomes impossible to point somewhere. The error then names that path.
    if (configured) return { path: configured, configured: true, source: 'tiko.server.path' };

    const inside = bundled(context);
    if (inside) return { path: inside, configured: false, source: 'included with the extension' };

    const fromPath = onPath();
    if (fromPath) return { path: fromPath, configured: false, source: 'PATH' };

    for (const folder of vscode.workspace.workspaceFolders || []) {
        const cand = path.join(folder.uri.fsPath, 'bin', EXE);
        if (isFile(cand)) return { path: cand, configured: false, source: 'workspace bin' };
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
    const found = findServer(context);
    if (!found) {
        // Only reachable without a bundled server: a platform no .vsix is
        // published for, or a development package (`npm run package`).
        notFound(
            `${SERVER_NAME} was not found. This extension includes the server for Windows x64, ` +
            `Linux x64 and macOS on Apple silicon only; elsewhere, put ${SERVER_NAME} on your PATH ` +
            `or set "tiko.server.path".`
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
    // about the toolchain arrives here, in `initialize`. With none of it, the
    // server looks for a toolchain itself (PATH, then where the website's
    // instructions leave one) and reports what it found -- see toolchainReport.
    const initializationOptions = {};
    const toolchainPath = cfg.get('toolchainPath', '');
    const includePaths = cfg.get('includePaths', []);
    const packagePaths = cfg.get('packagePaths', []);
    const compilerPath = cfg.get('compilerPath', '');
    if (toolchainPath) initializationOptions.toolchainPath = toolchainPath;
    if (includePaths.length > 0) initializationOptions.includePaths = includePaths;
    if (packagePaths.length > 0) initializationOptions.packagePaths = packagePaths;
    if (compilerPath) initializationOptions.compilerPath = compilerPath;

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
    output.appendLine(`starting ${found.path} ${args.join(' ')}  (${found.source})`);
    try {
        await client.start();
    } catch (err) {
        output.appendLine(`failed to start: ${err && err.message ? err.message : err}`);
        vscode.window.showErrorMessage(`tiko-lsp failed to start: ${err && err.message ? err.message : err}`);
        client = undefined;
        return;
    }

    const tc = toolchainReport(client);
    lastToolchain = tc;
    if (!tc) return; // a server older than 0.1.3 says nothing; nothing to act on
    if (toolchainFound(tc)) {
        output.appendLine(`toolchain: ${tc.root || '(no single folder)'}` +
            (tc.source ? `  (${TOOLCHAIN_SOURCES[tc.source] || tc.source})` : ''));
        if (tc.includeDirs.length > 0) output.appendLine(`  headers   ${tc.includeDirs.join(', ')}`);
        if (tc.packageDir) output.appendLine(`  packages  ${tc.packageDir}`);
        if (tc.compiler) output.appendLine(`  compiler  ${tc.compiler}`);
    } else {
        output.appendLine('toolchain: none found -- std/ and windows.bi names are unknown. Run "Tiko: Locate Toolchain...".');
        promptForToolchain(context, toolchainPath);
    }
}

// ---------------------------------------------------------------------------
// The toolchain: one folder, found by the server or located by the user.
//
// The server does the finding (initializationOptions.toolchainPath, else PATH,
// else where tiko-lang.net's instructions leave a `tiko-lang` folder) and
// reports the result in capabilities.experimental.tiko.toolchain. The
// extension only reads that report, offers once per window to locate a
// toolchain when nothing was found, and writes `tiko.toolchainPath`.
// ---------------------------------------------------------------------------

const DOWNLOAD_URL = 'https://tiko-lang.net/#install';
/** How the output channel names capabilities.experimental.tiko.toolchain.source. */
const TOOLCHAIN_SOURCES = {
    toolchainPath: 'tiko.toolchainPath',
    installed: 'the toolchain the server is installed in',
    detected: 'found automatically',
};
const NEVER_ASK_KEY = 'tiko.toolchainPrompt.never';
let promptedThisWindow = false;
/** The value Locate Toolchain just wrote: its change event needs no "restart?". */
let selfSetToolchainPath;

/** The server's toolchain report, or undefined when the server sends none. */
function toolchainReport(c) {
    const r = c && c.initializeResult;
    const tc = r && r.capabilities && r.capabilities.experimental &&
        r.capabilities.experimental.tiko && r.capabilities.experimental.tiko.toolchain;
    if (!tc || typeof tc !== 'object') return undefined;
    return {
        root: tc.root || '',
        source: tc.source || '',
        includeDirs: Array.isArray(tc.includeDirs) ? tc.includeDirs : [],
        packageDir: tc.packageDir || '',
        compiler: tc.compiler || '',
    };
}

function toolchainFound(tc) {
    return tc.includeDirs.length > 0 || tc.packageDir !== '';
}

function isDir(p) {
    try {
        return fs.statSync(p).isDirectory();
    } catch {
        return false;
    }
}

/**
 * The toolchain root that `chosen` names -- the root itself, its `bin`
 * folder, or the compiler -- or undefined. The same rule as the server's
 * ToolchainRootFrom: a root holds `inc` and a compiler, at its top
 * (Windows) or in `bin` (Linux, macOS).
 */
function toolchainRootFrom(chosen) {
    const exe = process.platform === 'win32' ? 'tiko.exe' : 'tiko';
    let p = path.resolve(chosen);
    if (isFile(p)) p = path.dirname(p);
    for (let tries = 0; tries < 2; tries++) {
        const hasCompiler = isFile(path.join(p, exe)) || isFile(path.join(p, 'bin', exe));
        if (hasCompiler && isDir(path.join(p, 'inc'))) return p;
        const up = path.dirname(p);
        if (up === p) break;
        p = up;
    }
    return undefined;
}

/** Shown at most once per window, and never after "Don't Ask Again". */
async function promptForToolchain(context, configuredPath) {
    if (promptedThisWindow || context.globalState.get(NEVER_ASK_KEY, false)) return;
    promptedThisWindow = true;

    const message = configuredPath
        ? `tiko.toolchainPath does not name a tiko toolchain: ${configuredPath}`
        : 'Tiko could not find the tiko toolchain, so names from std/ and windows.bi ' +
          'will not complete. Point it at the folder you unpacked tiko into.';
    const choice = await vscode.window.showInformationMessage(
        message, 'Locate Toolchain...', 'Download tiko', "Don't Ask Again");
    if (choice === 'Locate Toolchain...') {
        await locateToolchain(context);
    } else if (choice === 'Download tiko') {
        vscode.env.openExternal(vscode.Uri.parse(DOWNLOAD_URL));
    } else if (choice === "Don't Ask Again") {
        await context.globalState.update(NEVER_ASK_KEY, true);
    }
}

/** Tiko: Locate Toolchain... -- pick the folder, check it, save it, restart. */
async function locateToolchain(context) {
    for (;;) {
        const picked = await vscode.window.showOpenDialog({
            title: 'Locate the tiko toolchain (the tiko-lang folder)',
            openLabel: 'Use This Toolchain',
            canSelectFolders: true,
            canSelectFiles: false,
            canSelectMany: false,
        });
        if (!picked || picked.length === 0) return;

        const root = toolchainRootFrom(picked[0].fsPath);
        if (!root) {
            const inside = process.platform === 'win32' ? 'tiko.exe and an inc folder' : 'bin/tiko and an inc folder';
            const again = await vscode.window.showErrorMessage(
                `${picked[0].fsPath} is not a tiko toolchain: expected ${inside} inside it.`,
                'Choose Another Folder', 'Download tiko');
            if (again === 'Choose Another Folder') continue;
            if (again === 'Download tiko') vscode.env.openExternal(vscode.Uri.parse(DOWNLOAD_URL));
            return;
        }

        // A user setting: the toolchain is a property of this machine, not of
        // any one project -- unless this workspace already overrides it, in
        // which case a user setting would be shadowed and change nothing. The
        // restart below replaces the usual "restart?" prompt.
        const cfg = vscode.workspace.getConfiguration('tiko');
        const seen = cfg.inspect('toolchainPath') || {};
        const target = seen.workspaceValue !== undefined
            ? vscode.ConfigurationTarget.Workspace
            : vscode.ConfigurationTarget.Global;
        selfSetToolchainPath = root;
        await cfg.update('toolchainPath', root, target);
        await context.globalState.update(NEVER_ASK_KEY, false);
        output.appendLine(`tiko.toolchainPath set to ${root}`);
        await restart(context);
        return;
    }
}

// ---------------------------------------------------------------------------
// Build and run: the `tiko` task type.
//
// Every task is one `tiko build | run | check` process -- the compiler's own
// subcommands, which cache, link and (for run) start the program -- in VS
// Code's terminal. What is built:
//
//   - a project, when a `tiko.toml` is at or above the active file: the
//     command gets `--manifest <absolute path>`;
//   - otherwise the active file itself, by absolute path.
//
// Absolute paths in, absolute paths out: tiko prints a diagnostic's file as
// it was reached, so the `$tiko` problem matcher never depends on a working
// directory. The compiler is tiko.compilerPath, else the one the server found
// with the toolchain, else `tiko` on the PATH.
// ---------------------------------------------------------------------------

const TASK_TYPE = 'tiko';
const TASK_COMMANDS = ['build', 'run', 'check'];
/** The server's toolchain report from the last start (see toolchainReport). */
let lastToolchain;

/** `tiko` on the PATH, without running anything. */
function tikoOnPath() {
    const exe = process.platform === 'win32' ? 'tiko.exe' : 'tiko';
    for (const d of (process.env.PATH || '').split(path.delimiter)) {
        if (!d) continue;
        const cand = path.join(d.replace(/^"|"$/g, ''), exe);
        if (isFile(cand)) return cand;
    }
    return undefined;
}

/** The compiler to build with, or undefined. */
function compilerForTasks() {
    const configured = vscode.workspace.getConfiguration('tiko').get('compilerPath', '');
    if (configured) return configured;
    if (lastToolchain && lastToolchain.compiler) return lastToolchain.compiler;
    return tikoOnPath();
}

/** The nearest tiko.toml at or above `dir`, or undefined. */
function manifestAbove(dir) {
    let d = dir;
    for (;;) {
        const cand = path.join(d, 'tiko.toml');
        if (isFile(cand)) return cand;
        const up = path.dirname(d);
        if (up === d) return undefined;
        d = up;
    }
}

/**
 * What a task builds: { manifest } or { file }, plus the folder it belongs to.
 * `file` names a root explicitly (tasks.json); otherwise the active tiko
 * editor decides, then a tiko.toml at the top of a workspace folder.
 */
function buildSubject(file) {
    let target = file;
    if (!target) {
        const ed = vscode.window.activeTextEditor;
        if (ed && ed.document.languageId === 'tiko' && ed.document.uri.scheme === 'file') {
            target = ed.document.uri.fsPath;
        }
    }
    if (target) {
        const abs = path.resolve(target);
        const folder = vscode.workspace.getWorkspaceFolder(vscode.Uri.file(abs));
        // A file named in tasks.json is that file; the active editor's file
        // belongs to its project when it has one.
        const manifest = file ? undefined : manifestAbove(path.dirname(abs));
        if (manifest) return { manifest, folder, label: `${path.basename(path.dirname(manifest))} (tiko.toml)` };
        return { file: abs, folder, label: path.basename(abs) };
    }
    for (const folder of vscode.workspace.workspaceFolders || []) {
        const manifest = path.join(folder.uri.fsPath, 'tiko.toml');
        if (isFile(manifest)) return { manifest, folder, label: `${folder.name} (tiko.toml)` };
    }
    return undefined;
}

/** A vscode.Task for `definition`, or undefined when there is nothing to build. */
function makeTask(definition, subject, compiler) {
    const cfg = vscode.workspace.getConfiguration('tiko');
    const args = [definition.command, '--color=never'];
    if (subject.manifest) args.push('--manifest', subject.manifest);
    args.push(...(definition.args || cfg.get('build.arguments', [])));
    if (subject.file) args.push(subject.file);
    if (definition.command === 'run') {
        const runArgs = definition.runArgs || cfg.get('run.arguments', []);
        if (runArgs.length > 0) args.push('--', ...runArgs);
    }
    const cwd = subject.manifest ? path.dirname(subject.manifest) : path.dirname(subject.file);
    const task = new vscode.Task(
        definition,
        subject.folder || vscode.TaskScope.Workspace,
        `${definition.command} ${subject.label}`,
        'tiko',
        new vscode.ProcessExecution(compiler, args, { cwd }),
        '$tiko'
    );
    if (definition.command === 'build') task.group = vscode.TaskGroup.Build;
    task.presentationOptions = {
        reveal: definition.command === 'run' ? vscode.TaskRevealKind.Always : vscode.TaskRevealKind.Silent,
        clear: true,
        showReuseMessage: false,
    };
    return task;
}

function missingCompiler() {
    vscode.window.showErrorMessage(
        'Tiko cannot build: no tiko compiler was found. Locate the toolchain, or set "tiko.compilerPath".',
        'Locate Toolchain...', 'Download tiko'
    ).then((choice) => {
        if (choice === 'Locate Toolchain...') vscode.commands.executeCommand('tiko.locateToolchain');
        else if (choice === 'Download tiko') vscode.env.openExternal(vscode.Uri.parse(DOWNLOAD_URL));
    });
}

const taskProvider = {
    provideTasks() {
        const subject = buildSubject(undefined);
        const compiler = compilerForTasks();
        if (!subject || !compiler) return [];
        return TASK_COMMANDS.map((command) => makeTask({ type: TASK_TYPE, command }, subject, compiler));
    },
    resolveTask(task) {
        const def = task.definition;
        if (!def || !TASK_COMMANDS.includes(def.command)) return undefined;
        const subject = buildSubject(def.file);
        const compiler = compilerForTasks();
        if (!subject || !compiler) return undefined;
        const resolved = makeTask(def, subject, compiler);
        // tasks.json's own problemMatcher and presentation win over ours.
        return new vscode.Task(def, task.scope || resolved.scope, task.name || resolved.name, 'tiko',
            resolved.execution, task.problemMatchers && task.problemMatchers.length ? task.problemMatchers : '$tiko');
    },
};

/**
 * Tiko: Build / Tiko: Run / Tiko: Check -- the same tasks, started directly.
 * `more` carries a launch configuration's file, args and runArgs.
 */
async function runTiko(command, more) {
    const compiler = compilerForTasks();
    if (!compiler) {
        missingCompiler();
        return;
    }
    const definition = Object.assign({ type: TASK_TYPE, command }, more || {});
    const subject = buildSubject(definition.file);
    if (!subject) {
        vscode.window.showErrorMessage('Tiko: open a .tiko file, or a folder with a tiko.toml, to build it.');
        return;
    }
    // Tasks started this way do not pass through task.saveBeforeRun.
    await vscode.workspace.saveAll(false);
    return vscode.tasks.executeTask(makeTask(definition, subject, compiler));
}

// ---------------------------------------------------------------------------
// Run > Run Without Debugging (Ctrl+F5) and Start Debugging (F5).
//
// VS Code sends both through a debugger for the active file's language; with
// none contributed it offers to search the Marketplace for one. The `tiko`
// debugger type exists so that both find something: its configuration is
// resolved into a `tiko run` task, and resolving returns undefined, which
// ends the launch without starting a debug session. There is no debug adapter
// behind it -- under F5 the program runs without a debugger, and says so once.
// ---------------------------------------------------------------------------

let saidNoDebugger = false;

const RUN_CONFIG = { type: 'tiko', request: 'launch', name: 'Run tiko program' };

// Offered in Run and Debug's picker. A provider object of its own: VS Code
// resolves through EVERY provider registered for a type, so registering the
// one below twice would run the program twice.
const dynamicDebugProvider = {
    provideDebugConfigurations() {
        return [Object.assign({}, RUN_CONFIG)];
    },
};

const debugProvider = {
    provideDebugConfigurations() {
        return [Object.assign({}, RUN_CONFIG)];
    },
    // F5 / Ctrl+F5 with no launch.json arrive with an empty configuration.
    resolveDebugConfiguration(folder, config) {
        if (!config.type && !config.request && !config.name) {
            return Object.assign({}, RUN_CONFIG, { noDebug: config.noDebug });
        }
        return config;
    },
    // After ${workspaceFolder} and friends are substituted: run, and start no session.
    async resolveDebugConfigurationWithSubstitutedVariables(folder, config) {
        if (!config.noDebug && !saidNoDebugger) {
            saidNoDebugger = true;
            vscode.window.showInformationMessage(
                'Tiko cannot debug in VS Code yet: the program runs without a debugger.');
        }
        const more = {};
        if (config.file) more.file = folder && !path.isAbsolute(config.file)
            ? path.join(folder.uri.fsPath, config.file) : config.file;
        if (Array.isArray(config.args)) more.args = config.args;
        if (Array.isArray(config.runArgs)) more.runArgs = config.runArgs;
        await runTiko('run', more);
        return undefined;
    },
};

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
        vscode.commands.registerCommand('tiko.locateToolchain', () => locateToolchain(context)),
        vscode.commands.registerCommand('tiko.build', () => runTiko('build')),
        vscode.commands.registerCommand('tiko.run', () => runTiko('run')),
        vscode.commands.registerCommand('tiko.check', () => runTiko('check')),
        vscode.tasks.registerTaskProvider(TASK_TYPE, taskProvider),
        vscode.debug.registerDebugConfigurationProvider('tiko', debugProvider),
        vscode.debug.registerDebugConfigurationProvider('tiko', dynamicDebugProvider,
            vscode.DebugConfigurationProviderTriggerKind.Dynamic),

        // initializationOptions are read once, at `initialize`: a change to
        // anything the server is started with needs a restart to take effect.
        vscode.workspace.onDidChangeConfiguration((e) => {
            const affected = ['tiko.server.path', 'tiko.server.arguments', 'tiko.toolchainPath', 'tiko.includePaths', 'tiko.packagePaths', 'tiko.compilerPath']
                .some((key) => e.affectsConfiguration(key));
            if (!affected) return;
            if (selfSetToolchainPath !== undefined && e.affectsConfiguration('tiko.toolchainPath') &&
                vscode.workspace.getConfiguration('tiko').get('toolchainPath', '') === selfSetToolchainPath) {
                selfSetToolchainPath = undefined; // Locate Toolchain restarts the server itself
                return;
            }
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
