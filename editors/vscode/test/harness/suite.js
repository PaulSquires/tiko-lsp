// The clean-profile check of an INSTALLED Tiko extension (Track A, A.4).
//
// release/vscode/test.sh installs a .vsix into a fresh --extensions-dir, then
// starts VS Code on test/fixture/ws with this directory as the development
// extension and this file as --extensionTestsPath. VS Code calls run(); what
// it checks is the published package -- the extension installed from the
// .vsix, starting the server it carries -- not the source tree. This harness
// contributes nothing itself.
//
// Every check is recorded, pass or fail, in the JSON file named by
// TIKO_TEST_RESULTS, so a failure says which question failed and with what
// detail. run() rejects if any check failed, which makes VS Code exit non-zero.

'use strict';

const fs = require('fs');
const path = require('path');
const vscode = require('vscode');

const EXTENSION_ID = 'PaulSquires.tiko';
const EXE = process.platform === 'win32' ? 'tiko-lsp.exe' : 'tiko-lsp';
// The first answer waits for the server to start and index the folder.
const READY_MS = 60000;

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Polls fn until it returns something truthy, or returns undefined at the deadline. */
async function waitFor(fn, ms) {
    const until = Date.now() + ms;
    for (;;) {
        try {
            const v = await fn();
            if (v) return v;
        } catch {
            // Not ready yet: a provider may throw while the client is starting.
        }
        if (Date.now() > until) return undefined;
        await sleep(250);
    }
}

function hoverText(hovers) {
    const parts = [];
    for (const h of hovers || []) {
        for (const c of h.contents) parts.push(typeof c === 'string' ? c : c.value);
    }
    return parts.join('\n');
}

function labelOf(item) {
    return typeof item.label === 'string' ? item.label : item.label.label;
}

/** Executable paths of every running tiko-lsp process on this machine. */
function runningServers() {
    const { execFileSync } = require('child_process');
    try {
        if (process.platform === 'win32') {
            const out = execFileSync('powershell.exe',
                ['-NoProfile', '-Command', '(Get-Process tiko-lsp -ErrorAction SilentlyContinue).Path'],
                { encoding: 'utf8' });
            return out.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
        }
        return fs.readdirSync('/proc').filter((d) => /^\d+$/.test(d)).map((pid) => {
            try {
                return fs.readlinkSync(`/proc/${pid}/exe`);
            } catch {
                return '';
            }
        }).filter((p) => path.basename(p) === 'tiko-lsp');
    } catch {
        return [];
    }
}

async function open(rel) {
    const root = vscode.workspace.workspaceFolders[0].uri;
    const doc = await vscode.workspace.openTextDocument(vscode.Uri.joinPath(root, rel));
    await vscode.window.showTextDocument(doc);
    return doc;
}

/** The position of the n-th (0-based) occurrence of text in doc, plus an offset. */
function at(doc, text, n = 0, plus = 0) {
    let i = -1;
    for (let k = 0; k <= n; k++) i = doc.getText().indexOf(text, i + 1);
    if (i < 0) throw new Error(`'${text}' not found in ${doc.uri.path}`);
    return doc.positionAt(i + plus);
}

