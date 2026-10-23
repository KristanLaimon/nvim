-- ============================================================================
-- COLORSCHEME: nagatoro-fox -- Doki Theme "Hayase Nagatoro Dark", ported.
-- ============================================================================
-- Ported from the official Doki Theme VSCode extension, so colours match that
-- editor exactly.
--
-- USAGE
--   :colorscheme nagatoro-fox   (applied at startup in lua/plugins/ui/themes.lua)
--
-- HOW TO RETHEME
--   Every colour comes from the `p` palette table below; the highlight groups
--   only reference those names. Change a palette entry and the whole editor,
--   including the plugin-specific groups further down, follows.
-- ============================================================================

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

vim.g.colors_name = "nagatoro-fox"

-- Official Doki Theme Hayase Nagatoro Dark Palette
local p = {
	bg = "#151515", -- Official Nagatoro Dark Background
	bg_dark = "#171717", -- Sidebar / Popups / Panel background
	bg_highlight = "#1d1d1d", -- Line highlight background
	bg_selected = "#5d3e2f", -- Active selection / focus background
	fg = "#F8F8F2", -- Official Editor Foreground
	fg_muted = "#bbbbbb", -- Muted text
	comment = "#6f7a82", -- Soft Slate Cyan/Gray Comment (High contrast for transparent windows)

	-- Nagatoro Token Colors
	keyword = "#6d7fd4", -- Official Nagatoro Keyword Blue/Indigo
	func = "#E3A70E", -- Official Nagatoro Function Amber/Gold
	string = "#95acbd", -- Official Nagatoro String Slate/Cyan
	number = "#d776ae", -- Official Nagatoro Number/Constant Magenta/Pink
	type = "#5cd7d7", -- Official Nagatoro Type Teal/Cyan
	operator = "#62e665", -- Official Nagatoro Operator Mint Green
	declaration = "#D233A2", -- Official Nagatoro Function/Class Declaration Magenta
	accent = "#d2824e", -- Official Nagatoro Warm Orange/Amber Accent
	error = "#ff2525", -- Official Nagatoro Error Red
	warning = "#EFA554", -- Official Nagatoro Warning Yellow
	none = "NONE",
}

