local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local query, storage = require("fox.query"), require("fox.query.storage")

local function project(check)
	local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
	local layout = require("fox.query.layout")
	local old_layout_path = layout.path
	layout.path = root .. "/global-layout.json"
	vim.fn.mkdir(root, "p")
	vim.api.nvim_set_current_dir(root)
	query.setup()
	local ok, err = pcall(check, root)
	local state = query.state()
	for buf, item in pairs(state.consoles) do
		if item.client then
			item.client:close()
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.bo[buf].modified = false
		end
	end
	query.close_root(root)
	layout.path = old_layout_path
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].fox_query_root == storage.root(root) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	vim.wait(100)
	vim.api.nvim_set_current_dir(cwd)
	vim.fn.delete(root, "rf")
	if not ok then
		error(err)
	end
end

describe("FoxQuerier live workflow", function()
	it("renders bordered ASCII result tables and keeps row actions aligned across sets", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			local first = { columns = { "actualRank" }, rows = { { "CA" }, { "BR" } } }
			local second = { columns = { "id", "value" }, rows = { { "1", vim.NIL }, { "2", "表\ntext" } } }
			item.result = { sets = { first, second, { columns = { "empty" }, rows = {} } } }
			query.refresh_view(state)
			local lines = vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false)
			expect(lines[4]).toBe("+------------+")
			expect(lines[5]).toBe("| actualRank |")
			expect(lines[7]).toBe("| CA         |")
			expect(table.concat(lines, "\n")).toContain("NULL")
			expect(table.concat(lines, "\n")).toContain("表\\ntext")
			vim.api.nvim_set_current_win(state.result_win)
			for row, line in ipairs(lines) do
				vim.api.nvim_win_set_cursor(0, { row, 0 })
				local set, value = query.row()
				if line:find("| CA ", 1, true) then
					expect(set).toBe(first)
					expect(value).toBe(first.rows[1])
				elseif line:find("| 1 ", 1, true) then
					expect(set).toBe(second)
					expect(value).toBe(second.rows[1])
				elseif line:sub(1, 1) == "+" or line:find("actualRank", 1, true) then
					expect(value).toBeNil()
				end
			end
		end)
	end)

	it("persists only pane and popup geometry across projects", function()
		project(function(root)
			local layout = require("fox.query.layout")
			query.show("visual")
			local state = query.state()
			vim.api.nvim_win_set_width(state.side_win, math.floor(vim.o.columns * 0.6))
			vim.api.nvim_win_set_height(state.result_win, 4)
			query.help()
			local popup = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_width(popup, 48)
			vim.api.nvim_exec_autocmds("WinResized", {})
			expect(vim.wait(1000, function()
				return vim.fn.filereadable(layout.path) == 1
			end, 10)).toBeTruthy()
			local saved = require("fox.core.store").load(layout.path, {})
			expect(saved.menus.help.width).toBe(48)
			expect(saved.visual.side).toBe(vim.api.nvim_win_get_width(state.side_win) / vim.o.columns)
			expect(saved.profile).toBeNil()
			expect(saved.sql).toBeNil()
			vim.api.nvim_win_close(popup, true)
			query.hide()
			vim.fn.mkdir(root .. "/other", "p")
			vim.api.nvim_set_current_dir(root .. "/other")
			query.show("visual")
			expect(vim.api.nvim_win_get_width(query.state().side_win)).toBe(math.floor(vim.o.columns * saved.visual.side))
			expect(vim.api.nvim_win_get_height(query.state().result_win)).toBe(4)
			query.help()
			expect(vim.api.nvim_win_get_width(0)).toBe(48)
			vim.api.nvim_win_close(0, true)
			query.close_root(root .. "/other")
			vim.api.nvim_set_current_dir(root)
		end)
	end)

	it("edits and deletes connection profiles without deleting databases or notes", function()
		project(function(root)
			query.show()
			local state = query.state()
			local profile = { id = "original", engine = "sqlite", path = "selected.db" }
			vim.fn.writefile({}, root .. "/selected.db")
			storage.save(root, "connections.json", { profiles = { profile } })
			storage.write(root, "notes/keep.md", "keep")
			local old_select, old_input, old_connect = vim.ui.select, vim.ui.input, query.connect
			local old_lazy, old_explorer = package.loaded.lazy, package.loaded["plugins.fox.tools.file_explorer"]
			local connected
			local ok, err = pcall(function()
				package.loaded.lazy = { load = function() end }
				package.loaded["plugins.fox.tools.file_explorer"] = {
					open_desktop_explorer = function(opts)
						opts.on_select_file(root .. "/selected.db")
					end,
				}
				vim.ui.select = function(items, _, callback)
					callback(items[1], 1)
				end
				vim.ui.input = function(opts, callback)
					expect(opts.default).toBe("original")
					callback("renamed")
				end
				query.connect = function(value)
					connected = value
				end
				query.add_profile(profile)
				local profiles = storage.profiles(root)
				expect(#profiles).toBe(1)
				expect(profiles[1].id).toBe("renamed")
				expect(connected.id).toBe("renamed")
				query.delete_profile(profiles[1], state)
				expect(#storage.profiles(root)).toBe(0)
				expect(vim.fn.filereadable(root .. "/selected.db")).toBe(1)
				expect(storage.read(root, "notes/keep.md")).toBe("keep")
			end)
			vim.ui.select, vim.ui.input, query.connect = old_select, old_input, old_connect
			package.loaded.lazy, package.loaded["plugins.fox.tools.file_explorer"] = old_lazy, old_explorer
			if not ok then
				error(err)
			end
		end)
	end)

	it("binds native and terminal escape keys to the real completion and run actions", function()
		project(function()
			query.show()
			local old_lazy, old_blink, old_mode, old_run =
				package.loaded.lazy, package.loaded["blink.cmp"], vim.api.nvim_get_mode, query.run
			local shown, runs = 0, 0
			local ok, err = pcall(function()
				package.loaded.lazy = { load = function() end }
				package.loaded["blink.cmp"] = {
					show = function(opts)
						expect(opts.providers).toEqual({ "fox_query" })
						shown = shown + 1
					end,
				}
				vim.api.nvim_get_mode = function()
					return { mode = "i" }
				end
				for _, key in ipairs({ "<C-Space>", "<C-x><C-o>", "\27[32;5u", "\27[27;5;32~" }) do
					vim.fn.maparg(key, "i", false, true).callback()
				end
				expect(shown).toBe(4)
				query.run = function(kind)
					expect(kind).toBe("statement")
					runs = runs + 1
				end
				for _, mode in ipairs({ "n", "i" }) do
					for _, key in ipairs({ "<C-CR>", "<F5>", "\27[13;5u", "\27[27;5;13~" }) do
						vim.fn.maparg(key, mode, false, true).callback()
					end
				end
				expect(runs).toBe(8)
			end)
			package.loaded.lazy, package.loaded["blink.cmp"], vim.api.nvim_get_mode, query.run =
				old_lazy, old_blink, old_mode, old_run
			if not ok then
				error(err)
			end
		end)
	end)

	it("only schedules complete SELECT statements and does not repeat unchanged SQL", function()
		project(function()
			query.show()
			local state, old_run = query.state(), query.run
			local item, calls = state.consoles[state.active], {}
			item.profile, item.client = { engine = "sqlite" }, { connected = true, close = function() end }
			query.run = function(_, text, _, _, automatic)
				calls[#calls + 1] = { text, automatic }
			end
			local ok, err = pcall(function()
				for _, text in ipairs({
					"UPDATE t SET x=1",
					"DELETE FROM t",
					"INSERT INTO t VALUES(1)",
					"WITH x AS (SELECT 1) SELECT * FROM x",
					"SELECT 'unfinished",
					"SELECT * FROM things t INNER JOIN other o",
					"SELECT * FROM things t INNER JOIN other o ON",
				}) do
					vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { text })
					query.autorun(state)
				end
				expect(#calls).toBe(0)
				vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT 7 AS value;" })
				query.autorun(state)
				query.autorun(state)
				expect(#calls).toBe(1)
				expect(calls[1][2]).toBeTruthy()
				state.autorun = false
				vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT 8;" })
				query.autorun(state)
				expect(#calls).toBe(1)
			end)
			query.run = old_run
			if not ok then
				error(err)
			end
		end)
	end)

	it("debounces real SQLite SELECTs, skips parameter prompts, restores connections, and marks failures", function()
		project(function(root)
			local fixture = vim
				.system({
					require("fox.query.client").python(),
					"-B",
					"-c",
					"import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('CREATE TABLE things(id INTEGER PRIMARY KEY)'); c.commit(); c.close()",
					root .. "/fixture.db",
				}, { text = true })
				:wait()
			expect(fixture.code).toBe(0)
			local profile = { id = "local", engine = "sqlite", path = "fixture.db" }
			storage.save(root, "connections.json", { profiles = { profile } })
			query.show("visual")
			local state = query.state()
			local item = state.consoles[state.active]
			query.connect(profile, state)
			expect(vim.wait(5000, function()
				return item.metadata and item.client.connected and not item.client.busy
			end, 10)).toBeTruthy()
			local function type_sql(text)
				vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { text })
				vim.api.nvim_exec_autocmds("TextChangedI", { buffer = state.active })
			end
			type_sql("SELECT 1 AS answer;")
			type_sql("SELECT 2 AS answer;")
			vim.wait(100)
			expect(item.result).toBeNil()
			expect(vim.wait(4000, function()
				return item.result and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.execution).toBe(1)
			expect(item.result.sets[1].rows[1][1]).toBe("2")
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT 11 AS first;", "", "SELECT 22 AS second;" })
			vim.api.nvim_win_set_cursor(state.sql_win, { 3, 7 })
			vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.active })
			expect(vim.wait(4000, function()
				return item.execution == 2 and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.result.sets[1].rows[1][1]).toBe("22")
			vim.api.nvim_win_set_cursor(state.sql_win, { 1, 7 })
			vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = state.active })
			expect(vim.wait(4000, function()
				return item.execution == 3 and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.result.sets[1].rows[1][1]).toBe("11")
			query.show("standard")
			vim.api.nvim_set_current_win(state.sql_win)
			vim.fn.maparg("<C-CR>", "n", false, true).callback()
			expect(vim.wait(2000, function()
				return item.execution == 4 and not item.client.busy
			end, 10)).toBeTruthy()
			type_sql("SELECT ? AS answer;")
			query.autorun(state)
			expect(vim.wait(2000, function()
				return not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.execution).toBe(4)
			expect(item.status).toContain("Parameters needed")
			type_sql("SELECT 1 INTO dangerous;")
			query.autorun(state)
			expect(vim.wait(2000, function()
				return not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.execution).toBe(4)
			expect(item.status).toContain("Read-only")
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "" })
			local saved = storage.load(root, "private/session.json")
			expect(saved.profile).toBe("local")
			item.client:close()
			item.client, item.profile, item.metadata, item.restore_attempted = nil, nil, nil, nil
			query.restore_connection(state)
			expect(vim.wait(5000, function()
				return item.client and item.client.connected and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.profile.id).toBe("local")
			query.connect({ id = "missing", engine = "sqlite", path = "missing.db" }, state)
			expect(vim.wait(5000, function()
				return state.connection_status.missing == "failed"
			end, 10)).toBeTruthy()
			expect(vim.api.nvim_win_get_config(0).relative ~= "").toBeTruthy()
			vim.api.nvim_win_close(0, true)
			storage.save(
				root,
				"connections.json",
				{ profiles = { { id = "missing", engine = "sqlite", path = "missing.db" } } }
			)
			query.draw_connections(state)
			expect(table.concat(vim.api.nvim_buf_get_lines(state.connections_buf, 0, -1, false), "\n")).toContain(
				"[Can't connect] missing"
			)
		end)
	end)

	it("keeps results below SQL and defaults to a 30/70 editor/diagram split", function()
		project(function()
			query.show("standard")
			local state = query.state()
			expect(vim.api.nvim_win_is_valid(state.connections_win)).toBeTruthy()
			expect(vim.api.nvim_win_get_position(state.connections_win)[2] < vim.api.nvim_win_get_position(state.sql_win)[2]).toBeTruthy()
			query.show("visual")
			expect(state.connections_win).toBeNil()
			expect(vim.api.nvim_win_get_position(state.result_win)[1] > vim.api.nvim_win_get_position(state.sql_win)[1]).toBeTruthy()
			expect(math.abs(vim.api.nvim_win_get_width(state.side_win) - vim.o.columns * 0.7) < 4).toBeTruthy()
		end)
	end)

	it("shows dim unused columns and FK candidates without treating hints as actual predicates", function()
		local metadata = {
			tables = {
				{ key = "kisses", name = "kisses", columns = { { name = "id" }, { name = "player_id" }, { name = "unused" } } },
				{ key = "players", name = "players", columns = { { name = "id" }, { name = "name" } } },
			},
			relations = {
				{
					name = "player",
					source = "kisses",
					target = "players",
					columns = { { source = "player_id", target = "id" } },
				},
			},
		}
		local graph = require("fox.query.sql").analyze("SELECT k.id FROM kisses k INNER JOIN players p", metadata)
		local lines, styles = require("fox.query.render").graph(graph, metadata, 90)
		local text = table.concat(lines, "\n")
		expect(text).toContain("unused")
		expect(text).toContain(" ?  player_id")
		expect(graph.edges[1].predicate).toBeNil()
		local dim, hint = false, false
		for _, style in ipairs(styles) do
			if lines[style[1] + 1]:find("unused", 1, true) and style[2] == "Comment" then
				dim = true
			end
			if style[2] == "DiagnosticHint" then
				hint = true
			end
		end
		expect(dim).toBeTruthy()
		expect(hint).toBeTruthy()
		expect(text:find("Possible M:N bridge", 1, true)).toBeNil()
	end)
end)
