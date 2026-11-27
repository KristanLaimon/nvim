local t = require("fox.lib.foxnvim.test")
local toolchain = require("fox.langs.toolchain")

t.describe("current language toolchain", function()
	t.it("persists an ordered choice and distinguishes an empty selection from a reset", function()
		local root = vim.fn.tempname()
		local ctx = { root = root, path = root .. "/toolchain.json", ft = "typescript" }
		local defaults = { "prettier", "biome" }
		local function selected()
			return toolchain.selection(toolchain.read(ctx, true), "formatters", defaults)
		end
		t.expect(toolchain.save(ctx, "formatters", { "biome", "prettier" })).toBe(true)
		t.expect(selected()).toEqual({ "biome", "prettier" })
		t.expect(toolchain.save(ctx, "formatters", {})).toBe(true)
		t.expect(selected()).toEqual({})
		t.expect(toolchain.save(ctx, "formatters", nil)).toBe(true)
		t.expect(selected()).toEqual(defaults)
		vim.fn.delete(root, "rf")
	end)

	t.it("resolves native config markers without allowing directory traversal", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/src", "p")
		local buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(buf, root .. "/src/example.ts")
		vim.fn.writefile({ "{}" }, root .. "/custom.json")
		local ctx = { root = root, buf = buf }
		t.expect(toolchain.find_config(ctx, { "custom.json" })).toBe(vim.fs.joinpath(root, "custom.json"))
		t.expect(toolchain.valid_filename("../custom.json")).toBe(false)
		t.expect(toolchain.valid_filename("..\\custom.json")).toBe(false)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(root, "rf")
	end)

	t.it("does not start an LSP whose executable is missing", function()
		local buf = vim.api.nvim_create_buf(false, false)
		local started = false
		local old_notify = vim.notify
		local message
		vim.notify = function(text)
			message = text
		end
		toolchain.wrap_root("fox_missing_test_lsp", { cmd = { "fox_missing_test_executable" } })(buf, function()
			started = true
		end)
		vim.wait(1000, function()
			return message ~= nil
		end)
		vim.notify = old_notify
		t.expect(started).toBe(false)
		t.expect(message).toContain("LSP fox_missing_test_lsp not installed yet")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
