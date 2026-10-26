# Plugin List

Inventario de las specs importadas por `lua/lazy_init.lua`, sus dependencias transitivas y el propio gestor. Cada plugin aparece una sola vez; no incluye carpetas residuales de instalaciones anteriores.

Core = carga explícita al iniciar (`lazy = false`), más el gestor de plugins.
Non-core = carga por evento, comando, tecla, filetype, dependencia o `require`. `VimEnter` y `VeryLazy` siguen siendo eventos: no equivalen a `lazy = false`. El valor global es `defaults.lazy = true`.

Total actual: **23 externos** y **73 specs locales activas**. El plan de sustitución está en [DEPENDENCYFOX.plan.md](DEPENDENCYFOX.plan.md).

## (External)

### Core

- `folke/lazy.nvim` — [`lua/lazy_init.lua`](../../lua/lazy_init.lua)

### Non-core

**Editor**

- `folke/snacks.nvim` — [`editor/neo-tree.lua`](../../lua/plugins/editor/neo-tree.lua)
- `iamcco/markdown-preview.nvim` — [`editor/markdown.lua`](../../lua/plugins/editor/markdown.lua)
- `lewis6991/gitsigns.nvim` — [`editor/gitsigns.lua`](../../lua/plugins/editor/gitsigns.lua)
- `m00qek/baleia.nvim` — [`editor/dap.lua`](../../lua/plugins/editor/dap.lua)
- `MeanderingProgrammer/render-markdown.nvim` — [`editor/markdown.lua`](../../lua/plugins/editor/markdown.lua)
- `mfussenegger/nvim-dap` — [`editor/dap.lua`](../../lua/plugins/editor/dap.lua)
- `MunifTanjim/nui.nvim` — [`editor/neo-tree.lua`](../../lua/plugins/editor/neo-tree.lua)
- `NeogitOrg/neogit` — [`editor/neogit.lua`](../../lua/plugins/editor/neogit.lua)
- `nvim-lua/plenary.nvim` — [`editor/neo-tree.lua`](../../lua/plugins/editor/neo-tree.lua), [`editor/neogit.lua`](../../lua/plugins/editor/neogit.lua), [`editor/telescope.lua`](../../lua/plugins/editor/telescope.lua), [`fox/git/git_center/init.lua`](../../lua/plugins/fox/git/git_center/init.lua), [`fox/tools/environments.lua`](../../lua/plugins/fox/tools/environments.lua), [`fox/tools/workspaces.lua`](../../lua/plugins/fox/tools/workspaces.lua)
- `nvim-neo-tree/neo-tree.nvim` — [`editor/neo-tree.lua`](../../lua/plugins/editor/neo-tree.lua)
- `nvim-neotest/nvim-nio` — [`editor/dap.lua`](../../lua/plugins/editor/dap.lua)
- `nvim-telescope/telescope-file-browser.nvim` — [`editor/telescope.lua`](../../lua/plugins/editor/telescope.lua)
- `nvim-telescope/telescope.nvim` — [`editor/neogit.lua`](../../lua/plugins/editor/neogit.lua), [`editor/project.lua`](../../lua/plugins/editor/project.lua), [`editor/telescope.lua`](../../lua/plugins/editor/telescope.lua), [`fox/dev/tasks.lua`](../../lua/plugins/fox/dev/tasks.lua), [`fox/git/git_accounts.lua`](../../lua/plugins/fox/git/git_accounts.lua), [`fox/git/git_center/init.lua`](../../lua/plugins/fox/git/git_center/init.lua), [`fox/tools/command_palette.lua`](../../lua/plugins/fox/tools/command_palette.lua), [`fox/tools/environments.lua`](../../lua/plugins/fox/tools/environments.lua), [`fox/tools/file_explorer.lua`](../../lua/plugins/fox/tools/file_explorer.lua), [`fox/tools/nuget.lua`](../../lua/plugins/fox/tools/nuget.lua), [`fox/tools/workspaces.lua`](../../lua/plugins/fox/tools/workspaces.lua)
- `nvim-treesitter/nvim-treesitter` — [`editor/markdown.lua`](../../lua/plugins/editor/markdown.lua), [`lsp/treesitter.lua`](../../lua/plugins/lsp/treesitter.lua)
- `rcarriga/nvim-dap-ui` — [`editor/dap.lua`](../../lua/plugins/editor/dap.lua)
- `sindrets/diffview.nvim` — [`editor/neogit.lua`](../../lua/plugins/editor/neogit.lua), [`fox/git/git_center/init.lua`](../../lua/plugins/fox/git/git_center/init.lua)

**LSP**

