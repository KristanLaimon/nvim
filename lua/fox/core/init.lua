-- ============================================================================
-- fox.core -- Shared foundation layer for every FOX module.
-- ============================================================================
-- WHAT LIVES HERE
--   path      Cross-platform path normalize / join / compare.
--   store     JSON file load & save that never throws.
--   project   Project root detection and `.foxnvim/` config resolution.
--   ui        Floating window and scratch buffer factory.
--   lazyspec  Unique lazy.nvim `dir` per local plugin spec.
--
-- RULES FOR THIS LAYER
--   * No module in fox.core may require anything from `plugins.*`. Dependencies
--     point downward only: plugins -> fox.core -> Neovim API.
--   * No global state, no autocmds, no keymaps. Pure helpers only.
--
-- USAGE -- require submodules directly, or the aggregate for convenience:
--   local path = require("fox.core.path")
--   local core = require("fox.core"); core.store.load(file, {})
-- ============================================================================

return {
	path = require("fox.core.path"),
	store = require("fox.core.store"),
	project = require("fox.core.project"),
	ui = require("fox.core.ui"),
	lazyspec = require("fox.core.lazyspec"),
	z_index = require("fox.core.z_index"),
	zindex = require("fox.core.z_index"),
}
