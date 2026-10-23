local t = require("fox.lib.foxnvim.test")
local query = require("fox.query")
local envs = require("plugins.fox.tools.environments")
local storage = require("fox.query.storage")
dofile(vim.fn.stdpath("config") .. "/config/tests/query/neotree.lua")

t.describe("Query environment restoration", function()
	t.it("restores editor focus and Query panels through repeated switches and saves", function()
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		local saved_envs, saved_slot = _G._fox_environments, _G._fox_active_env_slot
		local saved_dir, saved_layout = envs.settings.storage_dir, require("fox.query.layout").path
		vim.fn.mkdir(root .. "/one", "p")
		vim.fn.mkdir(root .. "/two", "p")
		envs.settings.storage_dir = root .. "/sessions"
		require("fox.query.layout").path = root .. "/layout.json"
		_G._fox_environments, _G._fox_active_env_slot = {}, 1
		local ok, err = pcall(function()
			vim.api.nvim_set_current_dir(root .. "/one")
			envs.create_environment(1, root .. "/one", "One", false)
			envs.create_environment(2, root .. "/two", "Two", false)
			vim.cmd("enew")
			local editor = vim.api.nvim_get_current_win()
			vim.cmd("Neotree focus dir=" .. vim.fn.fnameescape(root .. "/one"))
			vim.api.nvim_set_current_win(editor)
			envs.switch_environment(2)
			envs.switch_environment(1)
			t.expect(vim.api.nvim_get_current_win()).toBe(editor)
			query.setup()
			for _, view in ipairs({ "standard", "visual" }) do
				query.show(view)
				local state = query.state()
				local buf = state.active
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 42;" })
				state.consoles[buf].result = { sets = { { columns = { "answer" }, rows = { { "42" } } } } }
				query.refresh_view(state)
				for _ = 1, 3 do
					envs.switch_environment(2)
					envs.switch_environment(1)
					vim.wait(200, function()
						return false
					end, 10)
					t.expect(vim.api.nvim_get_current_tabpage()).toBe(state.tab)
					t.expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(buf)
					t.expect(vim.api.nvim_win_get_buf(state.result_win)).toBe(state.result_buf)
					t.expect(vim.api.nvim_win_get_buf(state.side_win)).toBe(state.side_buf)
					t.expect(table.concat(vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false), "\n")).toContain("42")
					for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
						local pane = vim.api.nvim_win_get_buf(win)
						if vim.bo[pane].filetype == "neo-tree" then
							t.expect(vim.b[pane].neo_tree_source).toBe("fox_query")
						end
					end
				end
				envs.save_all()
				t.expect(vim.api.nvim_win_get_buf(state.result_win)).toBe(state.result_buf)
				t.expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(buf)
				t.expect(vim.bo[buf].modified).toBeTruthy()
				query.hide()
				t.expect(vim.api.nvim_get_current_win()).toBe(editor)
				t.expect(envs.get_environment(1).neotree_open).toBeTruthy()
			end
		end)
		for _, name in ipairs({ "one", "two" }) do
			local state = query.states[storage.root(root .. "/" .. name)]
			if state then
				for buf in pairs(state.consoles) do
					vim.bo[buf].modified = false
				end
				query.close_root(state.root)
			end
		end
		vim.cmd("silent! Neotree close")
		_G._fox_environments, _G._fox_active_env_slot = saved_envs, saved_slot
		envs.settings.storage_dir, require("fox.query.layout").path = saved_dir, saved_layout
		vim.api.nvim_set_current_dir(cwd)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)
end)