exports.run = async function run() {
    const results = [];
    const check = (name, ok, detail) => results.push({ name, ok: !!ok, detail: detail === undefined ? '' : String(detail) });

    try {
        // 1. The extension is the INSTALLED one, carrying its server.
        const ext = vscode.extensions.getExtension(EXTENSION_ID);
        check('extension installed', ext, ext ? `${ext.packageJSON.version} at ${ext.extensionPath}` : 'not found');
        if (!ext) throw new Error('nothing to test');
        const expected = process.env.TIKO_TEST_EXTENSIONS_DIR || '';
        check('loaded from the clean extensions dir',
            expected && path.resolve(ext.extensionPath).toLowerCase().startsWith(path.resolve(expected).toLowerCase()),
            ext.extensionPath);
        const server = path.join(ext.extensionPath, 'server', EXE);
        check('bundled server present', fs.existsSync(server), server);
        if (process.platform !== 'win32' && fs.existsSync(server)) {
            check('bundled server executable', (fs.statSync(server).mode & 0o111) === 0o111,
                (fs.statSync(server).mode & 0o777).toString(8));
        }
        const onPath = (process.env.PATH || '').split(path.delimiter).filter((d) => d && fs.existsSync(path.join(d, EXE)));
        check('no tiko-lsp on PATH to mask the bundled one', onPath.length === 0, onPath.join(', ') || 'none');

        // 2. A .tiko file is Tiko, and the extension activates for it.
        const hello = await open('hello.tiko');
        check('hello.tiko is language tiko', hello.languageId === 'tiko', hello.languageId);
        const active = await waitFor(() => ext.isActive, 20000);
        check('extension activated', active);

        // 3. Hover: only the server answers this, so it proves the server runs.
        const call = at(hello, 'Greet', 1);
        const hover = await waitFor(async () => {
            const t = hoverText(await vscode.commands.executeCommand('vscode.executeHoverProvider', hello.uri, call));
            return t.includes('Greet') ? t : undefined;
        }, READY_MS);
        check('hover on Greet( ... )', hover, hover ? hover.split('\n').find((l) => l.includes('Greet')) : 'no hover');

        // The server that answered is the bundled one: some running tiko-lsp
        // process has exactly that executable path.
        const running = runningServers();
        check('the bundled server is running',
            running.some((p) => path.resolve(p).toLowerCase() === path.resolve(server).toLowerCase()),
            running.join(', ') || 'no tiko-lsp process found');

        // 4. Completion after 'p.' lists the members of Point.
        const member = at(hello, 'p.x', 0, 2);
        const labels = await waitFor(async () => {
            const list = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', hello.uri, member);
            const l = (list ? list.items : []).map(labelOf);
            return l.includes('x') && l.includes('y') ? l : undefined;
        }, READY_MS);
        check('completion after p. has x and y', labels, labels ? labels.slice(0, 10).join(', ') : 'missing');

        // 4b. A space after a declaration's `as` asks, and gets types only;
        //     a space anywhere else gets nothing. The command also returns VS
        //     Code's own word-based items (kind Text), which a typed space never
        //     shows -- only the server's items are checked.
        const fromServer = (list) => (list ? list.items : [])
            .filter((i) => i.kind !== vscode.CompletionItemKind.Text).map(labelOf);
        const afterAs = at(hello, 'dim q as ', 0, 'dim q as '.length);
        const typeList = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', hello.uri, afterAs, ' ');
        const typeLabels = fromServer(typeList);
        check('space after `as` offers types only', typeLabels.includes('Widget') && typeLabels.includes('long') &&
            !typeLabels.includes('Greet') && !typeLabels.includes('if'),
            `${typeLabels.length} item(s), Widget ${typeLabels.includes('Widget') ? 'in' : 'missing'}, Greet ${typeLabels.includes('Greet') ? 'in' : 'out'}`);
        const afterPrint = at(hello, 'print ', 0, 'print '.length);
        const spaceList = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', hello.uri, afterPrint, ' ');
        const spaceLabels = fromServer(spaceList);
        check('space elsewhere offers nothing', spaceLabels.length === 0, spaceLabels.slice(0, 10).join(', ') || 'nothing');

        // 4c. `->` through a pointer offers the pointed-to type's members, as
        //     `.` does; the `>` that ends it is the trigger.
        const afterArrow = at(hello, 'pq->', 0, 'pq->'.length);
        const arrowList = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', hello.uri, afterArrow, '>');
        const arrowLabels = fromServer(arrowList);
        check('completion after pq-> has w only', arrowLabels.includes('w') && !arrowLabels.includes('x') &&
            !arrowLabels.includes('Greet'), arrowLabels.slice(0, 10).join(', ') || 'nothing');
        const arrowHover = hoverText(await vscode.commands.executeCommand('vscode.executeHoverProvider', hello.uri,
            at(hello, 'pq->w', 0, 'pq->'.length)));
        check('hover on pq->w shows the field', /w as long/.test(arrowHover), arrowHover.split(/\r?\n/).find((l) => l.trim()) || 'no hover');

        // 5. Go to definition from the call lands on the sub.
        const defs = await waitFor(async () => {
            const d = await vscode.commands.executeCommand('vscode.executeDefinitionProvider', hello.uri, call);
            return d && d.length ? d : undefined;
        }, READY_MS);
        const defLine = defs ? (defs[0].range || defs[0].targetRange).start.line : -1;
        check('definition of Greet is line 6', defLine === at(hello, 'sub Greet').line, `line ${defLine + 1}`);

        // 6. A diagnostic for the unclosed IF.
        const broken = await open('broken.tiko');
        const diags = await waitFor(() => {
            const d = vscode.languages.getDiagnostics(broken.uri);
            return d.length ? d : undefined;
        }, READY_MS);
        check('diagnostic in broken.tiko', diags, diags ? diags.map((d) => `${d.range.start.line + 1}: ${d.message}`).join(' | ') : 'none');

        // 7. Formatting indents the body.
        const fmt = await open('format.tiko');
        const edits = await waitFor(async () => {
            const e = await vscode.commands.executeCommand('vscode.executeFormatDocumentProvider', fmt.uri,
                { tabSize: 4, insertSpaces: true });
            return e && e.length ? e : undefined;
        }, READY_MS);
        check('format.tiko gets edits', edits, edits ? `${edits.length} edit(s); first: ${JSON.stringify(edits[0].newText)}` : 'none');

        // 8. Legacy .bas is NOT claimed by default (A-D2).
        const legacy = await open('legacy.bas');
        check('legacy.bas is not tiko by default', legacy.languageId !== 'tiko', legacy.languageId);

        // 8b. Built-ins -- declared nowhere, lexed as keywords -- answer from
        //     their codetips: signature help inside left( and hover on mid.
        const bi = await open('builtins.tiko');
        const sigAt = at(bi, 'left( s, ', 0, 'left( s, '.length);
        const sh = await waitFor(async () => {
            const h = await vscode.commands.executeCommand('vscode.executeSignatureHelpProvider', bi.uri, sigAt);
            return h && h.signatures && h.signatures.length ? h : undefined;
        }, READY_MS);
        check('signature help inside left( ... )',
            sh && sh.signatures[0].label === 'Left(string, n)' && sh.activeParameter === 1,
            sh ? `${sh.signatures[0].label}, parameter ${sh.activeParameter}` : 'none');
        const midHover = await waitFor(async () => {
            const t = hoverText(await vscode.commands.executeCommand('vscode.executeHoverProvider', bi.uri, at(bi, 'mid', 0, 1)));
            return t.includes('Mid(') ? t : undefined;
        }, READY_MS);
        check('hover on mid shows its codetip', midHover,
            midHover ? midHover.split('\n').find((l) => l.includes('Mid(')) : 'no hover');

        // 9. The toolchain: the setting and the command exist, and naming a
        //    toolchain folder in tiko.toolchainPath -- nothing else -- makes
        //    std/ names complete. TIKO_TEST_TOOLCHAIN is that folder; without
        //    it the end-to-end half is skipped and says so.
        const props = ((ext.packageJSON.contributes || {}).configuration || {}).properties || {};
        check('tiko.toolchainPath setting contributed', 'tiko.toolchainPath' in props);
        const commands = await vscode.commands.getCommands(true);
        check('Tiko: Locate Toolchain... registered', commands.includes('tiko.locateToolchain'));

        const toolchain = process.env.TIKO_TEST_TOOLCHAIN || '';
        if (!toolchain) {
            check('std/ completion through tiko.toolchainPath', true, 'skipped: TIKO_TEST_TOOLCHAIN not set');
        } else {
            await vscode.workspace.getConfiguration('tiko')
                .update('toolchainPath', toolchain, vscode.ConfigurationTarget.Global);
            await vscode.commands.executeCommand('tiko.restartServer');
            const std = await open('std.tiko');
            const after = at(std, 'strings.', 0, 'strings.'.length);
            const stdLabels = await waitFor(async () => {
                const list = await vscode.commands.executeCommand('vscode.executeCompletionItemProvider', std.uri, after);
                const l = (list ? list.items : []).map(labelOf);
                return l.includes('PadLeft') ? l : undefined;
            }, READY_MS);
            check('std/ completion through tiko.toolchainPath', stdLabels,
                stdLabels ? `${stdLabels.length} items after strings., PadLeft among them` : `no PadLeft (toolchain ${toolchain})`);
        }

        // 10. Build and run: the `tiko` task type, the $tiko problem matcher, and
        //     the commands. The compiler is the toolchain's, found in step 9.
        const pkgContrib = ext.packageJSON.contributes || {};
        check('task type tiko and problem matcher $tiko contributed',
            (pkgContrib.taskDefinitions || []).some((t) => t.type === 'tiko') &&
            (pkgContrib.problemMatchers || []).some((m) => m.name === 'tiko'));
        check('Tiko: Build and Tiko: Run registered',
            commands.includes('tiko.build') && commands.includes('tiko.run'));
        if (!toolchain) {
            check('build and run', true, 'skipped: TIKO_TEST_TOOLCHAIN not set');
        } else {
            const root = vscode.workspace.workspaceFolders[0].uri.fsPath;
            const scratch = [path.join(root, 'ran.txt'), path.join(root, 'proj', 'proj-ran.txt'),
                path.join(root, 'runme.exe'), path.join(root, 'runme'), path.join(root, 'undeclared.exe'),
                path.join(root, 'undeclared'), path.join(root, 'proj', 'out')];
            const cleanup = () => scratch.forEach((p) => fs.rmSync(p, { recursive: true, force: true }));
            cleanup();

            /** Runs the provided task `command` for the active editor; its exit code, or undefined. */
            const runProvided = async (command) => {
                const tasks = await vscode.tasks.fetchTasks({ type: 'tiko' });
                const task = tasks.find((t) => t.definition.command === command);
                if (!task) return { code: undefined, name: `no '${command}' task among ${tasks.map((t) => t.name).join(', ')}` };
                return new Promise((resolve) => {
                    let exec;
                    const timer = setTimeout(() => { sub.dispose(); resolve({ code: undefined, name: `${task.name}: timed out` }); }, 120000);
                    const sub = vscode.tasks.onDidEndTaskProcess((e) => {
                        if (exec && e.execution !== exec) return;
                        clearTimeout(timer);
                        sub.dispose();
                        resolve({ code: e.exitCode, name: task.name });
                    });
                    vscode.tasks.executeTask(task).then((x) => { exec = x; });
                });
            };

            // a. A compile error the server cannot see lands in Problems.
            const und = await open('undeclared.tiko');
            const built = await runProvided('build');
            const tikoDiags = await waitFor(() => {
                const d = vscode.languages.getDiagnostics(und.uri).filter((x) => /not declared/.test(x.message));
                return d.length ? d : undefined;
            }, 20000);
            check('build: a compiler error lands in Problems', tikoDiags && built.code === 1,
                `${built.name} exit ${built.code}; ` +
                (tikoDiags ? tikoDiags.map((d) => `${d.range.start.line + 1}:${d.range.start.character + 1} ${d.code && d.code.value ? d.code.value : d.code} ${d.message}`).join(' | ') : 'no diagnostic'));

            // b. Run a single file: built, then started in its own folder.
            await open('runme.tiko');
            const ranFile = await runProvided('run');
            const marker = path.join(root, 'ran.txt');
            check('run: a single file builds and runs', ranFile.code === 0 && fs.existsSync(marker),
                `${ranFile.name} exit ${ranFile.code}; ran.txt ${fs.existsSync(marker) ? 'written' : 'missing'}`);

            // c. Run a project: the tiko.toml above the active file wins.
            await open('proj/src/main.tiko');
            const ranProj = await runProvided('run');
            const projMarker = path.join(root, 'proj', 'proj-ran.txt');
            check('run: a tiko.toml project builds and runs', ranProj.code === 0 && fs.existsSync(projMarker) &&
                /tiko\.toml/.test(ranProj.name),
                `${ranProj.name} exit ${ranProj.code}; proj-ran.txt ${fs.existsSync(projMarker) ? 'written' : 'missing'}`);

            // d. Run > Run Without Debugging with no launch.json: the tiko
            //    debugger type resolves it into `tiko run`, and no debug
            //    session starts (before, VS Code offered the Marketplace).
            cleanup();
            await open('runme.tiko');
            let sessions = 0;
            const sessSub = vscode.debug.onDidStartDebugSession(() => { sessions += 1; });
            const ended = new Promise((resolve) => {
                const timer = setTimeout(() => { sub.dispose(); resolve(undefined); }, 120000);
                const sub = vscode.tasks.onDidEndTaskProcess((e) => {
                    clearTimeout(timer);
                    sub.dispose();
                    resolve(e);
                });
            });
            await vscode.commands.executeCommand('workbench.action.debug.run');
            const runEnd = await ended;
            sessSub.dispose();
            check('Run Without Debugging runs the program', runEnd && runEnd.exitCode === 0 &&
                fs.existsSync(marker) && sessions === 0,
                `${runEnd ? runEnd.execution.task.name + ' exit ' + runEnd.exitCode : 'no task ended'}; ` +
                `ran.txt ${fs.existsSync(marker) ? 'written' : 'missing'}; ${sessions} debug session(s)`);
            cleanup();
        }
    } catch (err) {
        check('no exception', false, err && err.stack ? err.stack : err);
    }

    const out = process.env.TIKO_TEST_RESULTS;
    if (out) fs.writeFileSync(out, JSON.stringify({ vscode: vscode.version, platform: process.platform, results }, null, 2));
    const failed = results.filter((r) => !r.ok);
    if (failed.length) throw new Error(`${failed.length} check(s) failed: ${failed.map((r) => r.name).join('; ')}`);
};
