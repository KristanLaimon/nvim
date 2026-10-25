return {
	name = "fox_color_highlights",
	dir = vim.fn.stdpath("config"),
	event = { "BufReadPre", "BufNewFile" },
	cmd = "HighlightColors",
	config = function()
		require("fox.ui.color_highlights").setup({})
	end,
}
