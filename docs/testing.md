# 🧪 Testing

[← Back to Wiki Index](index.md)

This configuration has a test suite. It exists because a Neovim config fails at
the worst possible moment — on startup, in the middle of something else — and a
typo in a plugin file is invisible until then.

---

## 🏃 Running the tests

| Command | What it checks | Speed |
| :--- | :--- | :--- |
| `nvim -l config/tests/syntax_check.lua` | Every `.lua` file parses | instant |
| `nvim -l config/tests/run.lua --only-failure` | Full Lua suite, including worker and local HTTP checks | about 1–2 minutes |
| `nvim -l config/tests/run.lua tasks --only-failure` | Only specs whose name contains "tasks" | ~1s |
| `nvim --headless -S config/tests/integration/run.lua -- --only-failure` | Specs that need the real editor | a few seconds |
| `node config/tests/integration/markdown_browser.mjs` | GFM and Mermaid rendering and live updates in Chromium | a few seconds |
| `nvim --headless -S config/tests/integration/run.lua -- kitty_shortcuts --only-failure` | Kitty shortcut setup, upgrades and undo (requires Kitty) | a few seconds |
| `:FoxTest --only-failure` | Full Lua suite in a separate headless process | about 1–2 minutes |
| `:FoxTest git --only-failure` | Filtered, from inside the editor | ~1s |

AI assistants use `--only-failure` by default, for full and filtered Lua test
runs. It hides passing cases, passing suite headings, and their `print`,
`vim.notify`, and `nvim_echo` output. Failed cases retain their diagnostics and
errors, and the final totals and exit
status remain unchanged. Omit the flag when verbose output is useful. The flag
also works with `run_me.lua --tests` or `--all`.

`:FoxTest` and `run_me.lua` launch the unit suite in a clean Neovim process so
test mocks cannot interfere with the editor's plugins or active language servers.

The full Lua suite also exercises installed plugin integrations, the bundled Query
worker, and Markdown HTTP serving over loopback using `curl`. A restricted sandbox
must allow local TCP sockets for those HTTP checks. Test preferences use temporary
files; theme tests isolate Omarchy/Ryoku sync settings from the desktop's saved
preferences. A passing run on one OS does not replace native Windows or Ryoku
validation.

The browser test runs from the config root and requires Node 22+, `chromium`,
`nvim`, and the installed `markdown-preview.nvim` plugin. It starts an isolated
browser profile and a local preview server, checks
[`config/tests/fixtures/markdown/gfm.md`](../config/tests/fixtures/markdown/gfm.md), and removes
its temporary files afterward.

Integration tests use the existing Lua runner where possible. The Chromium test
uses JavaScript because Node provides WebSocket for the browser's debugging
protocol. The Kitty test uses Lua for orchestration and assertions; its short
`kitty +runpy` check accesses Kitty's own Python parser rather than duplicating
Kitty's shortcut rules.

All of them exit non-zero on failure, so they work unchanged in CI or a git hook.

---

## 🗂️ Layout

```
config/tests/
├── run.lua              Unit runner: loads every config/tests/spec/*_spec.lua, prints one summary
├── syntax_check.lua     Compiles (never runs) every Lua file in the repository
├── spec/                Unit specs -- pure logic, no plugins loaded (one file per feature)
├── integration/         Specs that need plugins and a real UI (run.lua + a handful of *_spec.lua)
└── lua/                 Lua library specs and LuaLS completion check
```

`config/tests/spec/` has one `*_spec.lua` per feature (`tasks_spec.lua`, `git_status_spec.lua`,
`wiki_modal_spec.lua`, and so on) — the filename always matches the module it pins down, so
if you're editing `lua/plugins/fox/tasks.lua`, its test is `config/tests/spec/tasks_spec.lua`. This
list grows constantly, so don't trust a snapshot of it here — `nvim -l config/tests/run.lua --only-failure` summarizes
the current suite (omit `--only-failure` to list passing cases), and `ls config/tests/spec/` shows the files directly.

The Lua in Neovim library keeps its own suite in `lua/fox/lib/foxnvim/tests/`, run with
`require("fox.lib.foxnvim.tests").run_all()`.

---

## ✍️ Writing a spec

Both runners use the same framework, `foxnvim.test` — the Vitest-style
`describe` / `it` / `expect` already shipped with the FoxVim Lua library.

