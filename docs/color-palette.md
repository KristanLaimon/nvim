# Color Palette & Theme Configuration Guide

[← Back to Wiki Index](index.md)

This guide explains how to manage, customize, and extend colorschemes in this Neovim configuration.

---

## 📁 Key Files & Directories

- **Nagatoro Theme System & Picker:** [`lua/plugins/fox/theme_picker.lua`](../lua/plugins/fox/theme_picker.lua)
- **Statusline Theme Picker:** [`lua/plugins/fox/statusline_picker.lua`](../lua/plugins/fox/statusline_picker.lua)
- **Colorify Engine (CMP Completion):** [`lua/fox/lsp/colorify.lua`](../lua/fox/lsp/colorify.lua)
- **Theme Palette Files:** `colors/nagatoro-fox.lua`, `colors/nagatoro-light.lua`, `colors/onedark-fox.lua`, `colors/catppuccin-fox.lua`, `colors/nord-fox.lua`
- **Customization Guide:** [`how-to-customize-editor.md`](how-to-customize-editor.md)

---

## 🎨 Nagatoro Theme System (`:FoxThemePicker`)

FoxVim ships with a set of complete, hand-crafted themes matching the `nagatoro-fox` palette schema. Run `:FoxThemePicker` to open the interactive theme picker:

- **Available Themes:**
  - `nagatoro-fox` (Hayase Nagatoro Dark — Default)
  - `nagatoro-light` (Hayase Nagatoro Light)
  - `onedark-fox` (NvChad OneDark in nagatoro format)
  - `catppuccin-fox` (NvChad Catppuccin Mocha in nagatoro format)
  - `nord-fox` (NvChad Nord in nagatoro format)
  - `omarchy-fox` (Dynamic theme synced with Omarchy Linux)
- **Live Preview & Store Persistence:** Previews themes in real time while tabbed/selected. Cancelling (`<Esc>`) restores the previous theme; confirming (`<Enter>`) saves choice to `.foxnvim/theme.json` via [`fox.core.store`](architecture.md#layer-2--shared-libraries-luafox).

---

## 🦊 Omarchy Dynamic Theme Sync (`:FoxOmarchySyncToggle`)

When running under [Omarchy Linux](https://omarchy.org/) (Hyprland), FoxVim can dynamically adapt all editor highlights, syntax tokens, and UI colors to match the active system theme:

- **Command Palette Toggle:** Open `<C-S-p>` and choose `🎨 Toggle Omarchy Theme Sync (Adapt colors to Omarchy - Default: OFF)`.
- **Default State:** Disabled (`false`) by default, preserving your explicit local theme choice until explicitly turned on.
- **Commands:**
  - `:FoxOmarchySyncToggle` — Toggle live Omarchy synchronization on/off.
  - `:FoxOmarchySyncNow` — Force an immediate re-sync with Omarchy's current active theme.
  - `:FoxOmarchySyncStatus` — Inspect current sync status and detected Omarchy theme.
- **Live Adaptation:** When enabled, a libuv filesystem event watcher (`vim.uv.new_fs_event`) monitors `~/.local/state/omarchy/current/theme/colors.toml` and `theme.name`. When `omarchy theme set <theme>` is executed in your terminal or desktop shell, Neovim automatically recompiles and applies the matching color palette on the fly with no restart required. Supports all 20+ Omarchy stock themes and custom themes in dark and light modes.

---

## 📊 NvChad Statusline & Statusline Theme Picker

Run `:FoxStatuslineTheme` (or select from Command Palette `<C-Shift-P>`) to switch statusline layouts:
- `nvchad_pills` (Rounded pill blocks with mode icons ` NORMAL`, Git diff icons, LSP server info ` lua_ls`, and diagnostics)
- `nvchad_blocks` (Slanted powerline block separators `` ``)
- `nvchad_round` (Curved slant separators `` ``)
- `nagatoro_classic` (Minimal classic layout)
- `vscode` (Flat VSCode style)
- `minimal` (Compact)

---

## 🎨 NvChad Completion Kind Icons & Colorify (`lua/fox/lsp/colorify.lua`)

Completion items in `blink.cmp` use NvChad layout:
- **Left**: Kind icon pill (` 󰊕 `, ` 󰩫 `, ` 󰀫 `, ` 󰌋 `, ` 󰌗 `) rendered with dedicated background and accent colors (`CmpKindBg_*`) from the active theme.
- **Color Items**: CSS & Tailwind hex/RGB colors render a preview rectangle badge (` ██ `) using the exact hex color as background with luminance-aware contrast text.
- **Right**: Kind label (`<Snippet>`, `<Function>`, `<Variable>`, etc.).

---

## 📦 How to Add a New Theme

To add a custom theme, create a new file `colors/mytheme-fox.lua` adhering to the `nagatoro-fox.lua` palette format. See [`how-to-customize-editor.md#5-how-to-customize-statusline--themes`](how-to-customize-editor.md#5-how-to-customize-statusline--themes) for full step-by-step instructions and code examples.
