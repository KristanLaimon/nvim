-- Current desktop palette, also available for theme-picker previews.
if not require("plugins.fox.ui.ryoku_theme").apply({ quiet = true }) then
	vim.cmd.colorscheme("nagatoro-fox")
end
