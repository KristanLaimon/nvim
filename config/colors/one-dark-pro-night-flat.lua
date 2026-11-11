-- One Dark Pro Night Flat, adapted to the local FoxVim highlight schema.
-- Palette: https://github.com/Binaryify/OneDark-Pro/blob/master/themes/OneDark-Pro-night-flat.json

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

vim.o.background = "dark"
vim.g.colors_name = "one-dark-pro-night-flat"

local p = {
	bg = "#16191d",
	bg_dark = "#1e2227",
	bg_highlight = "#2c313c",
	bg_selected = "#2c313a",
	selection = "#343c4b", -- VS Code selection alpha composited over the editor background.
	variable = "#e06c75",
	fg = "#abb2bf",
	fg_muted = "#5c6370",
	comment = "#5c6370",

	keyword = "#c678dd",
	func = "#61afef",
	string = "#98c379",
	number = "#d19a66",
	type = "#e5c07b",
	operator = "#56b6c2",
	declaration = "#c678dd",
	accent = "#61afef",
	error = "#e06c75",
	warning = "#e5c07b",
	none = "NONE",
}

local highlights = {
	Normal = { fg = p.fg, bg = p.bg },
	NormalNC = { fg = p.fg, bg = p.bg },
	NormalFloat = { fg = p.fg, bg = p.bg_dark },
	FloatBorder = { fg = p.accent, bg = p.bg_dark },
	FloatTitle = { fg = p.accent, bg = p.bg_dark },
	Cursor = { fg = p.bg, bg = "#528bff" },
	CursorLine = { bg = p.bg_highlight },
	CursorColumn = { bg = p.bg_highlight },
	SignColumn = { bg = p.bg },
	EndOfBuffer = { fg = p.bg },
	ColorColumn = { bg = p.bg_dark },
	LineNr = { fg = "#667187" },
	CursorLineNr = { fg = p.fg },
	VertSplit = { fg = "#181a1f", bg = p.none },
	WinSeparator = { fg = "#181a1f", bg = p.none },
	MatchParen = { fg = p.accent, bg = p.bg_selected },

	Visual = { bg = p.selection },
	VisualNOS = { link = "Visual" },
	Search = { fg = p.fg, bg = p.bg_selected },
	IncSearch = { fg = p.bg, bg = p.accent },
	CurSearch = { fg = p.bg, bg = p.accent },

	StatusLine = { fg = "#9da5b4", bg = p.bg },
	StatusLineNC = { fg = p.fg_muted, bg = p.bg },
	TabLine = { fg = p.fg_muted, bg = p.bg },
	TabLineFill = { bg = p.bg },
	TabLineSel = { fg = "#dcdcdc", bg = "#23272e" },

	Pmenu = { fg = p.fg, bg = p.bg_dark },
	PmenuSel = { fg = p.fg, bg = p.bg_selected },
	PmenuSbar = { bg = p.bg_dark },
	PmenuThumb = { bg = p.accent },

	Comment = { fg = p.comment, italic = true },
	Constant = { fg = p.number },
	String = { fg = p.string },
	Character = { fg = p.string },
	Number = { fg = p.number },
	Boolean = { fg = p.number },
	Float = { fg = p.number },

	Identifier = { fg = p.variable },
	Function = { fg = p.func },
	Statement = { fg = p.keyword },
	Conditional = { fg = p.keyword },
	Repeat = { fg = p.keyword },
	Label = { fg = p.keyword },
	Operator = { fg = p.operator },
	Keyword = { fg = p.keyword },
	Exception = { fg = p.error },

	PreProc = { fg = p.accent },
	Include = { fg = p.keyword },
	Define = { fg = p.keyword },
	Macro = { fg = p.keyword },

	Type = { fg = p.type },
	StorageClass = { fg = p.keyword },
	Structure = { fg = p.type },
	Typedef = { fg = p.type },

	Special = { fg = p.accent },
	Delimiter = { fg = p.fg },
	Error = { fg = p.error },
	Todo = { fg = p.bg, bg = p.accent },

	["@comment"] = { fg = p.comment, italic = true },
	["@variable"] = { fg = p.variable },
	["@variable.builtin"] = { fg = p.type },
	["@function"] = { fg = p.func },
	["@keyword"] = { fg = p.keyword },
	["@string"] = { fg = p.string },
	["@number"] = { fg = p.number },
	["@type"] = { fg = p.type },
	["@property"] = { fg = p.fg },
	["@variable.parameter"] = { fg = p.fg },
	["@variable.member"] = { fg = p.variable },
	["@boolean"] = { link = "Boolean" },
	["@tag"] = { fg = p.variable },
	["@tag.attribute"] = { fg = p.number },
	["@operator"] = { fg = p.operator },

	DiagnosticError = { fg = p.error },
	DiagnosticWarn = { fg = p.warning },
	DiagnosticInfo = { fg = p.func },
	DiagnosticHint = { fg = p.operator },

	GitSignsAdd = { fg = p.string },
	GitSignsChange = { fg = p.warning },
	GitSignsDelete = { fg = p.error },
	DiffAdd = { bg = "#223526", fg = p.string },
	DiffChange = { bg = "#3b3123", fg = p.warning },
	DiffDelete = { bg = "#3d2226", fg = p.error },

	NeoTreeNormal = { fg = p.fg, bg = p.bg },
	NeoTreeNormalNC = { link = "NeoTreeNormal" },
	NeoTreeDirectoryName = { fg = p.accent },
	TelescopeNormal = { fg = p.fg, bg = p.bg_dark },
	TelescopeBorder = { fg = p.accent, bg = p.bg_dark },
	TelescopeSelection = { fg = p.fg, bg = p.bg_selected },

	-- NvChad Style Completion Kind Icon Highlights (Background + Accent)
	CmpKindBg_Function = { fg = p.bg, bg = p.func },
	CmpKindBg_Method = { fg = p.bg, bg = p.func },
	CmpKindBg_Constructor = { fg = p.bg, bg = p.func },
	CmpKindBg_Snippet = { fg = p.bg, bg = p.declaration },
	CmpKindBg_Variable = { fg = p.bg, bg = p.number },
	CmpKindBg_Constant = { fg = p.bg, bg = p.number },
	CmpKindBg_Value = { fg = p.bg, bg = p.number },
	CmpKindBg_Keyword = { fg = p.bg, bg = p.keyword },
	CmpKindBg_Statement = { fg = p.bg, bg = p.keyword },
	CmpKindBg_Class = { fg = p.bg, bg = p.type },
	CmpKindBg_Interface = { fg = p.bg, bg = p.type },
	CmpKindBg_Struct = { fg = p.bg, bg = p.type },
	CmpKindBg_TypeParameter = { fg = p.bg, bg = p.type },
	CmpKindBg_Enum = { fg = p.bg, bg = p.type },
	CmpKindBg_Field = { fg = p.bg, bg = p.string },
	CmpKindBg_Property = { fg = p.bg, bg = p.string },
	CmpKindBg_Operator = { fg = p.bg, bg = p.operator },
	CmpKindBg_Module = { fg = p.bg, bg = p.accent },
	CmpKindBg_Folder = { fg = p.bg, bg = p.accent },
	CmpKindBg_File = { fg = p.bg, bg = p.string },
	CmpKindBg_Text = { fg = p.fg, bg = p.bg_highlight },
	CmpKindBg_Color = { fg = p.bg, bg = p.type },
}

for hl, spec in pairs(highlights) do
	vim.api.nvim_set_hl(0, hl, spec)
end
