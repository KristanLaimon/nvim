import { strict as assert } from "node:assert";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const source = readFileSync(new URL("../lua/fox/terminal/opencode_hook.js", import.meta.url), "utf8");
const { default: plugin } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

test("OpenCode TUI hooks follow each selected session and stop on disposal", async () => {
  const directory = mkdtempSync(join(tmpdir(), "foxvim-hooks-"));
  const previousDirectory = process.env.FOXVIM_AGENT_EVENT_DIR;
  const previousTerminal = process.env.FOXVIM_TERMINAL_ID;
  process.env.FOXVIM_AGENT_EVENT_DIR = directory;
  process.env.FOXVIM_TERMINAL_ID = "terminal-1";
  const read = () => JSON.parse(readFileSync(join(directory, "terminal-1.json"), "utf8"));
  let dispose;
  try {
    let route = { type: "session", sessionID: "first" };
    dispose = plugin.setup({ ui: { router: { current: () => route } } });
    assert.deepEqual(read(), { agent: "opencode", id: "first", event: "start" });
    route = { type: "session", sessionID: "second" };
    await new Promise((resolve) => setTimeout(resolve, 150));
    assert.equal(read().id, "second");
    dispose();
    const api = {
      route: { current: { name: "session", params: { sessionID: "v2" } } },
      lifecycle: { onDispose: (callback) => { dispose = callback; } },
    };
    plugin.tui(api);
    assert.equal(read().id, "v2");
    dispose();
    api.route.current.params.sessionID = "after-disposal";
    await new Promise((resolve) => setTimeout(resolve, 150));
    assert.equal(read().id, "v2");
  } finally {
    dispose?.();
    if (previousDirectory === undefined) delete process.env.FOXVIM_AGENT_EVENT_DIR;
    else process.env.FOXVIM_AGENT_EVENT_DIR = previousDirectory;
    if (previousTerminal === undefined) delete process.env.FOXVIM_TERMINAL_ID;
    else process.env.FOXVIM_TERMINAL_ID = previousTerminal;
    rmSync(directory, { recursive: true, force: true });
  }
});
