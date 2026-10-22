-- ============================================================================
-- PLUGINS: Theme and statusline.
-- ============================================================================
-- All selectable FOX palettes and highlights live locally in colors/.
--
-- lualine renders the single global statusline (`laststatus = 3`): branch, diff
-- and diagnostics on the left, file name next, mode and position on the right.
-- ============================================================================

return {
	{
		name = "fox_theme_startup",
		dir = require("fox.core.lazyspec").for_module(),
		-- Eager: a lazily loaded theme means a flash of the default colours.
		lazy = false,
		config = function()
			local ryoku = require("plugins.fox.ui.ryoku_theme")
			if ryoku.is_sync_enabled() and ryoku.apply({ quiet = true }) then
				ryoku.setup()
				ryoku.start_watcher()
				return
			end
			local has_omarchy, omarchy_mod = pcall(require, "plugins.fox.ui.omarchy_theme")
			if has_omarchy and omarchy_mod.is_sync_enabled() and omarchy_mod.is_omarchy_available() then
				omarchy_mod.apply_omarchy_theme({ quiet = true })
				omarchy_mod.start_watcher()
				return
			end

			local has_picker, picker = pcall(require, "plugins.fox.ui.theme_picker")
			if has_picker then
				picker.restore_saved_theme()
			else
				pcall(vim.cmd.colorscheme, "nagatoro-fox")
			end
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		event = "VimEnter",
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		opts = function()
			local has_picker, picker = pcall(require, "plugins.fox.ui.statusline_picker")
			if has_picker then
				return picker.get_lualine_config()
			end
			return {
				options = { theme = "auto", globalstatus = true },
				sections = {
					lualine_a = { "mode" },
					lualine_b = { "branch", "diff", "diagnostics" },
					lualine_c = { "filename" },
					lualine_x = { "filetype" },
					lualine_y = { "progress" },
					lualine_z = { "location" },
				},
			}
		end,
	},
}
