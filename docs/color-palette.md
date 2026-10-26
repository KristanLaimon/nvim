# Color Palette & Theme Configuration Guide

[← Back to Wiki Index](index.md)

Theme startup uses the local `fox_theme_startup` spec in `lua/plugins/ui/themes.lua`.
All palettes offered by `:FoxThemePicker` live in `config/colors/`; no external Doki plugin
is required. Additional scheme names exclusive to the upstream Doki catalog are
not bundled. Existing local palette attributions are preserved.

This guide explains how to manage, customize, and extend colorschemes in this Neovim configuration.

---

## 📁 Key Files & Directories

- **Nagatoro Theme System & Picker:** [`lua/plugins/fox/ui/theme_picker.lua`](../lua/plugins/fox/ui/theme_picker.lua)
- **Statusline Theme Picker:** [`lua/plugins/fox/ui/statusline_picker.lua`](../lua/plugins/fox/ui/statusline_picker.lua)
- **Colorify Engine (CMP Completion):** [`lua/fox/lsp/colorify.lua`](../lua/fox/lsp/colorify.lua)
- **Theme Palette Files:** `config/colors/nagatoro-fox.lua`, `config/colors/nagatoro-light.lua`, `config/colors/onedark-fox.lua`, `config/colors/catppuccin-fox.lua`, `config/colors/nord-fox.lua`
- **Customization Guide:** [`how-to-customize-editor.md`](how-to-customize-editor.md)

---

## 🎨 Nagatoro Theme System (`:FoxThemePicker`)

FoxVim ships with a set of complete, hand-crafted themes matching the `nagatoro-fox` palette schema. Run `:FoxThemePicker` or choose **Select UI-Theme** in the Command Palette. After selecting a theme, choose **Global theme** or **This project only**.

Global themes are saved in the Neovim config directory under `.foxnvim/theme.json`. Project overrides are read exclusively from `<project>/.foxnvim/theme.json` (`{"theme":"nord-fox"}`). They load on startup and when switching projects; projects without an override use the global default. Choosing a global theme updates the default; existing project overrides remain saved. Delete the project file to return permanently to the global default.

- **Available Themes:**
  - `nagatoro-fox` (Hayase Nagatoro Dark — Default)
  - `nagatoro-light` (Hayase Nagatoro Light)
  - `onedark-fox` (NvChad OneDark in nagatoro format)
  - `catppuccin-fox` (NvChad Catppuccin Mocha in nagatoro format)
  - `nord-fox` (NvChad Nord in nagatoro format)
  - `omarchy-fox` (Dynamic theme synced with Omarchy Linux)
- **Live Preview & Store Persistence:** Previews themes in real time while tabbed/selected. Cancelling (`<Esc>`) restores the previous theme; confirming (`<Enter>`) asks where to save the choice via [`fox.core.store`](architecture.md#layer-2--shared-libraries-luafox).

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

The statusline is rendered locally by `fox.ui.statusline`, with no lualine dependency.
The six layouts keep their saved choice in `.foxnvim/statusline.json`. Git branch and
diff queries run asynchronously; GitSigns counters include unsaved edits when available.
Diagnostics, attached LSP names, terminal/task titles and environment indicators update
from editor events. Colors follow the active colorscheme and mode.

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

To add a custom theme, create a new file `config/colors/mytheme-fox.lua` adhering to the `nagatoro-fox.lua` palette format. See [`how-to-customize-editor.md#5-how-to-customize-statusline--themes`](how-to-customize-editor.md#5-how-to-customize-statusline--themes) for full step-by-step instructions and code examples.

### Ryoku (Arch Linux)

On Ryoku, the dashboard shows `FOX Neovim (Ryoku - Arch Linux)`.
Choose **Toggle Ryoku Theme Auto Sync** in `:CommandPalette`, or run
`:FoxRyokuSyncToggle`, to enable or disable persistent desktop theme sync.
`:FoxRyokuSyncNow` applies the current palette once; `:FoxRyokuSyncStatus`
shows whether automatic sync is enabled. Sync follows wallpaper and theme
changes by checking `~/.cache/ryoku/colors.json` every second and on editor focus,
reading the palette only when the file changes, including atomic replacements.
Both Material palettes and terminal-only `color0`–`color15` palettes are supported.
No Ryoku configuration is modified. Turning sync off restores
the previous editor theme; selecting an editor theme disables desktop sync.

Kitty sessions are supported through Neovim's terminal UI. FoxVim's managed
terminals start `$SHELL -il` on Unix, loading the same Fish/Zsh/Bash login and
interactive setup used by the desktop (including the Ryoku prompt and greeting).
Tool commands continue using the configured command shell. Existing terminal
slots need to be closed and reopened to pick up the new initialization.
