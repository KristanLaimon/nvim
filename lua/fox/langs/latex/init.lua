-- ============================================================================
-- FOX LATEX: LaTeX and BibTeX Language Configuration
-- ============================================================================

---@type FoxLangModule
local M = {}

M.lsp_server = { "texlab" }
M.lsp_config = {
	texlab = {},
}

M.mason = {
	texlab = { mason = "texlab", lang = "LaTeX / BibTeX", type = "lsp", cmd = "texlab" },
	latexindent = { mason = "latexindent", name = "latexindent", type = "formatter", cmd = "latexindent" },
}
M.mason_order = { "texlab", "latexindent" }
M.bundle_name = "📄 LaTeX / BibTeX"
M.treesitter = { "latex", "bibtex" }

M.health_tools = {
	{ cmd = "latexmk", name = "latexmk", note = "LaTeX PDF builds; install with MiKTeX or TeX Live" },
	{ cmd = "pdflatex", name = "pdfLaTeX", note = "default PDF engine; provided by MiKTeX or TeX Live" },
	{ cmd = "perl", name = "Perl", note = "latexmk script runtime; MiKTeX requires a separate Perl installation" },
}

M.formatters_by_ft = {
	tex = { "latexindent" },
	plaintex = { "latexindent" },
}

M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "tex", "plaintex", "bib" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
