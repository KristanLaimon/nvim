local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local query = require("fox.query")
local storage = require("fox.query.storage")

describe("FoxQuerier UI and session integration", function()
	it("switches layouts without losing SQL and excludes SQL from generic sessions", function()
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		vim.fn.mkdir(root, "p")
		vim.api.nvim_set_current_dir(root)
		local spec = require("plugins.fox.tools.query")
		spec.config()
		expect(spec.keys[1][1]).toBe("<F3>")
		local ok, err = pcall(function()
			local editor = vim.api.nvim_get_current_buf()
			query.show("standard")
			local state = query.state()
			local buf = state.active
			expect(vim.wo[state.sql_win].winbar).toContain("Ctrl+Enter Run")
			expect(table.concat(vim.api.nvim_buf_get_lines(state.result_buf, 0, -1, false), "\n")).toContain("gC: choose")
			for _, pane in ipairs({ state.side_buf, state.result_buf, state.activity_buf, buf }) do
				vim.api.nvim_buf_call(pane, function()
					expect(vim.fn.maparg("<C-k>", "n", false, true).buffer).toBe(1)
					expect(vim.fn.maparg("gV", "n", false, true).buffer).toBe(1)
				end)
			end
			vim.api.nvim_buf_call(buf, function()
				local old_run, runs = query.run, 0
				query.run = function()
					runs = runs + 1
				end
				for _, mode in ipairs({ "n", "i" }) do
					vim.fn.maparg("<C-CR>", mode, false, true).callback()
				end
				query.run = old_run
				expect(runs).toBe(2)
			end)
			vim.api.nvim_set_current_win(state.result_win)
			vim.fn.maparg("<C-k>", "n", false, true).callback()
			expect(vim.api.nvim_get_current_win()).toBe(state.sql_win)
			expect(query.buffer_visible(buf)).toBeTruthy()
			expect(query.buffer_visible(editor)).toBeFalsy()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT 42 AS answer;" })
			vim.cmd("FoxModeToggle")
			expect(state.mode).toBe("editor")
			expect(vim.api.nvim_get_current_buf()).toBe(editor)
			vim.cmd("FoxModeToggle")
			expect(state.mode).toBe("query")
			expect(state.active).toBe(buf)
			query.show("visual")
			vim.api.nvim_set_current_tabpage(state.editor_tab)
			vim.cmd("FoxModeToggle")
			expect(vim.api.nvim_get_current_tabpage()).toBe(state.tab)
			expect(state.active).toBe(buf)
			expect(vim.bo[buf].modified).toBeTruthy()
			expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]).toBe("SELECT 42 AS answer;")
			local restore = query.suspend()
			local session = root .. "/generic.vim"
			vim.cmd("mksession! " .. vim.fn.fnameescape(session))
			local content = table.concat(vim.fn.readfile(session), "\n")
			expect(content:find(".foxnvim/query", 1, true) == nil).toBeTruthy()
			restore()
			expect(state.view).toBe("visual")
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("write")
			end)
			expect(query.workspace_save("test-workspace")).toBeTruthy()
			query.hide()
			expect(vim.api.nvim_get_current_buf()).toBe(editor)
			expect(query.buffer_visible(buf)).toBeFalsy()
			query.workspace_load("test-workspace")
			expect(query.state().view).toBe("visual")
			for _, item in pairs(state.consoles) do
				expect(item.client).toBeNil()
			end
			query.hide()
		end)
		query.close_root(root)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.b[buf].fox_query_root == storage.root(root) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
		vim.api.nvim_set_current_dir(cwd)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)

	it("connects and executes through the actual Python SQLite worker", function()
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		vim.fn.mkdir(root, "p")
		local fixture = vim
			.system({
				require("fox.query.client").python(),
				"-B",
				"-c",
				"import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('CREATE TABLE things(id INTEGER PRIMARY KEY,name TEXT)'); c.execute('INSERT INTO things VALUES(?,?)',(1,sys.argv[2])); c.commit(); c.close()",
				root .. "/fixture.db",
				"fox",
			}, { text = true })
			:wait()
		if fixture.code ~= 0 then
			error(fixture.stderr)
		end
		vim.api.nvim_set_current_dir(root)
		local ok, err = pcall(function()
			query.show("visual")
			local state = query.state()
			local buf = state.active
			query.connect({ id = "sqlite-test", engine = "sqlite", path = "fixture.db" }, state)
			local item = state.consoles[buf]
			expect(vim.wait(10000, function()
				return item.client.connected and not item.client.busy and item.metadata ~= nil
			end, 10)).toBeTruthy()
			expect(#state.metadata.tables).toBe(1)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT name FROM things WHERE id = ?;" })
			query.run("statement", "SELECT name, ? AS bound FROM things WHERE id = ?", { "safe'quote", "1" })
			expect(vim.wait(10000, function()
				return item.result ~= nil and not item.client.busy
			end, 10)).toBeTruthy()
			expect(item.result.sets[1].rows[1]).toEqual({ "fox", "safe'quote" })
			expect(vim.fn.filereadable(storage.path(root, "cache/" .. storage.fingerprint(item.profile) .. ".json"))).toBe(1)
			vim.bo[buf].modified = false
			query.hide()
		end)
		query.close_root(root)
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
	end)
end)

