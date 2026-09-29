# 🗂️ Workspaces & Session Manager (`plugins.fox.tools.workspaces`)

[← Back to Wiki Index](index.md)

The **Workspaces Manager** allows saving, loading, restoring, and switching full project session states in Neovim.

---

## ⚡ Highlights

- **Full Session Persistence**: Saves open buffers, tab pages, window splits, and fold states.
- **Terminal Exclusion**: Excludes terminal buffers/windows (`buftype=terminal`) from sessions to prevent stale terminal splits from messing up layout on load.
- **Telescope Selection UI**: `<C-S-w>` opens an interactive Telescope workspace manager with preview, relative timestamps, and slot indexing.
- **Top-Right Floating Indicator Badge**: A discreet, stylish floating badge (e.g. `/🦊1\/2\`) in the top-right corner of the editor visually displays your active workspace/environment slot numbers at all times.
- **Interactive Badge Focus & Slot Switching**: Press `<C-S-b>` (or `<leader>wb` / `<leader>wf` / `:WorkspaceFocus`) to focus the workspace badge. While focused, switch seamlessly between active slots with `<C-h>` / `<C-l>` (or `h`/`l`/`1..9`), and press `<CR>` or `<Esc>` to return focus to your editor.
- **Dashboard Return**: `<leader>wm` allows closing the current workspace and returning cleanly to the Main Menu (Alpha Dashboard).

---

## ⌨️ Workspace Shortcuts

- `<C-S-w>`: Open Workspaces UI (Telescope)
- `<C-S-b>` / `<leader>wb` / `<leader>wf`: Focus top-right workspace badge section
- `<C-h>` / `<C-l>` / `1..9` (inside badge): Switch between workspace/environment slots
- `<CR>` / `<Esc>` / `q` (inside badge): Return focus to editor window
- `<leader>wm`: Close session and return to Dashboard
- `<leader>ws`: Quick save current workspace
- `<leader>ww`: Open Workspaces UI
- `<leader>w1..9`: Quick load workspace slot #1..9

---

## 💻 Commands

- `:WorkspaceSelect` / `:Workspaces`: Open the Telescope workspace manager.
- `:WorkspaceSave [name]`: Save current layout as a workspace.
- `:WorkspaceNew`: Prompt for name and save as a new workspace.
- `:WorkspaceLoad [name/slot]`: Load saved workspace by name or numeric slot (1..9).
- `:WorkspaceDelete [name]`: Delete saved workspace.
- `:WorkspaceRename [name]`: Rename workspace.
- `:WorkspaceFocus` / `:WorkspaceBadgeFocus`: Focus the workspace badge for `<C-h>`/`<C-l>` slot switching.
- `:WorkspaceBadgeToggle`: Toggle visibility of the floating top-right workspace badge.
- `:WorkspaceBadgeUpdate`: Refresh the floating workspace badge.
