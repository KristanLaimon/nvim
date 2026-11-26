local t = require("fox.lib.foxnvim.test")

t.describe("Query SQL editor split", function()
	t.it("executes a saved SQL tab and restores its results and full Query popups across environments", function()
		require("lazy").load({ plugins = { "fox_query", "fox_tabline" } })
		local query, storage = require("fox.query"), require("fox.query.storage")
		local inline, tabs = require("fox.query.inline"), require("fox.ui.tabline")
		local environments = require("plugins.fox.tools.environments")
		local cwd, shada = vim.fn.getcwd(), vim.o.shada
		local root, other = vim.fn.tempname(), vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		vim.fn.mkdir(other, "p")
		vim.api.nvim_set_current_dir(root)
		local first = environments.get_active_slot()
		local second = first == 2 and 3 or 2
		environments.create_environment(second, other, "Other", false)
		local editor_tab, editor = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()

		local function key(lhs)
			local mapping = vim.fn.maparg(lhs, "n", false, true)
			assert(mapping.callback, "missing mapping " .. lhs)
			mapping.callback()
		end
		local function wait_until(predicate, message)
			assert(vim.wait(5000, predicate, 10), message)
		end

		local ok, err = xpcall(function()
			local fixture = vim.fn.stdpath("config") .. "/tests/query/fixture.db"
			assert(vim.uv.fs_copyfile(fixture, root .. "/fixture.db"))
			assert(storage.save(root, "connections.json", {
				profiles = { { id = "local", engine = "sqlite", path = "fixture.db" } },
			}))
			assert(
				storage.write(
					root,
					"queries/example.sql",
					"SELECT name, id FROM things WHERE id = 1 UNION ALL SELECT 'second', 2;\n\nSELECT 42;"
				)
			)
			local sql = query.new("example.sql", "sqlite", false)
			local origin = vim.api.nvim_get_current_buf()
			key("<C-S-l>")
			t.expect(vim.api.nvim_buf_get_lines(0, 6, 7, false)[1]).toContain("[3]   SQL Tab")
			key("3")
			key("<CR>")
			local view = assert(inline.current())
			local owner = view.sql_win
			local item = query.state().consoles[sql]
			t.expect(vim.api.nvim_get_current_tabpage()).toBe(editor_tab)
			t.expect(vim.api.nvim_win_get_buf(editor)).toBe(origin)
			t.expect(tabs.buffers(owner)).toEqual({ sql })
			t.expect(#vim.api.nvim_tabpage_list_wins(editor_tab)).toBe(2)
			wait_until(function()
				return item.metadata and item.client.connected and not item.client.busy
			end, "SQLite metadata unavailable")
			local lines = vim.api.nvim_buf_get_lines(sql, 0, -1, false)
			local first_statement = assert(vim.fn.search("SELECT name", "w"))
			local second_statement = assert(vim.fn.search("SELECT 42", "w"))
			local namespace = vim.api.nvim_get_namespaces().fox_query_statement
			local function check_outline(row)
				vim.api.nvim_win_set_cursor(owner, { row, 0 })
				vim.api.nvim_exec_autocmds("CursorMoved", { buffer = sql })
				wait_until(function()
					local marks = vim.api.nvim_buf_get_extmarks(sql, namespace, 0, -1, { details = true })
					return #marks == 2
						and marks[1][2] == row - 1
						and marks[2][2] == row - 1
						and marks[1][4].virt_lines_above
						and marks[2][4].virt_lines ~= nil
				end, "Statement outline did not follow the SQL cursor")
			end
			check_outline(first_statement)
			check_outline(second_statement)
			check_outline(first_statement)
			local completion = require("fox.query.completion").new()
			local function labels()
				local names = {}
				completion:get_completions({ bufnr = sql, cursor = { first_statement, 8 } }, function(result)
					for _, entry in ipairs(result.items) do
						names[entry.label] = true
					end
				end)
				return names
			end
			t.expect(labels().name).toBe(true)
			local workspace = query.state()
			local metadata = workspace.metadata
			workspace.metadata = { tables = { { key = "unrelated", name = "unrelated" } }, relations = {} }
			vim.api.nvim_buf_set_lines(sql, -1, -1, false, { "-- " .. string.rep("x", 129 * 1024) })
			local large = labels()
			t.expect(large.SELECT).toBe(true)
			t.expect(large.things).toBe(true)
			t.expect(large.unrelated).toBe(nil)
			vim.api.nvim_buf_set_lines(sql, 0, -1, false, lines)
			workspace.metadata = metadata
			vim.api.nvim_win_set_cursor(owner, { first_statement, 0 })

			key("<C-CR>")
			wait_until(function()
				return view.result_win and item.result
			end, "Bottom results did not open")
			t.expect(item.result.sets[1].rows[1]).toEqual({ "fox", "1" })
			t.expect(vim.api.nvim_win_get_config(view.result_win).win).toBe(owner)
			t.expect(vim.api.nvim_win_get_config(view.result_win).anchor).toBe("SW")
			t.expect(vim.api.nvim_get_current_win()).toBe(owner)
			vim.api.nvim_set_current_win(editor)
			key("<C-l>")
			t.expect(vim.api.nvim_get_current_win()).toBe(owner)
			key("<C-j>")
			t.expect(vim.api.nvim_get_current_win()).toBe(view.result_win)
			key("J")
			local first_cell = vim.api.nvim_win_get_cursor(0)
			key("L")
			local next_cell = vim.api.nvim_win_get_cursor(0)
			t.expect(next_cell[1]).toBe(first_cell[1])
			t.expect(next_cell[2] > first_cell[2]).toBe(true)
			key("J")
			t.expect(vim.api.nvim_win_get_cursor(0)[1]).toBe(first_cell[1] + 1)
			key("K")
			t.expect(vim.api.nvim_win_get_cursor(0)).toEqual(next_cell)
			key("H")
			t.expect(vim.api.nvim_win_get_cursor(0)).toEqual(first_cell)
			key("<C-k>")
			t.expect(vim.api.nvim_get_current_win()).toBe(owner)
			key("<C-S-CR>")
			wait_until(function()
				return view.result_popup and vim.api.nvim_win_is_valid(view.result_popup)
			end, "Large results popup did not open")
			local popup = view.result_popup
			assert(environments.switch_environment(second))
			t.expect(vim.api.nvim_win_get_config(popup).hide).toBe(true)
			t.expect(vim.api.nvim_win_is_valid(owner)).toBe(false)
			assert(environments.switch_environment(first))
			owner = view.sql_win
			t.expect(not vim.api.nvim_win_get_config(popup).hide).toBe(true)
			t.expect(vim.api.nvim_get_current_win()).toBe(popup)
			t.expect(vim.api.nvim_win_get_buf(owner)).toBe(sql)
			key("q")
			key("gC")
			local picker = vim.api.nvim_get_current_win()
			assert(environments.switch_environment(second))
			t.expect(vim.api.nvim_win_get_config(picker).hide).toBe(true)
			assert(environments.switch_environment(first))
			owner = view.sql_win
			t.expect(vim.api.nvim_get_current_win()).toBe(picker)
			key("q")

			query.show()
			local state = query.state()
			query.results_popup()
			local query_popup = assert(state.result_popup)
			assert(environments.switch_environment(second))
			t.expect(vim.api.nvim_get_current_tabpage() == state.tab).toBe(false)
			assert(environments.switch_environment(first))
			t.expect(vim.api.nvim_get_current_tabpage()).toBe(state.tab)
			t.expect(vim.api.nvim_get_current_win()).toBe(query_popup)
			t.expect(state.mode).toBe("query")
			query.hide()
			owner = view.sql_win
			vim.api.nvim_set_current_win(owner)
			vim.cmd.FoxQ()
			t.expect(vim.api.nvim_win_is_valid(owner)).toBe(false)
			t.expect(vim.api.nvim_buf_is_valid(sql)).toBe(true)
			t.expect(not vim.t.fox_query_root).toBe(true)

			-- Recover a pane left on Query's placeholder by an older close path.
			vim.cmd("rightbelow vsplit")
			local stranded = vim.api.nvim_get_current_win()
			local placeholder = query.empty(state)
			vim.api.nvim_win_set_buf(stranded, placeholder)
			vim.cmd.FoxQ()
			t.expect(vim.api.nvim_win_is_valid(stranded)).toBe(false)

			query.show()
			vim.api.nvim_set_current_win(state.sql_win)
			vim.cmd.write()
			vim.cmd.FoxQ()
			t.expect(vim.api.nvim_win_is_valid(state.sql_win)).toBe(true)
			t.expect(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(state.sql_win), 0, 1, false)[1])
				.toContain("Select a SQL tab")
			query.hide()
		end, debug.traceback)

		if environments.get_active_slot() ~= first then
			environments.switch_environment(first)
		end
		for buf in pairs(query.state(root).consoles) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modified = false
			end
		end
		query.close_root(root)
		vim.api.nvim_set_current_dir(cwd)
		vim.o.shada = shada
		vim.fn.delete(root, "rf")
		vim.fn.delete(other, "rf")
		assert(ok, err)
	end)
end)
