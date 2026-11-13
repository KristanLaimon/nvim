local t = require("fox.lib.foxnvim.test")
local envs = require("plugins.fox.tools.environments")

t.describe("deferred environment UI restoration", function()
	t.it("ignores stale switches and respects panels opened by the user", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local saved_envs, saved_slot = _G._fox_environments, _G._fox_active_env_slot
		local saved_terms, saved_manager = _G._fox_terminals, _G.TerminalManager
		local saved_selected, saved_restore = _G._fox_selected_terminal, envs._restore_token
		local cwd = vim.fn.getcwd()
		local saved_schedule = vim.schedule
		local key = "plugins.fox.git.git_center"
		local saved_center, saved_query = package.loaded[key], package.loaded["fox.query"]
		local queue, terminal_opens, git_opens = {}, 0, 0
		local buffers = {}
		vim.cmd("tabnew")
		local tab = vim.api.nvim_get_current_tabpage()
		local ok, err = pcall(function()
			_G._fox_environments, _G._fox_active_env_slot, _G._fox_terminals = {}, 1, {}
			package.loaded["fox.query"] = nil
			package.loaded[key] = {
				is_open = function()
					return false
				end,
				open_git_center = function()
					git_opens = git_opens + 1
				end,
			}
			_G.TerminalManager = {
				open_terminal = function(slot)
					terminal_opens = terminal_opens + 1
					local term = _G._fox_terminals[slot]
					term.win = vim.api.nvim_open_win(term.buf, true, { split = "below", height = 3 })
				end,
				toggle_selected_terminal = function() end,
			}
			for slot = 1, 3 do
				envs.create_environment(slot, root, "Test " .. slot, false)
			end
			vim.schedule = function(fn)
				queue[#queue + 1] = fn
			end
			local function drain()
				local pending = queue
				queue = {}
				for _, fn in ipairs(pending) do
					fn()
				end
			end
			local function show_terminal(slot)
				local buf = vim.api.nvim_create_buf(false, true)
				buffers[#buffers + 1] = buf
				vim.b[buf].fox_is_multi_term = true
				vim.b[buf].fox_env_slot = envs.get_active_slot()
				_G._fox_selected_terminal = slot
				_G._fox_terminals[slot] = { buf = buf }
				_G.TerminalManager.open_terminal(slot)
				return buf
			end
			local first = show_terminal(4)
			envs.switch_environment(2)
			t.expect(_G._fox_selected_terminal).toBe(1)
			local second = show_terminal(7)
			envs.switch_environment(1)
			drain()
			t.expect(vim.api.nvim_get_current_buf()).toBe(first)
			t.expect(vim.fn.bufwinid(second)).toBe(-1)

			envs.switch_environment(2)
			envs.switch_environment(3)
			drain()
			t.expect(terminal_opens).toBe(3)
			t.expect(vim.fn.bufwinid(second)).toBe(-1)

			_G._fox_environments[2].git_center_open = true
			envs.switch_environment(2)
			local panel = vim.api.nvim_create_buf(false, true)
			local win = vim.api.nvim_open_win(panel, true, { relative = "editor", row = 2, col = 2, width = 20, height = 3 })
			drain()
			t.expect(git_opens).toBe(0)
			t.expect(vim.api.nvim_get_current_win()).toBe(win)
			t.expect(vim.fn.bufwinid(second) ~= -1).toBe(true)
			vim.api.nvim_win_close(win, true)
			vim.api.nvim_buf_delete(panel, { force = true })
			vim.api.nvim_win_close(vim.fn.bufwinid(second), true)
			envs.switch_environment(3)
			_G._fox_environments[2].git_center_open = true
			envs.switch_environment(2)
			drain()
			t.expect(git_opens).toBe(1)
			t.expect(vim.fn.bufwinid(second)).toBe(-1)
		end)
		vim.schedule = saved_schedule
		_G._fox_environments, _G._fox_active_env_slot = saved_envs, saved_slot
		_G._fox_terminals, _G.TerminalManager = saved_terms, saved_manager
		_G._fox_selected_terminal, envs._restore_token = saved_selected, saved_restore
		package.loaded[key], package.loaded["fox.query"] = saved_center, saved_query
		vim.api.nvim_set_current_dir(cwd)
		if vim.api.nvim_tabpage_is_valid(tab) then
			vim.api.nvim_set_current_tabpage(tab)
			vim.cmd("tabclose!")
		end
		for _, buf in ipairs(buffers) do
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
