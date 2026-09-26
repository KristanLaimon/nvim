# 🐞 Debug Adapters: How Debugging Actually Works in Neovim

[← Back to Wiki Index](index.md)

A from-scratch guide to wiring **any** debugger into this config, written around a real
worked example: making `bun` stop on breakpoints (`lua/plugins/fox/bun_dap.lua`).

You do not need to know anything about debuggers to start here. By the end you should be
able to add a new language's debugger yourself, and — more importantly — diagnose it when
it silently does nothing, which is what debugger integrations do 90% of the time.

> **Related:** [Launch Profiles](launch-profiles.md) is the layer above this one — it builds
> DAP configurations from a per-project `launch.json` so you don't hand-write them.
> [Breakpoints](breakpoints.md) covers persistence, disabled breakpoints and the signs.

---

## 1. The mental model: three processes, not one

The single most common misconception is that "the debugger" is one thing. It is three
separate processes talking over pipes:

```
┌──────────────┐   DAP over stdio    ┌───────────────┐  runtime-specific  ┌─────────────┐
│   Neovim     │ ─────────────────▶  │ Debug Adapter │ ─────────────────▶ │ Your program│
│  (nvim-dap)  │ ◀─────────────────  │  (translator) │ ◀───────────────── │  (bun/node) │
└──────────────┘   JSON messages     └───────────────┘   inspector proto  └─────────────┘
     client                              adapter                              debuggee
```

| Piece | Job | Example |
| :--- | :--- | :--- |
| **Client** | UI. Shows breakpoint signs, variables, step buttons. Knows nothing about any language. | `nvim-dap` + `nvim-dap-ui` |
| **Adapter** | Translator. Speaks DAP to the editor, speaks the runtime's own debug protocol to the program. | `js-debug-adapter`, `debugpy`, `delve`, Bun's adapter |
| **Debuggee** | Your actual code, launched with a debug port/socket open. | `bun ./index.ts` with `BUN_INSPECT=...` |

**Why this split exists:** every runtime invented its own debug protocol. Node/Chrome use
**CDP** (Chrome DevTools Protocol). Safari/JavaScriptCore — and therefore **Bun** — use the
**WebKit Inspector protocol**. Python uses `debugpy`'s own wire format. Go uses Delve's.
If editors talked to runtimes directly, every editor would need N implementations and every
runtime would need M. Microsoft's **Debug Adapter Protocol (DAP)** is the middle layer that
turns `N × M` into `N + M`.

> 💡 **The one-line takeaway**: nvim-dap is not a debugger. It is a DAP client. Your job when
> "adding a debugger" is almost always just *finding or building the adapter* and telling
> nvim-dap how to start it.

---

## 2. DAP in five minutes

### 2.1 The wire format

DAP is JSON over a stream (stdin/stdout or a TCP socket), framed with an HTTP-style header.
Every message looks like this — note the `\r\n\r\n` and that `Content-Length` counts **bytes**,
not characters:

```
Content-Length: 71\r\n
\r\n
{"seq":1,"type":"request","command":"initialize","arguments":{...}}
```

There are exactly three message types:

| Type | Direction | Meaning |
| :--- | :--- | :--- |
| `request` | client → adapter (usually) | "do this": `initialize`, `launch`, `setBreakpoints`, `continue`, `stackTrace` |
| `response` | adapter → client | reply to one request, matched by `request_seq` |
| `event` | adapter → client | unsolicited news: `initialized`, `stopped`, `output`, `terminated`, `exited` |

Reverse requests exist too (adapter → client), the main one being `runInTerminal`: the adapter
asks the *editor* to spawn the process so its output lands in an editor terminal.

That entire format is ~15 lines of code to implement, and you can see it in this repo:
the `write()` function and the `process.stdin.on("data")` loop inside `SERVER_SOURCE` in
[`lua/plugins/fox/bun_dap.lua`](../lua/plugins/fox/bun_dap.lua).

### 2.2 The handshake — this is where bugs live

Read this sequence carefully. Almost every "breakpoints are ignored" bug is a violation of it.

