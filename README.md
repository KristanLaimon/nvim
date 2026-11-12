<p align="center">
  <img width="99%" height="auto" alt="image" src="https://github.com/user-attachments/assets/9bd6eeb4-e422-48de-8470-e75599960769" />
  <br></br>
  <a href="https://github.com/KristanLaimon/nvim/stargazers"><img src="https://img.shields.io/github/stars/KristanLaimon/nvim?style=flat-square" alt="GitHub Stars"></a>
</p>

> My personal neovim configuration with IDE features, many QOL and batteries-included for common coding workflows.

---

Language Support:

<p align="center">
  <img width="80%" height="auto" alt="image" src="https://github.com/user-attachments/assets/7b90ca21-dc22-4455-ad09-c131d7c823d0" />
</p>


> 🦊 **Neovim Version:** Tested and compatible with >= **v0.12.4**.

---

## Environment and terminal compatibility

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
nvim -l config/tests/syntax_check.lua                 # every Lua file still parses
nvim -l config/tests/run.lua                          # unit specs (fast, no plugins)
nvim --headless -S config/tests/integration/run.lua   # with the real editor loaded
```

Support assets, scripts, tests, and bundled tools live under `config/`. Plans and notes are in
[`config/plans_notes_md/`](config/plans_notes_md/); see the [directory map](docs/architecture.md) for the full layout.

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
