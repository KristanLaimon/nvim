# 🔌 How to Create a Local Plugin

[← Back to Wiki Index](index.md)

This guide walks you through creating custom local plugins inside the **FoxVim** configuration.

Unlike traditional Neovim configurations that require external directories (`my-plugins/plugin-name`) and `dev = true` settings in `lazy.nvim`, FoxVim uses a built-in **Dual Module-Spec Pattern** located inside `lua/plugins/fox/`.

---

## 🏛️ How Local Plugins Work in FoxVim

In FoxVim, custom plugins follow a 4-layer architectural hierarchy (see [Architecture](architecture.md)):

* **`lua/fox/` (Layer 2 — Shared Libraries):** Pure, reusable, unit-testable Lua logic (e.g., `fox.core.store`, `fox.git.cmd`, `fox.core.ui`). Pure modules have no side effects, keymaps, or auto-commands.
* **`lua/plugins/fox/` (Layer 3 — Features / Local Specs):** Single-file local plugin specs (e.g., `font.lua`, `tasks.lua`, `git_center.lua`). Every top-level file in this folder is automatically imported by `lazy.nvim`.
* **Subdirectories in `lua/plugins/fox/`:** `lazy.nvim` directory auto-import only scans top-level files. Subdirectories (such as `lua/plugins/fox/debuggers/`) are invisible to auto-import, making them safe for helper modules that are not specs.

---

## 🛠️ Step-by-Step Guide

### Step 1: Create the Plugin File
Create a new `.lua` file inside `lua/plugins/fox/`. The filename will become your module name:
```
lua/plugins/fox/my_custom_feature.lua
```

### Step 2: Define `M.settings`
Put all configurable options (keys, default sizes, limits, titles, paths) at the very top of your file in an `M.settings` table.

> ⚠️ **IMPORTANT:** Always use `M.settings` and **NEVER** `M.config` or `M.opts`. Because `config` and `opts` are reserved `lazy.nvim` spec fields, exposing `M.config` would shadow your module's functions when accessed via `require(...)`.

### Step 3: Implement Module Functions & Setup
Define your module's functions (`M.do_action()`) and a setup function (`M.setup()`) where user commands, autocmds, or keybindings are registered.

### Step 4: Return the Dual Spec-Module Metatable
At the end of the file, return a `lazy.nvim` spec table wrapped in a metatable:
```lua
return setmetatable({
	name = "fox_my_custom_feature",
	dir = require("fox.core.lazyspec").for_module(),
	lazy = false,
	config = M.setup,
}, { __index = M })
```

---

## 📄 Complete Starter Template

Copy and paste this template into `lua/plugins/fox/my_custom_feature.lua`:

```lua
-- ============================================================================
-- FOX PLUGIN: My Custom Feature -- Short description of what it does.
-- ============================================================================
-- WHAT IT DOES
--   Explain the feature, background jobs, or user workflow here.
--
-- COMMANDS
--   :MyFeatureRun    Executes the main action
-- ============================================================================

local store = require("fox.core.store") -- Example: optional shared library

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================
M.settings = {
	--- Default message shown when the command runs.
	greeting = "Hello from my local FOX plugin!",

	--- Title used in vim.notify alerts.
	notify_title = "My Custom Feature",
}

-- ============================================================================
-- STATE (Optional)
-- ============================================================================
M.state = {
	run_count = 0,
}

-- ============================================================================
-- API / PUBLIC FUNCTIONS
-- ============================================================================

--- Main action function.
function M.do_action()
	M.state.run_count = M.state.run_count + 1
	vim.notify(
		string.format("%s (Run #%d)", M.settings.greeting, M.state.run_count),
		vim.log.levels.INFO,
		{ title = M.settings.notify_title }
	)
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers user commands, keymaps, and event listeners.
function M.setup()
	if vim.fn.exists(":MyFeatureRun") == 0 then
		vim.api.nvim_create_user_command("MyFeatureRun", M.do_action, {
			desc = "Run my custom FOX feature action",
		})
	end
end

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "fox_my_custom_feature",
	dir = require("fox.core.lazyspec").for_module(),
	lazy = false,
	config = M.setup,
}, { __index = M })
```

---

## ⚙️ How the Spec-Module Metatable Works

The `setmetatable(plugin_spec, { __index = M })` idiom allows the file to act as **both**:

1. **A `lazy.nvim` plugin spec:** `lazy.nvim` receives a table containing `name`, `dir`, `lazy`, and `config`.
2. **A Lua module:** Other files or keymaps can write `require("plugins.fox.my_custom_feature").do_action()`. The `__index` metatable redirects calls directly to `M`.

---

## ⚠️ Understanding `fox.core.lazyspec`

`lazy.nvim` indexes local plugin specs by their directory (`dir`). If multiple specs declare the same `dir`, `lazy.nvim` merges them together, keeping only one `name` and running only one `config()` function (silently dropping all other specs).

To prevent this collision without requiring external folders, `lua/fox/core/lazyspec.lua` dynamically generates a unique, empty marker directory for each plugin file:

```lua
dir = require("fox.core.lazyspec").for_module()
```

This creates an empty folder under `stdpath("data")/fox-specs/<module_name>`, satisfying `lazy.nvim`'s requirement for unique directories.

---

## ⚡ Lazy-Loading Options

If your plugin should not load at startup (e.g., heavy popups or on-demand tools), configure lazy loading in the return spec table:

```lua
return setmetatable({
	name = "fox_my_custom_feature",
	dir = require("fox.core.lazyspec").for_module(),
	lazy = true,
	cmd = { "MyFeatureRun" },
	keys = {
		{ "<leader>mf", function() require("plugins.fox.my_custom_feature").do_action() end, desc = "Run My Feature" },
	},
	config = M.setup,
}, { __index = M })
```

---

## 📋 Checklist & Best Practices

- [ ] **Tab Indentation:** Use tabs for indentation (per `.editorconfig`).
- [ ] **Configuration First:** Store all user-tunable values in `M.settings` at the top.
- [ ] **No Monolithic Shared Files:** If you write a helper function needed by two features, place it in `lua/fox/<area>/<helper>.lua` rather than duplicating logic.
- [ ] **Unique Marker Directory:** Ensure `dir = require("fox.core.lazyspec").for_module()` is included in the spec return.
- [ ] **Test Coverage:** Add a unit spec in `tests/spec/` or an integration test in `tests/integration/` (see [Testing Guide](testing.md)).
