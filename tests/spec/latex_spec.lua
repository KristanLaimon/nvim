local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local latex = require("fox.langs.latex")

describe("fox.langs.latex", function()
	local buf
	t.beforeEach(function()
		buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].shiftwidth = 8
	end)
	t.afterEach(function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("applies two-space indentation when no EditorConfig is present", function()
		latex.apply_defaults(buf)
		expect(vim.bo[buf].shiftwidth).toBe(2)
		expect(vim.bo[buf].expandtab).toBe(true)
	end)

	it("preserves indentation supplied by EditorConfig", function()
		vim.b[buf].editorconfig_applied = true
		latex.apply_defaults(buf)
		expect(vim.bo[buf].shiftwidth).toBe(8)
	end)

	it("leaves BibTeX formatting to the language server", function()
		expect(latex.formatters_by_ft.tex).toEqual({ "latexindent" })
		expect(latex.formatters_by_ft.plaintex).toEqual({ "latexindent" })
		expect(latex.formatters_by_ft.bib).toBe(nil)
	end)
end)
