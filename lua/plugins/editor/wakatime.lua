return {
	name = "fox_wakatime",
	dir = require("fox.core.lazyspec").for_module(),
	lazy = false,
	config = function()
		require("fox.wakatime").setup()
	end,
}
