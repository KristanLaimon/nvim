local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("FoxVim formatter installation", function()
	it("uses Mason tools without an automatic formatter installation bridge", function()
		local specs = dofile(vim.fn.stdpath("config") .. "/lua/plugins/lsp/formatting.lua")
		expect(#specs).toBe(1)
		expect(specs[1][1]).toBe("stevearc/conform.nvim")
		expect(specs[1].dependencies).toEqual({ "williamboman/mason.nvim" })

		local opts = specs[1].opts()
		for _, lang in pairs(require("fox.langs").langs) do
			for ft, formatters in pairs(lang.formatters_by_ft or {}) do
				expect(opts.formatters_by_ft[ft]).toEqual(formatters)
			end
			for name, formatter in pairs(lang.conform_formatters or {}) do
				expect(opts.formatters[name]).toEqual(formatter)
			end
		end
	end)

	it("keeps every managed formatter available in its language bundle", function()
		local installer = require("fox.core.installer")
		for _, lang in pairs(require("fox.langs").langs) do
			for name, tool in pairs(lang.mason or {}) do
				if tool.type == "formatter" and vim.tbl_contains(lang.mason_order or {}, name) then
					local found = false
					for _, bundle in ipairs(installer.language_bundles) do
						if bundle.name == lang.bundle_name then
							found = vim.tbl_contains(bundle.mason_pkgs, name)
						end
					end
					expect(found).toBe(true, name .. " missing from language bundle")
				end
			end
		end
	end)

	it("returns only formatter names from default fallback lists", function()
		local spec = dofile(vim.fn.stdpath("config") .. "/lua/plugins/lsp/formatting.lua")[1]
		local opts = spec.opts()
		local old_conform = package.loaded.conform
		package.loaded.conform = {
			setup = function() end,
			get_formatter_info = function()
				return {}
			end,
		}
		spec.config(nil, opts)
		local list = opts.formatters_by_ft.astro(vim.api.nvim_get_current_buf())
		for _, name in ipairs(list) do
			expect(type(name)).toBe("string")
		end
		expect(list.stop_after_first).toBe(true)
		package.loaded.conform = old_conform
	end)

	it("allows PHP formatters longer to finish on save", function()
		local opts = dofile(vim.fn.stdpath("config") .. "/lua/plugins/lsp/formatting.lua")[1].opts()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].filetype = "php"
		expect(opts.format_on_save(buf).timeout_ms).toBe(10000)
		vim.bo[buf].filetype = "lua"
		expect(opts.format_on_save(buf).timeout_ms).toBe(1000)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
