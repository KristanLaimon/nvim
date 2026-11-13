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
	t.it("kills only the visible terminal job and leaves hidden slots running", function()
		local original = vim.api.nvim_get_current_win()
		local original_buf = vim.api.nvim_get_current_buf()
		local selected = terminal.get_selected_terminal()
		local buffers, jobs = {}, {}
		local ok, err = pcall(function()
			for i, slot in ipairs({ 8, 9 }) do
				local buf = vim.api.nvim_create_buf(false, true)
				buffers[i] = buf
				vim.api.nvim_set_current_buf(buf)
				vim.b[buf].fox_is_multi_term = true
				vim.b[buf].fox_term_num = slot
				vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
				jobs[i] = vim.fn.jobstart({ vim.v.progpath, "--headless", "-u", "NONE", "-c", "sleep 60" }, { term = true })
				assert(jobs[i] > 0, "terminal job failed to start")
			end
			vim.api.nvim_set_current_buf(original_buf)
			terminal.open_terminal(9, false)
			local pane = vim.api.nvim_get_current_win()
			-- Palette actions can execute with focus in an editor window.
			vim.api.nvim_set_current_win(original)
			terminal.kill_current_terminal()
			t.expect(vim.api.nvim_buf_is_valid(buffers[2])).toBe(false)
			t.expect(vim.api.nvim_win_is_valid(pane)).toBe(false)
			t.expect(vim.wait(2000, function()
				return vim.fn.jobwait({ jobs[2] }, 0)[1] ~= -1
			end)).toBe(true)
			t.expect(vim.api.nvim_buf_is_valid(buffers[1])).toBe(true)
			t.expect(vim.fn.jobwait({ jobs[1] }, 0)[1]).toBe(-1)
			terminal.kill_current_terminal()
			t.expect(vim.fn.jobwait({ jobs[1] }, 0)[1]).toBe(-1)
		end)
		for _, job in ipairs(jobs) do
			pcall(vim.fn.jobstop, job)
		end
		for _, buf in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		_G._fox_selected_terminal = selected
		vim.api.nvim_set_current_win(original)
		vim.api.nvim_set_current_buf(original_buf)
		assert(ok, err)
	end)
end)
