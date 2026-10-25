return {
	{
		name = "fox_icons",
		dir = vim.fn.stdpath("config"),
		lazy = false,
		priority = 10000,
		config = function()
			local opts = {}
			for _, lang in pairs(require("fox.langs").langs) do
				opts = vim.tbl_deep_extend("force", opts, lang.icons or {})
			end
			require("fox.ui.icons").setup(opts)
		end,
	},
}
