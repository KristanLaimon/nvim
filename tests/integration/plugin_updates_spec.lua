local t = require("fox.lib.foxnvim.test")

t.describe("installed plugin compatibility", function()
	t.it("compiles installed Treesitter queries against their parsers", function()
		require("lazy").load({ plugins = { "nvim-treesitter" } })
		local errors = {}
		local languages = require("nvim-treesitter.config").get_installed("parsers")
		assert(#languages > 0, "No installed parsers to check")
		for _, lang in ipairs(languages) do
			for _, kind in ipairs({ "highlights", "injections", "indents", "folds" }) do
				local ok, err = pcall(vim.treesitter.query.get, lang, kind)
				if not ok then
					errors[#errors + 1] = lang .. "/" .. kind .. ": " .. tostring(err)
				end
			end
		end
		assert(#errors == 0, table.concat(errors, "\n"))
		print("Checked Treesitter queries for " .. #languages .. " installed parsers")
	end)

	t.it("configures local JSON and YAML schemas with the current SchemaStore API", function()
		require("lazy").load({ plugins = { "nvim-lspconfig" } })
		local json = vim.lsp.config.jsonls.settings.json.schemas
		local yaml = vim.lsp.config.yamlls.settings.yaml.schemas
		local package_schema = false
		for _, schema in ipairs(json) do
			if schema.name == "package.json" then
				package_schema = schema.url:find("file://", 1, true) == 1
			end
		end
		assert(package_schema, "Local package.json schema override was lost")
		local golangci = false
		for url in pairs(yaml) do
			golangci = golangci or url:find("golangci.json", 1, true) ~= nil
		end
		assert(golangci, "Local YAML schema addition was lost")
	end)

	t.it("attaches Gitsigns and detects changes with the configured hunk mappings", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local previous = vim.api.nvim_get_current_buf()
		local buf
		local function git(args)
			local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
			assert(result.code == 0, result.stderr)
		end
		local ok, err = xpcall(function()
			git({ "init", "-q" })
			vim.fn.writefile({ "one", "two", "three" }, root .. "/sample.txt")
			git({ "add", "sample.txt" })
			git({ "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture" })
			vim.cmd.edit(vim.fn.fnameescape(root .. "/sample.txt"))
			buf = vim.api.nvim_get_current_buf()
			local gs = require("gitsigns")
			assert(
				vim.wait(5000, function()
					return vim.b[buf].gitsigns_head ~= nil
				end),
				"Gitsigns did not attach"
			)
			vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "changed" })
			assert(
				vim.wait(5000, function()
					return #(gs.get_hunks(buf) or {}) > 0
				end),
				"Gitsigns did not detect the change"
			)
			assert(vim.fn.maparg("]c", "n", false, true).buffer == 1)
			assert(type(gs.next_hunk) == "function" and type(gs.prev_hunk) == "function")
		end, debug.traceback)
		vim.api.nvim_set_current_buf(previous)
		if buf then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
