// FoxVim session integration; managed asset, no external packages.
import { writeFileSync, renameSync, unlinkSync } from "node:fs";
import { join } from "node:path";

function report(id) {
  const directory = process.env.FOXVIM_AGENT_EVENT_DIR;
  const terminal = process.env.FOXVIM_TERMINAL_ID;
  if (!directory || !terminal || !/^[\w-]+$/.test(terminal) || typeof id !== "string" || !id || id.length > 1024) return;
  const target = join(directory, `${terminal}.json`);
  const temporary = `${target}.${process.pid}.tmp`;
  try {
    writeFileSync(temporary, JSON.stringify({ agent: "opencode", id, event: "start" }), { mode: 0o600 });
    renameSync(temporary, target);
  } catch {
    try { unlinkSync(temporary); } catch {}
  }
}

function watch(selection) {
  let previous;
  const update = () => {
    const id = selection();
    if (id && id !== previous) { report(id); previous = id; }
  };
  update();
  const timer = setInterval(update, 100);
  timer.unref?.();
  return () => clearInterval(timer);
}

// Both OpenCode TUI SDKs provide the selected session; server-global events
// cannot safely attribute an attached TUI to a FoxVim terminal.
export default {
  id: "foxvim.session",
  setup(api) {
    if (!process.env.FOXVIM_AGENT_EVENT_DIR) return;
    return watch(() => {
      const route = api.ui.router.current();
      return route.type === "session" ? route.sessionID : undefined;
    });
  },
  tui(api) {
    if (!process.env.FOXVIM_AGENT_EVENT_DIR) return;
    const dispose = watch(() => {
      const route = api.route.current;
      return route?.name === "session" ? route.params?.sessionID : undefined;
    });
    api.lifecycle.onDispose(dispose);
  },
};
