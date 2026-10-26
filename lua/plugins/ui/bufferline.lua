-- Native FOX buffer tabs; retain the existing navigation and reorder keys.
return {
	name = "fox_tabline",
	dir = require("fox.core.lazyspec").for_module(),
	event = "VimEnter",
	dependencies = { "fox_icons" },
	config = function()
		require("fox.ui.tabline").setup()

		vim.keymap.set("n", "gt", "<Cmd>BufferLineCycleNext<CR>", { noremap = true, silent = true, desc = "Next tab" })
		vim.keymap.set("n", "gT", "<Cmd>BufferLineCyclePrev<CR>", { noremap = true, silent = true, desc = "Previous tab" })

		-- Move active tab order left / right (reordering buffer tabs)
		local move_left_keys = {
			"<C-A-Left>",
			"<C-M-Left>",
			"<A-S-h>",
			"<A-H>",
			"<M-S-h>",
			"<M-H>",
			"<A-S-Left>",
			"<M-S-Left>",
		}
		local move_right_keys = {
			"<C-A-Right>",
			"<C-M-Right>",
			"<A-S-l>",
			"<A-L>",
			"<M-S-l>",
			"<M-L>",
			"<A-S-Right>",
			"<M-S-Right>",
		}

		for _, key in ipairs(move_left_keys) do
			pcall(
				vim.keymap.set,
				"n",
				key,
				"<Cmd>BufferLineMovePrev<CR>",
				{ noremap = true, silent = true, desc = "Move buffer tab left" }
			)
		end

		for _, key in ipairs(move_right_keys) do
			pcall(
				vim.keymap.set,
				"n",
				key,
				"<Cmd>BufferLineMoveNext<CR>",
				{ noremap = true, silent = true, desc = "Move buffer tab right" }
			)
		end
	end,
}
