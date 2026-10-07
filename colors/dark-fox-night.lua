-- ============================================================================
-- COLORSCHEME: dark-fox-night -- Omarchy Vantablack.
-- ============================================================================
-- Copy of Omarchy's Vantablack Neovim palette. It is intentionally grayscale.
--
-- USAGE
--   :colorscheme dark-fox-night    (or pick it in :FoxThemePicker)
--
-- HOW TO RETHEME
--   `p` is Omarchy's base, `s` is its Aether syntax palette.
-- ============================================================================

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

vim.o.background = "dark"
vim.g.colors_name = "dark-fox-night"

-- Vantablack base (Omarchy's current theme), untouched by design.
local p = {
	bg = "#000000",
	bg_dark = "#090909",
	bg_darker = "#070707",
	bg_highlight = "#1a1a1a",
	bg_selected = "#1a1a1a",
	fg = "#ffffff",
	fg_muted = "#ececec",
	comment = "#505050",
	line_nr = "#7a7a7a",
	sep = "#070707",
	accent = "#8d8d8d",
	none = "NONE",
}

-- Omarchy Aether syntax palette. Keep this grayscale to match Vantablack.
local s = {
	green = "#b6b6b6",
	bright_green = "#b6b6b6",
	yellow = "#cecece",
	bright_yellow = "#cecece",
	orange = "#8d8d8d",
	bright_orange = "#8d8d8d",
	red = "#a4a4a4",
	bright_red = "#a4a4a4",
	blue = "#8d8d8d",
	bright_blue = "#8d8d8d",
	cyan = "#b0b0b0",
	bright_cyan = "#b0b0b0",
	magenta = "#9b9b9b",
	bright_magenta = "#9b9b9b",
}

local highlights = {
	-- Base Editor
	Normal = { fg = p.fg, bg = p.bg },
	NormalNC = { fg = p.fg, bg = p.bg },
	NormalFloat = { fg = p.fg, bg = p.bg_dark },
	FloatBorder = { fg = s.orange, bg = p.bg_dark },
	FloatTitle = { fg = s.orange, bg = p.bg_dark, bold = true },
	Cursor = { fg = p.bg, bg = p.fg },
	CursorLine = { bg = p.bg_highlight },
	CursorColumn = { bg = p.bg_highlight },
	ColorColumn = { bg = p.bg_dark },
	LineNr = { fg = p.line_nr },
	CursorLineNr = { fg = s.orange, bold = true },
	SignColumn = { bg = p.bg },
	VertSplit = { fg = p.sep, bg = p.none },
	WinSeparator = { fg = p.sep, bg = p.none },
	MatchParen = { fg = s.bright_orange, bg = p.bg_selected, bold = true },

	-- Visual & Search
	Visual = { bg = p.bg_selected },
	VisualNOS = { bg = p.bg_selected },
	Search = { fg = p.bg, bg = s.bright_yellow },
	IncSearch = { fg = p.bg, bg = s.bright_orange, bold = true },
	CurSearch = { fg = p.bg, bg = s.bright_orange, bold = true },

	-- Statusline & Tabline
	StatusLine = { fg = p.fg, bg = p.bg_dark },
	StatusLineNC = { fg = p.fg_muted, bg = p.bg_dark },
	TabLine = { fg = p.fg_muted, bg = p.bg_dark },
	TabLineFill = { bg = p.bg_dark },
	TabLineSel = { fg = s.bright_orange, bg = p.bg, bold = true },

	-- Popup Menu
	Pmenu = { fg = p.fg, bg = p.bg_dark },
	PmenuSel = { fg = p.fg, bg = p.bg_selected, bold = true },
	PmenuSbar = { bg = p.bg_dark },
	PmenuThumb = { bg = p.sep },

	-- Standard Syntax (kept monochrome on purpose: vantablack's calm code area)
	Comment = { fg = p.comment, italic = true },
	Constant = { fg = p.fg_muted },
	String = { fg = p.fg_muted },
	Character = { fg = p.fg_muted },
	Number = { fg = p.fg_muted },
	Boolean = { fg = p.fg, bold = true },
	Float = { fg = p.fg_muted },

	Identifier = { fg = p.fg },
	Function = { fg = p.fg, bold = true },
	Statement = { fg = p.fg, bold = true },
	Conditional = { fg = p.fg, bold = true },
	Repeat = { fg = p.fg, bold = true },
	Label = { fg = p.fg },
	Operator = { fg = p.fg_muted },
	Keyword = { fg = p.fg, bold = true },
	Exception = { fg = s.red, bold = true },

	PreProc = { fg = p.fg },
	Include = { fg = p.fg },
	Define = { fg = p.fg },
	Macro = { fg = p.fg },

	Type = { fg = p.fg, bold = true },
	StorageClass = { fg = p.fg, bold = true },
	Structure = { fg = p.fg },
	Typedef = { fg = p.fg },

	Special = { fg = p.fg_muted },
	SpecialChar = { fg = p.fg_muted },
	Tag = { fg = p.fg },
	Delimiter = { fg = p.fg },
	SpecialComment = { fg = p.comment, italic = true },
	Debug = { fg = s.red },

	Underlined = { underline = true },
	Bold = { bold = true },
	Italic = { italic = true },
	Error = { fg = s.bright_red, bold = true },
	Todo = { fg = p.bg, bg = s.bright_yellow, bold = true },
	WarningMsg = { fg = s.bright_yellow },
	NonText = { fg = p.comment },
	Directory = { fg = s.blue },
	ErrorMsg = { fg = s.bright_red },
	MoreMsg = { fg = s.cyan },
	ModeMsg = { fg = s.green },
	Question = { fg = s.cyan },
	Title = { fg = p.fg, bold = true },
	SpellBad = { undercurl = true, sp = s.bright_red },
	SpellCap = { undercurl = true, sp = s.bright_yellow },
	SpellRare = { undercurl = true, sp = s.cyan },
	SpellLocal = { undercurl = true, sp = s.green },
	QuickFixLine = { fg = s.cyan, bg = p.bg_highlight },
	WinBar = { fg = p.fg_muted, bg = p.bg_dark },
	WinBarNC = { fg = p.fg_muted, bg = p.bg_dark },
	OkMsg = { fg = s.green },
	Added = { fg = s.green },
	Changed = { fg = s.cyan },
	Removed = { fg = s.red },
	Conceal = { fg = p.comment },
	FloatShadow = { bg = p.bg_dark },
	FloatShadowThrough = { bg = p.bg_dark },
	RedrawDebugClear = { bg = p.bg_highlight },
	RedrawDebugComposed = { bg = p.bg_highlight },
	RedrawDebugRecompose = { bg = p.bg_highlight },
	NvimInternalError = { fg = s.bright_red, bg = s.bright_red },

	-- Treesitter Captures
	["@comment"] = { fg = p.comment, italic = true },
	["@variable"] = { fg = p.fg },
	["@variable.builtin"] = { fg = p.fg, italic = true },
	["@variable.parameter"] = { fg = p.fg_muted },
	["@function"] = { fg = p.fg, bold = true },
	["@function.builtin"] = { fg = p.fg, bold = true },
	["@function.call"] = { fg = p.fg },
	["@function.method"] = { fg = p.fg },
	["@function.method.call"] = { fg = p.fg },
	["@keyword"] = { fg = p.fg, bold = true },
	["@keyword.function"] = { fg = p.fg, bold = true },
	["@keyword.return"] = { fg = p.fg, bold = true },
	["@keyword.conditional"] = { fg = p.fg, bold = true },
	["@keyword.repeat"] = { fg = p.fg, bold = true },
	["@keyword.import"] = { fg = p.fg, bold = true },
	["@keyword.operator"] = { fg = p.fg },
	["@string"] = { fg = p.fg_muted },
	["@number"] = { fg = p.fg_muted },
	["@boolean"] = { fg = p.fg, bold = true },
	["@type"] = { fg = p.fg, bold = true },
	["@type.builtin"] = { fg = p.fg, italic = true },
	["@property"] = { fg = p.fg, bold = true },
	["@operator"] = { fg = p.fg_muted },
	["@punctuation.delimiter"] = { fg = p.fg_muted },
	["@punctuation.bracket"] = { fg = p.fg_muted },
	["@module"] = { fg = p.fg },

	-- LSP Diagnostics (colored symbols)
	DiagnosticError = { fg = s.bright_red },
	DiagnosticWarn = { fg = s.bright_yellow },
	DiagnosticInfo = { fg = s.bright_blue },
	DiagnosticHint = { fg = s.bright_cyan },
	DiagnosticOk = { fg = s.bright_green },
	DiagnosticUnnecessary = { fg = p.comment, italic = true },
	DiagnosticDeprecated = { fg = p.comment, strikethrough = true },
	DiagnosticSignError = { fg = s.bright_red, bold = true },
	DiagnosticSignWarn = { fg = s.bright_yellow, bold = true },
	DiagnosticSignInfo = { fg = s.bright_blue, bold = true },
	DiagnosticSignHint = { fg = s.bright_cyan, bold = true },
	DiagnosticSignOk = { fg = s.bright_green, bold = true },
	DiagnosticVirtualTextError = { fg = s.bright_red, bg = p.bg_highlight },
	DiagnosticVirtualTextWarn = { fg = s.bright_yellow, bg = p.bg_highlight },
	DiagnosticVirtualTextInfo = { fg = s.bright_blue, bg = p.bg_highlight },
	DiagnosticVirtualTextHint = { fg = s.bright_cyan, bg = p.bg_highlight },
	DiagnosticUnderlineError = { underline = true, sp = s.bright_red },
	DiagnosticUnderlineWarn = { underline = true, sp = s.bright_yellow },
	DiagnosticUnderlineInfo = { underline = true, sp = s.bright_blue },
	DiagnosticUnderlineHint = { underline = true, sp = s.bright_cyan },
	DiagnosticUnderlineOk = { underline = true, sp = s.bright_green },

	-- Git Signs & Diff (colored symbols)
	GitSignsAdd = { fg = s.bright_green, bold = true },
	GitSignsChange = { fg = s.bright_yellow, bold = true },
	GitSignsDelete = { fg = s.bright_red, bold = true },
	GitSignsChangedelete = { fg = s.bright_orange, bold = true },
	GitSignsTopdelete = { fg = s.bright_red, bold = true },
	GitSignsUntracked = { fg = s.bright_cyan, bold = true },
	GitSignsAddNr = { fg = s.green },
	GitSignsChangeNr = { fg = s.yellow },
	GitSignsDeleteNr = { fg = s.red },
	GitSignsAddLn = { bg = p.bg_highlight },
	GitSignsChangeLn = { bg = p.bg_highlight },
	GitSignsDeleteLn = { bg = p.bg_highlight },
	DiffAdd = { bg = p.bg_highlight, fg = s.bright_green },
	DiffChange = { bg = p.bg_highlight, fg = s.bright_yellow },
	DiffDelete = { bg = p.bg_highlight, fg = s.bright_red },
	DiffText = { bg = p.bg_selected, fg = s.bright_yellow, bold = true },

	-- Blame author gutter
	GitDiffBlameAuthor = { fg = s.bright_blue },
	GitDiffBlameSelf = { fg = s.bright_orange, bold = true },
	GitDiffBlameUncommitted = { fg = s.bright_magenta, italic = true },

	-- Fold & indent markers (colored symbols)
	Folded = { fg = s.bright_blue, bg = p.bg_highlight },
	FoldColumn = { fg = p.comment, bg = p.bg },
	IblIndent = { fg = p.sep },
	IblScope = { fg = s.blue },
	IndentBlanklineChar = { fg = p.sep },
	IndentBlanklineSpaceChar = { fg = p.sep },
	IndentBlanklineContextChar = { fg = s.blue },

	-- Neo-Tree (colored icons and git status)
	NeoTreeNormal = { fg = p.fg, bg = p.bg_dark },
	NeoTreeNormalNC = { fg = p.fg, bg = p.bg_dark },
	NeoTreeDirectoryName = { fg = s.bright_orange, bold = true },
	NeoTreeDirectoryIcon = { fg = s.orange },
	NeoTreeRootName = { fg = s.bright_orange, bold = true },
	NeoTreeFileName = { fg = p.fg },
	NeoTreeFileIcon = { fg = s.blue },
	NeoTreeExpander = { fg = s.blue },
	NeoTreeIndentMarker = { fg = p.sep },
	NeoTreeSymbolicLinkTarget = { fg = s.cyan },
	NeoTreeCursorLine = { bg = p.bg_highlight },
	NeoTreeGitAdded = { fg = s.bright_green, bold = true },
	NeoTreeGitModified = { fg = s.bright_yellow, bold = true },
	NeoTreeGitDeleted = { fg = s.bright_red, bold = true },
	NeoTreeGitRenamed = { fg = s.bright_magenta, bold = true },
	NeoTreeGitUntracked = { fg = s.bright_cyan, bold = true },
	NeoTreeGitIgnored = { fg = p.comment },
	NeoTreeGitConflict = { fg = s.bright_red, bold = true },
	NeoTreeGitUnstaged = { fg = s.bright_yellow, bold = true },
	NeoTreeGitStaged = { fg = s.bright_green, bold = true },

	-- Telescope
	TelescopeNormal = { fg = p.fg, bg = p.bg_dark },
	TelescopeBorder = { fg = s.orange, bg = p.bg_dark },
	TelescopePromptBorder = { fg = s.orange, bg = p.bg_dark },
	TelescopePromptTitle = { fg = p.bg, bg = s.bright_orange, bold = true },
	TelescopeResultsTitle = { fg = p.bg, bg = s.bright_blue, bold = true },
	TelescopePreviewTitle = { fg = p.bg, bg = s.bright_green, bold = true },
	TelescopeSelection = { fg = p.fg, bg = p.bg_selected, bold = true },

	-- Completion kind badges (colored symbols)
	CmpKindBg_Function = { fg = p.bg, bg = s.bright_blue, bold = true },
	CmpKindBg_Method = { fg = p.bg, bg = s.bright_blue, bold = true },
	CmpKindBg_Constructor = { fg = p.bg, bg = s.bright_blue, bold = true },
	CmpKindBg_Snippet = { fg = p.bg, bg = s.bright_magenta, bold = true },
	CmpKindBg_Variable = { fg = p.bg, bg = s.bright_orange, bold = true },
	CmpKindBg_Constant = { fg = p.bg, bg = s.bright_orange, bold = true },
	CmpKindBg_Value = { fg = p.bg, bg = s.bright_orange, bold = true },
	CmpKindBg_Keyword = { fg = p.bg, bg = s.bright_red, bold = true },
	CmpKindBg_Statement = { fg = p.bg, bg = s.bright_red, bold = true },
	CmpKindBg_Class = { fg = p.bg, bg = s.bright_cyan, bold = true },
	CmpKindBg_Interface = { fg = p.bg, bg = s.bright_cyan, bold = true },
	CmpKindBg_Struct = { fg = p.bg, bg = s.bright_cyan, bold = true },
	CmpKindBg_TypeParameter = { fg = p.bg, bg = s.bright_cyan, bold = true },
	CmpKindBg_Enum = { fg = p.bg, bg = s.bright_cyan, bold = true },
	CmpKindBg_Field = { fg = p.bg, bg = s.bright_green, bold = true },
	CmpKindBg_Property = { fg = p.bg, bg = s.bright_green, bold = true },
	CmpKindBg_Operator = { fg = p.bg, bg = s.bright_green, bold = true },
	CmpKindBg_Module = { fg = p.bg, bg = s.bright_orange, bold = true },
	CmpKindBg_Folder = { fg = p.bg, bg = s.bright_orange, bold = true },
	CmpKindBg_File = { fg = p.bg, bg = s.bright_blue, bold = true },
	CmpKindBg_Text = { fg = p.fg, bg = p.bg_highlight, bold = true },
	CmpKindBg_Color = { fg = p.bg, bg = s.bright_magenta, bold = true },

	-- Standard CmpItemKind aliases
	CmpItemKindFunction = { fg = p.bg, bg = s.bright_blue, bold = true },
	CmpItemKindMethod = { fg = p.bg, bg = s.bright_blue, bold = true },
	CmpItemKindSnippet = { fg = p.bg, bg = s.bright_magenta, bold = true },
	CmpItemKindVariable = { fg = p.bg, bg = s.bright_orange, bold = true },
	CmpItemKindKeyword = { fg = p.bg, bg = s.bright_red, bold = true },
	CmpItemKindClass = { fg = p.bg, bg = s.bright_cyan, bold = true },
	CmpItemKindField = { fg = p.bg, bg = s.bright_green, bold = true },
	CmpItemKindModule = { fg = p.bg, bg = s.bright_orange, bold = true },
}

for hl, spec in pairs(highlights) do
	vim.api.nvim_set_hl(0, hl, spec)
end
