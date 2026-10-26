-- ============================================================================
-- PLUGINS: Theme and statusline.
-- ============================================================================
-- All selectable FOX palettes and highlights live locally in config/colors/.
--
-- fox.ui.statusline renders the single global statusline (`laststatus = 3`): branch, diff
-- and diagnostics on the left, file name next, mode and position on the right.
-- ============================================================================

return {
	{
		name = "fox_theme_startup",
		dir = require("fox.core.lazyspec").for_module(),
		-- Eager: a lazily loaded theme means a flash of the default colours.
		lazy = false,
		config = function()
			local has_picker, picker = pcall(require, "plugins.fox.ui.theme_picker")
			if has_picker then
				picker.setup()
				picker.restore_saved_theme()
			else
				pcall(vim.cmd.colorscheme, "nagatoro-fox")
			end
		end,
	},
}