local highlights = {
	-- Base Editor
	Normal = { fg = p.fg, bg = p.bg },
	NormalNC = { fg = p.fg, bg = p.bg },
	NormalFloat = { fg = p.fg, bg = p.bg_dark },
	FloatBorder = { fg = p.accent, bg = p.bg_dark },
	FloatTitle = { fg = p.accent, bg = p.bg_dark, bold = true },
	Cursor = { fg = p.bg, bg = p.accent },
	CursorLine = { bg = p.bg_highlight },
	CursorColumn = { bg = p.bg_highlight },
	ColorColumn = { bg = p.bg_dark },
	LineNr = { fg = "#5d5550" },
	CursorLineNr = { fg = p.accent, bold = true },
	VertSplit = { fg = "#272626", bg = p.none },
	WinSeparator = { fg = "#272626", bg = p.none },
	MatchParen = { fg = p.accent, bg = p.bg_selected, bold = true },

	-- Visual & Search
	Visual = { bg = p.bg_selected },
	VisualNOS = { bg = p.bg_selected },
	Search = { fg = p.fg, bg = p.bg_selected },
	IncSearch = { fg = p.bg, bg = p.accent, bold = true },
	CurSearch = { fg = p.bg, bg = p.accent, bold = true },

	-- Statusline & Tabline
	StatusLine = { fg = p.fg, bg = p.bg_dark },
	StatusLineNC = { fg = p.fg_muted, bg = p.bg_dark },
	TabLine = { fg = p.fg_muted, bg = p.bg_dark },
	TabLineFill = { bg = p.bg_dark },
	TabLineSel = { fg = p.accent, bg = p.bg, bold = true },

	-- Popup Menu
	Pmenu = { fg = p.fg, bg = p.bg_dark },
	PmenuSel = { fg = p.fg, bg = p.bg_selected, bold = true },
	PmenuSbar = { bg = p.bg_dark },
	PmenuThumb = { bg = p.accent },

	-- Standard Syntax Highlighting
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
	SpecialChar = { fg = p.accent },
	Tag = { fg = p.operator },
	Delimiter = { fg = p.fg },
	SpecialComment = { fg = p.accent, italic = true },
	Debug = { fg = p.error },

	Underlined = { underline = true },
	Bold = { bold = true },
	Italic = { italic = true },
	Error = { fg = p.error, bold = true },
	Todo = { fg = p.bg, bg = p.accent, bold = true },

	-- Treesitter Captures (Fine-tuned for Lua and all languages)
	["@comment"] = { fg = p.comment, italic = true },
	["@variable"] = { fg = p.fg },
	["@variable.builtin"] = { fg = p.keyword, italic = true },
	["@variable.parameter"] = { fg = p.string },
	["@function"] = { fg = p.func, bold = true },
	["@function.builtin"] = { fg = p.func, bold = true },
	["@function.call"] = { fg = p.func },
	["@function.method"] = { fg = p.func },
	["@function.method.call"] = { fg = p.func },
	["@keyword"] = { fg = p.keyword, bold = true },
	["@keyword.function"] = { fg = p.keyword, bold = true },
	["@keyword.return"] = { fg = p.keyword, bold = true },
	["@keyword.conditional"] = { fg = p.keyword, bold = true },
	["@keyword.repeat"] = { fg = p.keyword, bold = true },
	["@keyword.import"] = { fg = p.keyword, bold = true },
	["@keyword.operator"] = { fg = p.keyword },
	["@string"] = { fg = p.string },
	["@number"] = { fg = p.number },
	["@boolean"] = { fg = p.keyword, bold = true },
	["@type"] = { fg = p.type, bold = true },
	["@type.builtin"] = { fg = p.type, italic = true },
	["@property"] = { fg = p.fg, bold = true },
	["@operator"] = { fg = p.operator },
	["@punctuation.delimiter"] = { fg = p.fg },
	["@punctuation.bracket"] = { fg = p.fg },
	["@module"] = { fg = p.type },

	-- LSP Diagnostics
	DiagnosticError = { fg = p.error },
	DiagnosticWarn = { fg = p.warning },
	DiagnosticInfo = { fg = p.keyword },
	DiagnosticHint = { fg = p.type },
	DiagnosticUnderlineError = { underline = true, sp = p.error },
	DiagnosticUnderlineWarn = { underline = true, sp = p.warning },

	-- Git Signs & Diff
	GitSignsAdd = { fg = p.operator },
	GitSignsChange = { fg = p.warning },
	GitSignsDelete = { fg = p.error },
	DiffAdd = { bg = "#132A13", fg = p.operator },
	DiffChange = { bg = "#255926", fg = p.warning },
	DiffDelete = { bg = "#3E1D1D", fg = p.error },

	-- Neo-Tree
	NeoTreeNormal = { fg = p.fg, bg = p.bg_dark },
	NeoTreeNormalNC = { fg = p.fg, bg = p.bg_dark },
	NeoTreeDirectoryName = { fg = p.accent, bold = true },
	NeoTreeDirectoryIcon = { fg = p.accent },
	NeoTreeFileName = { fg = p.fg },

	-- Telescope
	TelescopeNormal = { fg = p.fg, bg = p.bg_dark },
	TelescopeBorder = { fg = p.accent, bg = p.bg_dark },
	TelescopePromptBorder = { fg = p.accent, bg = p.bg_dark },
	TelescopePromptTitle = { fg = p.bg, bg = p.accent, bold = true },
	TelescopeResultsTitle = { fg = p.bg, bg = p.func, bold = true },
	TelescopePreviewTitle = { fg = p.bg, bg = p.operator, bold = true },
	TelescopeSelection = { fg = p.fg, bg = p.bg_selected, bold = true },

	-- NvChad Style Completion Kind Icon Highlights (Background + Accent)
	CmpKindBg_Function = { fg = p.bg, bg = p.func, bold = true },
	CmpKindBg_Method = { fg = p.bg, bg = p.func, bold = true },
	CmpKindBg_Constructor = { fg = p.bg, bg = p.func, bold = true },
	CmpKindBg_Snippet = { fg = "#ffffff", bg = p.declaration, bold = true },
	CmpKindBg_Variable = { fg = p.bg, bg = p.number, bold = true },
	CmpKindBg_Constant = { fg = p.bg, bg = p.number, bold = true },
	CmpKindBg_Value = { fg = p.bg, bg = p.number, bold = true },
	CmpKindBg_Keyword = { fg = "#ffffff", bg = p.keyword, bold = true },
	CmpKindBg_Statement = { fg = "#ffffff", bg = p.keyword, bold = true },
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

	-- Standard CmpItemKind aliases
	CmpItemKindFunction = { fg = p.bg, bg = p.func, bold = true },
	CmpItemKindMethod = { fg = p.bg, bg = p.func, bold = true },
	CmpItemKindSnippet = { fg = "#ffffff", bg = p.declaration, bold = true },
	CmpItemKindVariable = { fg = p.bg, bg = p.number, bold = true },
	CmpItemKindKeyword = { fg = "#ffffff", bg = p.keyword, bold = true },
	CmpItemKindClass = { fg = p.bg, bg = p.type, bold = true },
	CmpItemKindField = { fg = p.bg, bg = p.operator, bold = true },
	CmpItemKindModule = { fg = p.bg, bg = p.accent, bold = true },
}

for hl, spec in pairs(highlights) do
	vim.api.nvim_set_hl(0, hl, spec)
end