```
client                                adapter
  │  initialize ─────────────────────▶ │   "what can you do?"
  │ ◀───────────── capabilities        │   e.g. supportsConfigurationDoneRequest: true
  │                                    │
  │  launch (or attach) ─────────────▶ │   adapter starts the program, PAUSED
  │                                    │
  │ ◀───────────── event: initialized  │   "I'm ready to receive configuration"
  │                                    │
  │  setBreakpoints ─────────────────▶ │   ← breakpoints are registered HERE
  │  setExceptionBreakpoints ────────▶ │
  │  configurationDone ──────────────▶ │   "done configuring — let it run"
  │                                    │
  │ ◀───────────── event: stopped      │   reason: "breakpoint"
  │  stackTrace / scopes / variables ▶ │   the UI fills in
```

Three non-obvious facts:

1. **`initialized` is an event, not a response.** It does *not* mean "initialize finished".
   It means "you may now send configuration". It typically arrives *after* `launch`.
2. **The program must be frozen between `launch` and `configurationDone`.** This is the whole
   point of `configurationDone`. If the program starts running before breakpoints are
   registered, the breakpoints do nothing — they arrive at a program that already ran past them.
3. **Whether the client sends `configurationDone` at all depends on capabilities.** nvim-dap
   only sends it if the adapter advertised `supportsConfigurationDoneRequest: true`.

You can read nvim-dap's side of this in
`~/AppData/Local/nvim-data/lazy/nvim-dap/lua/dap/session.lua`, function `Session:event_initialized`
(~line 315). It is short and worth reading in full — breakpoints first, then exception
breakpoints, then `configurationDone` in the callback. Strictly ordered, all async.

---

## 3. How nvim-dap is configured

Only two tables matter.

### 3.1 `dap.adapters` — how to *start* the translator

```lua
-- Kind A: "executable" — nvim spawns it, talks DAP over its stdin/stdout.
dap.adapters.bun = {
  type = "executable",
  command = "bun",                    -- binary to run
  args = { bun_dap.server },          -- args; here, our generated stdio server
}

-- Kind B: "server" — the adapter listens on a TCP port. nvim can spawn it first
-- via `executable`, then connect. `${port}` is substituted with a free port.
dap.adapters["pwa-node"] = {
  type = "server",
  host = "localhost",
  port = "${port}",
  executable = { command = "node", args = { dap_server, "${port}" } },
}
```

Both live in [`lua/plugins/editor/dap.lua`](../lua/plugins/editor/dap.lua) (~lines 127–173).
Which kind you use is dictated by the adapter you're integrating, not by preference.

### 3.2 `dap.configurations` — *what* to debug

Keyed by **filetype**, and each entry is a list of launchable configs shown in the picker:

```lua
dap.configurations.typescript = {
  {
    type = "bun",              -- must match a key in dap.adapters
    request = "launch",        -- "launch" (adapter starts it) or "attach" (already running)
    name = "🐰 Launch Current File (Bun)",
    program = "${file}",       -- nvim-dap expands ${file}, ${workspaceFolder}, etc.
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  },
  -- ...
}
```

Everything past `type`/`request`/`name` is **adapter-specific** and passed through verbatim.
`program`, `cwd`, `stopOnEntry`, `runtimeExecutable`, `skipFiles`, `watchMode` are not DAP
standard — they are whatever that particular adapter documents. This is why copying a config
from a random blog post for a different adapter fails: the keys are simply ignored.

> 🧠 **Field values can be functions.** nvim-dap calls them at launch time, which is how
> `runtimeArgs = function() return ts_launch().args end` resolves the right TS runner per
> project, and how `processId = require("dap.utils").pick_process` prompts you.

### 3.3 `launch.json` and `type_to_filetypes`

nvim-dap reads `.vscode/launch.json` automatically. One gotcha, already handled in this config:

```lua
require("dap.ext.vscode").type_to_filetypes = {
  bun = { "typescript", "javascript", "typescriptreact", ... },
}
```

Without that mapping, a `launch.json` entry with `"type": "bun"` would only be offered in
buffers whose *filetype* is literally `bun` — i.e. never. The table tells nvim-dap which
filetypes each adapter type is relevant for.

