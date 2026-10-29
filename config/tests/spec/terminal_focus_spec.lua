local t = require("fox.lib.foxnvim.test")
local terminal = require("plugins.fox.dev.terminal")

t.describe("terminal return focus", function()
	t.it("exchanges Git Center and terminal panes while preserving unrelated floats and terminal contents", function()
		local cwd = vim.fn.getcwd()
		vim.api.nvim_set_current_dir(vim.fn.stdpath("config"))
		local center = require("plugins.fox.git.git_center")
		local config = require("plugins.fox.git.git_center.config")
		local original, selected = vim.api.nvim_get_current_win(), terminal.get_selected_terminal()
		center.close_git_center()
		config.cached_view, config.cached_view_data = nil, nil
		local buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].fox_is_multi_term, vim.b[buf].fox_term_num = true, 9
		vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "terminal output survives" })
		local pane = vim.api.nvim_open_win(buf, true, { split = "below", height = 3 })
		local other_buf, other = require("fox.core.ui").float({ lines = { "unrelated panel" }, width = 20, height = 2 })
		local ok, err = pcall(function()
			center.open_git_center()
			t.expect(center.is_open()).toBe(true)
			t.expect(vim.api.nvim_win_is_valid(pane)).toBe(false)
			t.expect(vim.api.nvim_win_is_valid(other)).toBe(true)
			terminal.open_terminal(9)
			t.expect(center.is_open()).toBe(false)
			t.expect(vim.api.nvim_get_current_buf()).toBe(buf)
			t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]).toBe("terminal output survives")
			center.open_git_center()
			terminal.select_terminal(9)
			t.expect(center.is_open()).toBe(false)
			t.expect(vim.api.nvim_get_current_buf()).toBe(buf)
			t.expect(vim.api.nvim_win_is_valid(other)).toBe(true)
		end)
		pcall(vim.cmd, "stopinsert")
		center.close_git_center()
		terminal.hide_terminal()
		if vim.api.nvim_win_is_valid(other) then
			vim.api.nvim_win_close(other, true)
		end
		if vim.api.nvim_buf_is_valid(other_buf) then
			vim.api.nvim_buf_delete(other_buf, { force = true })
		end
		vim.api.nvim_buf_delete(buf, { force = true })
		_G._fox_selected_terminal = selected
		if vim.api.nvim_win_is_valid(original) then
			vim.api.nvim_set_current_win(original)
		end
		vim.api.nvim_set_current_dir(cwd)
		assert(ok, err)
	end)
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
