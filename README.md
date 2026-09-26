<p align="center">
  <img width="300" height="300" alt="foxnvim-logo" src="https://github.com/user-attachments/assets/fdd81f9b-85ff-49ff-a2c3-7918fed9ab32" />

  <br>
  <strong>Foxnvim</strong>
  <br>
  <span style="display:block;font-size:1.25rem;">An opinionated neovim distribution for fox coders with IDE features included for FullStack development in many languages.</span>
  <br><br>
  <a href="https://github.com/KristanLaimon/nvim/stargazers"><img src="https://img.shields.io/github/stars/KristanLaimon/nvim?style=flat-square" alt="GitHub Stars"></a>
</p>

<img width="1703" height="807" alt="image" src="https://github.com/user-attachments/assets/aeefe6e7-1d6c-4af5-997d-dd3adc0e025f" />


# Features

- Custom config & compatibility with `Neovide`
<img width="1703" height="874" alt="image" src="https://github.com/user-attachments/assets/d31db9d2-ea1a-4d46-b17a-6c3f0d2a78b0" />

- Project environments with isolated buffers, layouts, LSPs, and terminal pools.
- Nine persistent integrated terminals, task output slots, dev-server control, and launch profiles.
- LSP, formatting, completion, Tree-sitter, DAP, language bundles, and a minimal fresh-install toolchain.
- File and project navigation, Git Center, conflict resolution, secondary Git accounts, and diff tools.
- Command Palette, dashboard, interactive wiki, offline documentation, snippets, templates, and VS Code settings support.
- Persistent breakpoints, workspace sessions, TODO sidebar, Tailwind organization, type injection, image previews, and Omarchy palette sync.

Open the Command Palette with `<C-S-p>` or `:CommandPalette` to discover actions. The [documentation index](docs/index.md) links to the full feature guides.

## Environment and terminal compatibility

> 🦊 **Neovim Version:** Currently running on **NVIM v0.12.4** (requires Neovim >= 0.10).
> 
| Environment | FoxVim support |
|---|---|
| **Windows** | Native PowerShell or Git Bash setup, Windows paths, and Windows Terminal keybinding setup. |
| **WSL** | Discovers installed distros; browses `\\wsl.localhost` / `\\wsl$` projects; opens integrated terminals in the matching distro and directory. |
| **Ubuntu / Debian Linux** | `apt` setup path, native Linux tooling, and ordinary terminal workflow. |
| **Arch Linux** | `pacman` setup path. |
| **Arch + Omarchy** | Detects Omarchy and can synchronize the active Omarchy color palette with FoxVim using `:FoxOmarchySyncToggle`. |
| **Termux → Ubuntu PRoot** | Detects the layered Android environment, applies mobile performance settings, and retains terminal-safe key aliases. Native Termux is supported too. |
| **macOS, Fedora, Alpine** | `brew`, `dnf`, and `apk` setup paths are included. |

The shell-keybinding setup supports **Windows Terminal, Kitty, Foot, WezTerm, Alacritty, Ghostty, and Termux**. Inside Neovim, each environment has nine independent terminals; a WSL filesystem path automatically selects a WSL shell. See [installation](docs/installation.md), [terminals](docs/terminals.md), and [environments](docs/environments.md).

## Plugin inventory

FoxVim has **48 hand-crafted local plugins** in [`lua/plugins/fox/`](lua/plugins/fox/) and **48 pinned external plugins** in [`lazy-lock.json`](lazy-lock.json). Local modules are part of this repository; lazy.nvim installs and manages the external packages on first launch.

### Hand-crafted FoxVim plugins

| Area | Modules |
|---|---|
| Developer workflow | Bun DAP, DAP Breakpoints, Dev Server, FoxNvim Completion, Launch Completion, Launch Profiles, Sneak Peek, Tasks, Terminal |
| Editing | Buffer Cleaner, Caps Lock, Folding, Hover Links, Line Endings, Neo-tree Hidden Files, Neo-tree Mover, Smart Check, Tailwind Organizer |
| Git | Conflict Resolver, Diff Mode, Git Accounts, Git Center, Secondary Git |
| Tools | Command Palette, .NET Creator, Environments, File Explorer, Installer, LSP References, Notes, NuGet Manager, PHP Tools, TODO Sidebar, Type Injector, Lua Type Injector, TypeScript Type Injector, Usages Picker, Workspaces, WSL Bridge |
| UI | Colorscheme Preview, Font, Help Modal, Input Modal, Omarchy Theme Sync, Pinned Tabs, Statusline Picker, Theme Picker, Wiki Modal |

### External plugins

