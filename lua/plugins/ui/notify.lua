return {
	name = "fox_notify",
	dir = require("fox.core.lazyspec").for_module(),
	event = "VeryLazy",
	priority = 1000,
	config = function()
		require("fox.core.notify").setup()
	end,
}
