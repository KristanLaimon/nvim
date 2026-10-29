-- ============================================================================
-- PLUGINS: PHP & Laravel support.
-- ============================================================================
-- 1. fox_blade      Native syntax and indentation for `.blade.php` templates.
-- 2. fox_laravel    Jump to and complete Laravel references.
-- 3. PATH vendor/bin  Prepends project `./vendor/bin` to `PATH` for local Composer binaries.
--
-- Language tools, formatting and detection live in fox.langs.php.
-- ============================================================================

return {
	-- Blade filetype syntax highlighting
	{
		name = "fox_blade",
		dir = require("fox.core.lazyspec").for_module(),
		ft = { "blade" },
		init = function()
			vim.g.blade_custom_directives_pairs = {
				script = "endscript",
				assets = "endassets",
			}
		end,
	},

	-- Register blade-nav autocompletion provider in blink.cmp
	{
		"saghen/blink.cmp",
		opts = function(_, opts)
			opts.sources = opts.sources or {}
			opts.sources.providers = opts.sources.providers or {}
			opts.sources.providers["blade-nav"] = {
				name = "blade-nav",
				module = "fox.langs.php.blink",
				score_offset = 100,
				enabled = function()
					local ft = vim.bo.filetype
					return ft == "blade" or ft == "php"
				end,
			}
			opts.sources.default = opts.sources.default or {}
			if not vim.tbl_contains(opts.sources.default, "blade-nav") then
				table.insert(opts.sources.default, "blade-nav")
			end
		end,
	},
}
