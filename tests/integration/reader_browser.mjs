// Run from the config root: node tests/integration/reader_browser.mjs
// Requires Node 22+, Neovim and Chromium/Edge; Fox Reader itself uses Lua only.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = process.cwd();
const temporary = mkdtempSync(join(tmpdir(), 'fox-reader-'));
const first = join(temporary, 'workspace one');
const second = join(temporary, 'workspace two');
mkdirSync(join(first, 'nested'), { recursive: true });
mkdirSync(second);
const stateFile = join(temporary, 'reader-state.json');
const source = join(first, 'start.md');
const target = join(first, 'nested', 'Guía uno.md');
writeFileSync(source, '---\ntitle: A <safe> title\ntags:\n  - reading\n  - fox\ndescription: |\n  two lines\n  stay together\n---\n# Start\n\n[Go](nested/Gu%C3%ADa%20uno.md#destination)\n\n![Local](nested/pixel.png)\n\n| A | B |\n| --- | --- |\n| one | two |\n\n- [x] Task\n\n```mermaid\ngraph TD\nA[Reader] --> B[Diagram]\n```\n');
writeFileSync(target, '# Destination\n\n' + Array.from({length: 80}, (_, i) => `${i === 40 ? "## Middle\n\n" : ""}Paragraph ${i}\n`).join('\n') + '\n## End\n');
writeFileSync(join(first, 'nested', 'pixel.png'), Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aWQAAAAASUVORK5CYII=', 'base64'));
writeFileSync(join(first, 'notes.custom'), '# Custom extension\n');
writeFileSync(join(first, 'ordinary.md'), '---\nNormal text\n---\n# Regular document\n');
writeFileSync(join(second, 'other.md'), '# Other workspace\n');
const socket = process.platform === 'win32' ? `\\\\.\\pipe\\fox-reader-${process.pid}` : join(temporary, 'nvim.sock');
const browser = process.env.FOX_TEST_BROWSER || (process.platform === 'win32'
  ? 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe' : 'chromium');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, description) {
  for (let attempt = 0; attempt < 150; attempt++) {
    if (await check()) return;
    await delay(100);
  }
  throw new Error(`Timed out waiting for ${description}`);
}
function lua(code) {
  return execFileSync('nvim', ['--headless', '--server', socket, '--remote-expr',
    `luaeval('${code.replaceAll("'", "''")}')`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}

let editor, chromium, connection;
try {
  editor = spawn('nvim', ['--headless', '-u', 'NONE', '-i', 'NONE', '-n', '--listen', socket,
    '-c', `lua vim.opt.rtp:prepend(${JSON.stringify(root)}); require('fox.reader.state').path = ${JSON.stringify(stateFile)}; require('fox.reader').setup(); require('fox.markdown.browser').open = function(url) _G.reader_url = url end`],
  { stdio: ['ignore', 'ignore', 'inherit'] });
  await until(() => { try { return lua('true'); } catch { return false; } }, 'Neovim');
  lua(`(function() vim.cmd.cd(${JSON.stringify(first)}); vim.cmd.edit('start.md'); vim.bo.filetype = 'markdown'; vim.cmd('FoxReader'); return true end)()`);
  const url = lua('_G.reader_url');
  assert.match(url, /^http:\/\/127\.0\.0\.1:\d+\/[a-f0-9]+\/\?path=start.md$/);

  chromium = spawn(browser, ['--headless', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
    '--disable-extensions', '--no-proxy-server', '--remote-debugging-port=0', `--user-data-dir=${temporary}/chrome`, 'about:blank'], { stdio: 'ignore' });
  const portFile = join(temporary, 'chrome', 'DevToolsActivePort');
  await until(() => existsSync(portFile), 'browser debugging port');
  const port = readFileSync(portFile, 'utf8').split('\n')[0];
  const pages = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
  connection = new WebSocket(pages.find(page => page.type === 'page').webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    connection.addEventListener('open', resolve, { once: true });
    connection.addEventListener('error', reject, { once: true });
  });
  let nextId = 0;
  const pending = new Map();
  connection.addEventListener('message', event => {
    const response = JSON.parse(event.data);
    if (!response.id) return;
    const request = pending.get(response.id);
    if (!request) return;
    pending.delete(response.id);
    clearTimeout(request.timeout);
    if (response.error) request.reject(new Error(JSON.stringify(response.error)));
    else request.resolve(response.result);
  });
  function cdp(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`Chromium did not answer ${method}`)); }, 10000);
      pending.set(id, { resolve, reject, timeout });
      connection.send(JSON.stringify({ id, method, params }));
    });
  }
  async function evaluate(expression) {
    const response = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    assert.ok(!response.exceptionDetails, JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }
  writeFileSync(stateFile, '{broken');
  lua(`(function() vim.o.background = 'dark'; vim.api.nvim_set_hl(0, 'Normal', {fg = '#eeddcc', bg = '#123456'}); return true end)()`);
  const initialPage = await (await fetch(url)).text();
  assert.match(initialPage, /data-theme="editor"/);
  assert.match(initialPage, /--editor-background:#123456/);
  assert.ok(initialPage.indexOf('--editor-background:#123456') < initialPage.indexOf('reader.css'));
  await cdp('Page.navigate', { url });
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'initial document');
  await until(() => evaluate('document.querySelector("#content img")?.naturalWidth === 1'), 'local image');
  await until(() => evaluate('Boolean(document.querySelector("#content .mermaid svg"))'), 'Mermaid');
  assert.equal(await evaluate('document.querySelector(".metadata summary")?.textContent'), 'Properties');
  assert.match(await evaluate('document.querySelector("#state-status").textContent'), /corrupt/);
  assert.deepEqual(await evaluate('[...document.querySelectorAll(".metadata dt")].map(node => node.textContent)'), ['title', 'tags', 'description']);
  assert.equal(await evaluate('document.querySelector(".metadata dd").textContent'), 'A <safe> title');
  assert.deepEqual(await evaluate('[...document.querySelectorAll(".metadata dd")][1].querySelectorAll(".metadata-item").length'), 2);
  assert.deepEqual(await evaluate('[...document.querySelectorAll(".metadata-item")].map(item => item.textContent)'), ['reading', 'fox']);
  assert.equal(await evaluate('document.querySelector(".metadata dd safe")'), null);
  assert.equal(await evaluate('document.querySelector("#content h1").dataset.sourceLine'), '10');
  assert.ok(await evaluate('[...document.querySelectorAll("header .icon-button")].every(button => button.title && button.getAttribute("aria-label") && !button.textContent.includes("?"))'));
  lua(`(function() vim.api.nvim_buf_set_lines(0, 1, 2, false, {'title: Updated properties'}); return true end)()`);
  await until(() => evaluate('document.querySelector(".metadata dd")?.textContent === "Updated properties"'), 'metadata-only update');
  await evaluate(`document.querySelector('[aria-controls="size-panel"]').click()`);
  assert.equal(await evaluate('document.querySelector("#size-panel").hidden'), false);
  assert.equal(await evaluate(`document.querySelector('[aria-controls="size-panel"]').getAttribute('aria-expanded')`), 'true');
  await evaluate(`document.querySelector('#size').value = '22'; document.querySelector('#size').dispatchEvent(new Event('input'))`);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#content")).fontSize'), '22px');
  await evaluate(`document.querySelector('#size').value = '18'; document.querySelector('#size').dispatchEvent(new Event('change'))`);
  await evaluate(`document.querySelector('[aria-controls="spacing-panel"]').click(); document.querySelector('#lineSpacing').value = '2.1'; document.querySelector('#lineSpacing').dispatchEvent(new Event('input'))`);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#content")).lineHeight'), '37.8px');
  await evaluate(`document.querySelector('#lineSpacing').value = '1.8'; document.querySelector('#lineSpacing').dispatchEvent(new Event('change')); document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'}))`);
  assert.equal(await evaluate('document.querySelector("#spacing-panel").hidden'), true);
  await evaluate(`document.querySelector('[aria-controls="width-panel"]').click(); document.querySelector('#width').value = '860'; document.querySelector('#width').dispatchEvent(new Event('input'))`);
  assert.equal(await evaluate('document.documentElement.style.getPropertyValue("--reading-width")'), '860px');
  await evaluate(`document.querySelector('#width').value = '760'; document.querySelector('#width').dispatchEvent(new Event('change'))`);
  const ordinary = await (await fetch(new URL('document?path=ordinary.md', url))).json();
  assert.equal(ordinary.frontmatter, undefined);
  assert.ok(ordinary.html.includes('Normal text'));
  assert.equal(await evaluate('document.querySelector("#font").value'), 'Trebuchet MS');
  assert.match(await evaluate('getComputedStyle(document.body).fontFamily'), /Trebuchet MS/);
  assert.match(await evaluate('getComputedStyle(document.querySelector("#content")).fontFamily'), /Trebuchet MS/);
  if (existsSync('tools/fox-reader/fonts/trebuc.ttf')) {
    const fontResponse = await fetch(new URL('fonts/trebuc.ttf', url));
    assert.equal(fontResponse.status, 200);
    assert.equal((await fontResponse.arrayBuffer()).byteLength, readFileSync('tools/fox-reader/fonts/trebuc.ttf').length);
  }
  if (process.platform === 'win32') {
    await cdp('DOM.enable');
    await cdp('CSS.enable');
    const { root: documentRoot } = await cdp('DOM.getDocument');
    const { nodeId } = await cdp('DOM.querySelector', { nodeId: documentRoot.nodeId, selector: '#content h1' });
    const { fonts } = await cdp('CSS.getPlatformFontsForNode', { nodeId });
    assert.ok(fonts.some(font => font.familyName.includes('Trebuchet')), JSON.stringify(fonts));
  }
  assert.equal(await evaluate('document.querySelector("#content table tbody tr")?.textContent.replace(/\\s/g, "")'), 'onetwo');
  assert.equal(await evaluate('document.querySelector("#content input[type=checkbox]")?.checked'), true);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#content")).textAlign'), 'justify');
  assert.equal(await evaluate('getComputedStyle(document.body).backgroundColor'), 'rgb(18, 52, 86)');
  await until(() => evaluate('Boolean(document.querySelector("#files summary"))'), 'library icons');
  assert.notEqual(await evaluate('getComputedStyle(document.querySelector("#files summary"), "::before").content'), 'none');
  assert.notEqual(await evaluate('getComputedStyle(document.querySelector("#files a"), "::before").content'), 'none');
  await evaluate(`document.querySelector('#alignment').value = 'left'; document.querySelector('#alignment').dispatchEvent(new Event('change')); document.querySelector('#font').value = 'Verdana'; document.querySelector('#font').dispatchEvent(new Event('change'))`);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#content")).textAlign'), 'left');
  assert.match(await evaluate('getComputedStyle(document.querySelector("#content")).fontFamily'), /Verdana/);
  await evaluate(`document.querySelector('#lineSpacing').value = '2.1'; document.querySelector('#lineSpacing').dispatchEvent(new Event('change')); document.querySelector('#width').value = '920'; document.querySelector('#width').dispatchEvent(new Event('change'))`);
  await until(() => { try { return JSON.parse(readFileSync(stateFile, 'utf8')).preferences.width === 920; } catch { return false; } }, 'saved preferences');
  const handle = await evaluate(`(() => { const rect = document.querySelector('#width-right').getBoundingClientRect(); return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 }; })()`);
  await cdp('Input.dispatchMouseEvent', { type: 'mousePressed', x: handle.x, y: handle.y, button: 'left', clickCount: 1 });
  await cdp('Input.dispatchMouseEvent', { type: 'mouseMoved', x: handle.x - 80, y: handle.y, button: 'left' });
  await cdp('Input.dispatchMouseEvent', { type: 'mouseReleased', x: handle.x - 80, y: handle.y, button: 'left', clickCount: 1 });
  assert.ok(Number(await evaluate('document.querySelector("#width").value')) < 920, 'dragging the handle narrows the reading area');
  await evaluate(`document.querySelector('#width').value = '920'; document.querySelector('#width').dispatchEvent(new Event('change'))`);
  await until(() => { try { return JSON.parse(readFileSync(stateFile, 'utf8')).preferences.width === 920; } catch { return false; } }, 'width after drag');
  const forbidden = await fetch(new URL('state', url), {method: 'POST', headers: {'Content-Type': 'application/json', Origin: 'http://evil.invalid'}, body: '{}'});
  assert.equal(forbidden.status, 403);
  lua(`(function() vim.api.nvim_set_hl(0, 'Normal', {fg = '#eeddcc', bg = '#123456'}); return true end)()`);
  await until(() => evaluate('getComputedStyle(document.body).backgroundColor === "rgb(18, 52, 86)"'), 'editor theme');
  assert.equal(await evaluate('getComputedStyle(document.body).color'), 'rgb(238, 221, 204)');
  await until(() => evaluate('[...document.querySelectorAll("#files a")].some(a => a.textContent === "Guía uno.md")'), 'library');
  await evaluate('document.querySelector("#content a").click()');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Destination" && location.hash === "#destination"'), 'relative Unicode link and anchor');
  await evaluate('history.back()');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'history back');
  await evaluate('history.forward()');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Destination"'), 'history forward');
  console.log('PASS: GFM, Mermaid, reader controls, editor colors, library, links, images and history');

  await evaluate('document.querySelector("#middle").scrollIntoView(); window.scrollBy(0, 30); window.savedTop = document.querySelector("#middle").getBoundingClientRect().top');
  writeFileSync(target, '# Destination\n\nAdded above.\n\n' + Array.from({length: 80}, (_, i) => `${i === 40 ? "## Middle\n\n" : ""}Paragraph ${i}\n`).join('\n') + '\n## End\n');
  await until(() => evaluate('document.querySelector("#content").textContent.includes("Added above.")'), 'disk update');
  assert.ok(await evaluate('Math.abs(document.querySelector("#middle").getBoundingClientRect().top - window.savedTop) < 4'), 'refresh should preserve the heading position');
  lua(`(function() vim.cmd.edit(${JSON.stringify(target)}); vim.api.nvim_buf_set_lines(0, 0, 1, false, {'# Unsaved buffer'}); return true end)()`);
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Unsaved buffer"'), 'unsaved buffer update');
  writeFileSync(target, '# Disk should not win\n');
  await delay(1500);
  assert.equal(await evaluate('document.querySelector("#content h1")?.textContent'), 'Unsaved buffer');
  lua(`(function() vim.cmd('bdelete!'); return true end)()`);
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Disk should not win"'), 'disk after buffer closes');
  rmSync(target);
  await until(() => evaluate('document.querySelector("#status").textContent.includes("Document is unavailable")'), 'deleted document');
  assert.equal(await evaluate('document.querySelector("#content").textContent'), '');
  console.log('PASS: disk changes, structural refresh position, unsaved buffer priority and deleted files');

  lua(`(function() table.insert(require('fox.reader.workspace').extensions, '.custom'); vim.cmd.cd(${JSON.stringify(second)}); vim.cmd.edit('other.md'); vim.bo.filetype = 'markdown'; vim.cmd('FoxReader'); return true end)()`);
  const secondUrl = lua('_G.reader_url');
  assert.notEqual(secondUrl.split('?')[0], url.split('?')[0]);
  await until(async () => (await (await fetch(new URL('library', url))).json()).files.includes('notes.custom'), 'configured extension');
  const secondFiles = (await (await fetch(new URL('library', secondUrl))).json()).files;
  assert.deepEqual(secondFiles, ['other.md']);
  assert.ok((await (await fetch(new URL('document?path=start.md', url))).json()).html.includes('Start'));
  await cdp('Page.navigate', { url: secondUrl });
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Other workspace"'), 'second workspace');
  lua(`(function() vim.cmd('FoxReaderStop'); return true end)()`);
  await assert.rejects(fetch(url));
  await assert.rejects(fetch(secondUrl));
  console.log('PASS: configured extensions, isolated workspaces and stopping all sessions');
  writeFileSync(target, '# Destination\n\n' + Array.from({length: 80}, (_, i) => `${i === 40 ? "## Middle\n\n" : ""}Paragraph ${i}\n`).join('\n'));
  lua(`(function() vim.cmd.cd(${JSON.stringify(first)}); vim.cmd.edit(${JSON.stringify(target)}); vim.bo.filetype = 'markdown'; vim.cmd('FoxReader'); return true end)()`);
  const beforeRestart = lua('_G.reader_url');
  await cdp('Page.navigate', { url: beforeRestart });
  await until(() => evaluate('document.querySelector("#middle") !== null'), 'document before restart');
  await evaluate('document.querySelector("#middle").scrollIntoView(); window.scrollBy(0, 30)');
  await until(() => { try { return Object.values(JSON.parse(readFileSync(stateFile, 'utf8')).positions).some(position => position.heading === 'middle'); } catch { return false; } }, 'saved position');
  lua(`(function() vim.schedule(function() vim.cmd('qa!') end); return true end)()`);
  await until(() => editor.exitCode !== null, 'editor exit');
  editor = spawn('nvim', ['--headless', '-u', 'NONE', '-i', 'NONE', '-n', '--listen', socket,
    '-c', `lua vim.opt.rtp:prepend(${JSON.stringify(root)}); require('fox.reader.state').path = ${JSON.stringify(stateFile)}; require('fox.reader').setup(); require('fox.markdown.browser').open = function(url) _G.reader_url = url end`], {stdio: ['ignore', 'ignore', 'inherit']});
  await until(() => { try { return lua('true'); } catch { return false; } }, 'restarted Neovim');
  lua(`(function() vim.cmd.cd(${JSON.stringify(first)}); vim.cmd.edit(${JSON.stringify(target)}); vim.bo.filetype = 'markdown'; vim.cmd('FoxReader'); return true end)()`);
  const afterRestart = lua('_G.reader_url');
  assert.notEqual(new URL(beforeRestart).port, new URL(afterRestart).port);
  await cdp('Page.navigate', { url: afterRestart });
  await until(() => evaluate('document.querySelector("#middle") !== null && window.scrollY > 0'), 'restored position');
  assert.ok(Math.abs(await evaluate('document.querySelector("#middle").getBoundingClientRect().top') + 30) < 5);
  assert.equal(await evaluate('document.querySelector("#font").value'), 'Verdana');
  assert.equal(await evaluate('document.querySelector("#alignment").value'), 'left');
  assert.equal(await evaluate('document.querySelector("#width").value'), '920');
  assert.equal(await evaluate('document.querySelector("#lineSpacing").value'), '2.1');
  lua(`(function() require('fox.reader.state').path = ${JSON.stringify(stateFile + '/child')}; return true end)()`);
  await evaluate(`document.querySelector('#font').value = 'Arial'; document.querySelector('#font').dispatchEvent(new Event('change'))`);
  await until(() => evaluate('document.querySelector("#state-status").textContent.includes("could not be saved")'), 'unwritable state warning');
  assert.equal(await evaluate('document.querySelector("#font").value'), 'Arial');
  console.log('PASS: corrupt and unwritable state, origin checks, preferences and position across editor restarts and ports');
} finally {
  connection?.close();
  if (editor && editor.exitCode === null) {
    try { lua(`(function() require('fox.reader.server').stop(); vim.schedule(function() vim.cmd('qa!') end); return true end)()`); } catch {}
    await delay(100);
  }
  for (const child of [chromium, editor]) {
    if (!child || child.exitCode !== null) continue;
    const exited = new Promise(resolve => child.once('exit', resolve));
    child.kill();
    await exited;
  }
  await delay(200);
  rmSync(temporary, { recursive: true, force: true });
}
