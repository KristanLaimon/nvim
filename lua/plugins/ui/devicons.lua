return {
	{
		name = "fox_icons",
		dir = require("fox.core.lazyspec").for_module(),
		lazy = false,
		priority = 10000,
		config = function()
			local custom = {
				foxnvim = { glyph = "🦊", hl = "MiniIconsOrange" },
				proto = { glyph = "", hl = "MiniIconsAzure" },
				lua = { hl = "MiniIconsBlue" },
			}
			local opts = { extension = vim.deepcopy(custom), filetype = vim.deepcopy(custom) }
			for _, lang in pairs(require("fox.langs").langs) do
				opts = vim.tbl_deep_extend("force", opts, lang.icons or {})
			end
			require("fox.ui.icons").setup(opts)
		end,
	},
}
