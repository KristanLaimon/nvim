-- ============================================================================
-- PLUGINS: PHP & Laravel support.
-- ============================================================================
-- 1. fox_blade      Native syntax and indentation for `.blade.php` templates.
-- 2. fox_laravel    Jump to and complete Laravel references.
-- 3. fox_php_tools  Registers `:PHPCheckTools`, which reports whether PHP and
--                   Composer are actually installed (on Windows or in WSL) and
--                   how to install what is missing.
-- 4. PATH vendor/bin  Prepends project `./vendor/bin` to `PATH` for local Composer binaries.
--
-- Language tools, formatting and detection live in fox.langs.php.
-- ============================================================================

return {
	-- Blade filetype syntax highlighting
	{
		name = "fox_blade",
		dir = vim.fn.stdpath("config"),
		ft = { "blade" },
		init = function()
			vim.g.blade_custom_directives_pairs = {
				script = "endscript",
				assets = "endassets",
			}
		end,
	},

	-- Local Laravel navigation, completion indexes and compatibility commands.
	{
		name = "fox_laravel",
		dir = vim.fn.stdpath("config"),
		ft = { "blade", "php" },
		cmd = { "BladeNavClearCache", "BladeNavToggleShowValues", "BladeNavInstallArtisanCommand", "BladeNavGoToFile" },
		config = function()
			require("fox.langs.php.laravel").setup()
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

	-- PHP & Laravel Environment Check Modal Hook
	{
		name = "fox_php_tools",
		dir = vim.fn.stdpath("config") .. "/lua/plugins/fox",
		ft = { "php", "blade" },
		cmd = "PHPCheckTools",
		config = function()
			local php = require("fox.langs.php")
			local modal = php.modal

			vim.api.nvim_create_user_command("PHPCheckTools", function()
				modal.check_tools(false, true)
			end, { desc = "Check PHP & Laravel CLI environment status" })

			local checked, pending = false, false
			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "php", "blade" },
				callback = function(args)
					if not checked and not pending then
						pending = true
						local buf = args.buf
						-- Defer slightly to allow buffer layout to settle
						vim.defer_fn(function()
							pending = false
							if vim.g.fox_testing or _G.fox_testing then
								return
							end
							if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf then
								checked = true
								modal.check_tools(false)
							end
						end, 300)
					end
				end,
			})
		end,
	},
}