`load_launchjs` is deprecated: nvim-dap reads `.vscode/launch.json` on demand now. It still
needs this table, for exactly the reason above.

### 3.4 One file per language: `lua/plugins/fox/debuggers/`

Both tables used to be filled inline in `dap.lua`. They are now split one module per
language, each returning a `function(dap)` that registers its own adapter and appends its
own configurations:

```
lua/plugins/fox/debuggers/
├── _shared.lua   -- js-debug registration, skipFiles, web filetypes, the `add` helper
├── bun.lua       -- 🐰 Bun's WebKit-inspector adapter
├── node.lua      -- 🚀 pwa-node (js-debug)
├── browsers.lua  -- 🌐 Chrome / 🔷 Edge / 🦊 Firefox
├── python.lua    -- 🐍 debugpy
├── csharp.lua    -- 🎯 netcoredbg
├── php.lua       -- 🐘 Xdebug
└── go.lua        -- 🐹 delve, via nvim-dap-go
```

`dap.lua` just walks a list:

```lua
for _, language in ipairs({ "bun", "node", "browsers", "python", "csharp", "php", "go" }) do
  local ok, err = pcall(function()
    require("plugins.fox.debuggers." .. language)(dap)
  end)
  if not ok then
    vim.notify("DAP: failed to load debugger '" .. language .. "': " .. tostring(err), vim.log.levels.WARN)
  end
end
```

Three things follow from this shape:

- **List order is picker order.** The first configuration of the first module is what `<F5>`
  runs by default. Bun sits first because that's this config's usual JS runtime.
- **A broken module can't take the others down.** Each `require` is `pcall`'d and warns by
  name.
