local t = require("fox.lib.foxnvim.test")
local diff = getmetatable(require("plugins.fox.git.diff_mode")).__index

local function press(key)
	vim.fn.maparg(key, "n", false, true).callback()
end

t.describe("Git Diff card menu", function()
	t.it("selects with numbers, confirms with Enter and adapts to a narrow viewport", function()
		local columns, lines = vim.o.columns, vim.o.lines
		local original, called = diff.open_config_dialog, nil
		local win
		local ok, err = pcall(function()
			vim.o.columns, vim.o.lines = 160, 40
			diff.open_config_dialog = function(index, start)
				called = { index, start }
			end
			local buf
			buf, win = diff.open()
			local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			t.expect(text).toContain("Working Tree vs HEAD")
			t.expect(text).toContain("Last N commits")
			t.expect(text).toContain("Until a branch")
			press("2")
			t.expect(called).toBe(nil)
			t.expect(#vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("fox_git_diff_menu"), 0, -1, {}))
				.toBe(18)
			press("<CR>")
			t.expect(called[1]).toBe(2)
			t.expect(called[2]).toBe(true)
			t.expect(vim.api.nvim_win_is_valid(win)).toBe(false)
			win = select(2, diff.open())
			vim.o.columns, vim.o.lines = 50, 16
			vim.api.nvim_exec_autocmds("VimResized", {})
			t.expect(vim.api.nvim_win_get_width(win) <= 46).toBe(true)
			t.expect(vim.api.nvim_win_get_height(win) <= 12).toBe(true)
			press("5")
			press("<CR>")
			win = vim.api.nvim_get_current_win()
			t.expect(vim.api.nvim_win_get_config(win).title[1][1]).toContain("Advanced")
			press("<Esc>")
		end)
		diff.open_config_dialog = original
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		vim.o.columns, vim.o.lines = columns, lines
		assert(ok, err)
	end)
end)
