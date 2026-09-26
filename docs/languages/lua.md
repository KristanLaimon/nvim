# 🌙 Lua & FoxVim Script Development Suite

[← Back to Wiki Index](../index.md) | [← Back to Languages Overview](../languages.md)

FoxVim provides full editing and transpilation support for **Lua** and local `.foxnvim` scripts (`foxnvimtranspiler`).

---

## 🛠️ Toolchain Summary

| Feature | Tool / Package | Details |
| :--- | :--- | :--- |
| **Language Server (LSP)** | `lua_ls` | Configured with Neovim API globals (`vim`) and `.foxnvim` script globals (`fetch`, `console`, `import`, `cli`, `terminal`, `fs`) |
| **Formatters (Conform)** | `stylua` | Opinionated Lua code formatting |
| **Treesitter Parsers** | `lua` | Full syntax trees for Lua and `.foxnvim` scripts |
| **Autocompletion** | `blink.cmp` + `foxnvim_cmp` | Neovim Lua API completion + `.foxnvim` library completion |
| **Transpiler** | `foxnvimtranspiler` | Transpiles `.foxnvim` scripts to cross-platform Bash (`.sh`) and PowerShell (`.ps1`) |

---

## 🧰 Ex Commands & Command Palette Actions

Accessible via **Command Palette** (`<C-S-p>` / `:CommandPalette`):

* `:FormatDocument` – Format active Lua file using StyLua.
* `:FoxTranspile` – Transpile active `.foxnvim` script.
* `:FoxTranspileSh` – Transpile `.foxnvim` script to Bash (`.sh`).
* `:FoxTranspilePs1` – Transpile `.foxnvim` script to PowerShell (`.ps1`).
* `:FoxTranspileBoth` – Transpile `.foxnvim` script to both `.sh` and `.ps1`.
* `:LanguageManager` – Manage Lua language bundle.
