local t = require("fox.lib.foxnvim.test")

local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
end

t.describe("Comment shortcuts", function()
	t.beforeEach(function()
		vim.cmd("enew!")
		vim.bo.commentstring = "-- %s"
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
		-- Shortcuts must work even when a filetype overrides the default maps.
		vim.keymap.set({ "n", "x" }, "gc", "<Nop>", { buffer = true })
		vim.keymap.set("n", "gcc", "<Nop>", { buffer = true })
	end)

	t.afterEach(function()
		feed("<Esc>")
		vim.cmd("bwipeout!")
	end)

	t.it("toggles a line twice with Ctrl+apostrophe", function()
		feed("<C-'>")
		t.expect(vim.fn.getline(1)).toBe("-- one")
		feed("<C-'>")
		t.expect(vim.fn.getline(1)).toBe("one")
	end)

	t.it("toggles the selected lines without using gc", function()
		feed("Vj<C-'>")
		t.expect(vim.api.nvim_buf_get_lines(0, 0, -1, false)).toEqual({ "-- one", "-- two", "three" })
	end)

	t.it("toggles while inserting and continues inserting text", function()
		feed("i<C-'>X<Esc>")
		t.expect(vim.fn.getline(1)).toBe("X-- one")
	end)

	t.it("exposes the same action as a range command", function()
		vim.cmd("2,3ToggleComment")
		t.expect(vim.api.nvim_buf_get_lines(0, 0, -1, false)).toEqual({ "one", "-- two", "-- three" })
	end)
end)
