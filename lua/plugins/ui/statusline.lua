return {
	name = "fox_statusline",
	dir = require("fox.core.lazyspec").for_module(),
	event = "VimEnter",
	dependencies = { "fox_icons" },
	config = function()
		require("fox.ui.statusline").setup(require("plugins.fox.ui.statusline_picker").get_config())
	end,
}
