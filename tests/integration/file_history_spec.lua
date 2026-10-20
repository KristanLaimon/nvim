local t = require("fox.lib.foxnvim.test")
local history = require("plugins.fox.git.log_diff")
local center = require("plugins.fox.git.git_center")

require("lazy").load({ plugins = { "neo-tree.nvim", "telescope.nvim" } })

t.describe("file history entry points", function()
	t.afterEach(function()
		history.close()
		center.close_git_center()
		vim.cmd("Neotree close")
		vim.wait(100)
	end)

	t.it("binds gH only in Neo-tree and ignores directory nodes", function()
		vim.cmd("Neotree show")
		local state = require("neo-tree.sources.manager").get_state("filesystem")
		vim.api.nvim_set_current_win(state.winid)
		t.expect(vim.fn.maparg("gH", "n", false, true).buffer).toBe(1)
		local command = require("neo-tree.setup").config.commands.file_history
		local node = { type = "directory", path = vim.fn.getcwd() }
		local selection = { tree = {
			get_node = function()
				return node
			end,
		} }
		command(selection)
		t.expect(history.is_open()).toBe(false)
		node = { type = "file", path = vim.fn.getcwd() .. "/lua/plugins/fox/git/log_diff.lua" }
		command(selection)
		t.expect(history.is_open()).toBe(true)
		t.expect(history.state.history_file).toBe("lua/plugins/fox/git/log_diff.lua")
	end)

	t.it("opens the shared finder from Git Center and selects a file's history", function()
		center.open_git_center()
		vim.api.nvim_set_current_win(center.main_win)
		vim.fn.maparg("h", "n", false, true).callback()
		local action_state = require("telescope.actions.state")
		local prompt
		t.expect(vim.wait(3000, function()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].filetype == "TelescopePrompt" then
					prompt = buf
					vim.api.nvim_set_current_win(win)
					return true
				end
			end
		end)).toBe(true)
		local picker = action_state.get_current_picker(prompt)
		picker:set_prompt("log_diff.lua")
		t.expect(vim.wait(5000, function()
			local entry = action_state.get_selected_entry()
			return entry and entry.value:gsub("\\", "/") == "lua/plugins/fox/git/log_diff.lua"
		end)).toBe(true)
		require("telescope.actions").select_default(prompt)
		t.expect(vim.wait(3000, history.is_open)).toBe(true)
		t.expect(history.state.history_file).toBe("lua/plugins/fox/git/log_diff.lua")
		t.expect(#history.state.files).toBe(1)
	end)

	t.it("returns focus to Git Center when hiding an already visible terminal", function()
		local terminal = require("plugins.fox.dev.terminal")
		local selected = terminal.get_selected_terminal()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].fox_is_multi_term = true
		vim.b[buf].fox_term_num = 9
		vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
		local win = vim.api.nvim_open_win(buf, false, { split = "below", height = 3 })
		local ok, err = pcall(function()
			terminal.open_terminal(9)
			center.open_git_center()
			vim.api.nvim_set_current_win(center.main_win)
			terminal.toggle_selected_terminal()
			t.expect(vim.api.nvim_get_current_win()).toBe(win)
			terminal.toggle_selected_terminal()
			vim.wait(100)
			t.expect(center.is_open()).toBe(true)
			t.expect(vim.api.nvim_get_current_win()).toBe(center.main_win)
		end)
		pcall(vim.cmd, "stopinsert")
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		vim.api.nvim_buf_delete(buf, { force = true })
		_G._fox_selected_terminal = selected
		assert(ok, err)
	end)
end)