```lua
-- ============================================================================
-- config/tests/spec/my_feature_spec.lua -- What this file pins down.
-- ============================================================================
-- Why these particular cases matter.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local feature = require("fox.core.path")

describe("fox.core.path.normalize", function()
    it("converts backslashes to forward slashes", function()
        expect(feature.normalize([[C:\a\b]])).toBe("C:/a/b")
    end)
end)
```

Available matchers: `toBe`, `toEqual` (deep), `toBeTruthy`, `toBeFalsy`,
`toBeNil`, `toBeDefined`, `toContain`, `toHaveLength`, `toBeGreaterThan`,
`toBeGreaterThanOrEqual`, `toBeLessThan`, `toBeLessThanOrEqual`, `toThrow`, and
`not_` to invert any of them (`expect(x).not_.toBe(y)` — `not` is a Lua keyword,
so it cannot be used with a dot).

Lifecycle hooks: `beforeEach`, `afterEach`, `beforeAll`, `afterAll`.

### Rules

1. **Specs must be side-effect free.** No keymaps, no writes outside
   `vim.fn.tempname()`, no changing the working directory. Clean up in
   `afterEach`.
2. **Unit specs must not need a plugin.** If it needs telescope or nvim-dap, it
   belongs in `config/tests/integration/`, which boots the full config.
3. **Test the contract, not the implementation.** A spec that breaks whenever the
   code is reorganized is worse than no spec.
4. **Name the case, not the function.** `it("returns the fallback for malformed
   JSON")` beats `it("works")`.

---

## 🎯 What is covered

A sample of what's pinned down, to show the *kind* of thing a spec checks (see
[Layout](#🗂️-layout) above for how to find the full, current list):

| Area | Spec | What it pins |
| :--- | :--- | :--- |
| Paths | `core_path_spec` | Drive letters, trailing slashes, case rules, relative paths |
| Project config | `core_project_spec` | `.foxnvim` → `.foxlocal` → `.nvimfox` lookup ORDER |
| Task runner | `tasks_spec` | Chain resolution, `depends_on`, discovery, legacy files |
| Git | `git_status_spec`, `git_diff_spec` | Porcelain parsing, diff formatting and highlight tags |
| WSL | `wsl_spec` | UNC path parsing and the `wsl.exe --cd` command |
| Wiki keymaps | `wiki_modal_spec` | The open key doesn't collide with another feature's key, and always has a non-Ctrl+Shift fallback |
| Public surface | `commands_spec` (integration) | Every user command and keymap still registers |
| Debug adapters | `dap_adapters_spec` (integration) | Every language still registers its configurations |

UI-heavy flows (pickers, modals in use, terminal execution) are deliberately not
covered: they need a driven UI, and the checks would be brittle. The logic behind
them is factored out into `lua/fox/`, which IS covered.

---

## 🔧 "I edited a plugin file — do I need a test?"

Short version: if the change is logic (parsing, ordering, a conditional, a keymap
that must not collide with another one), yes — a few lines in the matching spec
pays for itself the first time a later edit breaks it silently. If it's pure UI
layout (window size, border color, title text), skip it; see the note above.

1. **Find its spec.** Filename mirrors the module: editing
   `lua/plugins/fox/tasks.lua` → open `config/tests/spec/tasks_spec.lua`. Nothing there
   yet? Copy the shape from [Writing a spec](#✍️-writing-a-spec) above and create
   `config/tests/spec/<module>_spec.lua` — `config/tests/run.lua` picks up every file in that
   folder automatically, no registration step.
2. **Write the case in plain language first**, then the assertion:
   `it("does not share its open key with LSP go-to-definition", ...)` reads as a
   sentence on its own, before you ever look at the `expect(...)` line.
3. **Run just that spec while you iterate**: `nvim -l config/tests/run.lua tasks --only-failure` (or
   `:FoxTest tasks --only-failure` inside the editor) filters by filename substring, so you're
   not waiting on the whole suite every save.
4. **Run everything once before you're done**: `nvim -l config/tests/run.lua --only-failure` — a change
   in a shared module (`lua/fox/core/*.lua`) can break a spec for a completely
   different feature that happens to depend on it.

Check real LuaLS completion (requires Mason LuaLS):

```sh
nvim -l config/tests/lua/completion_check.lua
```

This checks a markerless `main.lua` / `library.lua` project, `lua/` modules and
FoxVim library members using the same server settings as the editor.
