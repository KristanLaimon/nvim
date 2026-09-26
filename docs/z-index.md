# 📶 Dynamic Z-Index Stack Manager (`fox.core.z_index`)

[← Back to Wiki Index](index.md)

The **Dynamic Z-Index Stack Manager** (`lua/fox/core/z_index.lua`) provides a centralized, in-memory Z-Index registry for floating UI components and modals in FoxVim.

---

## 💡 Why This Exists & Mandatory Rules for New UI Plugins

When multiple floating UI components (such as **Git Center**, **File Explorer / Neo-Tree**, **Task Runner**, **Input Modal**, **Preview Modals**, or custom floating windows) are opened simultaneously or toggled in arbitrary order, static/hardcoded Z-Index values (e.g. `100`, `130`) cause severe visual bugs:
- Modals rendering *behind* the active component that spawned them.
- Opening UI A first, then UI B second, results in UI B being hidden or clipped underneath UI A.
- Returning from popups/modals dropping focus or displaying incorrect window order.

### ⚠️ Mandatory Guideline for Humans & AI Agents
1. **Never hardcode static Z-index numbers** (e.g. `zindex = 100`) when creating new UI plugins, floating windows, or input prompts.
2. **Always register with `fox.core.z_index`** (`require("fox.core.z_index")` or `require("fox.core").z_index`), or use [`ui.float`](../lua/fox/core/ui.lua) with `opts.name` / `opts.parent`.
3. **In-Memory Only**: Z-index tracking is strictly in-memory per Neovim session. `WinClosed` autocmds clean up stack entries automatically when floating windows close.

---

## 🏗️ Stack Layer Architecture

The Z-Index manager operates as a dynamic top-level stack:

- **Top-Level Stack Layers**: Each newly opened top-level UI component (e.g. `file_explorer`, `git_center`, `tasks`) gets assigned the next available stack layer:
  - **Layer 1** (First UI opened): Base Z-Index = `50`
  - **Layer 2** (Second UI opened): Base Z-Index = `100`
  - **Layer 3** (Third UI opened): Base Z-Index = `150`
  - *Result*: Opening UI A then UI B puts UI B on top (`100 > 50`). Opening UI B then UI A puts UI A on top (`100 > 50`).

- **Parent & Child Relativity**: Child popups and sub-modals (e.g. Git Log modal or Diff modal inside Git Center) register with a `parent` component name and relative `offset`:
  - `child_zindex = parent_base_zindex + offset`
  - Sub-modals are guaranteed to render on top of their parent component regardless of what stack layer the parent occupies.

- **Input Modals & Prompts**: Input prompts and dialogs register at the top layer (or relative to their parent UI with high offset, e.g. `+50`), ensuring prompt inputs are never hidden.

---

## 🛠️ Usage Examples & Code Patterns

### 1. High-Level Helper using `ui.float` (Recommended)

When creating scratch buffers or standard floating popups using `ui.float`, pass `name` or `parent`. `ui.float` automatically pulls from `fox.core.z_index` and registers the window:

```lua
local ui = require("fox.core.ui")

-- Top-level UI component automatically gets the top Z-index layer
local buf, win = ui.float({
    name = "my_custom_ui",
    title = " My Plugin ",
    width = 0.6,
    height = 0.6,
})
```

### 2. Manual Window Creation (`nvim_open_win`)

If creating custom windows directly via `vim.api.nvim_open_win`:

```lua
local z_index = require("fox.core.z_index")

-- 1. Allocate next dynamic z-index for the component
local base_z = z_index.next_zindex("my_plugin")

-- 2. Pass zindex to nvim_open_win
local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 60,
    height = 20,
    style = "minimal",
    border = "rounded",
    zindex = base_z,
})

-- 3. Register the window handle with the manager (attaches automatic WinClosed cleanup)
z_index.register("my_plugin", win, { zindex = base_z })
```

### 3. Creating Child / Sub-Modals

When opening a sub-modal or detail popup from an existing parent UI:

```lua
local z_index = require("fox.core.z_index")

-- Calculates parent's active base z-index + 30
local child_z = z_index.next_zindex("my_plugin_detail_modal", { parent = "my_plugin", offset = 30 })

local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = 80,
    height = 25,
    style = "minimal",
    border = "rounded",
    zindex = child_z,
})

z_index.register("my_plugin_detail_modal", win, { parent = "my_plugin", offset = 30, zindex = child_z })
```

### 4. Re-ordering / Promoting to Top (`bring_to_front`)

If a user focuses or toggles an already open component (e.g., clicking back into Git Center while File Explorer is open):

```lua
local z_index = require("fox.core.z_index")

-- Promotes component to top of stack and updates all its windows to higher z-index
z_index.bring_to_front("git_center")
```

---

## 🔍 Module API Reference

```lua
local z_index = require("fox.core.z_index")

-- Get/calculate next z-index for name
z_index.next_zindex(name, opts)

-- Register window(s) for a component (handles WinClosed cleanup)
z_index.register(name, wins, opts)

-- Unregister a component or specific window
z_index.unregister(name)
z_index.unregister_window(win)

-- Promote component to top of stack
z_index.bring_to_front(name)

-- Get current active z-index for name
z_index.get_zindex(name, offset)

-- Get list of active top-level stack components (bottom to top)
z_index.active_stack()

-- Reset all tracking (testing/cleanup)
z_index.clear()
```

---

## 🔗 Require Aliases

All of the following require paths resolve to the exact same module:
- `require("fox.core.z_index")`
- `require("fox.core.zindex")`
- `require("fox.core.z-index")`
- `require("fox.core").z_index` / `require("fox.core").zindex`
