local t = require("fox.lib.foxnvim.test")
local dialect = require("fox.langs.sql.dialect")
local diagnostics = require("fox.langs.sql.diagnostics")
local storage = require("fox.query.storage")

t.describe("SQL dialect tooling", function()
	local root, buf, tab
	t.beforeEach(function()
		tab = vim.api.nvim_get_current_tabpage()
		vim.cmd("tabnew")
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		buf = vim.api.nvim_create_buf(false, true)
		vim.b[buf].fox_sql_root = storage.root(root)
	end)
	t.afterEach(function()
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.cmd("tabclose!")
		vim.api.nvim_set_current_tabpage(tab)
		vim.fn.delete(root, "rf")
	end)

	t.it("persists a file's dialect and prefers the sole engine or last project choice", function()
		t.expect(dialect.options(root)[1]).toBe("sqlite")
		storage.save(root, "settings.json", { diagram_columns = 22 })
		t.expect(dialect.set(buf, "postgres", root)).toBeTruthy()
		t.expect(dialect.read(buf)).toBe("postgres")
		t.expect(storage.load(root, "settings.json").diagram_columns).toBe(22)
		t.expect(dialect.options(root)[1]).toBe("postgres")
		storage.save(root, "connections.json", {
			profiles = {
				{ id = "only", engine = "mysql", host = "localhost", port = 3306, database = "app", user = "test" },
			},
		})
		t.expect(dialect.options(root)[1]).toBe("mysql")
		storage.write(root, "queries/one.sql", table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
		local state = { root = root, consoles = {} }
		t.expect(require("fox.query.files").rename(state, "one.sql", "two.sql")).toBeTruthy()
		local reopened = storage.document_buffer(root, "queries/two.sql", "sql")
		t.expect(dialect.ensure(reopened, root)).toBe("postgres")
		t.expect(vim.bo[reopened].modified).toBe(false)
		vim.api.nvim_buf_delete(reopened, { force = true })
	end)

	t.it("offers dialect functions with documentation even without a connection", function()
		for _, name in ipairs({ "mysql", "postgres", "sqlite" }) do
			dialect.set(buf, name, root)
			local items = {}
			require("fox.query.completion").new():get_completions({ bufnr = buf, cursor = { 1, 0 } }, function(response)
				for _, item in ipairs(response.items) do
					items[item.label] = item
				end
			end)
			local expected = ({ mysql = "CURDATE", postgres = "DATE_TRUNC", sqlite = "STRFTIME" })[name]
			t.expect(items[expected].documentation.value).toContain("Example:")
			t.expect(items[expected].documentation.value).toContain("Engine documentation")
			t.expect(items.SELECT.kind).toBe(14)
			t.expect(items.CURDATE ~= nil).toBe(name == "mysql")
		end
	end)

	t.it("shows Shift+K function signatures, explanations, examples and source links", function()
		local original, old_preview = vim.api.nvim_get_current_buf(), vim.lsp.util.open_floating_preview
		local received
		local ok, err = pcall(function()
			dialect.set(buf, "mysql", root)
			vim.api.nvim_buf_set_lines(buf, 1, -1, false, { "SELECT CURDATE();" })
			vim.api.nvim_set_current_buf(buf)
			vim.api.nvim_win_set_cursor(0, { 2, 9 })
			vim.lsp.util.open_floating_preview = function(lines)
				received = table.concat(lines, "\n")
			end
			require("fox.langs.sql").attach(buf, root)
			vim.api.nvim_buf_call(buf, function()
				vim.api.nvim_win_set_cursor(0, { 2, 9 })
				vim.fn.maparg("K", "n", false, true).callback()
			end)
			t.expect(received).toContain("CURDATE()")
			t.expect(received).toContain("session time zone")
			t.expect(received).toContain("SELECT CURDATE()")
		end)
		vim.lsp.util.open_floating_preview = old_preview
		vim.api.nvim_set_current_buf(original)
		if not ok then
			error(err)
		end
	end)

	t.it("keeps dialect checks on and general syntax checking off by default", function()
		dialect.set(buf, "sqlite", root)
		vim.api.nvim_buf_set_lines(
			buf,
			1,
			-1,
			false,
			{ "SELECT CURDATE(); -- NOW()", "SELECT 'CURDATE()';", "SELECT app.CURDATE();" }
		)
		diagnostics.check(buf)
		t.expect(vim.b[buf].fox_sql_syntax_status).toBe("general syntax off; dialect checks on")
		local found = vim.diagnostic.get(buf)
		t.expect(#found).toBe(1)
		t.expect(found[1].lnum).toBe(1)
		t.expect(found[1].col).toBe(7)
		t.expect(found[1].message).toContain("not a built-in SQLite")
		t.expect(#diagnostics.dialect_checks("SELECT CURDATE()", "mysql")).toBe(0)
		t.expect(#diagnostics.dialect_checks("SELECT custom_function()", "sqlite")).toBe(0)
	end)

	t.it("converts parser character offsets to editor byte offsets and ignores style rules", function()
		local parsed = diagnostics.parse(
			vim.json.encode({
				{
					violations = {
						{ code = "PRS", start_line_no = 1, start_line_pos = 9, description = "invalid SQL" },
						{ code = "LT01", start_line_no = 1, start_line_pos = 1, description = "spacing" },
					},
				},
			}),
			{ "SELECT é?" }
		)
		t.expect(#parsed).toBe(1)
		t.expect(parsed[1].col).toBe(9)
	end)

	t.it("checks real MySQL, PostgreSQL and SQLite syntax when SQLFluff is installed", function()
		if vim.fn.executable("sqlfluff") ~= 1 then
			return
		end
		storage.save(root, "settings.json", { sql_syntax_check = true })
		for name, expression in pairs({ mysql = "CURDATE()", postgres = "DATE_TRUNC('day', NOW())", sqlite = "DATE('now')" }) do
			dialect.set(buf, name, root)
			for _, text in ipairs({ "SELECT " .. expression .. ";", "SELECT FROM;" }) do
				vim.api.nvim_buf_set_lines(buf, 1, -1, false, { text })
				diagnostics.check(buf)
				t.expect(vim.wait(20000, function()
					return not vim.b[buf].fox_sql_syntax_status:match("^checking ")
				end, 20)).toBeTruthy()
				t.expect(vim.b[buf].fox_sql_syntax_status).toBe("checked " .. name)
				local found = vim.diagnostic.get(buf, { namespace = vim.api.nvim_create_namespace("fox_sql_syntax") })
				t.expect(#found > 0).toBe(text == "SELECT FROM;")
			end
		end
	end)
	t.it("discards an in-flight syntax response after the checker is disabled", function()
		dialect.set(buf, "sqlite", root)
		storage.save(root, "settings.json", { sql_syntax_check = true })
		local old_system, old_executable, old_exepath = vim.system, vim.fn.executable, vim.fn.exepath
		local completed, killed
		local ok, err = pcall(function()
			vim.fn.executable = function()
				return 1
			end
			vim.fn.exepath = function()
				return "sqlfluff"
			end
			vim.system = function(_, _, callback)
				completed = callback
				return {
					kill = function()
						killed = true
					end,
				}
			end
			diagnostics.check(buf)
			storage.save(root, "settings.json", { sql_syntax_check = false })
			diagnostics.check(buf)
			t.expect(killed).toBeTruthy()
			completed({ code = 1, stdout = '[{"violations":[{"code":"PRS","description":"stale"}]}]' })
			vim.wait(20)
			t.expect(vim.b[buf].fox_sql_syntax_status).toBe("general syntax off; dialect checks on")
			t.expect(#vim.diagnostic.get(buf)).toBe(0)
		end)
		vim.system, vim.fn.executable, vim.fn.exepath = old_system, old_executable, old_exepath
		if not ok then
			error(err)
		end
	end)
end)
