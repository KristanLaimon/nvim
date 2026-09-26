-- ============================================================================
-- PLUGINS: blink.cmp completion sources owned by this config.
-- ============================================================================
-- WHAT IS REGISTERED HERE
--   launch_json  IntelliSense inside `.foxnvim/launch.json`: task names, runtimes
--                and modes (lua/plugins/fox/launch_cmp.lua).
--   foxnvim      IntelliSense inside `*.foxnvim` scripts: console, fetch, import
--                and the library modules (lua/plugins/fox/foxnvim_cmp.lua).
--
--   `schemastore.nvim` is declared here too, because it is what jsonls and yamlls
--   pull their schemas from in lsp.lua.
--
-- WHY score_offset
--   Inside those two file types these completions are the only relevant ones, so
--   they outrank the generic buffer and snippet sources.
--
-- OTHER SOURCES
--   editorconfig -> lua/plugins/lsp/editorconfig.lua
--   dap repl     -> lua/plugins/lsp/lsp.lua (sources.providers.dap)
-- ============================================================================

--- Sources added to blink.cmp: provider name -> definition.
local sources = {
	launch_json = {
		name = "LaunchJson",
		module = "plugins.fox.dev.launch_cmp",
		score_offset = 100,
		enabled = function()
			return vim.fn.expand("%:t") == "launch.json"
		end,
	},
	foxnvim = {
		name = "FoxNvimScript",
		module = "plugins.fox.dev.foxnvim_cmp",
		score_offset = 100,
		enabled = function()
			local ft = vim.bo.filetype
			local name = vim.fn.expand("%:t")
			return ft == "lua" or ft == "foxnvim" or name:match("%.foxnvim$") ~= nil or name:match("%.lua$") ~= nil
		end,
	},
}

return {
	{
		"b0o/schemastore.nvim",
		lazy = true,
	},
	{
		"saghen/blink.cmp",
		opts = function(_, opts)
			opts.sources = opts.sources or {}
			opts.sources.providers = opts.sources.providers or {}

			for name, definition in pairs(sources) do
				opts.sources.providers[name] = definition

				opts.sources.default = opts.sources.default or {}
				if not vim.tbl_contains(opts.sources.default, name) then
					table.insert(opts.sources.default, name)
				end
			end
		end,
	},
}