describe("FoxQuerier editing actions", function()
	it("previews a JOIN edit without execution and keeps unrelated buffers untouched", function()
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		vim.fn.mkdir(root, "p")
		vim.api.nvim_set_current_dir(root)
		local old_select, old_input = query.select, vim.ui.input
		local ok, err = pcall(function()
			query.show("visual")
			local state, sql_module = query.state(), require("fox.query.sql")
			local buf = state.active
			local metadata = {
				engine = "sqlite",
				tables = {
					{ key = "orders", name = "orders", columns = { { name = "id" }, { name = "customer_id" } } },
					{ key = "customers", name = "customers", columns = { { name = "id" } } },
				},
				relations = {
					{
						name = "customer_fk",
						source = "orders",
						target = "customers",
						columns = { { source = "customer_id", target = "id" } },
					},
				},
			}
			state.metadata, state.consoles[buf].metadata = metadata, metadata
			state.consoles[buf].profile = { id = "offline", engine = "sqlite", path = "unused.db" }
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT o.id FROM orders o WHERE o.id = 1;" })
			query.select = function(items, _, callback)
				callback(items[1], 1)
			end
			vim.ui.input = function(_, callback)
				callback("c")
			end
			query.insert_join(sql_module.table(metadata, "customers"))
			local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			expect(text).toContain('INNER JOIN "customers" AS "c" ON "o"."customer_id" = "c"."id"')
			expect(text:find("INNER JOIN", 1, true) < text:find("WHERE", 1, true)).toBeTruthy()
			expect(state.consoles[buf].client).toBeNil()
			vim.bo[buf].modified = false
			query.hide()
		end)
		query.select, vim.ui.input = old_select, old_input
		query.close_root(root)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.b[buf].fox_query_root == storage.root(root) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
		vim.api.nvim_set_current_dir(cwd)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)

	it("keeps a compact terminal usable through panel toggles", function()
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		local columns, lines = vim.o.columns, vim.o.lines
		vim.fn.mkdir(root, "p")
		vim.api.nvim_set_current_dir(root)
		local ok, err = pcall(function()
			vim.o.columns, vim.o.lines = 60, 18
			query.show("visual")
			local state = query.state()
			expect(state.compact).toBeTruthy()
			expect(#vim.api.nvim_tabpage_list_wins(state.tab)).toBe(2)
			expect(vim.api.nvim_win_get_height(state.activity_win)).toBe(1)
			query.focus_panel("side")
			expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(state.side_buf)
			query.results()
			expect(vim.api.nvim_win_get_buf(state.sql_win)).toBe(state.result_buf)
			query.focus_panel("activity")
			expect(vim.api.nvim_get_current_win()).toBe(state.activity_win)
			query.hide()
		end)
		query.close_root(root)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.b[buf].fox_query_root == storage.root(root) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
		vim.o.columns, vim.o.lines = columns, lines
		vim.api.nvim_set_current_dir(cwd)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)
end)
