# 🗂️ Workspaces & Session Manager (`plugins.fox.tools.workspaces`)

[← Back to Wiki Index](index.md)

The **Workspaces Manager** allows saving, loading, restoring, and switching full project session states in Neovim.

---

## ⚡ Highlights

- **Full Session Persistence**: Saves open buffers, tab pages, window splits, and fold states.
- **Terminal Exclusion**: Excludes terminal buffers/windows (`buftype=terminal`) from sessions to prevent stale terminal splits from messing up layout on load.
- **Telescope Selection UI**: `<C-S-w>` opens an interactive Telescope workspace manager with preview, relative timestamps, and slot indexing.
- **Top-Right Floating Indicator Badge**: A discreet, stylish floating badge (` 🦊 1 `, ` 🦊 2 `, etc.) in the top-right corner of the editor visually displays your active workspace/environment slot number at all times (defaults to ` 1 ` when 1 or no workspace is active).
- **Dashboard Return**: `<leader>wm` allows closing the current workspace and returning cleanly to the Main Menu (Alpha Dashboard).

---

## ⌨️ Workspace Shortcuts

- `<C-S-w>`: Open Workspaces UI (Telescope)
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
- `:WorkspaceBadgeToggle`: Toggle visibility of the floating top-right workspace badge.
- `:WorkspaceBadgeUpdate`: Refresh the floating workspace badge.
