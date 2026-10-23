# 🏛️ Architecture

[← Back to Wiki Index](index.md)

How this configuration is put together: the layers, what may depend on what, how
startup runs, and where to add things.

If you only read one section, read [The four layers](#-the-four-layers) and
[Where do I put new code?](#-where-do-i-put-new-code).

---

## 📂 Directory map

```
nvim/
├── init.lua                  Editor entry point
├── lazy-lock.json            Plugin versions
├── run_me.lua                Setup and quality-check runner
├── README.md
├── AGENTS.md                 Assistant guidelines
├── lua/
│   ├── vim_options.lua       Editor options and bootstrap hooks
│   ├── lazy_init.lua         Plugin manager bootstrap
│   ├── keymaps/              Global keybindings
│   ├── fox/                  Core, languages, libraries, and features
│   └── plugins/              Plugin specifications
├── after/                    Filetype overrides
├── docs/                     Wiki and language guides
├── config/
│   ├── aliases/              Compiler shims
│   ├── colors/               Local colorschemes
│   ├── schemas/              JSON, TOML, and XML schemas
│   ├── schemas-langs/        Bundled type definitions
│   ├── snippets/             Snippet definitions and schema
│   ├── templates/            File creation templates
│   ├── scripts/              Setup scripts and utilities
│   ├── tests/                Unit and integration suites
│   ├── tools/                FoxQuery binaries and Go sources
│   ├── skills/               Local skills
│   └── plans_notes_md/       Plans, notes, and refactor briefs
├── .foxnvim/                 Local project state (ignored by Git)
├── .github/                  Repository assets
└── .*                        Git and tool configuration
```

---

## 🧱 The four layers

Dependencies point **downward only**. Nothing in a lower layer may require
something from a higher one.

```mermaid
graph TD
    subgraph L4["Layer 4 · Bootstrap"]
        INIT["init.lua"]
        CONFIG["lua/<br/>options · keymaps · lazy"]
    end

    subgraph L3["Layer 3 · Features (lazy specs)"]
        FOXPLUG["lua/plugins/fox/<br/>tasks · launch_profiles · git_center · …"]
        THIRD["lua/plugins/{ui,editor,lsp,miscelanea}/<br/>third-party plugin specs"]
    end

    subgraph L2["Layer 2 · Shared libraries"]
        CORE["fox.core<br/>path · store · project · ui · z_index · dock"]
        GIT["fox.git<br/>cmd · status · diff"]
        LAUNCH["fox.launch.runtimes"]
        FOXLSP["fox.lsp · fox.projects"]
    end

    subgraph L1["Layer 1 · Platform"]
        NVIM["Neovim API<br/>vim.api · vim.uv · vim.lsp"]
        FOXNVIM["lua/fox/lib/foxnvim/<br/>FoxVim Lua libraries"]
    end

    INIT --> CONFIG
    CONFIG --> FOXPLUG
    CONFIG --> THIRD
    FOXPLUG --> CORE
    FOXPLUG --> GIT
    FOXPLUG --> LAUNCH
    FOXPLUG --> FOXLSP
    THIRD --> CORE
    THIRD --> FOXPLUG
    CORE --> NVIM
    GIT --> NVIM
    LAUNCH --> NVIM
    FOXLSP --> NVIM
    FOXPLUG --> FOXNVIM
```

**Layer 1 — Platform.** The Neovim API, and `lua/fox/lib/foxnvim/`, which is a
self-contained scripting library with its own public API and test suite. It
knows nothing about this configuration.

**Layer 2 — Shared libraries (`lua/fox/`).** Pure Lua. No keymaps, no autocmds,
no user commands, no global state. Everything here is unit-testable without
starting a plugin, which is exactly why the tests in `config/tests/spec/` are fast.

**Layer 3 — Features (`lua/plugins/`).** Each file returns a lazy.nvim spec.
This is where UI, keymaps, commands and state live. FOX features may use
third-party plugins (telescope, dap) and each other.

**Layer 4 — Bootstrap (`lua/`).** Options, keymaps and the plugin
manager. It wires things together and owns no features of its own.

---

## 🚀 Startup sequence

```mermaid
sequenceDiagram
    participant NV as Neovim
    participant INIT as init.lua
    participant OPT as vim_options
    participant KEY as keymaps
    participant LAZY as lazy_init
    participant SPEC as plugins/*

    NV->>INIT: source init.lua
    INIT->>INIT: vim.loader.enable() (bytecode cache)
    INIT->>OPT: require
    OPT->>OPT: filetypes, options, shell, PATH repair
    INIT->>KEY: require
    KEY->>KEY: editor → search → lsp → debug → fox
    INIT->>LAZY: require
    LAZY->>LAZY: clone lazy.nvim if missing
    LAZY->>SPEC: import ui → editor → lsp → fox → miscelanea
    SPEC-->>NV: eager specs run setup(); lazy ones wait for key/cmd/event
    NV->>NV: VimEnter (breakpoint keys, dashboard)
```

Two ordering rules matter:

1. **Keymaps load before plugins.** A key therefore works even before the plugin
   behind it has loaded — the handler `require`s the module on first press, and
   lazy.nvim loads it then.
2. **`plugins.fox` is imported after `editor` and `lsp`.** FOX features assume
   telescope and nvim-dap exist as specs.

### ⚡ Startup Performance & `lazy_require`

To achieve ultra-fast startup times (~260ms total startup time on Windows), FoxVim enforces lazy module resolution during `lazy.nvim` spec discovery:

* **Top-Level Spec Import Deferral (`lazy_require`)**: Spec files in `lua/plugins/fox/` and `lua/plugins/editor/` use `require("fox.core.lazy_require")("fox.module.name")`. This creates a zero-overhead metatable proxy that defers actual module loading until a property or function is accessed at runtime.
* **Lazy Persistence State**: State reads from disk (such as Neo-tree sidebar width or terminal split height) are wrapped in lazy getters (`get_saved_width()`, `get_terminal_height()`) so no file I/O blocks initial editor startup.
* **Optimized PATH Repair**: Candidate toolchain directories in `lua/vim_options.lua` are checked and appended efficiently without blocking `init.lua`.

---

## 🧩 The local plugin spec pattern

Every file directly inside `lua/plugins/fox/` is BOTH a module and a lazy.nvim
spec:

```lua
local M = {}

M.settings = { ... }        -- everything tunable, at the top of the file
function M.setup() ... end  -- commands, keymaps, autocmds

return setmetatable({
  name = "fox_tasks",
  dir = require("fox.core.lazyspec").for_module(),
  lazy = false,
  config = M.setup,
}, { __index = M })
```

`setmetatable` makes both worlds work at once: lazy.nvim sees a spec table,
while `require("plugins.fox.dev.tasks").run_task_item(...)` still reaches the
module's own functions through `__index`.

Two rules come out of this:

* **`M.settings`, never `M.config` or `M.opts`.** `config` and `opts` are lazy
  spec fields; a module table using those names would shadow them.
* **Only top-level files are specs.** lazy.nvim does not descend into
  subdirectories, which is what makes `plugins/fox/debuggers/` a safe place for
  helper modules. Everything else that is not a spec belongs in `lua/fox/`.

See [module-architecture.md](module-architecture.md) for why each spec needs its
own `dir`.

---

## 🔗 Who depends on whom

```mermaid
graph LR
    TASKS["tasks"]
    LAUNCH["launch_profiles"]
    RUNTIMES["fox.launch.runtimes"]
    DAPBP["dap_breakpoints"]
    GITC["git_center"]
    TERM["terminal"]
    DOCK["fox.core.dock"]
    STORE["fox.core.store"]
    PROJECT["fox.core.project"]
    PATH["fox.core.path"]
    UI["fox.core.ui"]
    MODAL["input_modal"]
    EXPLORER["file_explorer"]
    FAV["fox.projects.favorites"]
    PROJNVIM["Local recent-project spec"]
    DEBUGGERS["plugins/fox/debuggers/*"]

    TASKS --> DOCK
    TASKS --> STORE
    TASKS --> PROJECT
    TERM --> DOCK
    LAUNCH --> TASKS
    LAUNCH --> RUNTIMES
    LAUNCH --> MODAL
    DAPBP --> TASKS
    DAPBP --> STORE
    DEBUGGERS --> RUNTIMES
    GITC --> MODAL
    GITC --> UI
    EXPLORER --> FAV
    PROJNVIM --> FAV
    PROJECT --> PATH
    STORE --> PATH
    UI --> PATH
```

Highlights worth knowing:

* **`tasks` is the execution engine.** Launch profiles, the dev-server bridge and
  the Lua runner all end up calling `tasks.run_custom_command`.
* **`fox.launch.runtimes` is the language table.** Both "run in a terminal" and
  "debug with DAP" read from it, so adding a language is one entry.
* **`fox.core.dock` owns the bottom strip.** The multi-terminal (left) and task
  outputs (right) share it; neither manages the layout alone any more.
* **Favorites are shared.** Starring a folder in the explorer pins the project in
  the recent-projects picker, because both read `fox.projects.favorites`.

---

## 💾 Per-project state

Everything project-specific lives in the project itself, under `.foxnvim/`.
Nothing is stored globally except caches and recent lists.

```mermaid
graph TD
    ROOT[".foxnvim/ in your project"]
    TASKS["tasks.json<br/>default task + custom tasks & chains"]
    LAUNCH["launch.json<br/>run/debug profiles"]
    BREAK["breakpoints.json<br/>lines, conditions, enabled state"]
    TYPES["types.json<br/>active type schemas"]
    GEN["types.d.ts<br/>generated, gitignorable"]

    ROOT --> TASKS
    ROOT --> LAUNCH
    ROOT --> BREAK
    ROOT --> TYPES
    TYPES -.generates.-> GEN

    TASKS --- P1["plugins/fox/tasks.lua"]
    LAUNCH --- P2["plugins/fox/launch_profiles.lua"]
    BREAK --- P3["plugins/fox/dap_breakpoints.lua"]
    TYPES --- P4["plugins/fox/type_injector.lua"]
```

All four go through `fox.core.project.config_path(name, root)`, which resolves
`.foxnvim/` first, then the legacy `.foxlocal/` and `.nvimfox/` locations, and
through `fox.core.store`, whose reads never throw: a corrupt file degrades to a
default instead of breaking startup.

Global state (caches, not settings) lives under `stdpath("data")`:
`project_favorites.json`, `wsl_recent_projects.json`, `command_palette_history.json`, `workspaces/index.json`,
`fox-specs/` (the empty marker directories), `fox-bun-dap/`.

---

## 🧭 Where do I put new code?

| I want to… | Put it in | Notes |
| :--- | :--- | :--- |
| Add a keybinding | `lua/keymaps/<domain>.lua` | Unless it belongs to a lazy-loaded plugin — then use that spec's `keys`. |
| Add a third-party plugin | `lua/plugins/<area>/<name>.lua` | Return a lazy spec. Nothing else to register. |
| Add a FOX feature | `lua/plugins/fox/<name>.lua` | Follow the local spec pattern above. |
| Add a helper used by two features | `lua/fox/<area>/<name>.lua` | Must stay pure: no keymaps, no commands. |
| Add a language to run/debug | `lua/fox/launch/runtimes.lua` + `lua/plugins/fox/debuggers/` | See [adding-language.md](adding-language.md). |
| Add an editor option | `lua/vim_options.lua` | The `settings` table at the top. |
| Change a feature's behaviour | That module's `M.settings` block | Always the first thing in the file. |
| Add a test | `config/tests/spec/` or `config/tests/integration/` | See [testing.md](testing.md). |

---

## 📐 Conventions

Every file in this configuration follows the same shape:

```lua
-- ============================================================================
-- WHAT THIS FILE IS -- one line.
-- ============================================================================
-- WHY IT EXISTS, what it owns, the keys or commands it exposes, and anything
-- surprising a reader would otherwise have to reverse-engineer.
-- ============================================================================

local dependency = require("...")

-- ============================================================================
-- CONFIGURATION -- everything tunable, before any logic
-- ============================================================================
M.settings = { ... }

-- ============================================================================
-- SECTIONS -- grouped by responsibility
-- ============================================================================
--- What the function does, and why when that is not obvious.
--- @param name type Description.
--- @return type Description.
function M.something(name) end
```

Rules that are load-bearing rather than cosmetic:

1. **Configuration first.** If a value could reasonably be changed — a key, a
   size, a path, a colour, a timeout, a list of languages — it belongs in the
   settings block at the top, not buried in a function.
2. **Comments explain WHY.** What the code does is visible; why it is written
   that way is not. Every workaround names the behaviour it works around.
3. **One owner per concern.** Two modules must not both implement path
   normalization, JSON persistence or dock layout; they share one library.
4. **Tabs for indentation**, following `.editorconfig`.
5. **English throughout**, including notifications.

---

## 🧪 Tests

```mermaid
graph LR
    SYNTAX["config/tests/syntax_check.lua<br/>parses every Lua file"]
    UNIT["config/tests/run.lua<br/>config/tests/spec/*_spec.lua"]
    INTEG["config/tests/integration/run.lua<br/>*_spec.lua with plugins"]
    FOXNVIM["lua/fox/lib/foxnvim/tests/<br/>library suite"]

    SYNTAX --> UNIT --> INTEG
    UNIT -.same framework.-> FOXNVIM
```

```sh
nvim -l config/tests/syntax_check.lua                 # nothing is broken
nvim -l config/tests/run.lua                          # unit specs (fast, no plugins)
nvim --headless -S config/tests/integration/run.lua   # with the real editor
```

Details, and how to write a spec, in [testing.md](testing.md).