- `b0o/schemastore.nvim` — [`lsp/blink_sources.lua`](../../lua/plugins/lsp/blink_sources.lua), [`lsp/lsp.lua`](../../lua/plugins/lsp/lsp.lua)
- `neovim/nvim-lspconfig` — [`lsp/lsp.lua`](../../lua/plugins/lsp/lsp.lua)
- `saghen/blink.cmp` — [`lsp/blink_sources.lua`](../../lua/plugins/lsp/blink_sources.lua), [`lsp/editorconfig.lua`](../../lua/plugins/lsp/editorconfig.lua), [`lsp/laravel.lua`](../../lua/plugins/lsp/laravel.lua), [`lsp/lsp.lua`](../../lua/plugins/lsp/lsp.lua)
- `stevearc/conform.nvim` — [`lsp/formatting.lua`](../../lua/plugins/lsp/formatting.lua)
- `williamboman/mason.nvim` — [`lsp/formatting.lua`](../../lua/plugins/lsp/formatting.lua), [`lsp/lsp.lua`](../../lua/plugins/lsp/lsp.lua)

**Misc**

- `vyfor/cord.nvim` — [`ui/discord.lua`](../../lua/plugins/ui/discord.lua)

El catálogo de iconos y la API devicons son locales: `fox.ui.icons` y `fox.ui.devicons`.

## (Fox-Made)

Specs locales: no requieren clonar otro repositorio. Se incluyen también las declaradas fuera de `lua/plugins/fox/`.

### Core

- `fox_autopairs` — [`editor/autopairs.lua`](../../lua/plugins/editor/autopairs.lua)
- `fox_icons` — [`ui/devicons.lua`](../../lua/plugins/ui/devicons.lua)
- `fox_theme_startup` — [`ui/themes.lua`](../../lua/plugins/ui/themes.lua)
- `image_viewer` — [`fox/ui/image_viewer.lua`](../../lua/plugins/fox/ui/image_viewer.lua)

### Non-core

**Editor**

- `fox_packages` — [`editor/package-info.lua`](../../lua/plugins/editor/package-info.lua)
- `fox_buffer_cleaner` — [`fox/editor/buffer_cleaner.lua`](../../lua/plugins/fox/editor/buffer_cleaner.lua)
- `fox_recent_projects` — [`editor/project.lua`](../../lua/plugins/editor/project.lua)
- `fox_caps_lock` — [`fox/editor/caps_lock.lua`](../../lua/plugins/fox/editor/caps_lock.lua)
- `fox_folding` — [`fox/editor/folding.lua`](../../lua/plugins/fox/editor/folding.lua)
- `fox_hover_links` — [`fox/editor/hover_links.lua`](../../lua/plugins/fox/editor/hover_links.lua)
- `fox_line_endings` — [`fox/editor/line_endings.lua`](../../lua/plugins/fox/editor/line_endings.lua)
- `fox_neotree_hidden` — [`fox/editor/neotree_hidden.lua`](../../lua/plugins/fox/editor/neotree_hidden.lua)
- `fox_neotree_mover` — [`fox/editor/neotree_mover.lua`](../../lua/plugins/fox/editor/neotree_mover.lua)
- `fox_relative_path` — [`fox/editor/relative_path.lua`](../../lua/plugins/fox/editor/relative_path.lua)
- `fox_smart_check` — [`fox/editor/smart_check.lua`](../../lua/plugins/fox/editor/smart_check.lua)
- `fox_tailwind_organizer` — [`fox/editor/tailwind_organizer.lua`](../../lua/plugins/fox/editor/tailwind_organizer.lua)

**LSP**

- `fox_blade` — [`lsp/laravel.lua`](../../lua/plugins/lsp/laravel.lua)
- `fox_laravel` — [`lsp/blade_navigation.lua`](../../lua/plugins/lsp/blade_navigation.lua)
- `fox_php_tools` — [`lsp/laravel.lua`](../../lua/plugins/lsp/laravel.lua)

**UI**

