local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local parameters = require("fox.query.parameters")
local storage = require("fox.query.storage")

local function project(check)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local ok, err = pcall(check, root)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].fox_query_root == storage.root(root) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end
	vim.fn.delete(root, "rf")
	assert(ok, err)
end

describe("Query parameters", function()
	it("retains intentions through predicate reordering, insertion, deletion and restoration", function()
		project(function(root)
			local document = "queries/intentions.sql"
			local query = "SELECT * FROM alumnos WHERE nombre = ? AND edad > ? AND curso IN (?)"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			for index, value in ipairs({ "Ana", "18", "math" }) do
				assert(parameters.set(root, document, description, description.groups[index].key, value))
			end
			query = "SELECT nombre FROM alumnos WHERE curso IN (?) AND nombre = ? AND edad > ? ORDER BY nombre"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "math", "Ana", "18" })
			query = "SELECT nombre FROM alumnos WHERE curso IN (?) AND edad > ? ORDER BY nombre"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "math", "18" })
			query = "SELECT nombre FROM alumnos WHERE curso IN (?) AND nombre = ? AND edad > ? ORDER BY nombre"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			description = parameters.describe(query, "sqlite")
			local values = parameters.values(root, document, description)
			expect(values[description.groups[1].key]).toBe("math")
			expect(values[description.groups[2].key]).toBeNil()
			expect(values[description.groups[3].key]).toBe("18")
			query = "SELECT nombre FROM alumnos WHERE curso IN (?) AND apellido = ? AND edad > ? ORDER BY nombre"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			description = parameters.describe(query, "sqlite")
			values = parameters.values(root, document, description)
			expect(values[description.groups[2].key]).toBeNil()
			expect(values[description.groups[3].key]).toBe("18")
		end)
	end)

	it("forgets a deleted placeholder even when it is restored before the next redraw", function()
		project(function(root)
			local document = "queries/restore.sql"
			local query = "SELECT * FROM alumnos WHERE nombre = ? AND edad = ?"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			assert(parameters.set(root, document, description, description.groups[1].key, "Ana"))
			assert(parameters.set(root, document, description, description.groups[2].key, "20"))
			local column = query:find("?", 1, true) - 1
			vim.api.nvim_buf_set_text(buf, 0, column, 0, column + 1, { "" })
			vim.api.nvim_buf_set_text(buf, 0, column, 0, column, { "?" })
			local values = parameters.values(root, document, description)
			expect(values[description.groups[1].key]).toBeNil()
			expect(values[description.groups[2].key]).toBe("20")
		end)
	end)

	it("keeps surviving IN-list values when an indistinguishable leading slot is removed and restored", function()
		project(function(root)
			local document = "queries/list.sql"
			local query = "SELECT * FROM alumnos WHERE curso IN (?, ?, ?)"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			for index, value in ipairs({ "math", "physics", "art" }) do
				assert(parameters.set(root, document, description, description.groups[index].key, value))
			end
			local column = query:find("?", 1, true) - 1
			vim.api.nvim_buf_set_text(buf, 0, column, 0, column + 3, { "" })
			query = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "physics", "art" })
			vim.api.nvim_buf_set_text(buf, 0, column, 0, column, { "?, " })
			query = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
			description = parameters.describe(query, "sqlite")
			local values = parameters.values(root, document, description)
			expect(values[description.groups[1].key]).toBeNil()
			expect(values[description.groups[2].key]).toBe("physics")
			expect(values[description.groups[3].key]).toBe("art")
		end)
	end)

	it("preserves cut and pasted statements with their independent values", function()
		project(function(root)
			local document = "queries/move.sql"
			local first = "SELECT * FROM alumnos WHERE nombre = ?;"
			local second = "SELECT * FROM cursos WHERE nombre = ?;"
			assert(storage.write(root, document, first .. "\n" .. second))
			local buf = storage.document_buffer(root, document, "sql")
			for index, query in ipairs({ first:sub(1, -2), second:sub(1, -2) }) do
				local description = parameters.describe(query, "sqlite")
				assert(parameters.set(root, document, description, description.groups[1].key, index == 1 and "Ana" or "math"))
			end
			vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
			assert(parameters.sync(root, document))
			vim.api.nvim_buf_set_lines(buf, 1, 1, false, { first })
			expect(parameters.bound(root, document, second .. "\n" .. first, "sqlite")).toEqual({ "math", "Ana" })
		end)
	end)

	it("distinguishes FROM, comparison, function, BETWEEN, HAVING and pagination intentions", function()
		project(function(root)
			local document = "queries/clauses.sql"
			local query =
				"SELECT coalesce(?, name) FROM ? WHERE age BETWEEN ? AND ? AND name LIKE ? GROUP BY name HAVING count(*) > ? LIMIT ? OFFSET ?"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			for index, group in ipairs(description.groups) do
				assert(parameters.set(root, document, description, group.key, tostring(index)))
			end
			query =
				"SELECT name, coalesce(?, name) FROM ? WHERE name LIKE ? AND age BETWEEN ? AND ? GROUP BY name HAVING count(*) > ? LIMIT ? OFFSET ?"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "1", "2", "5", "3", "4", "6", "7", "8" })
		end)
	end)

	it("recognizes nested SQL roles rather than numbering their surrounding syntax", function()
		project(function(root)
			local cases = {
				{
					"SELECT CASE WHEN role = 'student' THEN ? WHEN role = 'teacher' THEN ? ELSE ? END FROM alumnos",
					"SELECT CASE WHEN role = 'teacher' THEN ? WHEN role = 'student' THEN ? ELSE ? END FROM alumnos",
					{ "2", "1", "3" },
				},
				{
					"INSERT INTO alumnos (nombre, edad) VALUES (?, ?)",
					"INSERT INTO alumnos (edad, nombre) VALUES (?, ?)",
					{ "2", "1" },
				},
				{
					"SELECT * FROM alumnos WHERE nombre = ?",
					"select * from alumnos where ((nombre = ?))",
					{ "1" },
				},
				{
					"SELECT * FROM profesores WHERE EXISTS (SELECT 1 FROM cursos c WHERE c.nombre = ?) AND EXISTS (SELECT 1 FROM alumnos a WHERE a.nombre = ?)",
					"SELECT * FROM profesores WHERE EXISTS (SELECT 1 FROM alumnos a WHERE a.nombre = ?) AND EXISTS (SELECT 1 FROM cursos c WHERE c.nombre = ?)",
					{ "2", "1" },
				},
				{
					"SELECT * FROM alumnos a LEFT JOIN cursos c ON c.id = ? WHERE a.nombre = ?",
					"SELECT * FROM alumnos a LEFT JOIN cursos c ON c.id = ? LEFT JOIN departments d ON d.id = 1 WHERE a.nombre = ?",
					{ "1", "2" },
				},
				{
					"WITH people AS (SELECT * FROM alumnos WHERE nombre = ?) SELECT * FROM people WHERE edad > ?",
					"WITH other AS (SELECT 1), people AS (SELECT * FROM alumnos WHERE nombre = ?) SELECT * FROM people WHERE edad > ?",
					{ "1", "2" },
				},
				{
					"SELECT * FROM alumnos a WHERE a.id = ? UNION SELECT * FROM cursos c WHERE c.id = ?",
					"SELECT * FROM cursos c WHERE c.id = ? UNION SELECT * FROM alumnos a WHERE a.id = ?",
					{ "2", "1" },
				},
			}
			for index, case in ipairs(cases) do
				local document = "queries/roles-" .. index .. ".sql"
				assert(storage.write(root, document, case[1]))
				local buf = storage.document_buffer(root, document, "sql")
				local description = parameters.describe(case[1], "sqlite")
				for position, group in ipairs(description.groups) do
					assert(parameters.set(root, document, description, group.key, tostring(position)))
				end
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { case[2] })
				local bound, err = parameters.bound(root, document, case[2], "sqlite")
				assert(bound, "SQL role case " .. index .. ": " .. tostring(err))
				expect(bound).toEqual(case[3])
			end
		end)
	end)

	it("migrates existing positional values and forgets deletions during incomplete SQL", function()
		project(function(root)
			local document = "queries/legacy.sql"
			local query = "SELECT * FROM alumnos WHERE nombre = ? AND edad = ?"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			assert(storage.save(root, "private/parameters.json", {
				[document] = { [description.id] = { ["position:1"] = "Ana", ["position:2"] = "20" } },
			}))
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "Ana", "20" })
			vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { "(" })
			local column = query:find("?", 1, true)
			vim.api.nvim_buf_set_text(buf, 0, column, 0, column + 1, { "" })
			assert(parameters.sync(root, document))
			vim.api.nvim_buf_set_text(buf, 0, column, 0, column, { "?" })
			vim.api.nvim_buf_set_text(buf, 0, 0, 0, 1, { "" })
			local values = parameters.values(root, document, description)
			expect(values[description.groups[1].key]).toBeNil()
			expect(values[description.groups[2].key]).toBe("20")
		end)
	end)

	it("forgets the last removed binding even if an older saved SQL version exists", function()
		project(function(root)
			local document = "queries/last.sql"
			local query = "SELECT * FROM alumnos WHERE nombre = ?"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			assert(parameters.set(root, document, description, description.groups[1].key, "Ana"))
			local history = assert(parameters.load(root))
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "SELECT * FROM alumnos WHERE nombre = 'Ana'" })
			assert(parameters.sync(root, document))
			assert(storage.save(root, "private/parameters.json", history))
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			expect(next(parameters.values(root, document, description))).toBeNil()
		end)
	end)

	it("preserves corrupt storage and retries the pending edit after it is repaired", function()
		project(function(root)
			local document = "queries/retry.sql"
			local query = "SELECT * FROM alumnos WHERE nombre = ?"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			assert(parameters.set(root, document, description, description.groups[1].key, "Ana"))
			local saved = storage.read(root, "private/parameters.json")
			assert(storage.write(root, "private/parameters.json", "{"))
			query = query .. " ORDER BY nombre"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			local ok, err = parameters.sync(root, document)
			expect(ok).toBeNil()
			expect(err).toContain("Invalid JSON")
			expect(storage.read(root, "private/parameters.json")).toBe("{")
			assert(storage.write(root, "private/parameters.json", saved))
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "Ana" })
		end)
	end)

	it("keeps values across SQL edits, new bindings, save and reopen without mixing statements", function()
		project(function(root)
			local document = "queries/edits.sql"
			local first = "SELECT * FROM alumnos WHERE nombre = ?"
			local second = "SELECT * FROM alumnos WHERE edad = ?"
			assert(storage.write(root, document, first .. ";\n" .. second))
			local buf = storage.document_buffer(root, document, "sql")
			for index, query in ipairs({ first, second }) do
				local description = parameters.describe(query, "sqlite")
				assert(parameters.set(root, document, description, description.groups[1].key, index == 1 and "Ana" or "20"))
			end
			for _, edited in ipairs({
				"SELECT nombre FROM alumnos WHERE nombre = ?",
				"SELECT nombre FROM alumnos WHERE nombre = ? ORDER BY nombre LIMIT 10",
				"SELECT nombre FROM alumnos WHERE nombre = ? AND edad > ?",
			}) do
				first = edited
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { first .. ";", second })
				local description = parameters.describe(first, "sqlite")
				expect(parameters.values(root, document, description)[description.groups[1].key]).toBe("Ana")
				expect(parameters.bound(root, document, second, "sqlite")).toEqual({ "20" })
			end
			local description = parameters.describe(first, "sqlite")
			expect(parameters.values(root, document, description)[description.groups[2].key]).toBeNil()
			assert(parameters.set(root, document, description, description.groups[2].key, "18"))
			-- Saving must also carry an edit forward before pruning old statement hashes.
			first = first .. " ORDER BY nombre"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { first .. ";", second })
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("write")
			end)
			vim.api.nvim_buf_delete(buf, { force = true })
			storage.document_buffer(root, document, "sql")
			expect(parameters.bound(root, document, first .. ";" .. second, "sqlite")).toEqual({ "Ana", "18", "20" })
		end)
	end)

	it("recognizes separate statements when both are edited", function()
		project(function(root)
			local document = "queries/separate.sql"
			local query = "SELECT * FROM alumnos WHERE nombre = ?"
			assert(storage.write(root, document, query .. "; SELECT * FROM cursos WHERE id = ?"))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			assert(parameters.set(root, document, description, description.groups[1].key, "Ana"))
			query = query .. " LIMIT 5"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query .. "; SELECT id FROM cursos WHERE id = ?" })
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "Ana" })
		end)
	end)

	it("keeps qualified values with their columns when predicates move", function()
		project(function(root)
			local document = "queries/columns.sql"
			local query = "SELECT * FROM alumnos a WHERE a.nombre = ? AND a.edad = ?"
			assert(storage.write(root, document, query))
			local buf = storage.document_buffer(root, document, "sql")
			local description = parameters.describe(query, "sqlite")
			assert(parameters.set(root, document, description, description.groups[1].key, "Ana"))
			assert(parameters.set(root, document, description, description.groups[2].key, "20"))
			query = "SELECT a.nombre FROM alumnos a WHERE a.edad = ? AND a.nombre = ?"
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { query })
			expect(parameters.bound(root, document, query, "sqlite")).toEqual({ "20", "Ana" })
		end)
	end)

	it("labels plain placeholders by appearance without suggesting numbered SQL syntax", function()
		project(function(root)
			local query = "SELECT * FROM alumnos WHERE nombre = ? AND edad = ?"
			local description = parameters.describe(query, "sqlite")
			expect(description.groups[1].label).toBe("Parameter 1")
			expect(description.groups[2].label).toBe("Parameter 2")
			local _, missing = parameters.bound(root, "queries/a.sql", query, "sqlite")
			expect(missing).toBe("Set Parameter 1 in Parameters, then run again")
			for index, value in ipairs({ "Ana", "20" }) do
				assert(parameters.set(root, "queries/a.sql", description, description.groups[index].key, value))
			end
			expect(parameters.bound(root, "queries/a.sql", query, "sqlite")).toEqual({ "Ana", "20" })
		end)
	end)

	it("shares qualified equality values but keeps ambiguous and nested placeholders separate", function()
		local description = parameters.describe(
			"SELECT * FROM users u WHERE u.id = ? OR u.id = ? AND id = ? AND EXISTS (SELECT 1 FROM users u WHERE u.id = ?)",
			"sqlite"
		)
		expect(#description.order).toBe(4)
		expect(#description.groups).toBe(3)
		expect(description.order[1]).toBe(description.order[2])
		expect(description.order[1] == description.order[4]).toBe(false)
		expect(description.groups[1].label).toBe("u.id")
	end)

	it("keeps aliases in different UNION branches separate", function()
		local description =
			parameters.describe("SELECT * FROM users u WHERE u.id = ? UNION SELECT * FROM orders u WHERE u.id = ?", "sqlite")
		expect(#description.groups).toBe(2)
	end)

	it("keeps different schemas and quoted identifier paths separate", function()
		local description =
			parameters.describe('SELECT * FROM a.t WHERE a.t.id = ? AND b.t.id = ? AND "a.t".id = ?', "sqlite")
		expect(#description.groups).toBe(3)
		expect(description.groups[1].label).toBe("a.t.id")
	end)

	it("ignores quoted questions, comments, and PostgreSQL JSON operators like the worker", function()
		local description = parameters.describe(
			"SELECT data ? 'key', data ?| array['a'], data ?& array['b'], '?' FROM items WHERE id = ? -- ?\n AND name = ?",
			"postgres"
		)
		expect(#description.order).toBe(2)
		expect(#parameters.describe("SELECT `?` FROM t WHERE id = ? # ?", "mysql").order).toBe(1)
		expect(parameters.describe("SELECT 'unfinished ?", "sqlite")).toBeNil()
	end)

	it("persists visible values and binds shared, empty, null and literal null values in order", function()
		project(function(root)
			local query = "SELECT * FROM t WHERE t.id = ? OR t.id = ? AND a = ? AND b = ? AND c = ?"
			local description = parameters.describe(query, "sqlite")
			local _, missing = parameters.bound(root, "queries/a.sql", query, "sqlite")
			expect(missing).toContain("Set t.id")
			for index, value in ipairs({ "visible", "", "NULL", "text:NULL" }) do
				assert(parameters.set(root, "queries/a.sql", description, description.groups[index].key, value))
			end
			local values = assert(parameters.bound(root, "queries/a.sql", query, "sqlite"))
			expect(values).toEqual({ "visible", "visible", "", vim.NIL, "NULL" })
			expect(storage.read(root, "private/parameters.json")).toContain("visible")
			expect(storage.read(root, ".gitignore")).toContain("private/")
		end)
	end)

	it("retains values when statements move and removes deleted statements on save", function()
		project(function(root)
			local query = "SELECT * FROM t WHERE t.id = ?"
			local description = parameters.describe(query, "sqlite")
			assert(parameters.set(root, "queries/a.sql", description, description.groups[1].key, "42"))
			local moved = "-- moved\n SELECT 1;\n" .. query .. ";"
			assert(parameters.prune(root, "queries/a.sql", moved, "sqlite"))
			expect(parameters.bound(root, "queries/a.sql", moved, "sqlite")).toEqual({ "42" })
			assert(parameters.relocate(root, "queries/a.sql", "queries/folder/b.sql"))
			expect(parameters.bound(root, "queries/folder/b.sql", query, "sqlite")).toEqual({ "42" })
			assert(parameters.prune(root, "queries/folder/b.sql", "SELECT 1", "sqlite"))
			expect(next(assert(parameters.load(root)))).toBeNil()
		end)
	end)

	it("does not overwrite malformed persisted values", function()
		project(function(root)
			assert(storage.write(root, "private/parameters.json", '{"queries/a.sql":{"bad":{"key":123}}}'))
			local description = parameters.describe("SELECT ?", "sqlite")
			local ok = parameters.set(root, "queries/a.sql", description, description.groups[1].key, "42")
			expect(ok).toBeNil()
			expect(storage.read(root, "private/parameters.json")).toContain("123")
		end)
	end)
end)
