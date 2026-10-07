-- ============================================================================
-- COLORSCHEME: dark-fox-night -- Vantablack base, colored symbols.
-- ============================================================================
-- Built on top of Omarchy's current theme (vantablack): pure-black background
-- and grayscale UI. Vantablack is intentionally monochrome, which makes the
-- small glyphs (git signs, diagnostics, expander/indent markers, completion
-- kind badges, blame authors) impossible to tell apart.
--
-- This theme keeps the vantablack background/foreground but paints every
-- SYMBOL with the fox-night hue palette, so the UI reads at a glance while the
-- code area stays high-contrast and calm.
--
-- USAGE
--   :colorscheme dark-fox-night    (or pick it in :FoxThemePicker)
--
-- HOW TO RETHEME
--   `p` is the vantablack base, `s` the fox-night symbol hues. Highlights only
--   reference those names; change one entry and everything follows.
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
	bg_selected = "#2a2a2a",
	fg = "#ffffff",
	fg_muted = "#ececec",
	comment = "#8a8a8a",
	line_nr = "#6a6a6a",
	sep = "#262626",
	accent = "#d96a25",
	none = "NONE",
}

-- Fox-night symbol hues: the only saturated colors in the theme.
local s = {
	green = "#a8b86a",
	bright_green = "#c9d985",
	yellow = "#e8a34b",
	bright_yellow = "#ffc76b",
	orange = "#d96a25",
	bright_orange = "#f08a45",
	red = "#d85a4a",
	bright_red = "#ff7662",
	blue = "#7aa2c8",
	bright_blue = "#a4caee",
	cyan = "#79b8b5",
	bright_cyan = "#9cd9d4",
	magenta = "#c58aa7",
	bright_magenta = "#e4acc5",
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
	DiagnosticVirtualTextError = { fg = s.bright_red, bg = "#2a1414" },
	DiagnosticVirtualTextWarn = { fg = s.bright_yellow, bg = "#2a2410" },
	DiagnosticVirtualTextInfo = { fg = s.bright_blue, bg = "#101c2a" },
	DiagnosticVirtualTextHint = { fg = s.bright_cyan, bg = "#0f2323" },
	DiagnosticUnderlineError = { underline = true, sp = s.bright_red },
	DiagnosticUnderlineWarn = { underline = true, sp = s.bright_yellow },
	DiagnosticUnderlineInfo = { underline = true, sp = s.bright_blue },
	DiagnosticUnderlineHint = { underline = true, sp = s.bright_cyan },

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
	GitSignsAddLn = { bg = "#14200f" },
	GitSignsChangeLn = { bg = "#241d0e" },
	GitSignsDeleteLn = { bg = "#261312" },
	DiffAdd = { bg = "#14200f", fg = s.bright_green },
	DiffChange = { bg = "#241d0e", fg = s.bright_yellow },
	DiffDelete = { bg = "#261312", fg = s.bright_red },
	DiffText = { bg = "#3a2f12", fg = s.bright_yellow, bold = true },

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
