-- ============================================================================
-- PLUGIN: nvim-ts-autotag -- closes and renames HTML/JSX tags.
-- ============================================================================
-- Typing `<div>` writes the closing tag, and renaming one end renames the other.
-- Treesitter-driven, so it follows the real syntax tree rather than guessing;
-- the filetypes come from the parsers installed in treesitter.lua.
-- ============================================================================

return {
	name = "fox_autotag",
	dir = require("fox.core.lazyspec").for_module(),
	ft = {
		"html",
		"xml",
		"javascriptreact",
		"typescriptreact",
		"javascript",
		"typescript",
		"vue",
		"svelte",
		"astro",
		"php",
		"blade",
		"jsx",
		"tsx",
		"markdown",
	},
	config = function()
		require("fox.editor.autotag").setup()
	end,
}
