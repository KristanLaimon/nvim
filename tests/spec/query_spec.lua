local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local sql = require("fox.query.sql")
local storage = require("fox.query.storage")
local render = require("fox.query.render")

local metadata = {
	tables = {
		{
			key = "orders",
			name = "orders",
			columns = {
				{ name = "id", type = "int" },
				{ name = "customer_id", type = "int" },
				{ name = "total", type = "decimal" },
			},
		},
		{
			key = "customers",
			name = "customers",
			columns = { { name = "id", type = "int" }, { name = "name", type = "text" } },
		},
	},
	relations = {
		{
			name = "customer",
			source = "orders",
			target = "customers",
			columns = { { source = "customer_id", target = "id" } },
		},
	},
}

describe("FoxQuerier SQL structure", function()
	it("resolves aliases and distinguishes output/join/filter columns", function()
		local graph = sql.analyze(
			"SELECT o.id, c.name FROM orders o LEFT JOIN customers c ON c.id = o.customer_id WHERE o.id = ?",
			metadata
		)
		expect(#graph.nodes).toBe(2)
		expect(graph.nodes[1].roles.id.output).toBeTruthy()
		expect(graph.nodes[1].roles.id.filter).toBeTruthy()
		expect(graph.nodes[1].roles.customer_id.join).toBeTruthy()
		expect(graph.nodes[2].roles.name.output).toBeTruthy()
		expect(graph.edges[1].kind:upper()).toBe("LEFT")
	end)
	it("keeps self-join instances and incomplete input distinct", function()
		local graph = sql.analyze("SELECT a.id, b.id FROM orders a JOIN orders b ON a.id = b.id", metadata)
		expect(#graph.nodes).toBe(2)
		expect(graph.nodes[1].alias).toBe("a")
		expect(graph.nodes[2].alias).toBe("b")
		expect(sql.analyze("SELECT * FROM", metadata).partial).toBeTruthy()
		expect(sql.analyze(string.rep(" ", 128 * 1024 + 1), metadata).partial).toBeTruthy()
	end)
	it("does not split SQL at semicolons in quotes/comments", function()
		local statements = sql.statements("SELECT ';'; -- ;\n SELECT 'x';")
		expect(#statements).toBe(2)
		expect(statements[1].sql).toBe("SELECT ';'")
		expect(sql.statements("SELECT '('; SELECT 2")[1].sql).toBe("SELECT '('")
		expect(sql.scope("SELECT 'x\\'; SELECT 2", 20, "statement", nil, "sqlite")).toContain("SELECT 2")
		expect(sql.scope("SELECT 'unfinished", 4, "statement")).toBeNil()
	end)
	it("generates FK joins safely and rejects unsafe aliases", function()
		local graph = sql.analyze("SELECT * FROM orders o", metadata)
		local candidates = sql.join_candidates(metadata, graph)
		expect(sql.join_sql(candidates[1], "c", "LEFT", "mysql")).toBe(
			"LEFT JOIN `customers` AS `c` ON `o`.`customer_id` = `c`.`id`"
		)
		expect(sql.join_sql(candidates[1], "bad alias;", "LEFT", "mysql")).toBeNil()
	end)

	it("preserves every composite-key predicate in either direction", function()
		local composite = vim.deepcopy(metadata)
		composite.relations[1].columns[2] = { source = "tenant_id", target = "tenant_id" }
		local forward = sql.join_candidates(composite, sql.analyze("SELECT * FROM orders o", composite))[1]
		local reverse = sql.join_candidates(composite, sql.analyze("SELECT * FROM customers c", composite))[1]
		expect(sql.join_sql(forward, "c", "INNER", "postgres")).toContain('AND "o"."tenant_id" = "c"."tenant_id"')
		expect(sql.join_sql(reverse, "o", "LEFT", "postgres")).toContain('"c"."id" = "o"."customer_id"')
	end)

	it("identifies actual JOIN endpoints and marks ambiguous columns partial", function()
		local graph = sql.analyze(
			"SELECT a.id FROM orders a LEFT OUTER JOIN customers b ON b.id = a.customer_id JOIN orders c ON c.id = a.id",
			metadata
		)
		expect(graph.edges[1].kind:upper()).toBe("LEFT")
		expect(graph.edges[2].source).toBe("a")
		expect(sql.analyze("SELECT id FROM orders a JOIN customers b ON b.id=a.customer_id", metadata).partial).toBeTruthy()
	end)
	it("renders related tables as context instead of executed joins", function()
		local graph = sql.analyze("SELECT o.id FROM orders o", metadata)
		local lines = render.graph(graph, metadata)
		expect(table.concat(lines, "\n")).toContain("related, not joined")
		expect(#graph.edges).toBe(0)
	end)

	it("connects table cards and inspects the card under the cursor", function()
		local graph = sql.analyze("SELECT o.id, c.name FROM orders o JOIN customers c ON c.id=o.customer_id", metadata)
		local lines, _, objects = render.graph(graph, metadata, 60)
		local left, right
		for row, object in pairs(objects) do
			if object.regions and #object.regions == 2 then
				left = render.object_at(objects, row, object.regions[1].first)
				right = render.object_at(objects, row, object.regions[2].first)
				break
			end
		end
		expect(left.key).toBe("orders")
		expect(right.key).toBe("customers")
		expect(table.concat(lines, "\n")).toContain(">")
	end)
end)

describe("FoxQuerier project persistence", function()
	it("isolates notes/cache and preserves user documents on cache deletion", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local ok, err = pcall(function()
			expect(storage.write(root, "notes/example.md", "business note")).toBeTruthy()
			expect(storage.save(root, "cache/example.json", metadata)).toBeTruthy()
			vim.fn.delete(storage.path(root, "cache/example.json"))
			expect(storage.read(root, "notes/example.md")).toBe("business note")
			expect(storage.fingerprint({ id = "same", host = "a" }) == storage.fingerprint({ id = "same", host = "b" })).toBeFalsy()
			expect(pcall(storage.path, root, "../outside")).toBeFalsy()
		end)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)
	it("does not overwrite corrupted profiles or accept plaintext passwords", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		storage.write(root, "connections.json", "bad JSON")
		local data, err = storage.profiles(root)
		expect(data).toBeNil()
		expect(err).toContain("original file preserved")
		expect(storage.read(root, "connections.json")).toBe("bad JSON")
		expect(storage.validate({ id = "test", engine = "sqlite", path = "test.db", password = "secret" })).toBeNil()
		vim.fn.delete(root, "rf")
	end)

	it("rejects structurally invalid cache JSON without overwriting it", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		storage.save(root, "cache/test.json", { tables = { 42 }, relations = {} })
		local data, err = storage.cache(root, "test")
		expect(data).toBeNil()
		expect(err).toContain("Invalid")
		expect(storage.read(root, "cache/test.json")).toContain("42")
		vim.fn.delete(root, "rf")
	end)
end)
