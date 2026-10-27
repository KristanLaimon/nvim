local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local parameters = require("fox.query.parameters")
local storage = require("fox.query.storage")

local function project(check)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local ok, err = pcall(check, root)
	vim.fn.delete(root, "rf")
	assert(ok, err)
end

describe("Query parameters", function()
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
