# ⚙️ VSCode Compatibility & Configuration (`.vscode/`)

**FoxVim** provides first-class support for common `.vscode/` workspace files (`settings.json`, `launch.json`, and `tasks.json`) so your Neovim environment seamlessly inherits your VSCode project configurations without requiring any extra setup.

---

## 🛠️ Supported `.vscode/` Files

### 1. ⚙️ `.vscode/settings.json` (Workspace Options Sync)
Automatically loaded and applied to Neovim options and LSP configurations upon opening buffers or changing directories.

| VSCode Setting | Neovim / LSP Mapping |
| :--- | :--- |
| `editor.tabSize` | `vim.bo.tabstop` & `vim.bo.shiftwidth` |
| `editor.insertSpaces` | `vim.bo.expandtab` |
| `files.eol` (`"\n"`, `"\r\n"`) | `vim.bo.fileformat` (`"unix"` / `"dos"`) |
| `editor.formatOnSave` | `vim.b.autoformat` (Conform / LSP autoformat) |
| `editor.wordWrap` (`"on"`, `"off"`) | `vim.wo.wrap` |
| `editor.rulers` | `vim.wo.colorcolumn` |
| `python.defaultInterpreterPath` | Pyright & Debugpy Python path |
| `php.validate.executablePath` | PHP binary executable path |
| `lua.diagnostics.globals` | `lua_ls` workspace globals |

**Commands**:
- `:VSCodeSettings` / `:FoxVSCodeSettings` — Open menu to edit, view, or re-apply settings.

---

### 2. 🚀 `.vscode/launch.json` (Launch & Debug Profiles)
FoxVim automatically reads `.vscode/launch.json` alongside `.foxnvim/launch.json`.

* **Smart Launch (`<C-S-s>`)** & **Launch Profiles Menu (`<C-S-q>`)**: Any debug or run configuration defined in `.vscode/launch.json` automatically shows up in FoxVim's launch launcher tagged with `⚡ [VSCode]`.
* **DAP Integration (`<F5>`)**: Automatically wired to `nvim-dap` for breakpoints and live debugging.

---

### 3. 🛠️ `.vscode/tasks.json` (Task Runner Discovery)
* **Task Runner Menu (`<C-S-t>`)**: Tasks defined under `.vscode/tasks.json` are automatically discovered alongside `package.json`, `Makefile`, and `.foxnvim/tasks.json`.
* Tasks can be run as background terminal slots with live scrollback (`<C-A-S-1..4>`).
