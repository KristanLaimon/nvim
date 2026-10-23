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
	it("manages nested SQL files and folders without losing open edits or recreating old paths", function()
		project(function(root)
			query.show("standard")
			local state, files = query.state(), require("fox.query.files")
			local old_input, old_select = vim.ui.input, query.select
			local value, choice = nil, "Delete"
			local ok, err = pcall(function()
				vim.ui.input = function(_, callback)
					callback(value)
				end
				query.select = function(_, _, callback)
					callback(choice)
				end
				local function select(relative)
					query.refresh_view(state)
					vim.api.nvim_set_current_win(state.queries_win)
					for row, entry in pairs(state.query_nodes) do
						if entry.relative == relative then
							vim.api.nvim_win_set_cursor(0, { row, 0 })
							return
						end
					end
					error("SQL entry missing: " .. relative)
				end
				vim.api.nvim_set_current_win(state.queries_win)
				value = "reports"
				vim.fn.maparg("A", "n", false, true).callback()
				select("reports")
				value = "reports/monthly"
				vim.fn.maparg("a", "n", false, true).callback()
				local buf = state.active
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 42;" })
				select("reports/monthly.sql")
				value = "reports/renamed.sql"
				vim.fn.maparg("r", "n", false, true).callback()
				expect(vim.bo[buf].modified).toBeTruthy()
				expect(vim.b[buf].fox_query_document).toBe("queries/reports/renamed.sql")
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("write")
				end)
				expect(storage.read(root, "queries/reports/renamed.sql")).toBe("SELECT 42;")
				expect(storage.read(root, "queries/reports/monthly.sql")).toBeNil()
				expect(files.rename(state, "reports", "archive")).toBeTruthy()
				expect(files.rename(state, "archive", "reports")).toBeTruthy()
				expect(files.rename(state, "reports", "archive")).toBeTruthy()
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 43;" })
				expect(files.delete(state, "archive")).toBeNil()
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("write")
				end)
				expect(storage.read(root, "queries/archive/renamed.sql")).toBe("SELECT 43;")
				expect(storage.read(root, "queries/reports/renamed.sql")).toBeNil()
				expect(query.workspace_save("nested-sql")).toBeTruthy()
				query.workspace_load("nested-sql")
				state = query.state()
				local restored
				for console in pairs(state.consoles) do
					if vim.b[console].fox_query_document == "queries/archive/renamed.sql" then
						restored = console
					end
				end
				expect(restored ~= nil).toBeTruthy()
				state.query_expanded.archive = true
				select("archive/renamed.sql")
				state.consoles[restored].client = { busy = true }
				expect(files.delete(state, "archive")).toBeNil()
				state.consoles[restored].client = nil
				choice = "Cancel"
				vim.fn.maparg("d", "n", false, true).callback()
				expect(storage.read(root, "queries/archive/renamed.sql")).toBe("SELECT 43;")
				choice = "Delete"
				vim.fn.maparg("d", "n", false, true).callback()
				expect(vim.api.nvim_buf_is_valid(restored)).toBeFalsy()
				expect(storage.read(root, "queries/archive/renamed.sql")).toBeNil()
				expect(files.delete(state, "archive")).toBeTruthy()
				expect(vim.fn.isdirectory(storage.path(root, "queries/archive"))).toBe(0)
			end)
			vim.ui.input, query.select = old_input, old_select
			if not ok then
				error(err)
			end
		end)
	end)

	it("rejects SQL file escapes, overwrites, symlinks, and deletion of modified queries", function()
		project(function(root)
			query.show()
			local state, files = query.state(), require("fox.query.files")
			for _, name in ipairs({ "../outside.sql", "/outside.sql", "C:/outside.sql", "./outside.sql", "a/../outside.sql" }) do
				expect(files.create(state, name, false)).toBeNil()
				expect(files.rename(state, "one.sql", name)).toBeNil()
				expect(files.delete(state, name)).toBeNil()
			end
			expect(files.create(state, "one.sql", false)).toBeTruthy()
			expect(files.create(state, "one.sql", false)).toBeNil()
			expect(files.create(state, "two.sql", false)).toBeTruthy()
			expect(files.rename(state, "one.sql", "two.sql")).toBeNil()
			local buf = query.new("one.sql")
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 'unsaved';" })
			expect(files.delete(state, "one.sql")).toBeNil()
			expect(vim.api.nvim_buf_is_valid(buf)).toBeTruthy()
			expect(files.create(state, "folder", true)).toBeTruthy()
			expect(files.rename(state, "folder", "folder/child")).toBeNil()
			local uv = vim.uv or vim.loop
			local outside = root .. "/outside"
			vim.fn.mkdir(outside, "p")
			local link = storage.path(root, "queries/folder/link")
			if uv.fs_symlink(outside, link, { dir = true, junction = vim.fn.has("win32") == 1 }) then
				expect(files.path(root, "folder/link/outside.sql")).toBeNil()
				expect(files.delete(state, "folder")).toBeNil()
				uv.fs_unlink(link)
			end
		end)
	end)

	it("keeps table details in the inspector and relationship maps independent of pane geometry", function()
		project(function()
			query.show("standard")
			local state = query.state()
			local item = { key = "Season", name = "Season", columns = { { name = "id", type = "INTEGER" } } }
			state.metadata = { tables = { item }, relations = {} }
			state.consoles[state.active].metadata = state.metadata
			query.refresh_view(state)
			vim.api.nvim_set_current_win(state.side_win)
			for row, object in pairs(state.objects) do
				if object == item then
					vim.api.nvim_win_set_cursor(0, { row, 0 })
				end
			end
			vim.fn.maparg("<CR>", "n", false, true).callback()
			expect(state.selected).toBe("Season")
			vim.fn.maparg("q", "n", false, true).callback()
			query.refresh_view(state)
			expect(table.concat(vim.api.nvim_buf_get_lines(state.side_buf, 0, -1, false), "\n"):find("INDEXES", 1, true)).toBeNil()
			for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(state.side_buf, "n")) do
				expect(mapping.lhs == "/" or mapping.lhs == "n").toBeFalsy()
			end
			local sizes = {}
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
				sizes[win] = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }
			end
			query.graph(false)
			expect(vim.api.nvim_win_get_config(0).relative ~= "").toBeTruthy()
			for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
				expect(mapping.lhs == "/").toBeFalsy()
			end
			vim.fn.maparg("q", "n", false, true).callback()
			for win, size in pairs(sizes) do
				expect(vim.api.nvim_win_get_width(win)).toBe(size[1])
				expect(vim.api.nvim_win_get_height(win)).toBe(size[2])
			end
		end)
	end)

	it("labels JOINs with real column mappings and suggests unique table initials", function()
		project(function()
			query.show("visual")
			local state, old_select, old_input = query.state(), query.select, vim.ui.input
			local metadata = {
				engine = "sqlite",
				tables = {
					{ key = "PlayerKisses", name = "PlayerKisses", columns = { { name = "member_1" }, { name = "member_2" } } },
					{ key = "Player", name = "Player", columns = { { name = "id" } } },
				},
				relations = {},
			}
			for at = 1, 2 do
				metadata.relations[at] = {
					name = "PlayerKisses:" .. (at - 1),
					source = "PlayerKisses",
					target = "Player",
					columns = { { source = "member_" .. at, target = "id" } },
				}
			end
			local buf = state.active
			state.metadata, state.consoles[buf].metadata = metadata, metadata
			state.consoles[buf].profile = { id = "offline", engine = "sqlite" }
			state.autorun = false
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT * FROM PlayerKisses;" })
			local labels, aliases = {}, {}
			local ok, err = pcall(function()
				query.select = function(items, opts, callback)
					if opts.format_item then
						for _, candidate in ipairs(items) do
							labels[#labels + 1] = opts.format_item(candidate)
						end
					end
					callback(items[1])
				end
				vim.ui.input = function(opts, callback)
					aliases[#aliases + 1] = opts.default
					callback(opts.default)
				end
				query.insert_join(metadata.tables[2])
				query.insert_join(metadata.tables[2])
				expect(labels[1]).toBe("PlayerKisses.member_1 = Player.id")
				expect(labels[2]).toBe("PlayerKisses.member_2 = Player.id")
				expect(aliases).toEqual({ "p", "p2" })
				expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain(
					"INNER JOIN Player AS p ON PlayerKisses.member_1 = p.id"
				)
			end)
			query.select, vim.ui.input = old_select, old_input
			if not ok then
				error(err)
			end
		end)
	end)

	it("registers query keys without collisions and keeps result actions scoped to results", function()
		project(function()
			local registry = require("fox.core.keymap_registry")
			registry.install()
			local previous = #registry.collisions
			query.show("standard")
			query.show("visual")
			query.show("standard")
			query.new("keys.sql")
			query.new("keys.sql")
			expect(#registry.collisions).toBe(previous)
			local state = query.state()
			local old_results, old_follow, old_help = query.results, query.follow_row, query.help
			local results, follow, help = 0, 0, 0
			local ok, err = pcall(function()
				query.results = function()
					results = results + 1
				end
				query.follow_row = function()
					follow = follow + 1
				end
				query.help = function()
					help = help + 1
				end
				vim.api.nvim_set_current_win(state.sql_win)
				vim.fn.maparg("gR", "n", false, true).callback()
				vim.fn.maparg("<F1>", "n", false, true).callback()
				vim.api.nvim_set_current_win(state.result_win)
				vim.fn.maparg("gR", "n", false, true).callback()
				expect(results).toBe(1)
				expect(follow).toBe(1)
				expect(help).toBe(1)
			end)
			query.results, query.follow_row, query.help = old_results, old_follow, old_help
			if not ok then
				error(err)
			end
		end)
	end)

	it("browses saved SQL, switches tabs, and leaves an empty editor after the last close", function()
		project(function(root)
			storage.write(root, "queries/saved.sql", "SELECT 42;")
			query.show("standard")
			local state = query.state()
			expect(
				vim.api.nvim_win_get_position(state.queries_win)[1] < vim.api.nvim_win_get_position(state.connections_win)[1]
			).toBeTruthy()
			local lines = vim.api.nvim_buf_get_lines(state.queries_buf, 0, -1, false)
			local selected
			for row, line in ipairs(lines) do
				if line:find("saved.sql", 1, true) then
					selected = row
				end
			end
			vim.api.nvim_set_current_win(state.queries_win)
			vim.api.nvim_win_set_cursor(0, { selected, 0 })
			vim.fn.maparg("<CR>", "n", false, true).callback()
			local saved = state.active
			expect(vim.api.nvim_buf_get_lines(saved, 0, -1, false)[1]).toBe("SELECT 42;")
			query.new("second.sql")
			vim.fn.maparg("<A-h>", "n", false, true).callback()
			expect(state.active).toBe(saved)
			local buffers = vim.tbl_keys(state.consoles)
			for _, buf in ipairs(buffers) do
				query.close_buffer(buf, true)
			end
			expect(state.active).toBeNil()
			expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(state.empty_buf)
			expect(vim.api.nvim_buf_get_lines(state.empty_buf, 0, -1, false)[1]).toContain("create a new one with gN")
			query.show("visual")
			expect(state.active).toBeNil()
			expect(storage.read(root, "queries/saved.sql")).toBe("SELECT 42;")
		end)
	end)

	it("keeps status across the bottom, copies the full error, and moves connection hints below entries", function()
		project(function(root)
			storage.save(root, "connections.json", { profiles = { { id = "test", engine = "sqlite", path = "db" } } })
			query.show("standard")
			local state = query.state()
			local item = state.consoles[state.active]
			item.status, item.error_detail = "failed | 0.02s", "SQL error\nfull diagnostic with 100% detail"
			query.refresh_view(state)
			expect(vim.api.nvim_win_get_width(state.activity_win)).toBe(vim.o.columns)
			expect(vim.api.nvim_win_get_position(state.activity_win)[1] > vim.api.nvim_win_get_position(state.result_win)[1]).toBeTruthy()
			expect(vim.api.nvim_buf_get_lines(state.activity_buf, 0, -1, false)[1]).toContain("full diagnostic")
			local lines = vim.api.nvim_buf_get_lines(state.connections_buf, 0, -1, false)
			expect(lines[2]).toContain("test")
			expect(lines[#lines - 2]).toBe("------")
			expect(lines[#lines]).toBe("Enter Connect  D Disconnect")
			local old_setreg, old_mouse, registers = vim.fn.setreg, vim.fn.getmousepos, {}
			local ok, err = pcall(function()
				vim.fn.setreg = function(register, text)
					registers[register] = text
				end
				vim.fn.getmousepos = function()
					return { winid = state.activity_win }
				end
				vim.api.nvim_set_current_win(state.sql_win)
				vim.fn.maparg("<LeftMouse>", "n", false, true).callback()
				expect(registers['"']).toBe(item.error_detail)
				expect(registers["+"]).toBe(item.error_detail)
			end)
			vim.fn.setreg, vim.fn.getmousepos = old_setreg, old_mouse
			if not ok then
				error(err)
			end
		end)
	end)

	it("navigates result cells through Unicode values and multiple result sets", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			item.result = {
				sets = {
					{ columns = { "name", "id" }, rows = { { "表", "1" }, { "fox", "2" } } },
					{ columns = { "id" }, rows = { { "3" } } },
				},
			}
			query.refresh_view(state)
			vim.api.nvim_set_current_win(state.result_win)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			local function move(key)
				vim.fn.maparg(key, "n", false, true).callback()
			end
			move("L")
			expect(vim.fn.virtcol(".")).toBe(10)
			expect(query.row().rows[1][1]).toBe("表")
			move("J")
			local _, row = query.row()
			expect(row[2]).toBe("2")
			move("H")
			expect(vim.fn.virtcol(".")).toBe(3)
			move("J")
			_, row = query.row()
			expect(row[1]).toBe("3")
			move("K")
			_, row = query.row()
			expect(row[1]).toBe("fox")
		end)
	end)

	it("validates and persists the diagram column limit in the project", function()
		project(function(root)
			query.show("visual")
			local state, old_input = query.state(), vim.ui.input
			local ok, err = pcall(function()
				vim.ui.input = function(_, callback)
					callback("0")
				end
				query.column_limit()
				expect(state.diagram_columns).toBe(15)
				vim.ui.input = function(_, callback)
					callback("23")
				end
				query.column_limit()
				expect(storage.load(root, "settings.json", {}).diagram_columns).toBe(23)
				query.close_root(root)
				expect(query.state().diagram_columns).toBe(23)
			end)
			vim.ui.input = old_input
			if not ok then
				error(err)
			end
		end)
	end)

	it("shows 15 diagram columns by default and promotes selected columns without mutating metadata", function()
		local columns = {}
		for at = 1, 20 do
			columns[at] = { name = "prop" .. at }
		end
		local metadata = { tables = { { key = "player", name = "player", columns = columns } }, relations = {} }
		local graph = require("fox.query.sql").analyze("SELECT prop20 FROM player", metadata)
		local render = require("fox.query.render")
		local lines = render.graph(graph, metadata, 80)
		local text = table.concat(lines, "\n")
		expect(text).toContain("*   prop20")
		expect(text:find("prop20", 1, true) < text:find("prop1 ", 1, true)).toBeTruthy()
		expect(text).toContain("5 more")
		expect(text:find("Column markers", 1, true)).toBeNil()
		expect(columns[1].name).toBe("prop1")
		text = table.concat(render.graph(graph, metadata, 80, 20), "\n")
		expect(text:find("more;", 1, true)).toBeNil()
	end)

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
			expect(lines[1]).toBe("+------------+")
			expect(lines[2]).toBe("| actualRank |")
			expect(lines[4]).toBe("| CA         |")
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
			local old_select, old_input, old_connect = query.select, vim.ui.input, query.connect
			local old_lazy, old_explorer = package.loaded.lazy, package.loaded["plugins.fox.tools.file_explorer"]
			local connected
			local ok, err = pcall(function()
				package.loaded.lazy = { load = function() end }
				package.loaded["plugins.fox.tools.file_explorer"] = {
					open_desktop_explorer = function(opts)
						opts.on_select_file(root .. "/selected.db")
					end,
				}
				query.select = function(items, _, callback)
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
			query.select, vim.ui.input, query.connect = old_select, old_input, old_connect
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
