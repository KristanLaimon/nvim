local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local mdx = require("fox.langs.mdx")

describe("MDX support", function()
	it("detects MDX separately from Markdown and maps its highlighting", function()
		mdx.setup()
		expect(vim.filetype.match({ filename = "page.mdx" })).toBe("mdx")
		expect(vim.filetype.match({ filename = "page.md" })).toBe("markdown")
		expect(vim.treesitter.language.get_lang("mdx")).toBe("markdown")
	end)

	it("aggregates an optional bundle, LSP, and formatter without expanding Lua core", function()
		local installer = require("fox.core.installer")
		local bundle
		local minimal = {}
		for _, entry in ipairs(installer.language_bundles) do
			if entry.name == mdx.bundle_name then
				bundle = entry
			end
			if entry.is_minimal then
				table.insert(minimal, entry.mason_pkgs)
			end
		end
		expect(bundle).toBeDefined()
		expect(bundle.is_minimal == true).toBe(false)
		expect(bundle.mason_pkgs).toEqual({ "mdx-analyzer", "prettier" })
		expect(bundle.treesitter).toEqual({ "markdown", "markdown_inline" })
		expect(minimal).toEqual({ { "lua-language-server", "stylua" } })
		local lsp = dofile("lua/plugins/lsp/lsp.lua")
		expect(lsp[2].opts().servers.mdx_analyzer).toBeDefined()
		local formatting = dofile("lua/plugins/lsp/formatting.lua")
		expect(formatting[1].opts().formatters_by_ft.mdx).toEqual({ "prettier" })
	end)
end)
