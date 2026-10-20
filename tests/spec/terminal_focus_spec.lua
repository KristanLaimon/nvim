local t = require("fox.lib.foxnvim.test")
local terminal = require("plugins.fox.dev.terminal")

t.describe("terminal return focus", function()
	t.it("returns to a floating panel after focusing an already visible terminal", function()
		local original = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].fox_is_multi_term = true
		vim.b[buf].fox_term_num = 9
		vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
		local win = vim.api.nvim_open_win(buf, false, { split = "below", height = 3 })
		local panel_buf = vim.api.nvim_create_buf(false, true)
		local panel = vim.api.nvim_open_win(panel_buf, false, {
			relative = "editor",
			row = 1,
			col = 1,
			width = 30,
			height = 5,
		})
		local selected = terminal.get_selected_terminal()
		local ok, err = pcall(function()
			terminal.open_terminal(9)
			vim.api.nvim_set_current_win(panel)
			terminal.toggle_selected_terminal()
			t.expect(vim.api.nvim_get_current_win()).toBe(win)
			terminal.toggle_selected_terminal()
			t.expect(vim.api.nvim_get_current_win()).toBe(panel)
		end)
		pcall(vim.cmd, "stopinsert")
		for _, w in ipairs({ panel, win }) do
			if vim.api.nvim_win_is_valid(w) then
				vim.api.nvim_win_close(w, true)
			end
		end
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.api.nvim_buf_delete(panel_buf, { force = true })
		_G._fox_selected_terminal = selected
		vim.api.nvim_set_current_win(original)
		assert(ok, err)
	end)
end)
