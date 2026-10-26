# Plugin List

Active inventory from Lazy: **23 external dependencies** and **73 local plugin specs**. Installed leftovers from replaced plugins are excluded.

## External — dependencies

These repositories are still downloaded and managed by Lazy. Transitive dependencies and Lazy itself are included once.

| Repository | Lazy ID |
|---|---|
| [b0o/schemastore.nvim](https://github.com/b0o/schemastore.nvim) | `schemastore.nvim` |
| [folke/lazy.nvim](https://github.com/folke/lazy.nvim) | `lazy.nvim` |
| [folke/snacks.nvim](https://github.com/folke/snacks.nvim) | `snacks.nvim` |
| [iamcco/markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim) | `markdown-preview.nvim` |
| [lewis6991/gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | `gitsigns.nvim` |
| [m00qek/baleia.nvim](https://github.com/m00qek/baleia.nvim) | `baleia.nvim` |
| [MeanderingProgrammer/render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | `render-markdown.nvim` |
| [mfussenegger/nvim-dap](https://github.com/mfussenegger/nvim-dap) | `nvim-dap` |
| [MunifTanjim/nui.nvim](https://github.com/MunifTanjim/nui.nvim) | `nui.nvim` |
| [NeogitOrg/neogit](https://github.com/NeogitOrg/neogit) | `neogit` |
| [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | `nvim-lspconfig` |
| [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) | `plenary.nvim` |
| [nvim-neo-tree/neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | `neo-tree.nvim` |
| [nvim-neotest/nvim-nio](https://github.com/nvim-neotest/nvim-nio) | `nvim-nio` |
| [nvim-telescope/telescope-file-browser.nvim](https://github.com/nvim-telescope/telescope-file-browser.nvim) | `telescope-file-browser.nvim` |
| [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | `telescope.nvim` |
| [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | `nvim-treesitter` |
| [rcarriga/nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | `nvim-dap-ui` |
| [saghen/blink.cmp](https://github.com/saghen/blink.cmp) | `blink.cmp` |
| [sindrets/diffview.nvim](https://github.com/sindrets/diffview.nvim) | `diffview.nvim` |
| [stevearc/conform.nvim](https://github.com/stevearc/conform.nvim) | `conform.nvim` |
| [vyfor/cord.nvim](https://github.com/vyfor/cord.nvim) | `cord.nvim` |
| [williamboman/mason.nvim](https://github.com/williamboman/mason.nvim) | `mason.nvim` |

## Local — FOX implementations

The `fox-<name>` labels below identify local implementations; the Lazy ID column preserves their actual configuration names. These specs run code from this repository and require no separate plugin clone.

| FOX name | Lazy ID | Local source |
|---|---|---|
| `fox-context-help` | `context_help` | [lua/plugins/fox/tools/context_help.lua](lua/plugins/fox/tools/context_help.lua) |
| `fox-doc-manager` | `doc_manager` | [lua/plugins/fox/tools/doc_manager.lua](lua/plugins/fox/tools/doc_manager.lua) |
| `fox-autopairs` | `fox_autopairs` | [lua/plugins/editor/autopairs.lua](lua/plugins/editor/autopairs.lua) |
| `fox-autotag` | `fox_autotag` | [lua/plugins/lsp/autotag.lua](lua/plugins/lsp/autotag.lua) |
| `fox-blade` | `fox_blade` | [lua/plugins/lsp/laravel.lua](lua/plugins/lsp/laravel.lua) |
| `fox-buffer-cleaner` | `fox_buffer_cleaner` | [lua/plugins/fox/editor/buffer_cleaner.lua](lua/plugins/fox/editor/buffer_cleaner.lua) |
| `fox-buffer-language` | `fox_buffer_language` | [lua/plugins/fox/tools/buffer_language.lua](lua/plugins/fox/tools/buffer_language.lua) |
| `fox-bun-dap` | `fox_bun_dap` | [lua/plugins/fox/dev/bun_dap.lua](lua/plugins/fox/dev/bun_dap.lua) |
| `fox-caps-lock` | `fox_caps_lock` | [lua/plugins/fox/editor/caps_lock.lua](lua/plugins/fox/editor/caps_lock.lua) |
| `fox-color-highlights` | `fox_color_highlights` | [lua/plugins/ui/css-colors.lua](lua/plugins/ui/css-colors.lua) |
| `fox-colorscheme-preview` | `fox_colorscheme_preview` | [lua/plugins/fox/ui/colorscheme_preview.lua](lua/plugins/fox/ui/colorscheme_preview.lua) |
| `fox-command-palette` | `fox_command_palette` | [lua/plugins/fox/tools/command_palette.lua](lua/plugins/fox/tools/command_palette.lua) |
| `fox-conflict-resolver` | `fox_conflict_resolver` | [lua/plugins/fox/git/conflict_resolver.lua](lua/plugins/fox/git/conflict_resolver.lua) |
| `fox-dap-breakpoints` | `fox_dap_breakpoints` | [lua/plugins/fox/dev/dap_breakpoints.lua](lua/plugins/fox/dev/dap_breakpoints.lua) |
| `fox-dashboard` | `fox_dashboard` | [lua/plugins/ui/dashboard.lua](lua/plugins/ui/dashboard.lua) |
| `fox-dev-server` | `fox_dev_server` | [lua/plugins/fox/dev/dev_server.lua](lua/plugins/fox/dev/dev_server.lua) |
| `fox-dotnet-creator` | `fox_dotnet_creator` | [lua/plugins/fox/tools/dotnet_creator.lua](lua/plugins/fox/tools/dotnet_creator.lua) |
| `fox-environments` | `fox_environments` | [lua/plugins/fox/tools/environments.lua](lua/plugins/fox/tools/environments.lua) |
| `fox-file-explorer` | `fox_file_explorer` | [lua/plugins/fox/tools/file_explorer.lua](lua/plugins/fox/tools/file_explorer.lua) |
| `fox-folding` | `fox_folding` | [lua/plugins/fox/editor/folding.lua](lua/plugins/fox/editor/folding.lua) |
| `fox-font` | `fox_font` | [lua/plugins/fox/ui/font.lua](lua/plugins/fox/ui/font.lua) |
| `fox-git-accounts` | `fox_git_accounts` | [lua/plugins/fox/git/git_accounts.lua](lua/plugins/fox/git/git_accounts.lua) |
| `fox-git-center` | `fox_git_center` | [lua/plugins/fox/git/git_center/init.lua](lua/plugins/fox/git/git_center/init.lua) |
| `fox-git-diff-mode` | `fox_git_diff_mode` | [lua/plugins/fox/git/diff_mode.lua](lua/plugins/fox/git/diff_mode.lua) |
| `fox-git-log-diff` | `fox_git_log_diff` | [lua/plugins/fox/git/log_diff.lua](lua/plugins/fox/git/log_diff.lua) |
| `fox-help-modal` | `fox_help_modal` | [lua/plugins/fox/ui/help_modal.lua](lua/plugins/fox/ui/help_modal.lua) |
| `fox-hover-links` | `fox_hover_links` | [lua/plugins/fox/editor/hover_links.lua](lua/plugins/fox/editor/hover_links.lua) |
| `fox-icons` | `fox_icons` | [lua/plugins/ui/devicons.lua](lua/plugins/ui/devicons.lua) |
| `fox-inline-blame` | `fox_inline_blame` | [lua/plugins/editor/git_blame.lua](lua/plugins/editor/git_blame.lua) |
| `fox-input-modal` | `fox_input_modal` | [lua/plugins/fox/ui/input_modal.lua](lua/plugins/fox/ui/input_modal.lua) |
| `fox-installer` | `fox_installer` | [lua/plugins/fox/tools/installer.lua](lua/plugins/fox/tools/installer.lua) |
| `fox-laravel` | `fox_laravel` | [lua/plugins/lsp/blade_navigation.lua](lua/plugins/lsp/blade_navigation.lua) |
| `fox-launch-cmp` | `fox_launch_cmp` | [lua/plugins/fox/dev/launch_cmp.lua](lua/plugins/fox/dev/launch_cmp.lua) |
| `fox-launch-profiles` | `fox_launch_profiles` | [lua/plugins/fox/dev/launch_profiles.lua](lua/plugins/fox/dev/launch_profiles.lua) |
| `fox-line-endings` | `fox_line_endings` | [lua/plugins/fox/editor/line_endings.lua](lua/plugins/fox/editor/line_endings.lua) |
| `fox-lsp-references` | `fox_lsp_references` | [lua/plugins/fox/tools/lsp_references.lua](lua/plugins/fox/tools/lsp_references.lua) |
| `fox-neotree-hidden` | `fox_neotree_hidden` | [lua/plugins/fox/editor/neotree_hidden.lua](lua/plugins/fox/editor/neotree_hidden.lua) |
| `fox-neotree-mover` | `fox_neotree_mover` | [lua/plugins/fox/editor/neotree_mover.lua](lua/plugins/fox/editor/neotree_mover.lua) |
| `fox-notes` | `fox_notes` | [lua/plugins/fox/tools/notes.lua](lua/plugins/fox/tools/notes.lua) |
| `fox-notify` | `fox_notify` | [lua/plugins/ui/notify.lua](lua/plugins/ui/notify.lua) |
| `fox-nuget-manager` | `fox_nuget_manager` | [lua/plugins/fox/tools/nuget.lua](lua/plugins/fox/tools/nuget.lua) |
| `fox-omarchy-theme` | `fox_omarchy_theme` | [lua/plugins/fox/ui/omarchy_theme.lua](lua/plugins/fox/ui/omarchy_theme.lua) |
| `fox-packages` | `fox_packages` | [lua/plugins/editor/package-info.lua](lua/plugins/editor/package-info.lua) |
| `fox-php-tools` | `fox_php_tools` | [lua/plugins/lsp/laravel.lua](lua/plugins/lsp/laravel.lua) |
| `fox-php-tools-modal` | `fox_php_tools_modal` | [lua/plugins/fox/tools/php_tools_modal.lua](lua/plugins/fox/tools/php_tools_modal.lua) |
| `fox-pinned-tabs` | `fox_pinned_tabs` | [lua/plugins/fox/ui/pinned_tabs.lua](lua/plugins/fox/ui/pinned_tabs.lua) |
| `fox-query` | `fox_query` | [lua/plugins/fox/tools/query.lua](lua/plugins/fox/tools/query.lua) |
| `fox-recent-projects` | `fox_recent_projects` | [lua/plugins/editor/project.lua](lua/plugins/editor/project.lua) |
| `fox-relative-path` | `fox_relative_path` | [lua/plugins/fox/editor/relative_path.lua](lua/plugins/fox/editor/relative_path.lua) |
| `fox-ryoku-theme` | `fox_ryoku_theme` | [lua/plugins/fox/ui/ryoku_theme.lua](lua/plugins/fox/ui/ryoku_theme.lua) |
| `fox-secondary-git` | `fox_secondary_git` | [lua/plugins/fox/git/secondary_git.lua](lua/plugins/fox/git/secondary_git.lua) |
| `fox-smart-check` | `fox_smart_check` | [lua/plugins/fox/editor/smart_check.lua](lua/plugins/fox/editor/smart_check.lua) |
| `fox-sneak-peek` | `fox_sneak_peek` | [lua/plugins/fox/dev/sneak_peek.lua](lua/plugins/fox/dev/sneak_peek.lua) |
| `fox-statusline` | `fox_statusline` | [lua/plugins/ui/statusline.lua](lua/plugins/ui/statusline.lua) |
| `fox-statusline-picker` | `fox_statusline_picker` | [lua/plugins/fox/ui/statusline_picker.lua](lua/plugins/fox/ui/statusline_picker.lua) |
| `fox-symbol-usage` | `fox_symbol_usage` | [lua/plugins/lsp/symbol_usage.lua](lua/plugins/lsp/symbol_usage.lua) |
| `fox-tabline` | `fox_tabline` | [lua/plugins/ui/bufferline.lua](lua/plugins/ui/bufferline.lua) |
| `fox-tailwind-organizer` | `fox_tailwind_organizer` | [lua/plugins/fox/editor/tailwind_organizer.lua](lua/plugins/fox/editor/tailwind_organizer.lua) |
| `fox-tasks` | `fox_tasks` | [lua/plugins/fox/dev/tasks.lua](lua/plugins/fox/dev/tasks.lua) |
| `fox-terminal` | `fox_terminal` | [lua/plugins/fox/dev/terminal.lua](lua/plugins/fox/dev/terminal.lua) |
| `fox-theme-picker` | `fox_theme_picker` | [lua/plugins/fox/ui/theme_picker.lua](lua/plugins/fox/ui/theme_picker.lua) |
| `fox-theme-startup` | `fox_theme_startup` | [lua/plugins/ui/themes.lua](lua/plugins/ui/themes.lua) |
| `fox-todo-sidebar` | `fox_todo_sidebar` | [lua/plugins/fox/tools/todo_sidebar.lua](lua/plugins/fox/tools/todo_sidebar.lua) |
| `fox-type-injector` | `fox_type_injector` | [lua/plugins/fox/tools/type_injector.lua](lua/plugins/fox/tools/type_injector.lua) |
| `fox-type-injector-lua` | `fox_type_injector_lua` | [lua/plugins/fox/tools/type_injector_lua.lua](lua/plugins/fox/tools/type_injector_lua.lua) |
| `fox-type-injector-typescript` | `fox_type_injector_typescript` | [lua/plugins/fox/tools/type_injector_typescript.lua](lua/plugins/fox/tools/type_injector_typescript.lua) |
| `fox-usages-picker` | `fox_usages_picker` | [lua/plugins/fox/tools/usages_picker.lua](lua/plugins/fox/tools/usages_picker.lua) |
| `fox-wiki-modal` | `fox_wiki_modal` | [lua/plugins/fox/ui/wiki_modal.lua](lua/plugins/fox/ui/wiki_modal.lua) |
| `fox-workspaces` | `fox_workspaces` | [lua/plugins/fox/tools/workspaces.lua](lua/plugins/fox/tools/workspaces.lua) |
| `fox-wsl` | `fox_wsl` | [lua/plugins/fox/tools/wsl.lua](lua/plugins/fox/tools/wsl.lua) |
| `fox-image-viewer` | `image_viewer` | [lua/plugins/fox/ui/image_viewer.lua](lua/plugins/fox/ui/image_viewer.lua) |
| `fox-snippet-manager` | `snippet_manager` | [lua/plugins/fox/tools/snippet_manager.lua](lua/plugins/fox/tools/snippet_manager.lua) |
| `fox-vscode-settings` | `vscode_settings` | [lua/plugins/fox/tools/vscode_settings.lua](lua/plugins/fox/tools/vscode_settings.lua) |

## Additional local code and resources

Shared modules under `lua/fox/`, language modules under `lua/fox/langs/`, and compatibility entrypoints belong to these local specs; they are not additional external plugins. Examples include local snippet loading, LSP tooling and file operations, icon lookup, Git helpers, and package manager actions.

Some local data catalogs retain upstream attribution and licenses: icons and bundled snippet definitions are resources, rather than newly authored FOX data. See `licenses/` and the catalog documentation.

