-- ============================================================================
-- COLORSCHEME: nagatoro-light -- Doki Theme "Hayase Nagatoro Light", ported.
-- ============================================================================

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

vim.g.colors_name = "nagatoro-light"

local p = {
	bg = "#FAFAFA",
	bg_dark = "#F0F0F0",
	bg_highlight = "#EAEAEA",
	bg_selected = "#E2D0C6",
	fg = "#2A2A2A",
	fg_muted = "#666666",
	comment = "#7A8288",

	keyword = "#4A5BB2",
	func = "#C28500",
	string = "#456D8A",
	number = "#B34289",
	type = "#299999",
	operator = "#2E9931",
	declaration = "#A81D80",
	accent = "#C45B1E",
	error = "#D91E1E",
	warning = "#D9821E",
	none = "NONE",
}

local highlights = {
	Normal = { fg = p.fg, bg = p.bg },
	NormalNC = { fg = p.fg, bg = p.bg },
	NormalFloat = { fg = p.fg, bg = p.bg_dark },
	FloatBorder = { fg = p.accent, bg = p.bg_dark },
	FloatTitle = { fg = p.accent, bg = p.bg_dark, bold = true },
	Cursor = { fg = p.bg, bg = p.accent },
	CursorLine = { bg = p.bg_highlight },
	CursorColumn = { bg = p.bg_highlight },
	ColorColumn = { bg = p.bg_dark },
	LineNr = { fg = "#A0A0A0" },
	CursorLineNr = { fg = p.accent, bold = true },
	VertSplit = { fg = "#D0D0D0", bg = p.none },
	WinSeparator = { fg = "#D0D0D0", bg = p.none },
	MatchParen = { fg = p.accent, bg = p.bg_selected, bold = true },

	Visual = { bg = p.bg_selected },
	VisualNOS = { bg = p.bg_selected },
	Search = { fg = p.fg, bg = p.bg_selected },
	IncSearch = { fg = p.bg, bg = p.accent, bold = true },
	CurSearch = { fg = p.bg, bg = p.accent, bold = true },

	StatusLine = { fg = p.fg, bg = p.bg_dark },
	StatusLineNC = { fg = p.fg_muted, bg = p.bg_dark },
	TabLine = { fg = p.fg_muted, bg = p.bg_dark },
	TabLineFill = { bg = p.bg_dark },
	TabLineSel = { fg = p.accent, bg = p.bg, bold = true },

	Pmenu = { fg = p.fg, bg = p.bg_dark },
	PmenuSel = { fg = p.fg, bg = p.bg_selected, bold = true },
	PmenuSbar = { bg = p.bg_dark },
	PmenuThumb = { bg = p.accent },

	Comment = { fg = p.comment, italic = true },
	Constant = { fg = p.number },
	String = { fg = p.string },
	Character = { fg = p.string },
	Number = { fg = p.number },
	Boolean = { fg = p.keyword, bold = true },
	Float = { fg = p.number },

	Identifier = { fg = p.fg },
	Function = { fg = p.func, bold = true },
	Statement = { fg = p.keyword, bold = true },
	Conditional = { fg = p.keyword, bold = true },
	Repeat = { fg = p.keyword, bold = true },
	Label = { fg = p.keyword },
	Operator = { fg = p.operator },
	Keyword = { fg = p.keyword, bold = true },
	Exception = { fg = p.error, bold = true },

	PreProc = { fg = p.accent },
	Include = { fg = p.keyword },
	Define = { fg = p.keyword },
	Macro = { fg = p.keyword },

	Type = { fg = p.type, bold = true },
	StorageClass = { fg = p.keyword, bold = true },
	Structure = { fg = p.type },
	Typedef = { fg = p.type },

	Special = { fg = p.accent },
	Delimiter = { fg = p.fg },
	Error = { fg = p.error, bold = true },
	Todo = { fg = p.bg, bg = p.accent, bold = true },

	["@comment"] = { fg = p.comment, italic = true },
	["@variable"] = { fg = p.fg },
	["@variable.builtin"] = { fg = p.keyword, italic = true },
	["@function"] = { fg = p.func, bold = true },
	["@keyword"] = { fg = p.keyword, bold = true },
	["@string"] = { fg = p.string },
	["@number"] = { fg = p.number },
	["@type"] = { fg = p.type, bold = true },
	["@property"] = { fg = p.fg, bold = true },
	["@operator"] = { fg = p.operator },

	DiagnosticError = { fg = p.error },
	DiagnosticWarn = { fg = p.warning },
	DiagnosticInfo = { fg = p.keyword },
	DiagnosticHint = { fg = p.type },

	GitSignsAdd = { fg = p.operator },
	GitSignsChange = { fg = p.warning },
	GitSignsDelete = { fg = p.error },
	DiffAdd = { bg = "#E2F0E2", fg = p.operator },
	DiffChange = { bg = "#FFF0D6", fg = p.warning },
	DiffDelete = { bg = "#FCE4E4", fg = p.error },

	NeoTreeNormal = { fg = p.fg, bg = p.bg_dark },
	NeoTreeDirectoryName = { fg = p.accent, bold = true },
	TelescopeNormal = { fg = p.fg, bg = p.bg_dark },
	TelescopeBorder = { fg = p.accent, bg = p.bg_dark },
	TelescopeSelection = { fg = p.fg, bg = p.bg_selected, bold = true },

	-- NvChad Style Completion Kind Icon Highlights (Background + Accent)
	CmpKindBg_Function = { fg = p.bg, bg = p.func, bold = true },
	CmpKindBg_Method = { fg = p.bg, bg = p.func, bold = true },
	CmpKindBg_Constructor = { fg = p.bg, bg = p.func, bold = true },
	CmpKindBg_Snippet = { fg = p.bg, bg = p.declaration, bold = true },
	CmpKindBg_Variable = { fg = p.bg, bg = p.number, bold = true },
	CmpKindBg_Constant = { fg = p.bg, bg = p.number, bold = true },
	CmpKindBg_Value = { fg = p.bg, bg = p.number, bold = true },
	CmpKindBg_Keyword = { fg = p.bg, bg = p.keyword, bold = true },
	CmpKindBg_Statement = { fg = p.bg, bg = p.keyword, bold = true },
	CmpKindBg_Class = { fg = p.bg, bg = p.type, bold = true },
	CmpKindBg_Interface = { fg = p.bg, bg = p.type, bold = true },
	CmpKindBg_Struct = { fg = p.bg, bg = p.type, bold = true },
	CmpKindBg_TypeParameter = { fg = p.bg, bg = p.type, bold = true },
	CmpKindBg_Enum = { fg = p.bg, bg = p.type, bold = true },
	CmpKindBg_Field = { fg = p.bg, bg = p.operator, bold = true },
	CmpKindBg_Property = { fg = p.bg, bg = p.operator, bold = true },
	CmpKindBg_Operator = { fg = p.bg, bg = p.operator, bold = true },
	CmpKindBg_Module = { fg = p.bg, bg = p.accent, bold = true },
	CmpKindBg_Folder = { fg = p.bg, bg = p.accent, bold = true },
	CmpKindBg_File = { fg = p.bg, bg = p.string, bold = true },
	CmpKindBg_Text = { fg = p.fg, bg = p.bg_highlight, bold = true },
	CmpKindBg_Color = { fg = p.bg, bg = p.type, bold = true },
}

for hl, spec in pairs(highlights) do
	vim.api.nvim_set_hl(0, hl, spec)
end