- `fox_color_highlights` — [`ui/css-colors.lua`](../../lua/plugins/ui/css-colors.lua)
- `fox_colorscheme_preview` — [`fox/ui/colorscheme_preview.lua`](../../lua/plugins/fox/ui/colorscheme_preview.lua)
- `fox_font` — [`fox/ui/font.lua`](../../lua/plugins/fox/ui/font.lua)
- `fox_help_modal` — [`fox/ui/help_modal.lua`](../../lua/plugins/fox/ui/help_modal.lua)
- `fox_input_modal` — [`fox/ui/input_modal.lua`](../../lua/plugins/fox/ui/input_modal.lua)
- `fox_omarchy_theme` — [`fox/ui/omarchy_theme.lua`](../../lua/plugins/fox/ui/omarchy_theme.lua)
- `fox_pinned_tabs` — [`fox/ui/pinned_tabs.lua`](../../lua/plugins/fox/ui/pinned_tabs.lua)
- `fox_ryoku_theme` — [`fox/ui/ryoku_theme.lua`](../../lua/plugins/fox/ui/ryoku_theme.lua)
- `fox_notify` — [`ui/notify.lua`](../../lua/plugins/ui/notify.lua)
- `fox_tabline` — [`ui/bufferline.lua`](../../lua/plugins/ui/bufferline.lua)
- `fox_statusline` — [`ui/statusline.lua`](../../lua/plugins/ui/statusline.lua)
- `fox_statusline_picker` — [`fox/ui/statusline_picker.lua`](../../lua/plugins/fox/ui/statusline_picker.lua)
- `fox_theme_picker` — [`fox/ui/theme_picker.lua`](../../lua/plugins/fox/ui/theme_picker.lua)
- `fox_wiki_modal` — [`fox/ui/wiki_modal.lua`](../../lua/plugins/fox/ui/wiki_modal.lua)

**Tools**

- `context_help` — [`fox/tools/context_help.lua`](../../lua/plugins/fox/tools/context_help.lua)
- `doc_manager` — [`fox/tools/doc_manager.lua`](../../lua/plugins/fox/tools/doc_manager.lua)
- `fox_buffer_language` — [`fox/tools/buffer_language.lua`](../../lua/plugins/fox/tools/buffer_language.lua)
- `fox_command_palette` — [`fox/tools/command_palette.lua`](../../lua/plugins/fox/tools/command_palette.lua)
- `fox_dotnet_creator` — [`fox/tools/dotnet_creator.lua`](../../lua/plugins/fox/tools/dotnet_creator.lua)
- `fox_environments` — [`fox/tools/environments.lua`](../../lua/plugins/fox/tools/environments.lua)
- `fox_file_explorer` — [`fox/tools/file_explorer.lua`](../../lua/plugins/fox/tools/file_explorer.lua)
- `fox_query` — [`fox/tools/query.lua`](../../lua/plugins/fox/tools/query.lua)
- `fox_installer` — [`fox/tools/installer.lua`](../../lua/plugins/fox/tools/installer.lua)
- `fox_lsp_references` — [`fox/tools/lsp_references.lua`](../../lua/plugins/fox/tools/lsp_references.lua)
- `fox_notes` — [`fox/tools/notes.lua`](../../lua/plugins/fox/tools/notes.lua)
- `fox_nuget_manager` — [`fox/tools/nuget.lua`](../../lua/plugins/fox/tools/nuget.lua)
- `fox_php_tools_modal` — [`fox/tools/php_tools_modal.lua`](../../lua/plugins/fox/tools/php_tools_modal.lua)
- `fox_todo_sidebar` — [`fox/tools/todo_sidebar.lua`](../../lua/plugins/fox/tools/todo_sidebar.lua)
- `fox_type_injector` — [`fox/tools/type_injector.lua`](../../lua/plugins/fox/tools/type_injector.lua)
- `fox_type_injector_lua` — [`fox/tools/type_injector_lua.lua`](../../lua/plugins/fox/tools/type_injector_lua.lua)
- `fox_type_injector_typescript` — [`fox/tools/type_injector_typescript.lua`](../../lua/plugins/fox/tools/type_injector_typescript.lua)
- `fox_usages_picker` — [`fox/tools/usages_picker.lua`](../../lua/plugins/fox/tools/usages_picker.lua)
- `fox_workspaces` — [`fox/tools/workspaces.lua`](../../lua/plugins/fox/tools/workspaces.lua)
- `fox_wsl` — [`fox/tools/wsl.lua`](../../lua/plugins/fox/tools/wsl.lua)
- `snippet_manager` — [`fox/tools/snippet_manager.lua`](../../lua/plugins/fox/tools/snippet_manager.lua)
- `vscode_settings` — [`fox/tools/vscode_settings.lua`](../../lua/plugins/fox/tools/vscode_settings.lua)

**Git**

