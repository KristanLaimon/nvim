local t = require("fox.lib.foxnvim.test")
local snippets = require("fox.lsp.snippets")
t.describe("local snippet catalog", function()
	t.it("preserves every attributed JSON resource and the complete language manifest", function()
		local root = vim.fn.getcwd() .. "/config/snippet_catalog"
		local manifest = vim.json.decode(table.concat(vim.fn.readfile(root .. "/package.json"), "\n"))
		local languages = {}
		for _, item in ipairs(manifest.contributes.snippets) do
			t.expect(vim.fn.filereadable(root .. "/" .. item.path)).toBe(1)
			for _, ft in ipairs(type(item.language) == "table" and item.language or { item.language }) do
				languages[ft] = true
			end
		end
		for _, ft in ipairs({
			"all",
			"lua",
			"php",
			"blade",
			"javascript",
			"javascriptreact",
			"typescript",
			"typescriptreact",
			"astro",
			"svelte",
			"angular",
			"vue",
			"python",
			"cs",
			"csharp",
			"c",
			"cpp",
			"go",
			"rust",
			"ruby",
			"haskell",
			"zig",
			"sh",
			"ps1",
			"dockerfile",
			"yaml",
			"sql",
			"NeogitCommitMessage",
		}) do
			t.expect(languages[ft]).toBe(true)
		end
		local count, entries = 0, 0
		for _, file in ipairs(vim.fn.glob(root .. "/snippets/**/*.json", false, true)) do
			count = count + 1
			local data = vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
			entries = entries + vim.tbl_count(data)
			t.expect(#snippets.normalize(data) > 0).toBe(true)
		end
		t.expect(count).toBe(143)
		t.expect(entries).toBe(6194)
		t.expect(vim.fn.filereadable("licenses/friendly-snippets.txt")).toBe(1)
	end)
	t.it("handles prefix arrays, missing prefixes, descriptions and metadata safely", function()
		local result = snippets.normalize({
			["$schema"] = "./snippets.schema.json",
			bad = { prefix = "bad" },
			badbody = { body = { 123 } },
			badprefix = { body = "valid", prefix = false },
			valid = { prefix = { "first", "second" }, body = "${1:name} = $1$0", description = { "Some", " description" } },
			fallback = { body = { "one", "two" } },
		})
		t.expect(#result).toBe(3)
		t.expect(result[1].prefix).toBe("fallback")
		t.expect(result[2].body).toBe("${1:name} = $1$0")
		t.expect(result[3].description).toBe("Some description")
		t.expect(#snippets.normalize(false)).toBe(0)
	end)
end)