- **These files are not lazy specs.** lazy's directory import only walks subdirectories
  containing an `init.lua`, so `debuggers/` is invisible to `{ import = "plugins.fox" }` —
  which is precisely why plain modules can live there. See
  [Module Architecture](module-architecture.md#-subdirectories-are-invisible-to-import).

`_shared.lua` holds what more than one module needs:

| Export | Why it's shared |
| :--- | :--- |
| `js_debug(dap)` | Registers `pwa-node`, `pwa-chrome` and `pwa-msedge` from the same js-debug install (Edge is Chromium: same server, different binary). Idempotent, because both `node.lua` and `browsers.lua` call it and neither knows the load order. Falls back from `dapDebugServer.js` (server mode) to the `.cmd` shim (executable mode) |
| `add(dap, filetypes, configs)` | **Appends** configs so bun, node and browsers can share `typescript`. The first module to claim a filetype clears it first — `mason-nvim-dap`'s `default_setup` has already pushed its own generic entries ("Python: Launch file", "Chrome: Debug") into the same tables, and those would otherwise sit in the picker next to the configured ones |
| `js_skip` | `<node_internals>/**`, `**/node_modules/**`. Without it js-debug stops inside node internals and the tsx loader — and nvim-dap force-lists every frame's buffer, so each one becomes a bufferline tab with a long absolute path |
| `web_filetypes` | `typescript`, `javascript`, `typescriptreact`, `javascriptreact`, `svelte`, `vue`, `astro`. Also fed to `type_to_filetypes` |

Browser modules come in two shapes: **Launch** (starts the dev server if nothing is serving,
then opens the browser on it — `url` is a function, resolved inside nvim-dap's coroutine, so
it can wait for the port; see [Dev Server Bridge](launch-profiles.md#-dev-server-bridge-pluginsfoxdev_server)),
and **Attach** (starts nothing; Chromium must already be running with
`--remote-debugging-port=9222`).

Python prefers the project's virtualenv interpreter over whatever `python` resolves to on
`PATH`, so imports match what the project actually installed. Go adds nothing by hand —
`nvim-dap-go` already registers the adapter and the standard configurations.

`tests/dap_debuggers_check.lua` fails loudly if this wiring drifts (config counts and
per-filetype ordering):

```
nvim --headless -n -S tests/dap_debuggers_check.lua
```

### 3.5 The layer around the session

Also in `dap.lua`, and worth knowing because most of it exists to work around a specific
misbehaviour:

| Piece | What it does |
| :--- | :--- |
| **UI layout** | Scopes/stacks/breakpoints/watches on the **right** at `0.24` of the width, repl + console at the bottom at `0.26`. Right, not left, keeps the code window between the file tree and the debugger instead of sandwiched between two fixed-width panels; fractional sizes scale with the terminal, unlike the default flat 40 columns |
| **UI open timing** | Opened on `launch`/`attach`, not on `event_initialized`, so a session that never reaches "initialized" is still visible instead of failing invisibly |
| **`switchbuf`** | Forced to `useopen,usevisible,uselast`. nvim 0.12 defaults to `uselast`, which only reuses the current window when its `buftype` is `""` — stop with focus in the console and the source lands in `winnr('#')` instead of the code window |
| **ANSI output (baleia)** | nvim-dap writes adapter `output` events as plain text, so runtimes that colorize (Bun, anything with `FORCE_COLOR`) show literal `[0m[33m1[0m`. baleia turns the escapes back into highlights, applied globally to `dap-repl` and `dapui_console` |
| **Virtual text** | IntelliJ-style: values at end-of-line, floored at column 80, so code is never pushed right (the plugin's `inline` default shifts the rest of the line). Values truncated at 60 chars, linked to `Comment` so only what changed on this step stands out |
| **`fox_prefer_disk_source`** | js-debug returns a non-zero `sourceReference` for scripts Node ran through in-memory TypeScript stripping, even though the file exists on disk. `source_to_bufnr` checks `sourceReference` before `path`, so nvim-dap opens `dap-src://…` with adapter-served content: a duplicate buffer, no breakpoint signs, junk in the bufferline. A `before.stackTrace` listener zeroes the ref when the path is readable, sending it back to the real file |
| **`fox_jump_on_pause`** | nvim-dap only jumps to the stopped frame when `reason ~= "pause" or allThreadsStopped`. js-debug always reports `allThreadsStopped = false`, so a `debugger` statement, pause-on-entry or the pause button leaves the session stopped with no source buffer and no cursor move. This listener fetches the top frame and jumps for it |
| **Signs & highlights** | 🦊 breakpoint, 🔶 conditional, 💬 logpoint, ⭕ rejected, 🟡 stopped — see [Breakpoints](breakpoints.md). The highlight groups are re-applied on `ColorScheme`, since `:colorscheme` clears user-defined groups |

### 3.6 Repl completion ("immediate window")

The repl is a normal buffer, so blink.cmp's default sources offered string methods and words
scraped from the file — useless while stopped at a breakpoint. `lua/fox/lsp/dap_repl_source.lua`
asks the **debug adapter** instead, so the menu only holds what exists in the current frame.

- Enabled only while `dap.session()` is live; triggers on `.`, `[`, `"`, `'`.
- If the adapter advertises `supportsCompletionsRequest`, it sends a `completions` request for
  the current frame and maps `targets` to items.
- If it doesn't, it falls back to `scopes` → `variables` and lists the frame's variables, with
  each value squashed to one line as the item detail.
- nvim-dap prefixes repl lines with `dap> `; that prefix is stripped before the text reaches
  the adapter, otherwise every completion is computed against the wrong column.

---

## 4. The recipe: adding a debugger for a new language

1. **Find the adapter.** Check `:Mason` first (`debugpy`, `delve`, `js-debug-adapter`,
   `codelldb`, `netcoredbg`, `php-debug-adapter`). Mason installs the binary; it does not
   configure anything. Add its **nvim-dap adapter name** (not the Mason package name —
   `js` → js-debug-adapter, `python` → debugpy, `coreclr` → netcoredbg) to `ensure_installed`
   in `dap.lua`.
2. **Create `lua/plugins/fox/debuggers/<language>.lua`** returning `function(dap) … end`.
   Register the adapter (`executable` or `server`, per its README), guarded with
   `vim.fn.filereadable(...) == 1` so a missing install degrades quietly instead of erroring
   at startup.
3. **Append configs** with `_shared.add(dap, { "<filetype>" }, { … })`. Copy field names from
   that adapter's own docs, not from another adapter's.
4. **Add the module name to the list in `dap.lua`**, in the position you want it to occupy in
   the picker. Add the type to `type_to_filetypes` if `launch.json` should offer it too.
5. **Verify with the real handshake** (next section). "It opened a UI" is not verification;
   stopping on a breakpoint and seeing the right line is.

If Mason has no adapter, you are in the harder case — which is exactly the Bun story.

---

## 5. Case study: making Bun stop on breakpoints

Worth studying because everything that can go wrong did.

### 5.1 Problem one: the wrong protocol

`"type": "bun"` in a launch.json did nothing in Neovim. Reason: Bun is built on
JavaScriptCore, so it speaks the **WebKit Inspector protocol**. `js-debug` / `pwa-node`
speaks **CDP**. Superficially similar, incompatible in practice. There is no flag that fixes
this — a translator has to exist.

**Lesson:** before writing any config, confirm the adapter actually speaks your runtime's
protocol. Two JS runtimes does not mean one adapter.

### 5.2 Problem two: the adapter exists but ships no entry point

Bun's own adapter lives in the monorepo at `packages/bun-debug-adapter-protocol`. But the
VSCode extension runs it **in-process** via `vscode.DebugAdapterInlineImplementation` — no
stdio, no socket, no CLI. Neither package is published to npm.

So `bun_dap.lua` does three things:

- **Sparse git checkout** of just those two packages (`--filter=blob:none --sparse`), because
  the full bun repo is ~2GB and we need ~6MB.
- **Replaces the repo's root `package.json`** with a flat two-dependency manifest, because
  bun's own workspace manifest wants workspace-only deps that `bun install` cannot resolve.
- **Generates the missing entry point** (`bun-dap.ts`): construct `new DebugAdapter()`, pipe
  its `Adapter.response` / `Adapter.event` emissions out as framed JSON on stdout, and feed
  parsed stdin messages back in as `Adapter.request`. ~40 lines. That is the whole "port".

**Lesson:** an adapter designed for in-process embedding can usually be given a stdio face
cheaply, because DAP framing is trivial. Look for the class, not the CLI.

### 5.3 Problem three: the interesting one — breakpoints silently ignored

Sessions started, source loaded, breakpoints showed as verified, and the program ran to
completion without ever stopping. The event trace:

```
events: process, output, initialized, loadedSource, loadedSource, output
FAIL: never stopped
```

The initial theory was a race: fast script finishes before breakpoints register. Plausible,
wrong — and worth noting as a lesson in itself, because "race condition" is a comfortable
guess that stops you from reading the code. The real cause, in `adapter.ts` around line 521:

```ts
const { clientID, supportsConfigurationDoneRequest } = request;
if (!supportsConfigurationDoneRequest && clientID !== "vscode") {
  this.configurationDone();   // sends Inspector.initialized → bun resumes
}
```

Decode it against §2.2:

- Bun's adapter launches the program with `BUN_INSPECT=<url>?wait=1`, which freezes it until
  the adapter sends `Inspector.initialized`. Correct so far.
- That signal is sent by `configurationDone()`. Correct.
- But the snippet above calls `configurationDone()` **during `initialize`** unless the client
  either identifies as `"vscode"` or sets `supportsConfigurationDoneRequest` in the
  *initialize request*. That field is **not a DAP client field** — in the spec,
  `supportsConfigurationDoneRequest` is an **adapter capability**, returned in the
  initialize *response*. VSCode's extension host injects it as a private extra.
- nvim-dap is not `"vscode"` and does not send a non-standard field. So the resume signal was
  queued before `launch` was even called, and flushed the instant the inspector attached —
  before `setBreakpoints` could arrive.

The fix is one branch in our wrapper, where the raw messages already pass through:

```ts
if (message.command === "initialize") {
  (message.arguments ??= {}).supportsConfigurationDoneRequest = true;
}
```

Now the adapter waits for the real `configurationDone`, which nvim-dap sends *after*
breakpoints, exactly as §2.2 requires.

```
events: process, output, initialized, loadedSource, loadedSource, breakpoint, continued, stopped
stopped reason=breakpoint line=3
PASS
```

**Lessons, in order of value:**

1. **Read the adapter's source.** It is on your disk. Grepping `configurationDone` in it took
   less time than the wrong theory did.
2. **A wrapper you own is a seam.** Because every message crosses our `bun-dap.ts`, the fix
   was one line in our repo instead of a fork or an upstream PR wait.
3. **"Upstream bug, can't fix" deserves suspicion.** Here it was a client-side flag.
4. **Verify against the protocol sequence, not vibes.** The event list is what identified the
   defect: `initialized` present, `stopped` absent, `configurationDone` never mattering.

### 5.4 The generated-file trap

`bun-dap.ts` is generated from a Lua string. Editing the Lua does nothing to an existing
install until it is regenerated — a classic way to "fix" something and see no change. Hence
in `M.setup()`:

```lua
if M.installed() and table.concat(vim.fn.readfile(M.server), "\n") ~= SERVER_SOURCE then
  vim.fn.writefile(vim.split(SERVER_SOURCE, "\n"), M.server)
end
```

**Lesson:** any generated artifact needs an automatic staleness check, or you will one day
debug your own cached output.

---

## 5.6 Case study: "Node debug is broken — it exits in 200ms"

The bug report:

```js
async function Hola() {
    console.log("Before Hola");
    for (const i of [1, 2, 3, 4, 5]) console.log("i => ", i);
    console.log("After Hola");
}
Hola();
```

> `pwa-node` starts and ends in 200ms. Bun is fine. Is the rest of my debuggers broken too?

**There was no bug.** The script has no blocking work. With no breakpoint bound, the correct
behaviour of a debug session is: launch, run, print, `terminated`. 200ms *is* success.

It looks like a failure only because §5.3 trained the eye: "session ends instantly" was a real
defect once, for Bun, for a completely different reason. The symptom repeated; the cause did not.

### How it was settled in one command

Instead of clicking `<F5>` and guessing, drive the *real* config headless and print the events —
the §6.3 idea, applied to nvim-dap rather than to the adapter:

```lua
-- scratch.lua — nvim --headless -n -S scratch.lua
require("lazy").load({ plugins = { "nvim-dap" } })
local dap = require("dap")
vim.cmd("edit " .. vim.fn.expand("~/tmp/hola.js"))
vim.fn.cursor(3, 1)
dap.toggle_breakpoint()                       -- BEFORE dap.run, always

for _, e in ipairs({ "event_stopped", "event_terminated", "event_output", "setBreakpoints" }) do
  dap.listeners.after[e]["probe"] = function(_, err, body)
    print("[T] " .. e .. " " .. vim.inspect(err) .. " " .. vim.inspect(body):sub(1, 300))
  end
end

local cfg
for _, c in ipairs(dap.configurations.javascript) do
  if c.name:find("Node") and c.request == "launch" then cfg = c end   -- request, not just name:
end                                                                    -- "Node" also matches Attach
dap.run(cfg)
vim.defer_fn(function() print("alive: " .. tostring(dap.session() ~= nil)) vim.cmd("qa!") end, 6000)
```

Two runs, two facts:

| Run | Result |
| :--- | :--- |
| breakpoint set before `dap.run` | `event_stopped { reason = "breakpoint", hitBreakpointIds = { 1 } }` — works, `.js` and `.ts` alike |
| no breakpoint | `Before Hola … After Hola`, then `event_terminated` — the reported "200ms" |

Verdict in under two minutes, with no restarts and no other debuggers touched.

### Lessons

1. **"Fast exit" is not evidence of anything on its own.** Ask first what the program was
   *supposed* to do while stopped. A 200ms script with no breakpoint has no failure mode to see.
2. **A matching symptom is not a matching cause.** §5.3's instant exit was `configurationDone`
   ordering. This one was an empty breakpoint list. Pattern-matching on the symptom would have
   sent you back into `bun_dap.lua` for nothing.
3. **Reproduce before diagnosing — headless, with the actual config.** Not `dapmin.lua` (that
   bisects config vs environment); this loads *your* config and prints the event trace, which is
   the difference between "node is broken" and "node stopped at line 3".
4. **Suspect the report's scope claim.** "Is the rest broken too?" assumed one shared defect. One
   run of the real config disproved it without auditing seven debugger modules.
5. **Set the breakpoint before launch.** On a script this short there is no "during".

---

## 6. How to debug the debugger

When a session "does nothing", work down this list in order. It goes from cheapest to most
expensive, and stops most problems in the first two steps.

### 6.1 Read the events

```lua
:lua require("dap").set_log_level("TRACE")
:lua vim.cmd("tabnew " .. vim.fn.stdpath("cache") .. "/dap.log")
```

Every message in both directions, timestamped. Match it against §2.2 and ask: which expected
message is missing, or arrives in the wrong order? That question alone identifies most bugs.

### 6.2 Bisect config vs environment

[`dapmin.lua`](../dapmin.lua) at the repo root is a standalone debug setup that loads nothing
from your config:

```
nvim -u dapmin.lua path\to\file.ts
```

- Works here, broken normally → **your config**. Bisect it.
- Broken here too → **the environment**: adapter, runtime, paths, protocol.

[`dapdiag.lua`](../dapdiag.lua) is the complement: `:luafile dapdiag.lua`, run a session,
`:DapDiagOpen`. It logs every event *plus* window/buffer/sign state at each stop — for the
different failure where the session stops correctly but the UI shows you the wrong thing.

### 6.3 Cut the editor out entirely

The strongest move: drive the adapter yourself, no Neovim involved. That is
[`tests/bun_dap_breakpoint_check.ts`](../tests/bun_dap_breakpoint_check.ts) — ~60 lines that
spawn the adapter, send `initialize` + `launch`, respond to `initialized` with
`setBreakpoints` + `configurationDone`, and assert a `stopped` event on the expected line:

```
bun tests/bun_dap_breakpoint_check.ts
```

```
events: process,output,initialized,loadedSource,loadedSource,breakpoint,continued,stopped
stopped reason=breakpoint line=3
PASS
```

Why this is worth writing rather than clicking through the UI:

- **Seconds per iteration**, no nvim restart, no UI noise.
- **Unambiguous verdict** — `PASS` / `FAIL`, not "did it flash?".
- **Proves which layer is broken.** Failing here means the adapter or runtime. Passing here
  while the UI misbehaves means nvim-dap or your config, and you've halved the search space.
- **It is the regression test.** Run it before the fix to confirm you reproduced the bug;
  after, to confirm you fixed it. Both runs are in §5.3.

> 🎯 This is the habit worth stealing from this whole document: when a protocol is involved,
> write the smallest client that speaks it. It converts arguing into measuring.

### 6.4 Failure lookup table

| Symptom | Usual cause |
| :--- | :--- |
| `No configuration found for ''` | Filetype not detected, or no `dap.configurations[ft]` entry |
| Picker never offers your `launch.json` entry | Missing `type_to_filetypes` mapping (§3.3) |
| Session starts, exits instantly, no `stopped` | **First: is a breakpoint actually bound?** A short script with none exits in ~200ms and that is correct (§5.6). Otherwise: program ran before `configurationDone` (§5.3), or it crashed — check `output` events |
| Breakpoint sign turns `⭕` after launch | `DapBreakpointRejected` — adapter refused to bind it. Wrong `cwd`, file never loaded by the program, or sourcemap mismatch |
| Breakpoints show unverified / hollow | Adapter can't map the file: `cwd` wrong, sourcemaps off, or a path-case/separator mismatch on Windows |
| Stops, but shows the wrong file or a blank buffer | Source resolution or UI, not the protocol — use `dapdiag.lua` |
| External `cmd.exe` window pops up (Windows) | Adapter spawning a `.cmd` shim; use `console = "integratedTerminal"` |
| Adapter process dies immediately | Wrong argv in `dap.adapters`. Run that exact command in a shell and read stderr |

---

## 7. Windows-specific things that will bite you

Two-thirds of the work in this integration was platform detail, not protocol.

- **Path separators.** Adapters compare paths as strings. `C:\x\y` ≠ `C:/x/y` ≠ `c:/x/y`, and
  breakpoints silently fail to bind on a mismatch. This config normalizes to forward slashes
  (`:gsub("\\", "/")`), and Bun's adapter has its own `normalizeWindowsPath` — for the same reason.
- **No Unix domain sockets.** Bun's adapter uses a `ws+unix://` socket plus a Unix signal on
  POSIX, and falls back to TCP on `127.0.0.1` on Windows. Notice it uses `127.0.0.1`, not
  `localhost`: the latter can resolve to IPv6 `::1` and fail to connect.
- **`.cmd` shims.** npm-installed "binaries" on Windows are batch shims. Spawning one without
  a shell can pop a console window or fail outright — prefer the real `node <script.js>` form,
  which is why the `pwa-node` adapter here points at `dapDebugServer.js` directly.

---

## 8. Exercises, roughly by difficulty

1. **Read the log.** Start any working TS debug session with `TRACE` logging on and map every
   message to §2.2 by hand. Do this once and the rest of this document becomes obvious.
2. **Add a debugger from Mason.** Install `debugpy` or `delve` and wire it up yourself with §4.
   Small, and the payoff is real.
3. **Break it on purpose.** Delete the `supportsConfigurationDoneRequest` line from
   `SERVER_SOURCE`, restart nvim, run the check script. Watch it fail the same way. Restore it.
   Deliberately reproducing a bug you already fixed is the cheapest way to actually own the
   explanation.
4. **Write a check script for another adapter.** Copy `tests/bun_dap_breakpoint_check.ts`, point
   it at `debugpy`, adjust the launch arguments. You will learn more about DAP in that hour than
   from any spec.
5. **Handle a reverse request.** Make the check script answer a `runInTerminal` reverse request
   instead of ignoring it. This is the piece that lets program output land in an editor terminal.

---

## 9. Reference

**In this repo**

| Path | What it is |
| :--- | :--- |
| [`lua/plugins/editor/dap.lua`](../lua/plugins/editor/dap.lua) | All adapters + configurations + dap-ui setup |
| [`lua/plugins/fox/bun_dap.lua`](../lua/plugins/fox/bun_dap.lua) | Bun adapter installer and generated stdio server |
| [`lua/plugins/fox/launch_profiles.lua`](../lua/plugins/fox/launch_profiles.lua) | Per-project profiles that build DAP configs dynamically |
| [`tests/bun_dap_breakpoint_check.ts`](../tests/bun_dap_breakpoint_check.ts) | Editor-free breakpoint regression check |
| [`dapmin.lua`](../dapmin.lua) / [`dapdiag.lua`](../dapdiag.lua) | Minimal repro harness / session state logger |

**Outside**

- DAP specification — `microsoft.github.io/debug-adapter-protocol` (read *Overview* and the
  *Initialization* sequence diagram; skip the request catalogue until you need it)
- `nvim-dap` docs — `:h dap.txt`, `:h dap-adapter`, `:h dap-configuration`
- nvim-dap source: `nvim-data/lazy/nvim-dap/lua/dap/session.lua` — the client half of §2.2
- Bun's adapter: `nvim-data/fox-bun-dap/packages/bun-debug-adapter-protocol/src/debugger/adapter.ts`

---

## 10. The engineering habits, extracted

Independent of debuggers:

1. **Learn the protocol before touching the config.** Ten minutes on the handshake explains a
   whole class of bugs that no amount of option-tweaking will.
2. **Read the dependency's source.** It is on disk. "Upstream bug" is a conclusion, not a
   starting assumption.
3. **Own a seam.** A thin wrapper you control turns three-week upstream waits into one-line fixes.
4. **Build the smallest client that speaks the protocol.** Fast, unambiguous, and it becomes
   your regression test for free.
5. **Bisect layers, don't guess.** Minimal repro first: it tells you *which of three processes*
   to look at, and that is most of the work.
6. **Verify with an observable, not a feeling.** `stopped reason=breakpoint line=3` is a fact.
   "Seems to work now" is not.
7. **Distrust your first theory when it's comfortable.** "Race condition" felt right and cost
   real time; reading five lines of source ended it.
8. **Confirm the bug exists before fixing it.** A repeat symptom is not a repeat cause, and
   sometimes the system is behaving exactly as designed (§5.6). Reproducing costs minutes;
   chasing a phantom costs an afternoon.
