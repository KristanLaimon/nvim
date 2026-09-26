-- ============================================================================
-- COLORSCHEME: catppuccin-fox -- NvChad Catppuccin theme in nagatoro-fox format.
-- ============================================================================

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

vim.g.colors_name = "catppuccin-fox"

local p = {
	bg = "#1e1e2e",
	bg_dark = "#181825",
	bg_highlight = "#2A2A3C",
	bg_selected = "#45475a",
	fg = "#cdd6f4",
	fg_muted = "#a6adc8",
	comment = "#6c7086",

	keyword = "#cba6f7",
	func = "#89b4fa",
	string = "#a6e3a1",
	number = "#fab387",
	type = "#f9e2af",
	operator = "#94e2d5",
	declaration = "#f5c2e7",
	accent = "#89b4fa",
	error = "#f38ba8",
	warning = "#f9e2af",
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
	LineNr = { fg = "#585b70" },
	CursorLineNr = { fg = p.accent, bold = true },
	VertSplit = { fg = "#181825", bg = p.none },
	WinSeparator = { fg = "#181825", bg = p.none },
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
	DiagnosticInfo = { fg = p.func },
	DiagnosticHint = { fg = p.operator },

	GitSignsAdd = { fg = p.string },
	GitSignsChange = { fg = p.warning },
	GitSignsDelete = { fg = p.error },
	DiffAdd = { bg = "#253427", fg = p.string },
	DiffChange = { bg = "#3c3425", fg = p.warning },
	DiffDelete = { bg = "#3b232c", fg = p.error },

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
	CmpKindBg_Field = { fg = p.bg, bg = p.string, bold = true },
	CmpKindBg_Property = { fg = p.bg, bg = p.string, bold = true },
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
