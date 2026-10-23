// Run from the config root: node config/tests/integration/markdown_browser.mjs
// Requires Node 22+, Neovim, Chromium and the installed markdown-preview plugin.
import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = process.cwd();
const temporary = mkdtempSync(join(tmpdir(), 'fox-markdown-'));
const socket = join(temporary, 'nvim.sock');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function until(check) {
  for (let attempt = 0; attempt < 150; attempt++) {
    const result = await check();
    if (result) return result;
    await delay(100);
  }
  throw new Error('Timed out waiting for the Markdown preview');
}

function lua(code) {
  return execFileSync('nvim', [
    '--server', socket, '--remote-expr', `luaeval('${code.replaceAll("'", "''")}')`,
  ], { encoding: 'utf8' }).trim();
}

let editor, chromium, connection;
try {
  editor = spawn('nvim', [
    '--headless', '-u', 'NONE', '-i', 'NONE', '-n', '--listen', socket,
    '-c', `lua
      vim.opt.rtp:prepend(${JSON.stringify(root)})
      vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/markdown-preview.nvim')
      require('fox.markdown.browser').setup()
      vim.cmd('runtime plugin/mkdp.vim')
      require('fox.markdown.browser').setup_commands()
      vim.system = function(args) _G.preview_url = args[#args] end
    `,
  ], { stdio: ['ignore', 'ignore', 'inherit'] });
  await until(() => existsSync(socket));
  lua(`(function()
    vim.cmd.edit('config/tests/fixtures/markdown/gfm.md')
    vim.bo.filetype = 'markdown'
    vim.cmd('MarkdownPreviewToggle')
    return true
  end)()`);
  const url = await until(() => lua('_G.preview_url or ""'));

  chromium = spawn('chromium', [
    '--headless', '--no-sandbox', '--disable-gpu', '--disable-dev-shm-usage',
    '--disable-extensions', '--no-proxy-server', '--remote-debugging-port=0',
    `--user-data-dir=${temporary}/chrome`, 'about:blank',
  ], { stdio: 'ignore' });
  const portFile = join(temporary, 'chrome', 'DevToolsActivePort');
  const port = await until(() => existsSync(portFile) && readFileSync(portFile, 'utf8').split('\n')[0]);
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
    pending.delete(response.id);
    clearTimeout(request.timeout);
    if (response.error) request.reject(new Error(JSON.stringify(response.error)));
    else request.resolve(response.result);
  });
  function cdp(method, params = {}) {
    return new Promise((resolve, reject) => {
      const id = ++nextId;
      const timeout = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`Chromium did not answer ${method}`));
      }, 10000);
      pending.set(id, { resolve, reject, timeout });
      connection.send(JSON.stringify({ id, method, params }));
    });
  }
  async function evaluate(expression) {
    const response = await cdp('Runtime.evaluate', { expression, returnByValue: true });
    assert.ok(!response.exceptionDetails, JSON.stringify(response.exceptionDetails));
    return response.result.value;
  }

  await cdp('Page.navigate', { url });
  await until(() => evaluate('Boolean(document.querySelector(".mermaid svg"))'));
  const rendered = await evaluate(`(() => {
    const body = document.querySelector('.markdown-body');
    return {
      rows: [...body.querySelectorAll('tbody tr')].map(row => row.textContent.trim()),
      tasks: [...body.querySelectorAll('input[type="checkbox"]')].map(input => ({ checked: input.checked, disabled: input.disabled })),
      deleted: body.querySelector('s')?.textContent,
      links: [...body.querySelectorAll('a[href]')].map(link => link.getAttribute('href')),
      text: body.textContent,
      code: body.querySelector('pre code')?.textContent,
      inline: body.querySelector('p > code')?.textContent,
      summary: body.querySelector('details summary')?.textContent,
      diagram: body.querySelector('.mermaid svg')?.textContent,
    };
  })()`);
  assert.ok(rendered.rows.some(row => row.includes('Tables') && row.includes('Supported')));
  assert.ok(rendered.rows.some(row => row.includes('a|b')));
  assert.deepEqual(rendered.tasks, [
    { checked: false, disabled: true },
    { checked: true, disabled: true },
    { checked: true, disabled: true },
  ]);
  assert.equal(rendered.deleted, 'Obsolete');
  for (const link of ['https://github.com', 'https://example.com', 'mailto:test@example.com']) {
    assert.ok(rendered.links.includes(link), `Missing autolink: ${link}`);
  }
  assert.ok(rendered.text.includes('"Literal quotes" -- three dots... and (c).'));
  assert.ok(rendered.code.includes('"~~not struck~~"'));
  assert.equal(rendered.inline, '~~inline literal~~');
  assert.equal(rendered.summary, 'More information');
  assert.ok(rendered.diagram.includes('GFM document'));
  console.log('PASS: GFM tables, tasks, strikethrough, autolinks, literal text, code, details and Mermaid');

  lua(`(function()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, {'# Updated without saving'})
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
    return true
  end)()`);
  await until(() => evaluate('document.querySelector(".markdown-body h1")?.textContent.includes("Updated without saving")'));
  assert.equal(await evaluate('document.querySelectorAll("input[type=checkbox]").length'), 3);
  console.log('PASS: GFM preview updates without saving or reloading');
} finally {
  connection?.close();
  if (editor && existsSync(socket)) {
    try {
      lua(`(function()
        vim.cmd('MarkdownPreviewStop')
        vim.schedule(function() vim.cmd('qa!') end)
        return true
      end)()`);
    } catch {}
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
