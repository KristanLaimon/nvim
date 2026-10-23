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
end)
