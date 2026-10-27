local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local query, storage = require("fox.query"), require("fox.query.storage")
dofile(vim.fn.stdpath("config") .. "/config/tests/query/neotree.lua")

local function project(check)
	local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
	local old_input = vim.ui.input
	local layout = require("fox.query.layout")
	local old_layout_path = layout.path
	layout.path = root .. "/global-layout.json"
	vim.fn.mkdir(root, "p")
	vim.api.nvim_set_current_dir(root)
	query.setup()
	local ok, err = pcall(check, root)
	vim.ui.input = old_input
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
	it("uses Shift+K for compact column types, the existing table inspector and function documentation", function()
		project(function()
			query.show("standard")
			local state, original_preview = query.state(), vim.lsp.util.open_floating_preview
			local schema = {
				tables = {
					{
						key = "alumnos",
						name = "alumnos",
						columns = { { name = "nombre", type = "VARCHAR(100)" }, { name = "año_ingreso", type = "SMALLINT" } },
					},
					{ key = "carreras", name = "carreras", columns = { { name = "nombre", type = "VARCHAR(50)" } } },
				},
				relations = {},
			}
			state.consoles[state.active].metadata = schema
			local received, options
			local ok, err = pcall(function()
				vim.lsp.util.open_floating_preview = function(lines, _, opts)
					received, options = lines, opts
				end
				local text = "SELECT ca.nombre, a.año_ingreso, COUNT(*) FROM alumnos a JOIN carreras ca ON 1 = 1"
				vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { text })
				vim.api.nvim_set_current_win(state.sql_win)
				local function hover(fragment)
					vim.api.nvim_win_set_cursor(0, { 1, assert(text:find(fragment, 1, true)) - 1 })
					vim.fn.maparg("K", "n", false, true).callback()
				end
				hover("ca.nombre")
				expect(received).toEqual({ "carreras.nombre : VARCHAR(50)" })
				expect(options.max_height).toBe(4)
				hover("a.año_ingreso")
				expect(received).toEqual({ "alumnos.año_ingreso : SMALLINT" })
				hover("COUNT")
				expect(table.concat(received, "\n")).toContain("COUNT(")
				expect(table.concat(received, "\n")).toContain("Example:")
				hover("carreras ca")
				expect(state.inspectors[vim.api.nvim_get_current_win()]).toBeTruthy()
				expect(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")).toContain("carreras")
				expect(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")).toContain("VARCHAR(50)")
				vim.fn.maparg("q", "n", false, true).callback()
				expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
			end)
			vim.lsp.util.open_floating_preview = original_preview
			assert(ok, err)
		end)
	end)

	it("keeps Query pins separate, restores them and cycles in displayed order", function()
		project(function(root)
			local tabs = require("fox.ui.tabline")
			local pins = require("plugins.fox.ui.pinned_tabs")
			query.show("standard")
			local first = query.state().active
			vim.cmd("write")
			local second = query.new("second.sql", "mysql")
			vim.cmd("write")
			local third = query.new("third.sql", "mysql")
			vim.cmd("write")
			pins.toggle_pin()
			expect(tabs.is_pinned(third)).toBe(true)
			expect(storage.load(root, "private/tab-pins.json")).toEqual({ "queries/third.sql" })
			expect(vim.fn.filereadable(root .. "/.foxnvim/pins.json")).toBe(0)
			expect(tabs.buffers()).toEqual({ third, first, second })
			query.cycle(1)
			expect(query.state().active).toBe(first)
			query.cycle(-1)
			expect(query.state().active).toBe(third)
			local renamed, rename_err = require("fox.query.files").rename(query.state(), "third.sql", "pinned.sql")
			expect(renamed or rename_err).toBe(true)
			expect(storage.load(root, "private/tab-pins.json")).toEqual({ "queries/pinned.sql" })
			query.new("second.sql")
			expect(query.close_root(root)).toBe(true)
			for _, buf in ipairs({ first, second, third }) do
				vim.api.nvim_buf_delete(buf, { force = false })
			end
			query.show("standard")
			expect(vim.b[query.state().active].fox_query_document).toBe("queries/second.sql")
			local restored = vim.fn.bufnr(storage.path(root, "queries/pinned.sql"))
			expect(query.state().consoles[restored]).toBeTruthy()
			expect(tabs.is_pinned(restored)).toBe(true)
			query.new("pinned.sql")
			pins.toggle_pin()
			expect(tabs.is_pinned(restored)).toBe(false)
			expect(storage.load(root, "private/tab-pins.json")).toEqual({})
		end)
	end)

	it("moves focus left with Ctrl+h and right with Ctrl+l in both Query views", function()
		project(function()
			for _, view in ipairs({ "standard", "visual" }) do
				query.show(view)
				local state = query.state()
				for _, mode in ipairs({ "n", "i", "x" }) do
					vim.api.nvim_set_current_win(state.sql_win)
					local origin = vim.api.nvim_win_get_position(state.sql_win)[2]
					vim.fn.maparg("<C-l>", mode, false, true).callback()
					expect(vim.api.nvim_win_get_position(0)[2] > origin).toBe(true)
					vim.fn.maparg("<C-h>", mode, false, true).callback()
					expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
					if view == "standard" then
						vim.fn.maparg("<C-h>", mode, false, true).callback()
						expect(vim.api.nvim_win_get_position(0)[2] < origin).toBe(true)
						vim.fn.maparg("<C-l>", mode, false, true).callback()
						expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
					end
				end
			end
		end)
	end)

	it("registers gN once per pane and opens notes only from Tables", function()
		project(function()
			local set, notes, create = vim.keymap.set, query.notes, query.create
			local registrations, opened, created = {}, 0, 0
			local ok, err = pcall(function()
				vim.keymap.set = function(mode, key, callback, opts)
					if key == "gN" and opts and opts.buffer then
						registrations[opts.buffer] = (registrations[opts.buffer] or 0) + 1
					end
					return set(mode, key, callback, opts)
				end
				query.show("standard")
				local state = query.state()
				query.notes = function()
					opened = opened + 1
				end
				query.create = function()
					created = created + 1
				end
				expect(registrations[state.side_buf]).toBe(1)
				vim.api.nvim_set_current_win(state.side_win)
				vim.fn.maparg("gN", "n", false, true).callback()
				expect(opened).toBe(1)
				expect(created).toBe(0)
				vim.api.nvim_set_current_win(state.sql_win)
				vim.fn.maparg("gN", "n", false, true).callback()
				expect(created).toBe(1)
				expect(opened).toBe(1)
			end)
			vim.keymap.set, query.notes, query.create = set, notes, create
			assert(ok, err)
		end)
	end)

	it("opens blank table notes and deletes them after confirmation", function()
		project(function(root)
			local pending, word
			vim.ui.input = function(opts, callback)
				word = opts.prompt:match('confirm "(%a+)"')
				assert(word and opts.default == nil)
				pending = callback
			end
			query.show("standard")
			local state = query.state()
			local item = { key = "school.students", name = "students", columns = {} }
			state.metadata = { tables = { item }, relations = {} }
			state.consoles[state.active].metadata = state.metadata
			state.consoles[state.active].profile = { id = "notes", engine = "sqlite", path = "unused.db" }
			query.notes(item)
			local buf, relative = vim.api.nvim_get_current_buf(), vim.b.fox_query_document
			expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "" })
			expect(vim.bo[buf].modified).toBe(false)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Business note" })
			vim.cmd("write")
			expect(storage.read(root, relative)).toBe("Business note")
			query.notes(nil, "delete")
			pending(nil)
			expect(storage.read(root, relative)).toBe("Business note")
			query.notes(nil, "delete")
			pending("wrong")
			expect(storage.read(root, relative)).toBe("Business note")
			query.notes(nil, "delete")
			pending(word)
			expect(storage.read(root, relative)).toBeNil()
			expect(vim.api.nvim_buf_is_valid(buf)).toBe(false)
			expect(state.note_keys[item.key]).toBeNil()
			expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(state.active)
			query.notes(item)
			expect(vim.api.nvim_buf_get_lines(0, 0, -1, false)).toEqual({ "" })
			query.notes(nil, "delete")
			pending(word)
			expect(state.note_keys[item.key]).toBeNil()
			query.notes(item)
			vim.cmd("write")
			vim.api.nvim_win_set_buf(state.sql_win, state.active)
			query.refresh_view(state)
			vim.api.nvim_set_current_win(state.side_win)
			vim.api.nvim_win_set_cursor(state.side_win, { 1, 0 })
			vim.fn.maparg("gD", "n", false, true).callback()
			pending(word)
			expect(storage.read(root, relative)).toBeNil()
			expect(state.note_keys[item.key]).toBeNil()
		end)
	end)

	it("preserves modified and externally changed table notes on deletion", function()
		project(function(root)
			query.show("visual")
			local state = query.state()
			local item = { key = "students", name = "students", columns = {} }
			state.metadata = { tables = { item }, relations = {} }
			state.consoles[state.active].metadata = state.metadata
			state.consoles[state.active].profile = { id = "notes", engine = "sqlite", path = "unused.db" }
			query.notes(item)
			local buf, relative = vim.api.nvim_get_current_buf(), vim.b.fox_query_document
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Unsaved note" })
			query.notes(nil, "delete")
			expect(vim.api.nvim_get_current_buf()).toBe(buf)
			expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "Unsaved note" })
			vim.cmd("write")
			storage.write(root, relative, "External edit")
			query.notes(nil, "delete")
			expect(vim.api.nvim_get_current_buf()).toBe(buf)
			expect(storage.read(root, relative)).toBe("External edit")
		end)
	end)

	it("refreshes safely after the last SQL buffer is wiped", function()
		project(function()
			query.show()
			local state = query.state()
			local buf = state.active
			state.pinned = { buf = buf, id = 1 }
			vim.api.nvim_buf_delete(buf, { force = true })
			expect(vim.api.nvim_buf_is_valid(buf)).toBe(false)
			expect(next(state.consoles)).toBeNil()
			expect(vim.api.nvim_get_current_tabpage()).toBe(state.tab)
			for _, view in ipairs({ "standard", "visual" }) do
				state.view = view
				query.refresh_view(state)
			end
		end)
	end)

	it("asks for a new SQL dialect, remembers it, and leaves no file on cancellation", function()
		project(function(root)
			query.show()
			local state = query.state()
			local old_select, selected = query.select, "mysql"
			local ok, err = pcall(function()
				query.select = function(options, opts, callback)
					expect(opts.prompt).toBe("SQL dialect")
					if selected == "postgres" then
						expect(options[1]).toBe("mysql")
					end
					callback(selected)
				end
				query.create("mysql.sql")
				expect(require("fox.langs.sql.dialect").read(state.active)).toBe("mysql")
				selected = "postgres"
				query.create("postgres.sql")
				expect(require("fox.langs.sql.dialect").read(state.active)).toBe("postgres")
				expect(storage.load(root, "settings.json").sql_dialect).toBe("postgres")
				local active, count = state.active, vim.tbl_count(state.consoles)
				selected = nil
				query.create("cancelled.sql")
				expect(state.active).toBe(active)
				expect(vim.tbl_count(state.consoles)).toBe(count)
				expect(storage.read(root, "queries/cancelled.sql")).toBeNil()
				query.syntax_check()
				expect(storage.load(root, "settings.json").sql_syntax_check).toBe(true)
				query.syntax_check()
				expect(storage.load(root, "settings.json").sql_syntax_check).toBe(false)
			end)
			query.select = old_select
			if not ok then
				error(err)
			end
		end)
	end)
	it("shows full prepare and execution errors as toasts and keeps them in the activity bar", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			local old_notify, messages = vim.notify, {}
			vim.notify = function(message, level)
				messages[#messages + 1] = { message, level }
			end
			local ok, err = pcall(function()
				item.profile = { id = "test", engine = "sqlite", path = "db" }
				for _, phase in ipairs({ "prepare", "execute" }) do
					local full = phase .. " failed\nserver detail: invalid SQL near 100%"
					item.client = {
						connected = true,
						close = function() end,
						request = function(_, op, _, callback)
							if op == phase then
								callback(nil, "SQL error", full)
							else
								callback({ parameters = 0, statements = 1 })
							end
						end,
					}
					query.run("statement", "SELECT broken", {})
					expect(item.error_detail).toBe(full)
					expect(messages[#messages]).toEqual({ full, vim.log.levels.ERROR })
					expect(vim.api.nvim_buf_get_lines(state.activity_buf, 0, 1, false)[1]).toContain("server detail")
				end
			end)
			vim.notify = old_notify
			if not ok then
				error(err)
			end
		end)
	end)
	it("restores Query after the last dock closes even when a floating panel remains", function()
		project(function()
			query.show("standard")
			vim.wait(200, function()
				return false
			end, 10)
			vim.cmd("redraw")
			local state, dock = query.state(), require("fox.core.dock")
			local saved = vim.fn.winrestcmd()
			local terminal_buf = vim.api.nvim_create_buf(false, true)
			vim.b[terminal_buf].fox_is_multi_term = true
			local terminal_win = dock.open({ prefer = "terminal", height = 5 })
			vim.api.nvim_win_set_buf(terminal_win, terminal_buf)
			local task_buf = vim.api.nvim_create_buf(false, true)
			vim.b[task_buf].fox_is_task = true
			local task_win = dock.open({ prefer = "task", height = 5 })
			vim.api.nvim_win_set_buf(task_win, task_buf)
			expect(vim.api.nvim_win_get_position(terminal_win)[1]).toBe(vim.api.nvim_win_get_position(task_win)[1])
			vim.api.nvim_win_close(terminal_win, true)
			vim.wait(30, function()
				return false
			end, 10)
			expect(vim.t[state.tab].fox_query_dock).toBeTruthy()
			local popup_buf = vim.api.nvim_create_buf(false, true)
			local popup =
				vim.api.nvim_open_win(popup_buf, true, { relative = "editor", row = 1, col = 1, width = 20, height = 3 })
			vim.api.nvim_win_close(task_win, true)
			expect(vim.wait(1000, function()
				return not vim.t[state.tab].fox_query_dock
			end, 10)).toBeTruthy()
			expect(vim.api.nvim_get_current_win()).toBe(popup)
			vim.api.nvim_win_close(popup, true)
			vim.cmd("redraw")
			expect(vim.fn.winrestcmd()).toBe(saved)
			for _, buf in ipairs({ terminal_buf, task_buf, popup_buf }) do
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end)
	end)
	it("opens docked terminals below the whole Query dashboard and restores every pane on close", function()
		project(function()
			local terminal = require("plugins.fox.dev.terminal")
			local dock, layout = require("fox.core.dock"), require("fox.query.layout")
			local old_layout, old_selected = _G._fox_terminal_layout, _G._fox_selected_terminal
			local old_slot = _G._fox_terminals[9]
			local buf = vim.api.nvim_create_buf(false, true)
			vim.b[buf].fox_is_multi_term, vim.b[buf].fox_term_num = true, 9
			vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
			_G._fox_terminals[9] = { buf = buf }
			_G._fox_terminal_layout, _G._fox_selected_terminal = "dock", 9
			local ok, err = pcall(function()
				for _, view in ipairs({ "standard", "visual" }) do
					query.show(view)
					local state = query.state()
					for _, name in ipairs({ "sql", "side", "result", "activity", "queries", "connections" }) do
						local origin = state[name .. "_win"]
						if origin then
							vim.api.nvim_set_current_win(origin)
							local geometry, buffers = {}, {}
							for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
								geometry[win] = {
									vim.api.nvim_win_get_width(win),
									vim.api.nvim_win_get_height(win),
									vim.api.nvim_win_get_position(win),
								}
								buffers[win] = vim.api.nvim_win_get_buf(win)
							end
							layout.save(state)
							local saved = require("fox.core.store").read_file(layout.path)
							terminal.open_terminal(9)
							local _, win = dock.find()
							expect(win ~= state.sql_win).toBeTruthy()
							expect(vim.api.nvim_win_get_width(win)).toBe(vim.o.columns)
							local top = vim.api.nvim_win_get_position(win)[1]
							for pane, buffer in pairs(buffers) do
								expect(vim.api.nvim_win_get_buf(pane)).toBe(buffer)
								expect(vim.api.nvim_win_get_position(pane)[1] < top).toBeTruthy()
							end
							vim.api.nvim_win_set_height(win, 5)
							layout.save(state)
							expect(require("fox.core.store").read_file(layout.path)).toBe(saved)
							terminal.toggle_selected_terminal()
							expect(vim.wait(1000, function()
								return not vim.t[state.tab].fox_query_dock
							end, 10)).toBeTruthy()
							expect(vim.api.nvim_get_current_win()).toBe(origin)
							for pane, size in pairs(geometry) do
								expect({
									vim.api.nvim_win_get_width(pane),
									vim.api.nvim_win_get_height(pane),
									vim.api.nvim_win_get_position(pane),
								}).toEqual(size)
							end
						end
					end
				end
			end)
			pcall(vim.cmd, "stopinsert")
			for _, win in ipairs(vim.fn.win_findbuf(buf)) do
				pcall(vim.api.nvim_win_close, win, true)
			end
			vim.api.nvim_buf_delete(buf, { force = true })
			_G._fox_terminal_layout, _G._fox_selected_terminal = old_layout, old_selected
			_G._fox_terminals[9] = old_slot
			if not ok then
				error(err)
			end
		end)
	end)
	it("keeps saved Standard sidebar widths while constructing the other panels", function()
		project(function()
			local columns, equalalways = vim.o.columns, vim.o.equalalways
			vim.o.columns, vim.o.equalalways = 198, true
			local ok, err = pcall(function()
				require("fox.core.store").save(require("fox.query.layout").path, {
					standard = { connections = 0.12, side = 0.15 },
				})
				query.show("standard")
				local state = query.state()
				expect(vim.api.nvim_win_get_width(state.side_win)).toBe(math.floor(198 * 0.15))
				expect(vim.api.nvim_win_get_width(state.queries_win)).toBe(math.floor(198 * 0.12))
				query.hide()
				query.show("standard")
				expect(vim.api.nvim_win_get_width(state.side_win)).toBe(math.floor(198 * 0.15))
				expect(vim.api.nvim_win_get_width(state.queries_win)).toBe(math.floor(198 * 0.12))
			end)
			vim.o.columns, vim.o.equalalways = columns, equalalways
			if not ok then
				error(err)
			end
		end)
	end)
	it("opens SQL files through Neo-tree in a compact terminal", function()
		project(function(root)
			local columns = vim.o.columns
			vim.o.columns = 60
			local ok, err = pcall(function()
				storage.write(root, "queries/compact.sql", "SELECT 42;")
				query.show()
				local state = query.state()
				query.focus_panel("queries")
				expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(state.queries_buf)
				expect(vim.b[state.queries_buf].neo_tree_source).toBe("fox_query")
				require("neo-tree.ui.renderer").focus_node(state.query_tree, "compact.sql")
				vim.fn.maparg("<CR>", "n", false, true).callback()
				expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(state.active)
				expect(vim.b[state.active].fox_query_document).toBe("queries/compact.sql")
			end)
			vim.o.columns = columns
			if not ok then
				error(err)
			end
		end)
	end)
	it("searches result headers and keeps sidebar searches native", function()
		project(function()
			query.show("standard")
			local state = query.state()
			local item = state.consoles[state.active]
			item.result = { sets = { { columns = { "searchable_header" }, rows = { { "value" } } } } }
			query.refresh_view(state)
			vim.api.nvim_set_current_win(state.side_win)
			for _, key in ipairs({ "/", "?", "n", "N" }) do
				expect(vim.fn.maparg(key, "n", false, true).buffer).toBeNil()
			end
			vim.api.nvim_set_current_win(state.result_win)
			expect(vim.fn.maparg("?", "n", false, true).buffer).toBeNil()
			vim.api.nvim_win_set_cursor(0, { 4, 0 })
			expect(vim.fn.search("searchable_header", "bW")).toBe(item.result_headers[1].first)
			expect(item.result_rows[vim.api.nvim_win_get_cursor(0)[1]]).toBeNil()
			expect(vim.fn.search("value", "W")).toBe(4)
		end)
	end)

	it("shows connection details before connecting and closes on cancellation", function()
		project(function(root)
			query.show("standard")
			local state = query.state()
			local profile = {
				id = "school",
				engine = "mysql",
				host = "localhost",
				port = 3306,
				database = "school",
				user = "reader",
				password_env = "TEST_DB_PASSWORD",
			}
			storage.save(root, "connections.json", { profiles = { profile } })
			query.draw_connections(state)
			local old_connect, connected = query.connect, nil
			local ok, err = pcall(function()
				query.connect = function(value)
					connected = value
				end
				vim.api.nvim_set_current_win(state.connections_win)
				vim.api.nvim_win_set_cursor(0, { 2, 0 })
				expect(vim.api.nvim_get_current_line()).toContain(" school")
				local function open()
					vim.fn.maparg("<CR>", "n", false, true).callback()
				end
				open()
				local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
				for _, detail in ipairs({
					"engine: mysql",
					"host: localhost",
					"port: 3306",
					"database: school",
					"user: reader",
					"password_env: TEST_DB_PASSWORD",
				}) do
					expect(text).toContain(detail)
				end
				expect(connected).toBeNil()
				vim.fn.maparg("q", "n", false, true).callback()
				expect(connected).toBeNil()
				open()
				open()
				expect(connected.id).toBe(profile.id)
			end)
			query.connect = old_connect
			if not ok then
				error(err)
			end
		end)
	end)

	it("keeps result headers visible and aligned while scrolling and switches them between result sets", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			local first = { columns = { "id", "表nombre%", "long_column" }, rows = {} }
			local second = { columns = { "other_id", "description" }, rows = {} }
			for index = 1, 80 do
				first.rows[index] = { tostring(index), "value", string.rep("x", 32) }
				second.rows[index] = { tostring(index), "other" }
			end
			item.result = { sets = { first, second, { columns = { "empty_result" }, rows = {} } } }
			query.refresh_view(state)
			local win = state.result_win
			vim.api.nvim_set_current_win(win)
			vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].signcolumn = false, false, "no"
			vim.wo[win].statuscolumn = ""
			vim.wo[win].foldcolumn = "0"
			local function scroll(line, left, column)
				vim.fn.winrestview({ lnum = line, topline = line, leftcol = left or 0, col = column or 0 })
				vim.api.nvim_exec_autocmds("WinScrolled", { pattern = tostring(win) })
				return vim.api.nvim_eval_statusline(
					vim.wo[win].winbar,
					{ winid = win, maxwidth = vim.api.nvim_win_get_width(win) }
				).str
			end
			local header = scroll(40)
			expect(vim.fn.winsaveview().topline > 3).toBeTruthy()
			expect(header).toContain("id")
			expect(header).toContain("表nombre%")
			expect(item.result_rows[40].row).toBe(first.rows[37])
			local original = item.result_headers[1].text
			local start = original:find("表", 1, true)
			local left = vim.fn.strdisplaywidth(original:sub(1, start - 1)) + 1
			header = scroll(40, left, 15)
			expect(vim.fn.winsaveview().leftcol).toBe(left)
			expect(header:sub(1, 8)).toBe(" nombre%")
			vim.wo[win].number = true
			header = scroll(40)
			local gutter = vim.fn.getwininfo(win)[1].textoff
			expect(header:sub(1, gutter)).toBe(string.rep(" ", gutter))
			expect(header:sub(gutter + 1, gutter + #"│ ")).toBe("│ ")
			header = scroll(item.result_headers[2].first + 20)
			expect(header).toContain("other_id")
			expect(header:find("表nombre%", 1, true)).toBeNil()
			header = scroll(item.result_headers[3].first + 1)
			expect(header).toContain("empty_result")
			item.result, item.result_lines = nil, nil
			query.refresh_view(state)
			expect(vim.wo[win].winbar).toBe("")
		end)
	end)

	it("keeps fixed headers in the compact results panel without replacing the SQL status", function()
		project(function()
			local columns = vim.o.columns
			vim.o.columns = 60
			local ok, err = pcall(function()
				query.show()
				local state = query.state()
				local item = state.consoles[state.active]
				item.result = { sets = { { columns = { "compact_header" }, rows = { { "value" } } } } }
				query.results()
				expect(table.concat(vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false), "\n")).toContain(
					"compact_header"
				)
				vim.api.nvim_win_set_buf(state.sql_win, state.active)
				query.refresh_view(state)
				expect(vim.wo[state.sql_win].winbar).toContain("Ctrl+Enter Run")
			end)
			vim.o.columns = columns
			if not ok then
				error(err)
			end
		end)
	end)

	it("sizes live-diagram details from content despite an old small inspector size", function()
		project(function()
			query.show("visual")
			local state = query.state()
			local item = { key = "Season", name = "Season", columns = { { name = "id", type = "INTEGER" } } }
			state.metadata = { tables = { item }, relations = {} }
			state.consoles[state.active].metadata = state.metadata
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT * FROM Season;" })
			require("fox.core.store").save(
				require("fox.query.layout").path,
				{ menus = { inspect = { width = 12, height = 3 } } }
			)
			query.refresh_view(state)
			vim.api.nvim_set_current_win(state.side_win)
			local found = false
			for row, object in pairs(state.objects) do
				for _, region in ipairs(object.regions or {}) do
					if region.item == item then
						vim.api.nvim_win_set_cursor(0, { row, region.first })
						found = true
						break
					end
				end
				if found then
					break
				end
			end
			expect(found).toBeTruthy()
			vim.fn.maparg("<CR>", "n", false, true).callback()
			local content = require("fox.query.render").inspect(item, state.metadata)
			local width = math.min(vim.o.columns - 4, vim.fn.strdisplaywidth(content[1]))
			local height = math.min(vim.o.lines - 6, #content)
			local config = vim.api.nvim_win_get_config(0)
			expect(config.relative).toBe("editor")
			expect(config.width).toBe(width)
			expect(config.height).toBe(height)
			expect(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")).toContain("INTEGER")
			vim.fn.maparg("q", "n", false, true).callback()
			expect(vim.api.nvim_get_current_win()).toBe(state.side_win)
		end)
	end)

	it("outlines only the statement at the cursor and follows movement without executing", function()
		project(function()
			query.show()
			local state, ns = query.state(), vim.api.nvim_create_namespace("fox_query_statement")
			local buf = state.active
			local lines = { "SELECT 'á;表' AS value;", "", "SELECT", "  22 AS second;" }
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.api.nvim_win_set_cursor(state.sql_win, { 1, 9 })
			query.refresh_view(state)
			local function marks()
				return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
			end
			local entries = marks()
			expect(#entries).toBe(2)
			expect(entries[1][2]).toBe(0)
			expect(entries[1][4].virt_lines_above).toBeTruthy()
			for _, mark in ipairs(entries) do
				expect(mark[4].virt_text).toBeNil()
				expect(mark[4].virt_lines[1][1][1]).toBe(
					string.rep("\226\148\128", vim.api.nvim_win_get_width(state.sql_win) - 2)
				)
			end
			vim.api.nvim_win_set_cursor(state.sql_win, { 4, 3 })
			query.refresh_view(state)
			entries = marks()
			expect(entries[1][2]).toBe(2)
			expect(entries[2][2]).toBe(3)
			expect(state.consoles[buf].execution).toBeNil()
			expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual(lines)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 1; SELECT 2;" })
			vim.api.nvim_win_set_cursor(state.sql_win, { 1, 12 })
			query.refresh_view(state)
			expect(#marks()).toBe(2)
			expect(marks()[1][2]).toBe(0)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 'unfinished" })
			query.refresh_view(state)
			expect(#marks()).toBe(0)
		end)
	end)

	it("quotes text cells and opens full row details at the centered terminal size", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			local text = 'a"b\nc'
			local set = {
				columns = { "text", "number", "null", "empty", "long" },
				rows = { { text, "9007199254740993", vim.NIL, "", string.rep("表", 40) } },
				strings = { { true, false, false, true, true } },
			}
			item.result = { sets = { set } }
			query.refresh_view(state)
			local lines = vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false)
			expect(lines[2]).toContain("│ text")
			expect(lines[4]).toContain(vim.json.encode(text))
			expect(lines[4]).toContain("9007199254740993")
			expect(lines[4]).toContain("NULL")
			expect(lines[4]).toContain('""')
			expect(lines[4]).toContain('…"')
			vim.api.nvim_set_current_win(state.result_win)
			vim.api.nvim_win_set_cursor(state.result_win, { 4, 0 })
			vim.fn.maparg("<CR>", "n", false, true).callback()
			local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
			local config = vim.api.nvim_win_get_config(win)
			local width, height = require("plugins.fox.dev.terminal").float_size()
			expect(config.relative).toBe("editor")
			expect(config.width).toBe(width)
			expect(config.height).toBe(height)
			local row, col = require("fox.core.ui").center(width, height)
			expect(config.row).toBe(row)
			expect(config.col).toBe(col)
			local details = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			expect(details).toContain("text = " .. vim.json.encode(text))
			expect(details).toContain("number = 9007199254740993")
			expect(details).toContain("null = NULL")
			expect(details).toContain('empty = ""')
			expect(details).toContain(string.rep("表", 40))
			expect(set.rows[1][1]).toBe(text)
			vim.fn.maparg("q", "n", false, true).callback()
			expect(vim.api.nvim_win_is_valid(win)).toBeFalsy()
			expect(vim.api.nvim_get_current_win()).toBe(state.result_win)
		end)
	end)

	it("runs and browses in a large popup without moving dashboard panes", function()
		project(function(root)
			local fixture = vim.fn.stdpath("config") .. "/config/tests/query/fixture.db"
			vim.fn.writefile(vim.fn.readfile(fixture, "b"), root .. "/fixture.db", "b")
			storage.save(root, "connections.json", {
				profiles = { { id = "local", engine = "sqlite", path = "fixture.db" } },
			})
			query.show("standard")
			local state = query.state()
			local item = state.consoles[state.active]
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT 42 AS answer;" })
			local function panes()
				local sizes = {}
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
					if vim.api.nvim_win_get_config(win).relative == "" then
						sizes[win] = { vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }
					end
				end
				return sizes
			end
			local layout = panes()
			query.run_popup()
			expect(vim.wait(5000, function()
				return state.result_popup and vim.api.nvim_win_is_valid(state.result_popup)
			end, 10)).toBeTruthy()
			local popup = state.result_popup
			expect(vim.api.nvim_win_get_width(popup)).toBe(math.floor(vim.o.columns * 0.9))
			expect(vim.api.nvim_win_get_height(popup)).toBe(math.floor(vim.o.lines * 0.9))
			expect(vim.api.nvim_win_get_config(popup).relative).toBe("editor")
			expect(vim.api.nvim_win_get_buf(popup)).toBe(state.result_buf)
			expect(vim.api.nvim_buf_get_lines(state.result_buf, 1, 2, false)[1]).toContain("answer")
			expect(item.result.sets[1].rows[1][1]).toBe("42")
			vim.fn.maparg("<Esc>", "n", false, true).callback()
			expect(vim.api.nvim_win_is_valid(popup)).toBeFalsy()
			expect(panes()).toEqual(layout)
			expect(vim.wait(5000, function()
				return state.metadata.tables and #state.metadata.tables > 0
			end, 10)).toBeTruthy()
			vim.api.nvim_set_current_win(state.side_win)
			for row, object in pairs(state.objects) do
				if object.key == "things" then
					vim.api.nvim_win_set_cursor(state.side_win, { row, 0 })
				end
			end
			vim.fn.maparg("B", "n", false, true).callback()
			expect(vim.wait(5000, function()
				return state.result_popup and vim.api.nvim_win_is_valid(state.result_popup)
			end, 10)).toBeTruthy()
			expect(item.result_table).toBe("things")
			expect(item.executed_sql).toContain("SELECT * FROM")
			vim.fn.maparg("q", "n", false, true).callback()
			vim.api.nvim_set_current_win(state.sql_win)
			query.run()
			expect(vim.wait(5000, function()
				return item.execution == 3 and not item.client.busy
			end, 10)).toBeTruthy()
			expect(state.result_popup).toBeNil()
			query.new()
			query.results_popup(state, item)
			expect(state.result_popup).toBeNil()
		end)
	end)

	it("connects the sole profile and reconnects before running the captured statement", function()
		project(function(root)
			local fixture = {
				code = vim.fn.writefile(
					vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/query/fixture.db", "b"),
					root .. "/fixture.db",
					"b"
				),
			}
			expect(fixture.code).toBe(0)
			local profile = { id = "local", engine = "sqlite", path = "fixture.db" }
			storage.save(root, "connections.json", { profiles = { profile } })
			query.show()
			local state = query.state()
			expect(state.autorun).toBeFalsy()
			local item, buf = state.consoles[state.active], state.active
			expect(item.client and item.client.connecting).toBeTruthy()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 11;", "SELECT '22';" })
			vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
			vim.api.nvim_win_set_cursor(state.sql_win, { 2, 0 })
			vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
			vim.wait(1200)
			expect(item.execution).toBeNil()
			vim.fn.maparg("<C-CR>", "n", false, true).callback()
			vim.api.nvim_win_set_cursor(state.sql_win, { 1, 0 })
			expect(vim.wait(5000, function()
				return item.result and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.result.sets[1].rows[1][1]).toBe("22")
			expect(item.result.sets[1].strings[1][1]).toBeTruthy()
			expect(table.concat(vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false), "\n")).toContain('"22"')
			expect(item.execution).toBe(1)
			expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
			item.client:close()
			query.run("statement")
			expect(vim.wait(5000, function()
				return item.execution == 2 and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.result.sets[1].rows[1][1]).toBe("11")
			item.client:close()
			query.run("statement")
			query.new()
			expect(vim.wait(5000, function()
				return item.client.connected and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.execution).toBe(2)
		end)
	end)

	it("requires a choice for multiple profiles and never replaces a stale remembered profile", function()
		project(function(root)
			local profiles = {
				{ id = "one", engine = "sqlite", path = "one.db" },
				{ id = "two", engine = "sqlite", path = "two.db" },
			}
			storage.save(root, "connections.json", { profiles = profiles })
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			expect(item.client).toBeNil()
			query.run("statement")
			expect(vim.api.nvim_get_current_win()).toBe(state.connections_win)
			storage.save(root, "private/session.json", { profile = "removed", fingerprint = "old" })
			storage.save(root, "connections.json", { profiles = { profiles[1] } })
			item.restore_attempted = nil
			query.restore_connection(state)
			expect(item.client).toBeNil()
		end)
	end)

	it("shows a connection error without executing or retaining a queued statement", function()
		project(function(root)
			query.show()
			local state = query.state()
			state.autorun = false
			local item = state.consoles[state.active]
			storage.save(
				root,
				"connections.json",
				{ profiles = { { id = "missing", engine = "sqlite", path = "missing.db" } } }
			)
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT 1;" })
			query.run("statement")
			expect(vim.wait(5000, function()
				return state.connection_status.missing == "failed"
			end, 10)).toBeTruthy()
			expect(item.execution).toBeNil()
			expect(item.pending_run).toBeNil()
			vim.api.nvim_win_close(0, true)
		end)
	end)

	it("opens connections when running disconnected SQL and waits for an in-flight connection", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			local text = "SELECT * FROM escolar.alumnos"
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { text })
			query.run("statement")
			expect(vim.api.nvim_get_current_win()).toBe(state.connections_win)
			expect(item.client).toBeNil()
			expect(vim.api.nvim_buf_get_lines(state.active, 0, -1, false)[1]).toBe(text)
			vim.api.nvim_set_current_win(state.sql_win)
			item.profile = { id = "SIIA-DB" }
			item.client = { connecting = true, close = function() end }
			query.run("statement")
			expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
			item.client = nil
			query.run("statement", text, nil, nil, true)
			expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
		end)
	end)

	it("reopens the last saved SQL on first entry and creates a query only for an empty project", function()
		project(function(root)
			query.show()
			local state = query.state()
			expect(state.active ~= nil).toBeTruthy()
			query.close_buffer(state.active, true)
			expect(state.active).toBeNil()
			expect(storage.write(root, "queries/a.sql", "SELECT 1;")).toBeTruthy()
			expect(storage.write(root, "queries/nested/z.sql", "SELECT 2;")).toBeTruthy()
			query.new("nested/z.sql")
			vim.api.nvim_buf_call(state.active, function()
				vim.cmd("write")
			end)
			expect(query.close_root(root)).toBeTruthy()
			query.show()
			state = query.state()
			expect(vim.b[state.active].fox_query_document).toBe("queries/nested/z.sql")
			expect(vim.tbl_count(state.consoles)).toBe(1)
			expect(vim.api.nvim_buf_get_lines(state.active, 0, -1, false)[2]).toBe("SELECT 2;")
			expect(query.close_root(root)).toBeTruthy()
			vim.fn.delete(storage.path(root, "queries/nested/z.sql"))
			query.show()
			state = query.state()
			expect(vim.b[state.active].fox_query_document).toBe("queries/a.sql")
			expect(vim.tbl_count(state.consoles)).toBe(1)
		end)
	end)

	it("opens relationships at the focused table with FK colors and redraws when resized or recentered", function()
		project(function()
			query.show()
			local state = query.state()
			state.metadata = {
				tables = {
					{ key = "Bridge", name = "Bridge", columns = { { name = "player_id" } } },
					{ key = "Player", name = "Player", columns = { { name = "id", pk = true } } },
				},
				relations = {
					{ name = "fk", source = "Bridge", target = "Player", columns = { { source = "player_id", target = "id" } } },
				},
			}
			state.consoles[state.active].metadata = state.metadata
			state.selected = "Player"
			query.graph(false)
			local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			expect(lines[5]).toContain("> Player")
			expect(vim.fn.winsaveview().topline).toBe(1)
			local colored = false
			for _, mark in
				ipairs(vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_get_namespaces().fox_query, 0, -1, { details = true }))
			do
				if mark[4].hl_group == "DiagnosticInfo" then
					colored = true
				end
			end
			expect(colored).toBeTruthy()
			vim.api.nvim_win_set_width(win, 62)
			vim.api.nvim_exec_autocmds("WinResized", {})
			lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			expect(table.concat(lines, "\n")).toContain("> Player")
			for row, line in ipairs(lines) do
				local column = line:find("Bridge", 1, true)
				if column and line:find("│", 1, true) then
					vim.api.nvim_win_set_cursor(win, { row, column - 1 })
					break
				end
			end
			vim.fn.maparg("<CR>", "n", false, true).callback()
			expect(state.selected).toBe("Bridge")
			expect(vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1]).toContain("> Bridge")
			expect(vim.fn.winsaveview().topline).toBe(1)
			vim.fn.maparg("q", "n", false, true).callback()
			expect(vim.api.nvim_buf_is_valid(buf)).toBeFalsy()
			query.graph(true)
			vim.fn.maparg("q", "n", false, true).callback()
		end)
	end)

	it("manages nested SQL files and folders without losing open edits or recreating old paths", function()
		project(function(root)
			query.show("standard")
			local state, files = query.state(), require("fox.query.files")
			vim.api.nvim_buf_call(state.active, function()
				vim.cmd("write")
			end)
			local old_input, old_select = vim.ui.input, query.select
			local value, choice = nil, "Delete"
			local ok, err = pcall(function()
				vim.ui.input = function(_, callback)
					callback(value)
				end
				query.select = function(items, opts, callback)
					callback(opts.prompt == "SQL dialect" and items[1] or choice)
				end
				local function select(relative)
					query.refresh_view(state)
					vim.api.nvim_set_current_win(state.queries_win)
					local node = state.query_tree.tree:get_node(relative)
					if node then
						require("neo-tree.ui.renderer").focus_node(state.query_tree, relative)
						return
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
						vim.bo[console].modified = false
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

	it("stacks caret-aware table inspectors and dismisses them when focus leaves", function()
		project(function()
			query.show("standard")
			local state = query.state()
			local main = { key = "Main", name = "Main", columns = { { name = "id", pk = true } } }
			local related = { key = "右表", name = "右表", columns = { { name = "main_id" } } }
			state.metadata = {
				tables = { main, related },
				relations = { { source = related.key, target = main.key, columns = { { source = "main_id", target = "id" } } } },
			}
			state.consoles[state.active].metadata = state.metadata
			query.inspect(main, state)
			local parent = vim.api.nvim_get_current_win()
			local _, _, objects = require("fox.query.render").inspect(main, state.metadata)
			local found = false
			for row, object in pairs(objects) do
				for _, region in ipairs(object.regions or {}) do
					if region.item == related then
						vim.api.nvim_win_set_cursor(parent, { row, 0 })
						vim.cmd("normal! " .. (region.first + 3) .. "|")
						found = true
						break
					end
				end
				if found then
					break
				end
			end
			expect(found).toBeTruthy()
			local cursor, view = vim.api.nvim_win_get_cursor(parent), vim.fn.winsaveview()
			vim.fn.maparg("<CR>", "n", false, true).callback()
			local child = vim.api.nvim_get_current_win()
			expect(child == parent).toBeFalsy()
			expect(vim.api.nvim_win_get_config(child).title[1][1]).toContain(related.name)
			vim.wait(30, function()
				return false
			end)
			expect(vim.api.nvim_win_is_valid(parent)).toBeTruthy()
			vim.fn.maparg("q", "n", false, true).callback()
			expect(vim.api.nvim_get_current_win()).toBe(parent)
			expect(vim.api.nvim_win_get_cursor(parent)).toEqual(cursor)
			expect(vim.fn.winsaveview().topline).toBe(view.topline)
			query.inspect(nil, state)
			child = vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_win(state.sql_win)
			expect(vim.wait(500, function()
				return not vim.api.nvim_win_is_valid(child) and not vim.api.nvim_win_is_valid(parent)
			end, 10)).toBeTruthy()
			expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
		end)
	end)

	it("uses the relationship card under the caret for inspector actions", function()
		project(function()
			query.show("standard")
			local state = query.state()
			local main = { key = "Main", name = "Main", columns = {} }
			local related = { key = "Related", name = "Related", columns = {} }
			state.metadata = {
				tables = { main, related },
				relations = { { source = related.key, target = main.key, columns = {} } },
			}
			state.consoles[state.active].metadata = state.metadata
			local saved = { browse = query.browse, notes = query.notes, insert_join = query.insert_join, graph = query.graph }
			local ok, err = pcall(function()
				for _, action in ipairs({
					{ "b", "browse" },
					{ "B", "browse" },
					{ "n", "notes" },
					{ "J", "insert_join" },
					{ "g", "graph" },
				}) do
					local received, popup
					query[action[2]] = function(value, use_popup)
						received, popup = value, use_popup
					end
					query.inspect(main, state)
					local win = vim.api.nvim_get_current_win()
					local _, _, objects = require("fox.query.render").inspect(main, state.metadata)
					for row, object in pairs(objects) do
						for _, region in ipairs(object.regions or {}) do
							if region.item == related then
								vim.api.nvim_win_set_cursor(win, { row, 0 })
								vim.cmd("normal! " .. (region.first + 3) .. "|")
							end
						end
					end
					vim.fn.maparg(action[1], "n", false, true).callback()
					if action[1] == "g" then
						expect(state.selected).toBe(related.key)
						expect(received).toBe(false)
					else
						expect(received).toBe(related)
					end
					if action[1] == "B" then
						expect(popup).toBe(true)
					end
					expect(vim.api.nvim_win_is_valid(win)).toBeFalsy()
					query[action[2]] = saved[action[2]]
				end
			end)
			for name, action in pairs(saved) do
				query[name] = action
			end
			if not ok then
				error(err)
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
			vim.api.nvim_buf_call(state.side_buf, function()
				expect(vim.fn.maparg("/", "n", false, true).buffer).toBeNil()
				expect(vim.fn.maparg("n", "n", false, true).buffer).toBeNil()
			end)
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
			expect(vim.api.nvim_buf_get_lines(saved, 0, -1, false)[2]).toBe("SELECT 42;")
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
			expect(lines[#lines]).toBe("Enter Details  D Disconnect")
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

	it("renders Unicode result tables and keeps row actions aligned across sets", function()
		project(function()
			query.show()
			local state = query.state()
			local item = state.consoles[state.active]
			local first = { columns = { "actualRank" }, rows = { { "CA" }, { "BR" } } }
			local second = { columns = { "id", "value" }, rows = { { "1", vim.NIL }, { "2", "表\ntext" } } }
			item.result = { sets = { first, second, { columns = { "empty" }, rows = {} } } }
			query.refresh_view(state)
			local lines = vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false)
			expect(lines[1]).toBe("┌────────────┐")
			expect(lines[2]).toContain("actualRank")
			expect(lines[2]).toBe("│ actualRank │")
			expect(lines[4]).toBe("│ CA         │")
			expect(lines[6]).toBe("└────────────┘")
			expect(lines[9]).toContain("┬")
			expect(lines[14]).toContain("┴")
			expect(table.concat(lines, "\n")).toContain("NULL")
			expect(table.concat(lines, "\n")).toContain("表\\ntext")
			vim.api.nvim_set_current_win(state.result_win)
			for row, line in ipairs(lines) do
				vim.api.nvim_win_set_cursor(0, { row, 0 })
				local set, value = query.row()
				if line:find("│ CA ", 1, true) then
					expect(set).toBe(first)
					expect(value).toBe(first.rows[1])
				elseif line:find("│ 1 ", 1, true) then
					expect(set).toBe(second)
					expect(value).toBe(second.rows[1])
				elseif line:sub(1, #"┌") == "┌" or line:sub(1, #"└") == "└" or line:find("actualRank", 1, true) then
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

	it("saves a masked password once and reuses it when retrying a failed connection", function()
		project(function(root)
			query.show()
			local client = require("fox.query.client")
			local old_new, old_input = client.new, vim.fn.inputsecret
			local old_refresh = query.refresh_metadata
			local prompts, attempts = 0, 0
			local profile = { id = "mysql", engine = "mysql", host = "localhost", port = 3306, database = "db", user = "me" }
			local ok, err = pcall(function()
				vim.fn.inputsecret = function()
					prompts = prompts + 1
					return "saved-secret"
				end
				client.new = function()
					return {
						close = function() end,
						request = function(_, op, data, callback)
							expect(op).toBe("connect")
							expect(data.profile.password).toBe("saved-secret")
							attempts = attempts + 1
							if attempts == 1 then
								callback(nil, "Database connection failed")
								return
							end
							callback({ engine = "mysql", version = "test" })
						end,
					}
				end
				query.refresh_metadata = function() end
				local state = query.state()
				query.connect(profile, state)
				expect(storage.password(root, profile)).toBe("saved-secret")
				expect(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")).toContain("Database connection failed")
				vim.api.nvim_win_close(0, true)
				query.connect(profile, state)
				expect(vim.wait(1000, function()
					return state.connection_status.mysql == "connected"
				end, 10)).toBeTruthy()
				expect(attempts).toBe(2)
				expect(prompts).toBe(1)
				expect(profile.password).toBeNil()
			end)
			client.new, vim.fn.inputsecret = old_new, old_input
			query.refresh_metadata = old_refresh
			if not ok then
				error(err)
			end
		end)
	end)

	it("keeps or replaces private passwords when editing a connection", function()
		project(function(root)
			local old_select, old_input, old_secret, old_connect =
				query.select, vim.ui.input, vim.fn.inputsecret, query.connect
			local profile = { id = "mysql", engine = "mysql", host = "localhost", port = 3306, database = "db", user = "me" }
			local password = ""
			local ok, err = pcall(function()
				storage.save(root, "connections.json", { profiles = { profile } })
				storage.password(root, profile, "original")
				query.select = function(_, _, callback)
					callback("mysql")
				end
				vim.ui.input = function(opts, callback)
					callback(opts.default or "")
				end
				vim.fn.inputsecret = function()
					return password
				end
				query.connect = function(value)
					expect(value.password).toBeNil()
				end
				query.add_profile(profile)
				expect(storage.password(root, profile)).toBe("original")
				password = "replacement"
				query.add_profile(profile)
				expect(storage.password(root, profile)).toBe("replacement")
				expect(storage.profiles(root)[1].password).toBeNil()
				expect(storage.read(root, "connections.json"):find(password, 1, true)).toBeNil()
			end)
			query.select, vim.ui.input, vim.fn.inputsecret, query.connect = old_select, old_input, old_secret, old_connect
			if not ok then
				error(err)
			end
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
				query.run = function(kind, _, _, _, _, popup)
					expect(kind).toBe("statement")
					expect(popup).toBeNil()
					runs = runs + 1
				end
				for _, mode in ipairs({ "n", "i" }) do
					for _, key in ipairs({ "<C-CR>", "<F5>", "\27[13;5u", "\27[27;5;13~" }) do
						vim.fn.maparg(key, mode, false, true).callback()
					end
				end
				expect(runs).toBe(8)
				query.run = function(kind, _, _, _, _, popup)
					expect(kind).toBe("statement")
					expect(popup).toBeTruthy()
					runs = runs + 1
				end
				for _, mode in ipairs({ "n", "i" }) do
					for _, key in ipairs({ "<C-S-CR>", "\27[13;6u", "\27[27;6;13~" }) do
						vim.fn.maparg(key, mode, false, true).callback()
					end
				end
				expect(runs).toBe(14)
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
			state.autorun = true
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
			local fixture = {
				code = vim.fn.writefile(
					vim.fn.readfile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h") .. "/query/fixture.db", "b"),
					root .. "/fixture.db",
					"b"
				),
			}
			expect(fixture.code).toBe(0)
			local profile = { id = "local", engine = "sqlite", path = "fixture.db" }
			storage.save(root, "connections.json", { profiles = { profile } })
			query.show("visual")
			local state = query.state()
			state.autorun = true
			local item = state.consoles[state.active]
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
				"[Can't connect]  missing"
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
	it("keeps other panes in place when Parameters opens and closes", function()
		project(function()
			query.show("standard")
			local state = query.state()
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT ?;", "SELECT 1;" })
			vim.api.nvim_win_set_cursor(state.sql_win, { 2, 0 })
			query.refresh_view(state)
			local sizes = {}
			for _, win in ipairs({
				state.sql_win,
				state.result_win,
				state.queries_win,
				state.connections_win,
				state.activity_win,
			}) do
				sizes[win] =
					{ vim.api.nvim_win_get_position(win), vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win) }
			end
			for _ = 1, 3 do
				vim.api.nvim_win_set_cursor(state.sql_win, { 1, 0 })
				query.refresh_view(state)
				expect(vim.api.nvim_win_is_valid(state.parameters_win)).toBeTruthy()
				for win, size in pairs(sizes) do
					expect({
						vim.api.nvim_win_get_position(win),
						vim.api.nvim_win_get_width(win),
						vim.api.nvim_win_get_height(win),
					}).toEqual(size)
				end
				vim.api.nvim_win_set_cursor(state.sql_win, { 2, 0 })
				query.refresh_view(state)
				expect(state.parameters_win).toBeNil()
				for win, size in pairs(sizes) do
					expect({
						vim.api.nvim_win_get_position(win),
						vim.api.nvim_win_get_width(win),
						vim.api.nvim_win_get_height(win),
					}).toEqual(size)
				end
			end
		end)
	end)

	it("shows dim inline parameter values across statements without changing the SQL", function()
		project(function(root)
			query.show("standard")
			local state = query.state()
			local lines = {
				"SELECT '?' AS literal, 'á' AS unicode FROM alumnos WHERE nombre = ? AND edad > ?;",
				"SELECT * FROM cursos c WHERE c.id = ? OR c.id = ?;",
			}
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, lines)
			vim.api.nvim_buf_call(state.active, function()
				vim.cmd("write")
			end)
			local tick = vim.api.nvim_buf_get_changedtick(state.active)
			local parameters = require("fox.query.parameters")
			local document = vim.b[state.active].fox_query_document
			local first = parameters.describe(lines[1]:sub(1, -2), "sqlite")
			local second = parameters.describe(lines[2]:sub(1, -2), "sqlite")
			assert(parameters.set(root, document, first, first.groups[1].key, "Ana"))
			assert(parameters.set(root, document, first, first.groups[2].key, ""))
			assert(parameters.set(root, document, second, second.groups[1].key, "NULL"))
			query.refresh_view(state)
			local namespace = vim.api.nvim_get_namespaces().fox_query_parameters
			local marks = vim.api.nvim_buf_get_extmarks(state.active, namespace, 0, -1, { details = true })
			expect(#marks).toBe(4)
			for index, hint in ipairs({ " ⟨Ana⟩", ' ⟨""⟩', " ⟨NULL⟩", " ⟨NULL⟩" }) do
				local mark = marks[index]
				expect(mark[4].virt_text).toEqual({ { hint, "Comment" } })
				expect(mark[4].virt_text_pos).toBe("inline")
				expect(lines[mark[2] + 1]:sub(mark[3], mark[3])).toBe("?")
			end
			expect(marks[1][3]).toBe(lines[1]:find("? AND", 1, true))
			expect(vim.api.nvim_buf_get_lines(state.active, 0, -1, false)).toEqual(lines)
			expect(vim.api.nvim_buf_get_changedtick(state.active)).toBe(tick)
			expect(vim.bo[state.active].modified).toBe(false)
			assert(parameters.set(root, document, first, first.groups[1].key, nil))
			query.refresh_view(state)
			expect(#vim.api.nvim_buf_get_extmarks(state.active, namespace, 0, -1, {})).toBe(3)
			assert(parameters.set(root, document, first, first.groups[1].key, "Bea\n" .. string.rep("x", 80)))
			query.refresh_view(state)
			marks = vim.api.nvim_buf_get_extmarks(state.active, namespace, 0, -1, { details = true })
			local hint = marks[1][4].virt_text[1][1]
			expect(hint:find("\n", 1, true)).toBeNil()
			expect(hint).toContain("…")
			query.clear_parameters()
			expect(#vim.api.nvim_buf_get_extmarks(state.active, namespace, 0, -1, {})).toBe(0)
		end)
	end)

	it("labels equality and FROM rows using their SQL context", function()
		project(function()
			query.show("standard")
			local state = query.state()
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, {
				"SELECT * FROM ? WHERE apellido_paterno = ? AND año = ? UNION SELECT * FROM ? WHERE nombre = ?",
			})
			query.refresh_view(state)
			expect(vim.api.nvim_buf_get_lines(state.parameters_buf, 0, -1, false)).toEqual({
				"From #1: <unset>",
				"apellido_paterno = <unset>",
				"año = <unset>",
				"From #2: <unset>",
				"nombre = <unset>",
			})
		end)
	end)

	it("removes only the deleted intention from Parameters and leaves a restored slot unset", function()
		project(function(root)
			query.show("standard")
			local state = query.state()
			local text = "SELECT * FROM alumnos WHERE nombre = ? AND edad > ?"
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { text })
			query.refresh_view(state)
			local parameters = require("fox.query.parameters")
			local description = parameters.describe(text, "sqlite")
			local document = vim.b[state.active].fox_query_document
			assert(parameters.set(root, document, description, description.groups[1].key, "Ana"))
			assert(parameters.set(root, document, description, description.groups[2].key, "18"))
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { "SELECT * FROM alumnos WHERE edad > ?" })
			query.refresh_view(state)
			expect(vim.api.nvim_buf_get_lines(state.parameters_buf, 0, -1, false)).toEqual({ "Parameter 1 = 18" })
			vim.api.nvim_buf_set_lines(state.active, 0, -1, false, { text })
			query.refresh_view(state)
			expect(vim.api.nvim_buf_get_lines(state.parameters_buf, 0, -1, false)).toEqual({
				"nombre = <unset>",
				"Parameter 2 = 18",
			})
		end)
	end)

	it("shows only the active statement's parameters and executes persisted values without prompts", function()
		project(function(root)
			query.show("standard")
			local state = query.state()
			local buf = state.active
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				"SELECT * FROM t WHERE t.id = ? OR t.id = ?;",
				"SELECT 1;",
			})
			vim.api.nvim_win_set_cursor(state.sql_win, { 1, 0 })
			query.refresh_view(state)
			expect(vim.api.nvim_win_is_valid(state.parameters_win)).toBeTruthy()
			expect(vim.api.nvim_buf_get_lines(state.parameters_buf, 0, -1, false)).toEqual({ "t.id = <unset>" })
			local parameters = require("fox.query.parameters")
			local description = parameters.describe("SELECT * FROM t WHERE t.id = ? OR t.id = ?", "sqlite")
			query.parameters()
			local old_input = vim.ui.input
			local edited, edit_err = pcall(function()
				vim.ui.input = function(opts, callback)
					expect(opts.default).toBe("")
					callback("42")
				end
				vim.fn.maparg("<CR>", "n", false, true).callback()
			end)
			vim.ui.input = old_input
			assert(edited, edit_err)
			expect(parameters.values(root, vim.b[buf].fox_query_document, description)[description.groups[1].key]).toBe("42")
			local item, executed = state.consoles[buf], nil
			item.profile = { id = "test", engine = "sqlite", path = "test.db" }
			item.client = {
				connected = true,
				close = function() end,
				request = function(_, operation, data, callback)
					if operation == "prepare" then
						callback({ parameters = 2, statements = 1 })
					elseif operation == "execute" then
						executed = data.params
						callback({ sets = {} })
					end
				end,
			}
			query.run("statement")
			expect(executed).toEqual({ "42", "42" })
			vim.api.nvim_win_set_cursor(state.sql_win, { 2, 0 })
			query.refresh_view(state)
			expect(state.parameters_win).toBeNil()
			vim.api.nvim_win_set_cursor(state.sql_win, { 1, 0 })
			query.refresh_view(state)
			expect(vim.api.nvim_buf_get_lines(state.parameters_buf, 0, -1, false)).toEqual({ "t.id = 42" })
			query.show("visual")
			expect(state.parameters_win).toBeNil()
		end)
	end)
end)
