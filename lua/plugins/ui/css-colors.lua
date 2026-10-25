return {
	name = "fox_color_highlights",
	dir = require("fox.core.lazyspec").for_module(),
	event = { "BufReadPre", "BufNewFile" },
	cmd = "HighlightColors",
	config = function()
		require("fox.ui.color_highlights").setup({})
	end,
}
