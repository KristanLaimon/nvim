-- ============================================================================
-- FOX LUA: Centralized Lua Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard 2-space indentation defaults for Lua buffers when no
--   .editorconfig file specifies buffer settings. Also owns the lua_ls LSP server
--   and the stylua formatter.
-- ============================================================================

---@type FoxLangModule
local M = {}

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "lua_ls" }

--- LuaLS settings and project libraries supplied by the type injector.
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	lua_ls = {
		filetypes = { "lua" },
		root_dir = function(buf, on_dir)
			local filename = vim.api.nvim_buf_get_name(buf)
			if filename ~= "" then
				on_dir(vim.fs.root(buf, {
					".luarc.json",
					".luarc.jsonc",
					".emmyrc.json",
					".luacheckrc",
					".stylua.toml",
					"stylua.toml",
					"selene.toml",
					"selene.yml",
					".git",
				}) or vim.fs.dirname(filename))
			end
		end,
		before_init = function(_, config)
			local type_injector = require("plugins.fox.tools.type_injector")
			local libs = type_injector.get_active_lua_libraries(config.root_dir)
			local neovim = require("plugins.fox.tools.type_injector_lua").is_neovim_project(config.root_dir, type_injector)
			if neovim then
				config.settings.Lua.diagnostics.globals =
					{ "vim", "fetch", "console", "import", "foxnvim", "cli", "terminal", "fs" }
			end
			local ignored = type_injector.get_ignored_lua_directories(config.root_dir)

			-- Detect Omarchy and inject hyprland and omarchy types
			local env = require("fox.core.environment").detect()
			if neovim and env.is_omarchy then
				table.insert(libs, "/usr/share/hypr")
				table.insert(libs, "/usr/share/omarchy")
				-- Optionally also append to globals if not done in the diagnostics below
				local globals = config.settings.Lua.diagnostics.globals or {}
				table.insert(globals, "hl")
				table.insert(globals, "omarchy")
				config.settings.Lua.diagnostics.globals = globals
			end

			config.settings.Lua.workspace.library = libs
			config.settings.Lua.workspace.ignoreDir = ignored
		end,
		settings = {
			Lua = {
				runtime = {
					version = "LuaJIT",
					path = { "?.lua", "?/init.lua", "lua/?.lua", "lua/?/init.lua" },
				},
				diagnostics = {
					globals = {},
				},
				workspace = {
					checkThirdParty = false,
					ignoreDir = {
						".vscode",
						"config/schemas-langs/lua/garrysmod",
						"config/schemas-langs/lua/love",
						"config/schemas-langs/lua/koreader",
					},
				},
				completion = {
					callSnippet = "Replace",
					autoRequire = true,
				},
				hint = {
					enable = true,
					setType = true,
				},
				telemetry = {
					enable = false,
				},
				format = {
					enable = true,
					defaultConfig = {
						indent_style = "tab",
						indent_size = "2",
					},
				},
			},
		},
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	lua_ls = { mason = "lua-language-server", lang = "Lua", type = "lsp", cmd = "lua-language-server" },
	stylua = { mason = "stylua", name = "stylua", type = "formatter", cmd = "stylua" },
}

M.mason_order = { "lua_ls", "stylua" }

--- Language Tooling Manager bundle metadata (see lua/fox/core/installer.lua).
M.bundle_name = "🌙 Minimal Core"
M.is_minimal = true
M.requires = {} -- lua-language-server ships as a self-contained binary via Mason
M.treesitter = { "lua", "vim", "vimdoc", "markdown", "markdown_inline" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	lua = { "stylua" },
}

local NVIM_LUA_ENTRY_COMMAND =
	"nvim --headless -c \"lua package.path = vim.fn.stdpath('config') .. '/lua/?.lua;' .. vim.fn.stdpath('config') .. '/lua/?/init.lua;' .. package.path; require('fox.lib.foxnvim')\" -l"
M.launch_runtimes = {
	lua = {
		command = NVIM_LUA_ENTRY_COMMAND,
		dap = function()
			vim.notify("Lua debugging requires a Lua debug adapter", vim.log.levels.WARN)
			return nil
		end,
	},
}

--- Standard defaults for Lua & FoxVim scripts (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply Lua language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Lua language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "lua",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
