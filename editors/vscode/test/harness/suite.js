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
    } catch (err) {
        check('no exception', false, err && err.stack ? err.stack : err);
    }

    const out = process.env.TIKO_TEST_RESULTS;
    if (out) fs.writeFileSync(out, JSON.stringify({ vscode: vscode.version, platform: process.platform, results }, null, 2));
    const failed = results.filter((r) => !r.ok);
    if (failed.length) throw new Error(`${failed.length} check(s) failed: ${failed.map((r) => r.name).join('; ')}`);
};