| Area | Packages pinned in `lazy-lock.json` |
|---|---|
| UI and themes | `alpha-nvim`, `bufferline.nvim`, `doki-theme-vim`, `lualine.nvim`, `mini.icons`, `nvim-highlight-colors`, `nvim-notify`, `nvim-web-devicons`, `render-markdown.nvim` |
| Navigation and Git | `diffview.nvim`, `git-blame.nvim`, `gitsigns.nvim`, `neo-tree.nvim`, `neogit`, `nui.nvim`, `nvim-file-operations`, `nvim-lsp-file-operations`, `nvim-window-picker`, `package-info.nvim`, `plenary.nvim`, `project.nvim`, `snacks.nvim`, `telescope-file-browser.nvim`, `telescope.nvim` |
| LSP and editing | `blink.cmp`, `conform.nvim`, `friendly-snippets`, `mason-conform.nvim`, `mason-lspconfig.nvim`, `mason-nvim-dap.nvim`, `mason.nvim`, `nvim-lspconfig`, `nvim-treesitter`, `nvim-ts-autotag`, `schemastore.nvim`, `symbol-usage.nvim` |
| Debugging | `baleia.nvim`, `nvim-dap`, `nvim-dap-go`, `nvim-dap-ui`, `nvim-dap-virtual-text`, `nvim-nio` |
| Language and extras | `blade-nav.nvim`, `cord.nvim`, `lazy.nvim`, `markdown-preview.nvim`, `nvim-autopairs`, `vim-blade` |

For loading mode, dependencies, and source locations, see [PLUGINS-LIST.md](PLUGINS-LIST.md).

---

## 🖥️ Dashboard shortcuts

The start screen. One letter per entry:

| Key | Opens |
|---|---|
| `f` | File Explorer (Desktop) |
| `p` | Recent projects |
| `l` | File Explorer (WSL) — Windows only, shown when WSL is installed |
| `w` | Wiki / documentation (`:NvimWiki`) |
| `e` | Plugins & extensions (`:Lazy`) |
| `m` | LSPs & languages (`:Mason`) |
| `q` | Quit |

Return to the dashboard from anywhere with `<leader>wm`; closing the last open buffer also lands here.

---

## ⚡ Quick Setup

After cloning into `%LOCALAPPDATA%\nvim` (Windows) or `~/.config/nvim` (Linux, WSL, Termux, or macOS):

- **Windows (PowerShell)**: `powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1`
- **Linux / WSL / Termux / Git Bash**: `./scripts/setup.sh`

These idempotent scripts automatically install missing external dependencies (`ripgrep`, `fd`, `gcc`, `chafa`, Node.js, Bun, Go, .NET SDK). If you don't run them right away, FoxVim will still run with [graceful fallbacks](docs/installation.md#⚡-what-if-you-havent-run-setupps1-or-setupsh).

---

## 📚 Documentation & Help

Everything else — install, keybinds, debugging, launch profiles, custom modules — lives in the wiki:

- **Documentation Center Modal**: Press `<C-S-d>` (or run `:FoxWiki` / `:NvimWiki`) from anywhere to open the interactive Wiki Reader.
- **➡️ [docs/index.md](docs/index.md)** (Full Wiki Index)
- **➡️ [docs/how-to-customize-editor.md](docs/how-to-customize-editor.md)** (Complete How-To & Customization Guide with Examples)

Start here if you are reading the code:

| Page | What it answers |
|---|---|
| 🎓 [How-To & Customization Guide](docs/how-to-customize-editor.md) | Step-by-step guide for adding plugins, local modules, languages, themes, and terminals |
| 🏛️ [Architecture](docs/architecture.md) | The layers, what may depend on what, startup order, where new code goes |
| 🧩 [Module Architecture](docs/module-architecture.md) | How a file in `lua/plugins/fox/` is both a module and a lazy.nvim spec |
| 🔌 [Creating Local Plugins](docs/how-to-create-local-plugin.md) | Building custom features in `lua/plugins/fox/` using the dual spec-module metatable |
| 🧪 [Testing](docs/testing.md) | Running the suite and writing a spec |

---

## 🧪 Tests

```sh
nvim -l tests/syntax_check.lua                 # every Lua file still parses
nvim -l tests/run.lua                          # unit specs (fast, no plugins)
nvim --headless -S tests/integration/run.lua   # with the real editor loaded
```

Inside the editor: `:FoxTest` (optionally `:FoxTest git` to filter by spec name).

---

## 🦊 Master CLI Runner (`run_me.lua`)

You can run project scripts (test suite, syntax checks, setup dependencies, etc.) using the master Lua CLI:

```sh
# Launch interactive CLI menu
nvim --headless -l run_me.lua

# Run options directly via flags
nvim --headless -l run_me.lua -- --syntax
nvim --headless -l run_me.lua -- --tests
nvim --headless -l run_me.lua -- --setup
nvim --headless -l run_me.lua -- --help
```
