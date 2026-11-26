// Run from the config root: node tests/integration/reader_browser.mjs
// Requires Node 22+, Neovim and Chromium/Edge; Fox Reader itself uses Lua only.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = process.cwd();
const temporary = mkdtempSync(join(tmpdir(), 'fox-reader-'));
const first = join(temporary, 'workspace one');
const second = join(temporary, 'workspace two');
cpSync(join(root, 'tests', 'fixtures', 'fix-viewer-project'), first, { recursive: true });
mkdirSync(second);
const stateFile = join(temporary, 'reader-state.json');
const source = join(first, 'start.md');
const target = join(first, 'nested', 'Guía uno.md');
writeFileSync(join(first, 'actual-readme.md'), readFileSync(join(root, 'README.md')));
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
  const remoteImageURL = new URL('image?path=nested%2Ftall.svg', url).href;
  const layoutPath = join(first, 'nested', 'layout.md');
  writeFileSync(layoutPath, readFileSync(layoutPath, 'utf8').replace('![Tall](tall.svg)', `![Tall](tall.svg)\n\n![Remote](${remoteImageURL})`));

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
      const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`Chromium did not answer ${method}: ${params.expression || ''}`)); }, 10000);
      pending.set(id, { resolve, reject, timeout });
      connection.send(JSON.stringify({ id, method, params }));
    });
  }
  async function evaluate(expression) {
    const response = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    assert.ok(!response.exceptionDetails, JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }
  await cdp('Page.enable');
  const unexpectedDialogs = [];
  connection.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.method === 'Page.javascriptDialogOpening') {
      unexpectedDialogs.push(message.params.message);
      cdp('Page.handleJavaScriptDialog', {accept: false}).catch(() => {});
    }
  });
  writeFileSync(stateFile, '{broken');
  lua(`(function() vim.o.background = 'dark'; vim.api.nvim_set_hl(0, 'Normal', {fg = '#eeddcc', bg = '#123456'}); return true end)()`);
  const initialPage = await (await fetch(url)).text();
  assert.match(initialPage, /data-theme="editor"/);
  assert.match(initialPage, /--editor-background:#123456/);
  assert.ok(initialPage.indexOf('--editor-background:#123456') < initialPage.indexOf('reader.css'));
  await cdp('Page.navigate', { url });
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'initial document');
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden && Boolean(document.querySelector("#markdown-properties textarea"))'), 'continuous editing and properties');
  assert.match(await evaluate('document.querySelector("#markdown-properties textarea").value'), /title: A <safe> title/);
  await cdp('Emulation.setDeviceMetricsOverride', {width: 1280, height: 800, deviceScaleFactor: 1, mobile: false});
  await evaluate(`document.querySelector('#markdown-edit a').dispatchEvent(new PointerEvent('pointerover', {bubbles: true, clientX: 120, clientY: 120}))`);
  await until(() => evaluate('!document.querySelector("#link-preview").hidden && document.querySelector("#link-preview").textContent.includes("Destination")'), 'editable link preview');
  assert.ok(await evaluate(`(() => { const r = document.querySelector('#link-preview').getBoundingClientRect(); return r.width === Math.min(840, innerWidth - 16) && r.height === Math.min(600, innerHeight - 16); })()`));
  await evaluate('hideLinkPreview()');
  await cdp('Emulation.clearDeviceMetricsOverride');
  await until(() => evaluate('document.querySelector("#content img")?.naturalWidth === 1'), 'local image');
  await until(() => evaluate(`document.querySelector('img[alt="Vector"]')?.naturalWidth === 40`), 'local SVG image');
  const svg = await fetch(new URL('image?path=nested%2Fshape.svg', url));
  assert.equal(svg.headers.get('content-type').split(';')[0], 'image/svg+xml');
  assert.match(svg.headers.get('content-security-policy'), /sandbox/);
  assert.equal((await fetch(new URL('image?path=..%2Foutside.svg', url))).status, 404);
  await until(() => evaluate('Boolean(document.querySelector("#content .mermaid svg"))'), 'Mermaid');
  assert.equal(await evaluate('document.querySelector("#content .metadata summary")?.textContent'), 'Properties');
  assert.match(await evaluate('document.querySelector("#state-status").textContent'), /corrupt/);
  assert.deepEqual(await evaluate('[...document.querySelectorAll("#content .metadata dt")].map(node => node.textContent)'), ['title', 'tags', 'description']);
  assert.equal(await evaluate('document.querySelector("#content .metadata dd").textContent'), 'A <safe> title');
  assert.deepEqual(await evaluate('[...document.querySelectorAll("#content .metadata dd")][1].querySelectorAll(".metadata-item").length'), 2);
  assert.deepEqual(await evaluate('[...document.querySelectorAll("#content .metadata-item")].map(item => item.textContent)'), ['reading', 'fox']);
  assert.equal(await evaluate('document.querySelector("#content .metadata dd safe")'), null);
  assert.equal(await evaluate('document.querySelector("#content h1").dataset.sourceLine'), '10');
  assert.ok(await evaluate('[...document.querySelectorAll("header .icon-button")].every(button => button.title && button.getAttribute("aria-label") && !button.textContent.includes("?"))'));
  lua(`(function() vim.api.nvim_buf_set_lines(0, 1, 2, false, {'title: Updated properties'}); return true end)()`);
  await until(() => evaluate('document.querySelector("#content .metadata dd")?.textContent === "Updated properties"'), 'metadata-only update');
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
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#files a")).whiteSpace'), 'nowrap');
  await evaluate(`[...document.querySelectorAll('#files a')].find(a => a.textContent === 'ordinary.md').dispatchEvent(new MouseEvent('click', {bubbles: true, button: 0, ctrlKey: true, shiftKey: true}))`);
  await until(() => evaluate('document.querySelector("#split-frame").contentDocument?.querySelector("#content")?.textContent.includes("Normal text")'), 'library right split');
  assert.equal(await evaluate('document.querySelector("#content h1").textContent'), 'Start');
  assert.equal(await evaluate('document.querySelector("#panes").classList.contains("split-right")'), true);
  await evaluate('document.querySelector("#split-close").click()');
  const libraryWidth = await evaluate('document.querySelector("#library").offsetWidth');
  await evaluate(`document.querySelector('#library-resizer').dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowRight'}))`);
  assert.ok(await evaluate('document.querySelector("#library").offsetWidth') > libraryWidth);
  await evaluate(`document.querySelector('#content a').dispatchEvent(new PointerEvent('pointerover', {bubbles: true, clientX: 120, clientY: 120}))`);
  await until(() => evaluate('!document.querySelector("#link-preview").hidden && document.querySelector("#link-preview").textContent.includes("Destination")'), 'local link preview');
  assert.ok(await evaluate(`(() => { const r = document.querySelector('#link-preview').getBoundingClientRect(); return r.left >= 0 && r.top >= 0 && r.right <= innerWidth && r.bottom <= innerHeight && r.width === Math.min(840, innerWidth - 16) && r.height === Math.min(600, innerHeight - 16); })()`));
  await evaluate(`document.querySelector('#content a').dispatchEvent(new PointerEvent('pointerout', {bubbles: true})); document.querySelector('#content a').dispatchEvent(new MouseEvent('click', {bubbles: true, button: 0, ctrlKey: true, shiftKey: true}))`);
  await until(() => evaluate('document.querySelector("#split-frame").contentDocument?.querySelector("#content h1")?.textContent === "Destination"'), 'Ctrl+Shift+click split');
  await evaluate(`document.querySelector('#vim-motion').click(); document.dispatchEvent(new KeyboardEvent('keydown', {key: 'l', bubbles: true}))`);
  await evaluate(`document.querySelector('#split-frame').contentWindow.scrollTo(0, 0); document.querySelector('#split-frame').contentDocument.body.dispatchEvent(new KeyboardEvent('keydown', {key: 'j', bubbles: true, cancelable: true}))`);
  assert.ok(await evaluate('document.querySelector("#split-frame").contentWindow.scrollY > 0'), 'Vim j scrolls the focused document');
  assert.equal(await evaluate('document.activeElement.id'), 'split-frame');
  await evaluate(`document.querySelector('#split-frame').contentDocument.dispatchEvent(new KeyboardEvent('keydown', {key: 'h', bubbles: true}))`);
  assert.equal(await evaluate('document.activeElement.id'), 'content');
  await evaluate(`document.querySelector('#vim-motion').click(); document.querySelector('#split-close').click()`);
  await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown', {key: 'k', ctrlKey: true}))`);
  assert.equal(await evaluate('document.querySelector("#file-search").open'), true);
  await evaluate(`document.querySelector('#file-search-input').value = 'ordinary.md'; document.querySelector('#file-search-input').dispatchEvent(new Event('input')); document.querySelector('#file-search-input').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter'}))`);
  await until(() => evaluate('document.querySelector("#content").textContent.includes("Normal text")'), 'file search navigation');
  await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown', {key: 'L', ctrlKey: true, shiftKey: true})); document.querySelector('#file-search-input').value = 'start.md'; document.querySelector('#file-search-input').dispatchEvent(new Event('input')); document.querySelector('#file-search-input').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter'}))`);
  await until(() => evaluate('document.querySelector("#split-frame").contentDocument?.querySelector("#content h1")?.textContent === "Start"'), 'right split');
  await evaluate(`document.querySelector('#split-frame').contentDocument.dispatchEvent(new KeyboardEvent('keydown', {key: ' ', code: 'Space', ctrlKey: true, shiftKey: true, bubbles: true}))`);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#library")).display'), 'none');
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#library-resizer")).display'), 'none');
  await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown', {key: ' ', code: 'Space', ctrlKey: true, shiftKey: true, bubbles: true}))`);
  assert.notEqual(await evaluate('getComputedStyle(document.querySelector("#library")).display'), 'none');
  await evaluate(`document.querySelector('#library-toggle').click()`);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#library")).display'), 'none');
  await evaluate(`document.querySelector('#library-toggle').click()`);
  assert.notEqual(await evaluate('getComputedStyle(document.querySelector("#library")).display'), 'none');
  await evaluate(`document.querySelector('#split-frame').contentDocument.dispatchEvent(new KeyboardEvent('keydown', {key: 'w', ctrlKey: true, bubbles: true, cancelable: true}))`);
  assert.equal(await evaluate('document.querySelector("#split-pane").hidden'), true);
  for (const [key, side] of [['J', 'bottom'], ['K', 'top']]) {
    await evaluate(`document.dispatchEvent(new KeyboardEvent('keydown', {key: ${JSON.stringify(key)}, ctrlKey: true, shiftKey: true})); document.querySelector('#file-search-input').value = 'ordinary.md'; document.querySelector('#file-search-input').dispatchEvent(new Event('input')); document.querySelector('#file-search-input').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter'}))`);
    await until(() => evaluate(`document.querySelector('#panes').classList.contains(${JSON.stringify('split-' + side)}) && !document.querySelector('#split-pane').hidden`), `${side} split`);
    const positions = await evaluate(`(() => { const a = document.querySelector('#panes > main').getBoundingClientRect(), b = document.querySelector('#split-pane').getBoundingClientRect(); return { main: a.top, split: b.top, mainHeight: a.height, splitHeight: b.height }; })()`);
    assert.ok(side === 'top' ? positions.split < positions.main : positions.main < positions.split);
    assert.ok(positions.mainHeight > 100 && positions.splitHeight > 100);
    await evaluate(`document.querySelector('#split-close').click()`);
  }
  assert.equal(await evaluate(`(() => {const e = new KeyboardEvent('keydown', {key: 'w', ctrlKey: true, bubbles: true, cancelable: true}); document.dispatchEvent(e); return e.defaultPrevented; })()`), true);
  await until(() => evaluate('document.querySelector("#title").textContent === "Fox Reader"'), 'close active document');
  await evaluate(`document.querySelector('#split-close').click(); openDocument('start.md')`);
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'return after split');
  await evaluate('openDocument("data.json")');
  await until(() => evaluate('Boolean(document.querySelector("#content .json-view"))'), 'formatted JSON');
  assert.match(await evaluate('document.querySelector("#content .json-view").textContent'), /\n  "big": 9007199254740993123,/);
  assert.ok(await evaluate('document.querySelectorAll("#content .json-key").length >= 4'));
  assert.equal(await evaluate('document.querySelectorAll("#content .json-view img").length'), 0);
  await evaluate('openDocument("bad.json")');
  await until(() => evaluate('document.querySelector("#status").textContent.includes("Invalid JSON")'), 'invalid JSON notice');
  assert.equal(await evaluate('document.querySelector("#content .plain-text").textContent'), '{"broken":');
  await evaluate('openDocument("lines.txt")');
  await until(() => evaluate('document.querySelector("#content .plain-text")?.textContent.includes("second")'), 'plain text document');
  assert.equal(await evaluate('document.querySelector("#content .plain-text").textContent'), 'first\nsecond\n\nlast & <tag>\n');
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#content .plain-text")).whiteSpace'), 'pre-wrap');
  assert.ok((await (await fetch(new URL('library', url))).json()).files.includes('data.json'));
  await evaluate('openDocument("nested/layout.md")');
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden && document.querySelector("#markdown-edit img[src]")?.naturalHeight === 640'), 'layout image');
  await evaluate(`(() => { const block = [...document.querySelectorAll('#markdown-edit p')].find(p => p.textContent === 'Paragraph 16 is editable.'); block.scrollIntoView({block: 'center'}); window.layoutTop = block.getBoundingClientRect().top; })()`);
  const layoutPoint = await evaluate(`(() => { const block = [...document.querySelectorAll('#markdown-edit p')].find(p => p.textContent === 'Paragraph 16 is editable.'); const range = document.createRange(); range.setStart(block.firstChild, 5); range.collapse(true); const rect = range.getBoundingClientRect(); return {x: rect.left + 0.2, y: rect.top + rect.height / 2}; })()`);
  assert.equal(await evaluate(`document.elementFromPoint(${layoutPoint.x}, ${layoutPoint.y})?.closest('#markdown-edit')?.id`), 'markdown-edit', JSON.stringify({point: layoutPoint, element: await evaluate(`document.elementFromPoint(${layoutPoint.x}, ${layoutPoint.y})?.outerHTML.slice(0, 200)`)}));
  await cdp('Input.dispatchMouseEvent', {type: 'mousePressed', button: 'left', clickCount: 1, ...layoutPoint});
  await cdp('Input.dispatchMouseEvent', {type: 'mouseReleased', button: 'left', clickCount: 1, ...layoutPoint});
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden || document.querySelector("#markdown-status").textContent'), 'edit layout');
  assert.equal(await evaluate('document.querySelector("#markdown-status").textContent'), '');
  assert.ok(await evaluate('Boolean(document.querySelector("#markdown-edit img[src]"))'), 'Markdown image is shown');
  assert.equal(await evaluate('document.querySelector("#markdown-edit img[src]").getAttribute("src")'), 'image?path=nested%2Ftall.svg', await evaluate('document.querySelector("#markdown-edit img[src]").outerHTML'));
  await until(() => evaluate('document.querySelector("#markdown-edit img[src]")?.naturalHeight === 640'), 'image in editor');
  await until(() => evaluate('document.querySelectorAll("#markdown-edit img[src]").length === 4 && [...document.querySelectorAll("#markdown-edit img[src]")].every(image => image.naturalHeight === 640)'), 'Markdown, HTML and HTTP images in editor');
  assert.equal(await evaluate(`document.querySelector('#markdown-edit img[alt="HTML tall"]').getAttribute('width')`), '80');
  assert.ok(await evaluate(`Math.abs([...document.querySelectorAll('#markdown-edit p')].find(p => p.textContent === 'Paragraph 16 is editable.').getBoundingClientRect().top - window.layoutTop) < 4`), 'editing should retain the clicked viewport position');
  assert.match(await evaluate('document.querySelector("#markdown-edit img[src]").getAttribute("src")'), /image\?path=nested%2Ftall.svg/);
  assert.match(await evaluate('markdownEditor.getMarkdown()'), /!\[Tall\]\(tall\.svg\)/);
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#markdown-edit ul")).listStyleType'), 'disc');
  assert.equal(await evaluate('getComputedStyle(document.querySelector("#markdown-edit ol")).listStyleType'), 'decimal');
  assert.equal(await evaluate('document.querySelector("#markdown-edit ol").start'), 7);
  assert.equal(await evaluate('document.querySelectorAll("#markdown-edit li[data-item-type=task]").length'), 2, await evaluate('document.querySelector("#markdown-edit").innerHTML.slice(-1200)'));
  assert.match(await evaluate('getComputedStyle(document.querySelector("#markdown-edit li[data-checked=true]"), "::marker").content'), /☑/);
  await cdp('Input.insertText', {text: 'X'});
  await until(() => evaluate('document.querySelector("#markdown-edit").textContent.includes("ParagXraph 16 is editable.")'), 'layout cursor position');
  await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 's', code: 'KeyS', modifiers: 2, windowsVirtualKeyCode: 83});
  await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 's', code: 'KeyS', modifiers: 2, windowsVirtualKeyCode: 83});
  await delay(1000);
  await until(() => evaluate('document.querySelector("#markdown-status").textContent === "Saved"'), 'saved layout');
  const layoutMarkdown = readFileSync(join(first, 'nested', 'layout.md'), 'utf8');
  assert.match(layoutMarkdown, /!\[Tall\]\(tall\.svg\)/);
  assert.ok(layoutMarkdown.includes(remoteImageURL));
  assert.ok(layoutMarkdown.includes('<img src="tall.svg" alt="HTML tall" width="80">'));
  assert.ok(layoutMarkdown.includes('<table><tr><td><img src="tall.svg" alt="Table tall" width="60"></td></tr></table>'));
  assert.match(layoutMarkdown, /7\. First numbered/);
  assert.match(layoutMarkdown, /\[x\] Checked task/i);
  assert.match(layoutMarkdown, /\[ \] Open task/);
  await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 'k', code: 'KeyK', modifiers: 2, windowsVirtualKeyCode: 75});
  await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 'k', code: 'KeyK', modifiers: 2, windowsVirtualKeyCode: 75});
  assert.equal(await evaluate('document.querySelector("#file-search").open'), true, 'Ctrl+K works from the editor');
  await evaluate('document.querySelector("#file-search").close()');
  await evaluate('openDocument("start.md")');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'return after file views');
  lua(`(function() local b = vim.fn.bufadd(${JSON.stringify(join(first, 'editable.md'))}); vim.fn.bufload(b); return true end)()`);
  await evaluate('openDocument("editable.md")');
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden && document.querySelector("#markdown-edit h1")?.textContent === "Editing"'), 'editable document');
  assert.equal(await evaluate('Boolean(document.querySelector("#save-markdown, #close-markdown"))'), false);
  assert.equal(await evaluate('document.querySelector("#markdown-properties summary")?.textContent'), 'Properties');
  assert.equal(await evaluate('document.querySelector("#markdown-properties textarea").value'), 'title: Example');
  await evaluate(`(() => { const input = document.querySelector('#markdown-properties textarea'); input.value = 'title: Updated example\\ntags:\\n  - reader'; input.dispatchEvent(new Event('input', {bubbles:true})); window.originalConfirm = window.confirm; window.confirmCount = 0; window.confirm = () => { window.confirmCount++; return false; }; })()`);
  await evaluate('openDocument("ordinary.md")');
  assert.equal(await evaluate('current'), 'editable.md');
  assert.equal(await evaluate('window.confirmCount'), 1);
  await evaluate('window.confirm = () => { window.confirmCount++; return true; }; openDocument("ordinary.md")');
  await until(() => evaluate('current === "ordinary.md" && !document.querySelector("#markdown-edit").hidden'), 'leave with draft');
  await evaluate('openDocument("editable.md")');
  await until(() => evaluate('current === "editable.md" && !document.querySelector("#markdown-edit").hidden && document.querySelector("#markdown-properties textarea")?.value.includes("Updated example")'), 'restore properties draft');
  await evaluate('window.confirm = window.originalConfirm');
  await evaluate('document.querySelector("#markdown-properties textarea").focus()');
  await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 's', code: 'KeyS', modifiers: 2, windowsVirtualKeyCode: 83});
  await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 's', code: 'KeyS', modifiers: 2, windowsVirtualKeyCode: 83});
  await until(() => evaluate('document.querySelector("#markdown-status").textContent === "Saved"'), 'save only properties');
  assert.ok(readFileSync(join(first, 'editable.md'), 'utf8').startsWith('---\ntitle: Updated example\ntags:\n  - reader\n---\n# Editing\n\nStart\n'));
  await evaluate('hideLinkPreview()');
  await evaluate('document.querySelector("#markdown-edit p").scrollIntoView({block:"center"})');
  const editPoint = await evaluate('(() => { const text = document.querySelector("#markdown-edit p").firstChild; const range = document.createRange(); range.setStart(text, 2); range.collapse(true); const rect = range.getBoundingClientRect(); return {x: rect.left + 0.2, y: rect.top + rect.height / 2}; })()');
  assert.equal(await evaluate(`document.elementFromPoint(${editPoint.x}, ${editPoint.y})?.closest('#markdown-edit')?.id`), 'markdown-edit', JSON.stringify({point: editPoint, element: await evaluate(`document.elementFromPoint(${editPoint.x}, ${editPoint.y})?.outerHTML.slice(0, 400)`)}));
  await cdp('Input.dispatchMouseEvent', {type: 'mousePressed', button: 'left', clickCount: 1, ...editPoint});
  await cdp('Input.dispatchMouseEvent', {type: 'mouseReleased', button: 'left', clickCount: 1, ...editPoint});
  await until(() => evaluate('Boolean(document.querySelector("#markdown-edit .ProseMirror")) && !document.querySelector("#markdown-edit").hidden'), 'visual Markdown editor');
  await cdp('Input.insertText', {text: 'X'});
  await until(() => evaluate('document.querySelector("#markdown-edit .ProseMirror p")?.textContent === "StXart"'), 'clicked cursor position');
  await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8});
  await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8});
  await evaluate(`(() => { const editor = document.querySelector("#markdown-edit .ProseMirror"); const selection = window.getSelection(); const range = document.createRange(); range.selectNodeContents(editor.lastElementChild); range.collapse(false); selection.removeAllRanges(); selection.addRange(range); editor.focus(); })()`);
  for (const character of ' *hola*') await cdp('Input.insertText', {text: character});
  await until(() => evaluate('document.querySelector("#markdown-edit em")?.textContent === "hola"'), 'inline italic rendering');
  await evaluate('window.confirm = () => false; openDocument("ordinary.md")');
  assert.equal(await evaluate('current'), 'editable.md', 'unsaved Markdown text prevents navigation when cancelled');
  await evaluate('window.confirm = window.originalConfirm');
  await evaluate('document.dispatchEvent(new KeyboardEvent("keydown", {key:"s", ctrlKey:true, bubbles:true, cancelable:true}))');
  await until(() => evaluate('document.querySelector("#markdown-status").textContent === "Saved"'), 'saved Markdown');
  assert.match(readFileSync(join(first, 'editable.md'), 'utf8'), /[*_]hola[*_]/);
  assert.match(lua(`table.concat(vim.api.nvim_buf_get_lines(vim.fn.bufnr(${JSON.stringify(join(first, 'editable.md'))}), 0, -1, false), '\\n')`), /hola/);
  assert.ok(readFileSync(join(first, 'editable.md'), 'utf8').startsWith('---\ntitle: Updated example\ntags:\n  - reader\n---\n'));
  const savedMarkdown = readFileSync(join(first, 'editable.md'), 'utf8');
  await cdp('Input.insertText', {text: ' more'});
  await until(() => evaluate('markdownDrafts.get("editable.md").source.includes("hola* more")'), 'updated Markdown draft');
  writeFileSync(join(first, 'editable.md'), savedMarkdown + '\\nExternal change\\n');
  await evaluate('document.dispatchEvent(new KeyboardEvent("keydown", {key:"s", ctrlKey:true, bubbles:true, cancelable:true}))');
  await delay(800);
  assert.match(await evaluate('document.querySelector("#markdown-status").textContent'), /changed on disk/, JSON.stringify(await evaluate('({current, editing:markdownEditing, saving:markdownSaving, value:markdownEditor?.getMarkdown().slice(-100), status:document.querySelector("#markdown-status").textContent})')));
  assert.ok(readFileSync(join(first, 'editable.md'), 'utf8').includes('External change'));
  writeFileSync(join(first, 'editable.md'), savedMarkdown);
  await evaluate('document.dispatchEvent(new KeyboardEvent("keydown", {key:"s", ctrlKey:true, bubbles:true, cancelable:true}))');
  await until(() => evaluate('document.querySelector("#markdown-status").textContent === "Saved"'), 'save after conflict');
  await evaluate('openDocument("html.md")');
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden && document.querySelector("#markdown-edit h1")?.textContent === "HTML example"'), 'Markdown with HTML');
  assert.equal(await evaluate('document.querySelector("#markdown-edit b")?.textContent'), 'important');
  await evaluate(`document.querySelector('#markdown-edit a[href="ordinary.md"]').dispatchEvent(new PointerEvent('pointerover', {bubbles:true, clientX:100, clientY:100}))`);
  await until(() => evaluate('!document.querySelector("#link-preview").hidden && document.querySelector("#link-preview").textContent.includes("Normal text")'), 'HTML link preview');
  await evaluate('hideLinkPreview()');
  const htmlOriginalText = 'important';
  const htmlPoint = await evaluate('(() => { const walker = document.createTreeWalker(document.querySelector("#markdown-edit"), NodeFilter.SHOW_TEXT); let text; while ((text = walker.nextNode()) && !text.data.includes("important")) {} const range = document.createRange(); range.setStart(text, text.data.indexOf("important") + 4); range.collapse(true); const rect = range.getBoundingClientRect(); return {x: rect.left + 0.2, y: rect.top + rect.height / 2}; })()');
  await cdp('Input.dispatchMouseEvent', {type: 'mousePressed', button: 'left', clickCount: 1, ...htmlPoint});
  await cdp('Input.dispatchMouseEvent', {type: 'mouseReleased', button: 'left', clickCount: 1, ...htmlPoint});
  await until(() => evaluate('Boolean(document.querySelector("#markdown-edit .ProseMirror")) && !document.querySelector("#markdown-edit").hidden'), 'edit Markdown with HTML');
  await cdp('Input.insertText', {text: 'X'});
  assert.ok(await evaluate('document.querySelector("#markdown-edit").textContent.includes("impoXrtant")'), JSON.stringify({original: htmlOriginalText, editor: await evaluate('document.querySelector("#markdown-edit").textContent')}));
  await until(() => evaluate('document.querySelector("#markdown-edit").textContent.includes("impoXrtant")'), 'clicked HTML text position');
  assert.equal(await evaluate('(() => { const draft = markdownDrafts.get("html.md"); const copy = {...draft}; return updateMarkdownDraft(copy, markdownEditor.getMarkdown().replace(copy.tokens[0].token, "")) === false && copy.error.includes("HTML markers"); })()'), true);
  await evaluate(`(() => { const editor = document.querySelector("#markdown-edit .ProseMirror"); const range = document.createRange(); range.selectNodeContents(editor.querySelector("h1")); range.collapse(false); const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range); editor.focus(); })()`);
  await cdp('Input.insertText', {text: ' edited'});
  await evaluate('document.dispatchEvent(new KeyboardEvent("keydown", {key:"s", ctrlKey:true, bubbles:true, cancelable:true}))');
  await until(() => evaluate('document.querySelector("#markdown-status").textContent === "Saved"'), 'saved Markdown with HTML');
  const htmlMarkdown = readFileSync(join(first, 'html.md'), 'utf8');
  assert.match(htmlMarkdown, /HTML example edited/);
  assert.match(htmlMarkdown, /impoXrtant/);
  for (const html of ['<b class="highlight">', '</b>', '<!-- keep this -->', '<a href="ordinary.md">', '</a>', '<div class="note">', '</div>']) assert.ok(htmlMarkdown.includes(html), htmlMarkdown);
  lua(`(function() local b = vim.fn.bufadd(${JSON.stringify(join(first, 'blocked.md'))}); vim.fn.bufload(b); vim.api.nvim_buf_set_lines(b, 0, -1, false, {'# Unsaved'}); return true end)()`);
  await evaluate('openDocument("blocked.md")');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Unsaved"'), 'unsaved Markdown buffer');
  await evaluate('document.querySelector("#content h1").click()');
  await until(() => evaluate('document.querySelector("#markdown-status").textContent.includes("unsaved changes in Neovim")'), 'modified buffer protection');
  await evaluate('openDocument("start.md")');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'return after Markdown editing');
  await cdp('Emulation.setDeviceMetricsOverride', {width: 1280, height: 700, deviceScaleFactor: 1, mobile: false});
  await evaluate('openDocument("outline.md")');
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden && document.querySelectorAll("#outline nav a").length === 50'), 'editable outline');
  await evaluate(`document.querySelector('#markdown-edit #topic-30').scrollIntoView(); window.scrollBy(0, -60); document.dispatchEvent(new Event('scroll'))`);
  await until(() => evaluate('document.querySelector("#outline a[aria-current=location]")?.textContent === "Topic 30"'), 'outline follows heading');
  assert.equal(await evaluate('document.querySelector("#outline a[aria-current=location]")?.textContent'), 'Topic 30');
  assert.equal(await evaluate('document.querySelector("#outline a[aria-current=location]")?.textContent'), 'Topic 30', JSON.stringify(await evaluate('({top:document.querySelector("#markdown-edit #topic-30").getBoundingClientRect().top, header:document.querySelector("#panes > main > header").offsetHeight, scroll:window.scrollY, editing:markdownEditing, headings:document.querySelectorAll("#markdown-edit h1,#markdown-edit h2,#markdown-edit h3,#markdown-edit h4,#markdown-edit h5,#markdown-edit h6").length, links:document.querySelectorAll("#outline nav a").length, viewport:readingViewportTop(), selected:document.querySelector("#outline a[aria-current=location]")?.textContent})')));
  assert.ok(await evaluate(`(() => { const panel = document.querySelector('#outline'), link = panel.querySelector('[aria-current=location]'); return Math.abs((link.getBoundingClientRect().top - panel.getBoundingClientRect().top) / panel.clientHeight - .75) < .08; })()`), 'outline positions the active topic near 75%');
  await cdp('Emulation.clearDeviceMetricsOverride');
  await evaluate('openDocument("start.md")');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'return after outline');
  assert.ok((await (await fetch(new URL('library', url))).json()).files.includes('hello.js'));
  assert.equal((await fetch(new URL('vs/loader.js', url))).status, 200);
  assert.equal((await fetch(new URL('vs/../../README.md', url))).status, 404);
  assert.equal((await fetch(new URL('run', url), {method: 'POST', headers: {'Content-Type': 'application/json', Origin: 'http://evil.invalid'}, body: JSON.stringify({path: 'hello.js'})})).status, 403);
  for (const [script, expected] of [['hello.js', 'hello node'], ['hello.py', 'hello python']]) {
    await evaluate(`openDocument(${JSON.stringify(script)})`);
    await until(() => evaluate('Boolean(document.querySelector("#code-editor .monaco-editor")) && !document.querySelector("#code-panel").hidden'), `${script} Monaco editor`);
    if (script === 'hello.js') {
      await evaluate('scriptEditor.setValue("console.log(\\\"edited node\\\")\\n")');
      await evaluate('document.querySelector("#save-script").click()');
      await until(() => readFileSync(join(first, script), 'utf8').includes('edited node'), 'saved script');
      await evaluate('scriptEditor.setValue("console.log(\\\"hello node\\\")\\n")');
    }
    await evaluate(`document.querySelector('#run-script').click()`);
    await until(() => evaluate('document.querySelector("#run-status").textContent.includes("Exit code:")'), `${script} execution`);
    assert.equal(await evaluate('document.querySelector("#run-status").textContent'), 'Exit code: 0');
    assert.ok(await evaluate(`outputEditor.getValue().includes(${JSON.stringify(expected)})`), await evaluate('outputEditor.getValue()'));
  }
  for (const script of ['input.js', 'input.py']) {
    await evaluate(`openDocument(${JSON.stringify(script)})`);
    await until(() => evaluate(`scriptPath === ${JSON.stringify(script)}`), `${script} editor`);
    await evaluate(`document.querySelector('#run-script').click()`);
    await until(() => evaluate('outputEditor.getValue().includes("Name: ") && inputOpen'), `${script} prompt`);
    await evaluate(`outputEditor.focus(); outputEditor.trigger('test', 'type', {text: 'Ada'})`);
    await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13});
    await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13});
    await until(() => evaluate('outputEditor.getValue().includes("Hello Ada")'), `${script} input response`);
    if (script.endsWith('.js')) {
      await until(() => evaluate('!document.querySelector("#close-input").disabled'), 'EOF available');
      await evaluate(`document.querySelector('#close-input').click()`);
    }
    if (script.endsWith('.py')) {
      await until(() => evaluate('outputEditor.getValue().includes("Color: ") && inputOpen'), 'second Python prompt');
      await evaluate(`outputEditor.focus(); outputEditor.trigger('test', 'type', {text: 'blue'})`);
      assert.equal(await evaluate('outputInput'), 'blue', await evaluate('outputEditor.getValue()'));
      await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13});
      await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13});
      await until(() => evaluate('outputEditor.getValue().includes("Color is blue")'), 'second Python input response');
    }
    await until(() => evaluate('document.querySelector("#run-status").textContent === "Exit code: 0"'), `${script} interactive exit`);
    assert.equal(await evaluate('!inputOpen'), true);
  }
  assert.equal((await fetch(new URL('run-input', url), {method: 'POST', headers: {'Content-Type': 'application/json', Origin: 'http://evil.invalid'}, body: JSON.stringify({id: 'bad', input: 'text'})})).status, 403);
  await evaluate('openDocument("fail.js")');
  await until(() => evaluate('scriptPath === "fail.js"'), 'failing script');
  await evaluate(`document.querySelector('#run-script').click()`);
  await until(() => evaluate('document.querySelector("#run-status").textContent === "Exit code: 7"'), 'script error exit');
  assert.match(await evaluate('outputEditor.getValue()'), /script failed/);
  await evaluate('openDocument("wait.js")');
  await until(() => evaluate('scriptPath === "wait.js"'), 'long-running script');
  await evaluate(`document.querySelector('#run-script').click()`);
  await until(() => evaluate('outputEditor.getValue().includes("started")'), 'streamed script output');
  await evaluate(`document.querySelector('#stop-script').click()`);
  await until(() => evaluate('document.querySelector("#run-status").textContent.includes("Exit code:")'), 'stop script');
  await evaluate('openDocument("start.md")');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'return after scripts');
  const remoteRequests = [];
  connection.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    if (message.method !== 'Fetch.requestPaused') return;
    remoteRequests.push(message.params.request.url);
    const badge = message.params.request.url.startsWith('https://img.shields.io/');
    cdp('Fetch.fulfillRequest', { requestId: message.params.requestId, responseCode: 200,
      responseHeaders: [{name: 'Content-Type', value: badge ? 'image/svg+xml' : 'image/png'}],
      body: badge ? Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><rect width="1" height="1"/></svg>').toString('base64')
        : 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aWQAAAAASUVORK5CYII=' }).catch(() => {});
  });
  await cdp('Fetch.enable', { patterns: [{urlPattern: 'https://github.com/user-attachments/assets/*'}, {urlPattern: 'https://img.shields.io/*'}] });
  await evaluate('openDocument("actual-readme.md")');
  await until(() => evaluate('document.querySelectorAll("#content img").length === 3'), 'README images');
  const readmeImages = await evaluate('[...document.querySelectorAll("#content img")].map(image => ({src: image.getAttribute("src"), width: image.getAttribute("width"), link: image.parentElement.closest("a")?.href || ""}))');
  assert.ok(readmeImages.every(image => image.src?.startsWith('https://')), JSON.stringify(readmeImages));
  await until(() => evaluate('[...document.querySelectorAll("#content img")].every(image => image.naturalWidth === 1)'), 'remote README image downloads');
  assert.equal(remoteRequests.length, 3);
  assert.deepEqual(readmeImages.map(image => image.width), ['99%', null, '80%']);
  assert.match(readmeImages[1].link, /github\.com\/KristanLaimon\/nvim\/stargazers/);
  assert.match(await evaluate('getComputedStyle(document.querySelector("#content img").closest("p")).textAlign'), /^(?:-webkit-)?center$/);
  await cdp('Fetch.disable');
  await evaluate('openDocument("start.md")');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'return from README');
  console.log('PASS: actual README remote images and badge, local SVG and image boundaries');
  await evaluate('document.querySelector("#content a").click()');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Destination" && location.hash === "#destination"'), 'relative Unicode link and anchor');
  assert.ok(await evaluate(`(() => { const links = [...document.querySelectorAll('#outline nav a')]; const values = ['End', 'Details', 'More'].map(name => parseFloat(getComputedStyle(links.find(link => link.textContent === name)).paddingLeft)); return values[0] < values[1] && values[1] < values[2]; })()`), 'nested headings have greater indentation');
  await evaluate('history.back()');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Start"'), 'history back');
  await evaluate('history.forward()');
  await until(() => evaluate('document.querySelector("#content h1")?.textContent === "Destination"'), 'history forward');
  console.log('PASS: GFM, Mermaid, reader controls, editor colors, library, links, images and history');

  await evaluate('document.querySelector("#middle").scrollIntoView(); window.scrollBy(0, 30); window.savedTop = document.querySelector("#middle").getBoundingClientRect().top');
  writeFileSync(target, '# Destination\n\nAdded above.\n\n' + Array.from({length: 80}, (_, i) => `${i === 40 ? "## Middle\n\n" : ""}Paragraph ${i}\n`).join('\n') + '\n## End\n');
  await until(() => evaluate('!document.querySelector("#markdown-edit").hidden && document.querySelector("#markdown-edit").textContent.includes("Added above.")'), 'disk update');
  assert.ok(await evaluate('Math.abs(document.querySelector("#middle").getBoundingClientRect().top - window.savedTop) < 4'), JSON.stringify(await evaluate('({actual:document.querySelector("#middle").getBoundingClientRect().top, expected:window.savedTop, scroll:window.scrollY, restoring, editing:markdownEditing})')));
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
  await cdp('Page.bringToFront');
  await evaluate('window.scrollTo(0, 0)');
  await until(() => evaluate('window.scrollY === 0'), 'top before saving position');
  await delay(100);
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
  await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 'Control', code: 'ControlLeft', windowsVirtualKeyCode: 17, modifiers: 2});
  await cdp('Input.dispatchKeyEvent', {type: 'keyDown', key: 'w', code: 'KeyW', windowsVirtualKeyCode: 87, modifiers: 2});
  await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 'w', code: 'KeyW', windowsVirtualKeyCode: 87, modifiers: 2});
  await cdp('Input.dispatchKeyEvent', {type: 'keyUp', key: 'Control', code: 'ControlLeft', windowsVirtualKeyCode: 17, modifiers: 0});
  await until(() => evaluate('document.querySelector("#title").textContent === "Fox Reader"'), 'Ctrl+W closes document');
  assert.deepEqual(unexpectedDialogs, []);
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