- `fox_inline_blame` — [`editor/git_blame.lua`](../../lua/plugins/editor/git_blame.lua)
- `fox_conflict_resolver` — [`fox/git/conflict_resolver.lua`](../../lua/plugins/fox/git/conflict_resolver.lua)
- `fox_git_accounts` — [`fox/git/git_accounts.lua`](../../lua/plugins/fox/git/git_accounts.lua)
- `fox_git_center` — [`fox/git/git_center/init.lua`](../../lua/plugins/fox/git/git_center/init.lua)
- `fox_git_diff_mode` — [`fox/git/diff_mode.lua`](../../lua/plugins/fox/git/diff_mode.lua)
- `fox_git_log_diff` — [`fox/git/log_diff.lua`](../../lua/plugins/fox/git/log_diff.lua)
- `fox_secondary_git` — [`fox/git/secondary_git.lua`](../../lua/plugins/fox/git/secondary_git.lua)

**Development / DAP**

- `fox_bun_dap` — [`fox/dev/bun_dap.lua`](../../lua/plugins/fox/dev/bun_dap.lua)
- `fox_dap_breakpoints` — [`fox/dev/dap_breakpoints.lua`](../../lua/plugins/fox/dev/dap_breakpoints.lua)
- `fox_dev_server` — [`fox/dev/dev_server.lua`](../../lua/plugins/fox/dev/dev_server.lua)
- `fox_launch_cmp` — [`fox/dev/launch_cmp.lua`](../../lua/plugins/fox/dev/launch_cmp.lua)
- `fox_launch_profiles` — [`fox/dev/launch_profiles.lua`](../../lua/plugins/fox/dev/launch_profiles.lua)
- `fox_sneak_peek` — [`fox/dev/sneak_peek.lua`](../../lua/plugins/fox/dev/sneak_peek.lua)
- `fox_tasks` — [`fox/dev/tasks.lua`](../../lua/plugins/fox/dev/tasks.lua)
- `fox_terminal` — [`fox/dev/terminal.lua`](../../lua/plugins/fox/dev/terminal.lua)

- `fox_dashboard` — [`ui/dashboard.lua`](../../lua/plugins/ui/dashboard.lua)

- `fox_autotag` — [`lsp/autotag.lua`](../../lua/plugins/lsp/autotag.lua)

- `fox_symbol_usage` — [`lsp/symbol_usage.lua`](../../lua/plugins/lsp/symbol_usage.lua)

### Submódulos y soporte local

- `fox.lsp.snippets`: carga del catálogo JSON atribuido en `config/snippet_catalog/` y overrides de usuario; expansión nativa de Blink/Neovim, sin spec adicional.
- `fox.lsp.tooling`: acciones Mason explícitas integradas en la spec LSP existente.
- `fox.core.file_buffers`: reconciliación de buffers integrada en Neo-tree.
- `fox.lsp.file_operations`: eventos LSP de archivos integrados en Neo-tree.

No son plugins externos ni specs independientes adicionales:

- `fox_neotree_wrap`: spec desactivada; sus helpers se usan desde Neo-tree.

- `lua/fox/ui/devicons.lua` y `lua/nvim-web-devicons.lua`: API local para los consumidores de iconos; resolución propia en `lua/fox/ui/icons.lua` con metadatos originales atribuidos en `icon_data.lua` (licencia MIT en `licenses/mini.icons.txt`).

- `lua/fox/langs/csharp/navigation.lua`: navegación OmniSharp y fuentes de metadata/generadas asíncronas.

- `lua/fox/projects/history.lua` y `lua/telescope/_extensions/projects.lua`: historial local persistente y compatibilidad de `:Telescope projects`.
- `lua/fox/dap/virtual_text.lua`: variables DAP con extmarks, controles y seguimiento del ciclo de sesión; sustituye a `nvim-dap-virtual-text`.
- `lua/fox/core/window_picker.lua` y `lua/window-picker.lua`: selector local de ventanas y punto de compatibilidad con los comandos de Neo-tree; sustituye a `nvim-window-picker`.
- `lua/plugins/fox/debuggers/{_shared,browsers,bun,node}.lua`: soporte DAP compartido; los depuradores específicos de lenguaje viven en `lua/fox/langs/<lenguaje>/init.lua`.
- `lua/plugins/fox/git/git_center/*.lua`: implementación de la spec `git_center/init.lua`.
- `lua/plugins/fox/context_help.lua`: compatibilidad con la ruta anterior.
- `lua/plugins/lsp/editorconfig.lua`: IntelliSense local integrado en la spec de Blink.
- `lua/plugins/theme.lua`: spec dinámica de Omarchy; no está en los imports actuales.
- `lua/fox/`, `config/colors/`, `syntax/`, `ftplugin/` y `config/snippets/`: bibliotecas, temas y recursos propios; no implican clones de plugins.

La instalación de formateadores ya la cubre `fox.core.installer` mediante `:LanguageManager`; Conform depende directamente de Mason para encontrar sus ejecutables en PATH. No se usa `mason-conform.nvim`.
