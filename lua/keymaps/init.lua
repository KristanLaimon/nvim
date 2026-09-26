-- ============================================================================
-- CONFIG: Keymaps -- the whole keyboard layout of this editor.
-- ============================================================================
-- WHERE A KEY LIVES
--   editor.lua  Text, clipboard, windows, buffers, comments, saving.
--   search.lua  Finding files, opening them in splits, following URLs.
--   lsp.lua     Hover, signature help, diagnostics, code actions, rename.
--   debug.lua   DAP: breakpoints, stepping, the repl.
--   fox.lua     This config's own features: tasks, launch profiles, git center,
--               explorer, workspaces, foxnvimscript.
--
-- CONVENTIONS
--   * `<leader>` is Space.
--   * Ctrl+Shift+<letter> opens a FOX panel (G git, T tasks, F files, W
--     workspaces, P palette, Q launch profiles, S smart launch).
--   * Anything bound in terminal mode leaves terminal mode first, or the key
--     would be swallowed by the shell.
--   * Plugin-owned keys stay in the plugin's own spec (`keys = { ... }`), not
--     here, so lazy-loading still works.
--
-- ADDING A KEY
--   Put it in the module it belongs to, next to related keys, with a `desc`.
--   The description is what which-key and `:map` show, so write it for a reader.
-- ============================================================================

pcall(function()
	require("fox.core.keymap_registry").reset()
end)

--- Loaded in order. Later modules may rely on earlier ones being set up.
local modules = {
	"keymaps.editor",
	"keymaps.search",
	"keymaps.lsp",
	"keymaps.debug",
	"keymaps.fox",
}

for _, module in ipairs(modules) do
	require(module)
end
