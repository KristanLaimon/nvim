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
	it("includes derived, scalar, predicate and nested subqueries with scoped aliases", function()
		for _, text in ipairs({
			"SELECT d.id FROM (SELECT o.id FROM orders o) AS d",
			"SELECT (SELECT MAX(o.total) FROM orders o) FROM customers c",
			"SELECT c.id FROM customers c WHERE c.id IN (SELECT o.customer_id FROM orders o)",
			"SELECT d.id FROM (SELECT x.id FROM (SELECT o.id FROM orders o) x) d",
		}) do
			local graph = sql.analyze(text, metadata)
			local nodes = vim.tbl_filter(function(node)
				return node.table and node.table.key == "orders"
			end, graph.nodes)
			expect(#nodes).toBe(1)
			expect(nodes[1].nested).toBeTruthy()
			local lines = table.concat(render.graph(graph, metadata, 90), "\n")
			expect(lines).toContain("SUBQUERY")
			expect(lines).toContain("orders")
		end
		local graph =
			sql.analyze("SELECT o.id FROM orders o WHERE EXISTS (SELECT o.id FROM customers o WHERE o.id = 1)", metadata)
		expect(graph.nodes[1].roles.id.filter).toBeNil()
		expect(graph.nodes[3].roles.id.filter).toBeTruthy()
		graph = sql.analyze(
			"SELECT c.id FROM customers c WHERE EXISTS (SELECT o.id FROM orders o WHERE o.customer_id = c.id)",
			metadata
		)
		expect(graph.edges[1].kind).toBe("CORRELATED")
		expect(graph.edges[1].source).toBe("c")
	end)
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
		expect(sql.join_sql(candidates[1], "c", "LEFT", "mysql")).toBe("LEFT JOIN customers AS c ON o.customer_id = c.id")
		expect(sql.join_sql(candidates[1], "bad alias;", "LEFT", "mysql")).toBeNil()
		expect(sql.join_sql(candidates[1], "c", "LEFT", "sqlite")).toBe("LEFT JOIN customers AS c ON o.customer_id = c.id")
		local unusual = vim.deepcopy(candidates[1])
		unusual.target_table.name = "Order"
		unusual.relation.columns[1].target = 'odd"column'
		expect(sql.join_sql(unusual, "c", "LEFT", "sqlite")).toBe(
			'LEFT JOIN "Order" AS c ON o.customer_id = c."odd""column"'
		)
		expect(sql.suggest_alias({ name = "PlayerSecondaryNames" }, { nodes = { { alias = "PSN" }, { alias = "psn2" } } })).toBe(
			"psn3"
		)
		expect(sql.suggest_alias({ name = "player_trust" }, { nodes = {} })).toBe("pt")
	end)

	it("generates MySQL JOINs without quotes for ordinary schema, table, alias, and column names", function()
		local candidate = {
			node = { alias = "materias", table = { key = "materias" } },
			target_table = { schema = "escolar", name = "modulos_especialidad" },
			relation = {
				source = "materias",
				columns = { { source = "modulo_especialidad_id", target = "id" } },
			},
		}
		expect(sql.join_sql(candidate, "me", "INNER", "mysql")).toBe(
			"INNER JOIN escolar.modulos_especialidad AS me ON materias.modulo_especialidad_id = me.id"
		)
		candidate.target_table.name = "order"
		candidate.relation.columns[1].target = "odd`column"
		expect(sql.join_sql(candidate, "me", "LEFT", "mysql")).toBe(
			"LEFT JOIN escolar.`order` AS me ON materias.modulo_especialidad_id = me.`odd``column`"
		)
	end)

	it("generates PostgreSQL JOINs with quotes only when required", function()
		local candidate = {
			node = { alias = "quote", table = { key = "public.quote" } },
			target_table = { schema = "public", name = "rental_document" },
			relation = { source = "public.quote", columns = { { source = "rental_document_id", target = "id" } } },
		}
		expect(sql.join_sql(candidate, "rd", "INNER", "postgres")).toBe(
			"INNER JOIN public.rental_document AS rd ON quote.rental_document_id = rd.id"
		)
		for _, name in ipairs({ "user", "authorization", "RentalDocument", "rental document", 'odd"name' }) do
			candidate.target_table.name = name
			expect(sql.join_sql(candidate, "rd", "LEFT", "postgres")).toContain(sql.quote(name, "postgres"))
		end
		candidate.target_table.name = "rental_document"
		candidate.target_table.schema = "CustomSchema"
		candidate.node.alias = "Quote"
		candidate.relation.columns[1].target = "ID"
		expect(sql.join_sql(candidate, "User", "INNER", "postgres")).toBe(
			'INNER JOIN "CustomSchema".rental_document AS "User" ON "Quote".rental_document_id = "User"."ID"'
		)
	end)

	it("preserves every composite-key predicate in either direction", function()
		local composite = vim.deepcopy(metadata)
		composite.relations[1].columns[2] = { source = "tenant_id", target = "tenant_id" }
		local forward = sql.join_candidates(composite, sql.analyze("SELECT * FROM orders o", composite))[1]
		local reverse = sql.join_candidates(composite, sql.analyze("SELECT * FROM customers c", composite))[1]
		expect(sql.join_sql(forward, "c", "INNER", "postgres")).toContain("AND o.tenant_id = c.tenant_id")
		expect(sql.join_sql(reverse, "o", "LEFT", "postgres")).toContain("c.id = o.customer_id")
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
	it("keeps live query cards compact even in a wide sidebar", function()
		for _, text in ipairs({ "SELECT * FROM orders", "SELECT o.id FROM orders o JOIN customers c ON c.id=o.customer_id" }) do
			local graph = sql.analyze(text, metadata)
			local lines, _, objects = render.graph(graph, metadata, 160)
			for _, row in pairs(objects) do
				for _, region in ipairs(row.regions or {}) do
					expect(region.last - region.first).toBe(28)
				end
			end
			expect(vim.fn.strdisplaywidth(lines[4])).toBe(#graph.nodes == 1 and 28 or 63)
		end
	end)

	it("puts the focused schema table before its nearest neighbors and fills the available width", function()
		local schema = {
			tables = {
				{ key = "ADistant", name = "ADistant", columns = { { name = "bridge_id" } } },
				{
					key = "Bridge",
					name = "Bridge",
					columns = {
						{ name = "id", pk = true },
						{ name = "player_id" },
						{ name = "a_long_column_name_that_used_to_be_clipped" },
					},
				},
				{ key = "PlayerKisses", name = "PlayerKisses", columns = { { name = "member_1" } } },
				{ key = "Player", name = "Player", columns = { { name = "id", pk = true } } },
			},
			relations = {
				{
					name = "internal:0",
					source = "ADistant",
					target = "Bridge",
					columns = { { source = "bridge_id", target = "id" } },
				},
				{
					name = "internal:1",
					source = "Bridge",
					target = "Player",
					columns = { { source = "player_id", target = "id" } },
				},
				{
					name = "internal:2",
					source = "PlayerKisses",
					target = "Player",
					columns = { { source = "member_1", target = "id" } },
				},
			},
		}
		local nearby = render.neighborhood(schema, "Player", 2)
		expect(nearby[1].key).toBe("Player")
		expect(nearby[2].key).toBe("Bridge")
		expect(nearby[4].key).toBe("ADistant")
		local lines, objects, highlights = render.map(schema, "Player", 2, 160)
		expect(table.concat(lines, "\n")).toContain("> Player")
		expect(next(objects) ~= nil).toBeTruthy()
		expect(table.concat(lines, "\n")).toContain("a_long_column_name_that_used_to_be_clipped")
		expect(table.concat(lines, "\n"):find("internal:", 1, true)).toBeNil()
		local foreign, primary = false, false
		for _, span in ipairs(highlights) do
			local text = span[3] and lines[span[1] + 1]:sub(span[3] + 1, span[4]) or ""
			if span[2] == "DiagnosticInfo" and text:find("player_id", 1, true) then
				foreign = true
			end
			if span[2] == "Identifier" and text:find("PK", 1, true) then
				primary = true
			end
		end
		expect(foreign).toBeTruthy()
		expect(primary).toBeTruthy()
		expect(schema.tables[1].key).toBe("ADistant")
		local single = render.map({ tables = { schema.tables[4] }, relations = {} }, "Player", 1, 160)
		expect(table.concat(single, "\n")).toContain("> Player")
	end)
end)

describe("FoxQuerier project persistence", function()
	it("persists passwords privately, isolates connection identities, and preserves corrupt files", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local profile = { id = "mysql", engine = "mysql", host = "localhost", user = "test" }
		local ok, err = pcall(function()
			storage.write(root, ".gitignore", "custom/\n")
			expect(storage.password(root, profile)).toBeNil()
			expect(storage.password(root, profile, "private-secret")).toBeTruthy()
			expect(storage.password(root, profile)).toBe("private-secret")
			expect(storage.read(root, ".gitignore")).toContain("custom/\nprivate/\n")
			local path = "private/passwords/" .. storage.fingerprint(profile) .. ".json"
			if vim.fn.has("win32") == 0 then
				expect(vim.fn.getfperm(storage.path(root, path))).toBe("rw-------")
			end
			expect(storage.password(root, vim.tbl_extend("force", profile, { host = "other" }))).toBeNil()
			expect(storage.password(root, profile, "")).toBeTruthy()
			expect(storage.password(root, profile)).toBe("")
			storage.write(root, path, "broken JSON")
			local value, load_err = storage.password(root, profile)
			expect(value).toBeNil()
			expect(load_err).toContain("original file preserved")
			expect(storage.read(root, path)).toBe("broken JSON")
		end)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)
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
