-- ============================================================================
-- PLUGINS: conform.nvim -- formatting on save, with the project's own tools.
-- ============================================================================
-- THE RULE THIS FILE FOLLOWS
--   A formatter only runs when the PROJECT asks for it. prettier and prettierd
--   are skipped unless a prettier config file exists somewhere above the file;
--   pint and php-cs-fixer need the binary or a `vendor/bin` copy. Otherwise
--   opening someone else's repository would silently reformat it on save.
--
--   `stop_after_first` means the list is a preference order, not a pipeline:
--   prettierd (daemon, fast) then prettier then biome.
--
-- WHERE TO CHANGE THINGS
--   Which tool formats which filetype, and any formatter-specific condition/args
--   (prettier's astro handling, PHP's vendor/bin detection, ...), lives in the
--   owning language's lua/fox/langs/<lang>/init.lua (`M.formatters_by_ft` /
--   `M.conform_formatters`), NOT here. This file only merges those into conform's
--   `opts.formatters_by_ft` / `opts.formatters`.
--   format_on_save     Timeout and LSP fallback.
--
-- MANUAL FORMAT
--   <leader>ff (see lua/keymaps/lsp.lua).
-- ============================================================================

--- Merges every language module's `formatters_by_ft` into one table.
local function build_formatters_by_ft()
	local langs = require("fox.langs").langs
	local by_ft = {}
	for _, lang in pairs(langs) do
		if lang.formatters_by_ft then
			for ft, spec in pairs(lang.formatters_by_ft) do
				by_ft[ft] = spec
			end
		end
	end
	return by_ft
end

--- Merges every language module's `conform_formatters` (per-formatter condition/args
--- overrides) into one table.
local function build_conform_formatters()
	local langs = require("fox.langs").langs
	local formatters = {}
	for _, lang in pairs(langs) do
		if lang.conform_formatters then
			for name, spec in pairs(lang.conform_formatters) do
				formatters[name] = spec
			end
		end
	end
	return formatters
end

return {
	{
		"stevearc/conform.nvim",
		-- Mason exposes installed tools on PATH; LanguageManager owns installation.
		dependencies = { "williamboman/mason.nvim" },
		event = { "BufReadPre", "BufNewFile" },
		cmd = { "ConformInfo" },
		opts = function()
			return {
				formatters_by_ft = build_formatters_by_ft(),
				formatters = build_conform_formatters(),
				format_on_save = function(buf)
					local ft = vim.bo[buf].filetype
					return { timeout_ms = (ft == "php" or ft == "blade") and 10000 or 1000 }
				end,
				default_format_opts = {
					lsp_format = "fallback",
					-- Svelte keeps its language-server formatting fallback.
					filter = function(client)
						return not (client.name == "biome" and vim.bo.filetype == "svelte")
							and require("fox.langs.toolchain").allow_lsp_format(vim.api.nvim_get_current_buf(), client)
					end,
				},
			}
		end,
		config = function(_, opts)
			local toolchain = require("fox.langs.toolchain")
			for ft, defaults in pairs(opts.formatters_by_ft) do
				opts.formatters_by_ft[ft] = function(buf)
					local state = toolchain.read(toolchain.context(buf == 0 and vim.api.nvim_get_current_buf() or buf))
					local selected = toolchain.selection(state, "formatters", defaults)
					local result = {}
					for _, name in ipairs(selected) do
						if vim.tbl_contains(defaults, name) then
							local info = require("conform").get_formatter_info(name, buf)
							local missing = info.available_msg and info.available_msg:match("^Command '.+' not found$") ~= nil
							toolchain.missing_tool("Formatter", name, missing)
							if not missing then
								result[#result + 1] = name
							end
						end
					end
					result.stop_after_first = state.formatter_mode ~= "pipeline"
						and (state.formatter_mode == "fallback" or defaults.stop_after_first)
					if #result == 0 then
						result.lsp_format = "never"
					end
					return result
				end
			end
			local seen = {}
			for _, lang in pairs(require("fox.langs").langs) do
				for _, names in pairs(lang.formatters_by_ft or {}) do
					for _, name in ipairs(names) do
						seen[name] = true
					end
				end
			end
			for name in pairs(seen) do
				local base = opts.formatters[name] or {}
				opts.formatters[name] = function(buf)
					return toolchain.formatter_override(buf, name, base)
				end
			end
			require("conform").setup(opts)

			vim.api.nvim_create_user_command("FormatDocument", function()
				require("conform").format({ async = true })
			end, { desc = "Format current buffer using Pint / PHP-CS-Fixer / blade-formatter / project formatter" })

			vim.api.nvim_create_user_command("ConformFormat", function()
				require("conform").format({ async = true })
			end, { desc = "Format current buffer using Pint / PHP-CS-Fixer / blade-formatter / project formatter" })
		end,
	},
}
