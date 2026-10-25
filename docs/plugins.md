# 📦 Plugin Inventory

[← Back to Wiki Index](index.md)

Everything installed, split between the custom modules written for this config and the third-party plugins they sit on top of.

See [Module Architecture](module-architecture.md) for how the custom ones are wired.

---

## 🦊 Custom modules (`lua/plugins/fox/`)

| Module | File | What it does | Keys / commands |
|---|---|---|---|
| **FoxQuerier** | `config/tools/query.lua` | Read-only SQL workspace, Standard/Visual layouts, cached completion, FK maps, notes, and local workspace persistence. | `<C-A-o>`, `:FoxMode`, `:FoxQueryView`, `:FoxQueryConnections` |
| **Workspaces Manager** | `workspaces.lua` | Harpoon + Telescope hybrid session manager. Saves buffers, tab layout and `cwd` per project into numbered slots; rename, overwrite, delete from a floating UI. | `<C-S-w>`, `<leader>ws`, `<leader>ww`, `<leader>wm`, `<leader>w1`..`9` |
| **Command Palette** | `command_palette.lua` | VSCode-style fuzzy command list — Vim commands, simulated keypresses or Lua functions from one picker. Other modules register into it at runtime. | `<C-S-p>`, `:CommandPalette` |
| **Git Control Center** | `git_center.lua` | Floating Git UI: stage/unstage, live diff, commit form (title/description/tag), restore, push. | `<C-S-g>`, `:GitCenter` |
| **Launch Profiles** | `launch_profiles.lua` | Per-project entry points with runtime, args, env, pre-launch tasks and a run/debug mode. Card picker + single-screen form editor. | `<C-S-s>`, `<C-S-q>` |
| **Dev Server Bridge** | `dev_server.lua` | Starts (or reuses) the project's Vite/Astro/SvelteKit/Next/Angular dev server and yields its URL to browser debug configs. | used by debug configs |
| **Persistent Breakpoints** | `dap_breakpoints.lua` | Saves/restores breakpoints per project, adds disabled breakpoints (a concept nvim-dap doesn't have). | `<A-b>`, `<A-h>`, `:DapBreakpoints*` |
| **Bun Debug Adapter** | `bun_dap.lua` | Sparse-checks-out Bun's own debug adapter and writes the stdio entry point the VSCode extension never shipped. | `:FoxBunDapInstall` |
| **Task & Script Manager** | `tasks.lua` | Per-project tasks in `.foxnvim/tasks.json`; run, chain, set a default detected from `Makefile`/`package.json`/etc. Up to 4 background slots. | `<C-S-t>`, `<C-S-a>`, `<C-1>`..`<C-4>` |
| **Multi-Terminal Manager** | `terminal.lua` | 9 lazily-spawned terminals, toggled independently. A `cwd` inside a WSL distro path launches `wsl.exe` there instead of the Windows shell. | `<A-1>`..`<A-9>`, `<C-;>` |
| **Desktop File Explorer** | `file_explorer.lua` | Pure-Lua floating file browser rooted at `~/Desktop`. Create/rename/delete, drill in/out, set folder as active project. | `<C-S-f>`, `:TelescopeFileBrowserDesktop` |
| **Neo-tree Custom Hidden** | `neotree_hidden.lua` | Visually hides files and folders in Neo-tree UI, highlights hidden items with active theme colors, persists hidden paths. | `H`, `gh` (in Neo-tree), `:NeotreeToggleCustomHiddenVisibility` |
| **WSL File Explorer** | `file_explorer.lua` | Same explorer rooted at `\\wsl.localhost\<Distro>\`; lists distros when more than one is installed. Windows-only. | `<leader>fw`, `:TelescopeFileBrowserWSL` |
| **Type Injector** | `type_injector.lua` | Per-project Lua/TS type schemas + `@types` package installer, applied live to `lua_ls` and `tsc`. | `:FoxTypes`, `:TypeInjector` |
| **Tailwind Organizer** | `tailwind_organizer.lua` | Sorts and multi-rows `class` / `className` attributes on save. | `<leader>tw`, `<leader>tt`, `:TailwindOrganize` |
| **Nuget Package Manager** | `nuget.lua` | CRUD for `<PackageReference>` in a `.csproj` via `dotnet add/remove package`, in a Telescope picker. | `<leader>ng`, `:NugetManager` |
| **Buffer Cleaner & Smart Quit** | `buffer_cleaner.lua` | Makes `:q` context-aware (close split → close tab → back to dashboard → quit) and sweeps empty `[No Name]` buffers. | `:q`, `:q!` |
| **Context Help** | `context_help.lua` | Context-aware cheatsheet — different content in Neo-tree, Git, Telescope, editor. | `?`, `<F1>` |
| **Documentation Wiki** | `wiki_modal.lua` | This dual-pane wiki modal — categorized index on the left, live markdown preview with link-following on the right, native `/`/`<C-f>` search in either pane. | `<C-S-d>`, `<leader>?`, `:FoxWiki` |
| **Live Colorscheme Preview** | `colorscheme_preview.lua` | Previews themes live while tabbing through `:colorscheme`, reverts on cancel. | `:colorscheme <Tab>` |
| **Pixel-Art Image Viewer** | `image_viewer.lua` | Renders images as terminal pixel art via `chafa`, or hands off to the OS default app. | `<leader>i`, `<C-S-Enter>` |
| **Input Modal** | `input_modal.lua` | The shared floating input dialog; overrides `vim.ui.input` globally. | used everywhere |
| **Font Manager** | `font.lua` | Live GUI font sizing, persisted to `font_config.json` in `nvim-data`. | `<C-+>`, `<C-->`, `<C-0>` |
| **Line Endings Manager** | `line_endings.lua` | Detects/preserves LF and CRLF line endings. UI selection modal for current file and repo-wide line ending conversion. | `:ChangeLineEndings`, `:ChangeRepoLineEndings` |
| **PHP Tools Modal** | `php_tools_modal.lua` | Checks PHP, Composer, Intelephense, Pint and the debug adapter on host *and* WSL, with install steps. | `:PHPCheckTools` |

| **WSL Helpers** | `wsl.lua` | Distro detection and path translation; also decides whether the dashboard shows the WSL button. | internal |
| **launch.json IntelliSense** | `launch_cmp.lua` | blink.cmp source for `launch.json` — tasks, runtimes, modes. | automatic |

Plus the shared libraries outside the spec tree, in `lua/fox/`:

| Library | What it does |
|---|---|
| `fox.core.path` | Cross-platform path normalize / join / compare |
| `fox.core.store` | JSON load & save that never throws |
| `fox.core.project` | Project root and `.foxnvim/` config resolution |
| `fox.core.ui` | Floating window and scratch buffer factory |
| `fox.core.z_index` | Centralized dynamic Z-index stack manager for floating UI popups & inputs — see [Z-Index Manager](z-index.md) |
| `fox.core.dock` | The bottom dock shared by terminals and task outputs |
| `fox.core.lazyspec` | Unique lazy.nvim `dir` per local spec — see [Module Architecture](module-architecture.md#-lazydir--why-every-spec-needs-its-own-directory) |
| `fox.git.cmd` / `status` / `diff` | Running git, parsing status, formatting diffs |
| `fox.launch.runtimes` | How each language is run and debugged |
| `fox.lsp.code_action_menu` | The `<C-.>` dropdown at the caret |
| `fox.lsp.editorconfig` | `.editorconfig` knowledge base and completion source |
| `fox.lsp.dap_repl_source` | blink.cmp source that completes from the debug adapter's stopped frame |
| `fox.projects.favorites` | Starred paths, shared by the explorer and the project picker |

And the per-language debugger modules in `lua/plugins/fox/debuggers/`: `_shared.lua`, `bun.lua`, `node.lua`, `browsers.lua`, `python.lua`, `csharp.lua`, `php.lua`, `go.lua` — documented in [Debug Adapters](debug-adapters.md).

---

## 🔌 Third-party plugins

### Core & LSP
| Plugin | Purpose |
|---|---|
| `neovim/nvim-lspconfig` | LSP server configuration |
| `williamboman/mason.nvim` | Package manager for LSPs, formatters, linters, debug adapters |
| `fox.lsp.tooling` | Explicit Mason actions using local language metadata |
| FoxVim LanguageManager (local) | Installs selected language formatters; Mason exposes executables to Conform through PATH |
| FoxVim language modules (local) | Register adapters; LanguageManager installs selected tools |
| `saghen/blink.cmp` | Completion engine |
| `rafamadriz/friendly-snippets` | Snippet collection |
| `stevearc/conform.nvim` | Async formatting |
| `nvim-treesitter/nvim-treesitter` (`main`) | Highlighting and AST parsing |
| `b0o/schemastore.nvim` | JSON/YAML schemas for common config files |

### Debugging
| Plugin | Purpose |
|---|---|
| `mfussenegger/nvim-dap` | Debug Adapter Protocol client |
| `rcarriga/nvim-dap-ui` | Scopes / stacks / breakpoints / watches / repl / console panels |
| `nvim-neotest/nvim-nio` | Async library required by dap-ui |
| `fox.dap.virtual_text` (local) | Inline variable values while stopped; no external plugin |
| `fox.langs.go` (local) | Delve adapter and seven Go configurations; no external setup plugin |
| `m00qek/baleia.nvim` | Turns ANSI escapes in adapter output back into highlights |

### Editor & navigation
| Plugin | Purpose |
|---|---|
| `ThePrimeagen/harpoon` (v2) | File bookmarking behind the Workspaces manager |
| `nvim-telescope/telescope.nvim` | Fuzzy finder and picker framework |
| `nvim-tree/neo-tree.nvim` | Sidebar file explorer |
| `NeogitOrg/neogit` | Secondary Git UI |
| `sindrets/diffview.nvim` | Diff/history viewer for Neogit |
| `fox_recent_projects` / `fox.projects.history` (local) | Recent projects UI and persistent history; no external project plugin |
| `voldikss/package-info.nvim` | Inline `package.json` dependency management |
| `nvim-lua/plenary.nvim` | Lua utility library |

### Interface & theme
| Plugin | Purpose |
|---|---|
| `fox_dashboard` (local) | Start dashboard |
| `fox_theme_startup` (local) | Restore FOX palettes from config/colors/ at startup, including Ryoku/Omarchy sync |
| `akinsho/bufferline.nvim` | Buffer tab bar |
| `nvim-lualine/lualine.nvim` | Statusline |
| `fox_color_highlights` | Inline CSS colour previews (`:HighlightColors`) |
| `fox.core.window_picker` (local) | Visual window selector for Neo-tree; no external plugin |
| `nvim-file-operations` | Keeps buffers in sync with disk renames/moves |

- `mini.icons`: sustituido por `fox_icons`. Catálogo propio en fox.ui.icons, resolución de sufijos compuestos, filetypes y rutas Windows; conserva overrides por lenguaje, colores al cambiar tema y compatibilidad mini.icons/devicons. Ocho pruebas unitarias y dos integraciones NestJS aprobadas; sin copiar datos upstream.

- `nvim-highlight-colors`: sustituido por `fox_color_highlights`. Previews nativos con extmarks, CSS hex/rgb/hsl, nombres y variables; Tailwind opt-in reutiliza colorify. Debounce y render limitado a ventanas visibles y líneas acotadas. Conserva HighlightColors y añade acción de paleta. Tres pruebas con buffers reales cubren Unicode, edición, formatos y variables; sin dependencias externas.

- `mason-lspconfig.nvim`: sustituido por `fox_lsp_tooling`. Mapeo desde metadatos de lenguajes y genéricos existentes, sin instalaciones automáticas. Conserva LspInstall con selección cancelable, versiones y LspUninstall; activación mediante vim.lsp.config/enable. 17 pruebas de tooling/installer aprobadas e integración real LuaLS adjunto sin mason-lspconfig.

- `nvim-file-operations`: sustituido por `fox_file_buffers`. Sincronización nativa integrada en Neo-tree: renombrado conserva buffer/undo; borrado conserva ediciones en fox-recovered:// para guardar con saveas. No auto-guarda ni intercepta globalmente workspace edits. Seis pruebas unitarias y una integración real de eventos y archivo movido aprobadas. El plugin anterior no tenía consumidores de sus APIs públicas.

- `nvim-lsp-file-operations`: sustituido por `fox_lsp_file_operations`. Bridge nativo para will/did Rename/Create/Delete, filtros por workspace/scheme/glob/tipo, timeout total de 1.5s y workspace edits con encoding del cliente. Rechaza versiones obsoletas, cambios concurrentes y operaciones de recursos recursivas; nunca guarda ediciones automáticamente. Cuatro pruebas unitarias y una integración stdio con servidor fixture verifican edición y notificación reales; sin servidor opcional instalado.

- `vim-blade`: sustituido por `fox_blade`. Sintaxis e indentación propias en fox.langs.php.blade y puentes syntax/indent; reutiliza sintaxis PHP/HTML de Neovim, conserva comentarios, ecos, verbatim y pares personalizados script/assets. Detección Blade propiedad del módulo PHP; Treesitter respeta el indentexpr local. Cinco pruebas unitarias y una integración real gg=G aprobadas. Sin copiar código upstream.

- `blade-nav.nvim`: sustituido por `fox_laravel`. Índice propio por proyecto Artisan para vistas/componentes/Livewire/rutas/config/env/traducciones/Inertia, gf y fuente Blink cancelable. Caché con TTL, invalidación al guardar y rechazo de procesos antiguos; consultas Artisan asíncronas para rutas y aliases. Conserva los tres comandos de paleta y helper local de instalación exclusiva. Nueve pruebas unitarias y una integración real de navegación/completado aprobadas. PHP y parser PHP no disponibles: no se ejecutó el helper contra Laravel real.
