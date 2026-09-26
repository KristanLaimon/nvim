-- ============================================================================
-- FOX LANGS: Centralized Per-Language Configuration Manager
-- ============================================================================
-- WHAT IT DOES
--   1. Automatically imports and executes `setup()` for per-language submodules
--      under `lua/fox/langs/<lang>/init.lua`.
--   2. Provides `has_editorconfig(buf)` and `has_project_config(buf, config_files)`
--      helpers so per-language defaults apply only when no project-level
--      formatter configs (Prettier, Biome, ESLint, EditorConfig, Pint, etc.) exist.
--
-- WHERE LANGUAGE-SPECIFIC CONFIG LIVES
--   This file only holds generic, language-agnostic helpers and the module
--   registry. Anything specific to one language or its tools (LSP server
--   settings, mason package names, formatter file lists, conform entries)
--   belongs in that language's own lua/fox/langs/<lang>/init.lua -- see
--   lua/fox/langs/typescript/init.lua for the fullest example:
--     M.lsp_server        array of lspconfig server names this language owns
--     M.lsp_config         { [server_name] = <lspconfig opts> }
--     M.mason              { [tool_name] = { mason=, cmd=, lang=/name=, type= } }
--     M.formatters_by_ft    { [filetype] = <conform formatter list> }
--     M.conform_formatters  { [formatter_name] = <conform formatter opts> }
--   lua/plugins/lsp/lsp.lua, lua/plugins/lsp/formatting.lua and
--   lua/fox/core/installer.lua all read these fields instead of hardcoding
--   settings -- swapping a server or formatter is a one-file edit.
-- ============================================================================

--- Mason package metadata, keyed by lspconfig/formatter/tool name -- see any
--- language module's `M.mason` table.
---@class FoxMasonToolInfo
---@field mason string Mason package/registry name.
---@field type "lsp"|"formatter"|"dap"|"extra" Drives the Language Tooling Manager UI grouping.
---@field cmd string CLI binary used to detect an already-installed tool.
---@field lang? string Human-readable language label (lsp/dap tools).
---@field name? string Human-readable tool label (formatter tools).

--- System CLI binary requirement needed before Mason packages can install.
---@class FoxLangRequirement
---@field cmd string CLI command binary name checked via executable().
---@field name string Human-readable requirement name displayed in UI.
---@field alt? string Alternative binary name checked if cmd is missing.
---@field hint? string Helpful installation hint message displayed if missing.

--- Launch profile runtime definition owned by a language module.
---@class FoxLaunchRuntime
---@field command string|fun(ctx: table): string Executable prefix or builder callback.
---@field dap? fun(profile: table, root: string, ctx: table): table|nil DAP configuration builder callback.
---@field execute? fun(ctx: table): boolean Custom launch handler callback.

--- conform.nvim per-formatter options override table.
---@class FoxConformFormatterOpts
---@field condition? fun(self: table, ctx: { filename: string, buf: integer }): boolean Condition callback deciding if formatter runs.
---@field command? string|fun(self: table, ctx: table): string Formatter binary command override.
---@field args? string[]|fun(self: table, ctx: table): string[] Formatter CLI arguments list or builder callback.
---@field stdin? boolean Whether formatter takes code input via stdin (default: true).
---@field cwd? fun(self: table, ctx: table): string Working directory callback.

--- Static nvim-dap launch/attach configuration table.
---@class FoxDapConfig
---@field type string Debug adapter name (e.g. "codelldb", "php", "coreclr", "python", "go").
---@field request "launch"|"attach" DAP request mode.
---@field name string Display name for debugger picker menu.
---@field program? string|fun(): string Path to executable or main file.
---@field cwd? string Working directory.
---@field port? integer|string Debugger port.
---@field args? string[]|fun(): string[] Command line arguments.
---@field stopOnEntry? boolean Whether to pause execution on entry point.
---@field runtimeArgs? string[] Extra runtime flags passed to runtime executable.
---@field pathMappings? table<string, string> Remote-to-local path mapping dictionary.

--- Shape every `lua/fox/langs/<lang>/init.lua` submodule may export. Every
--- field is optional -- see docs/adding-language.md for which ones a new
--- language actually needs.
---@class FoxLangModule
---@field lsp_server? string[] lspconfig/mason server name(s) this language owns.
---@field lsp_config? table<string, vim.lsp.Config> lspconfig opts, keyed by server name; merged into lsp.lua's opts.servers.
---@field mason? table<string, FoxMasonToolInfo> Mason package metadata, keyed by lspconfig/formatter/tool name.
---@field mason_order? string[] Preferred Mason install/display order for this language's tools.
---@field formatters_by_ft? table<string, table> conform.nvim formatter list, keyed by filetype.
---@field conform_formatters? table<string, FoxConformFormatterOpts> conform.nvim per-formatter option overrides, keyed by formatter name.
---@field formatter_configs? string[] Formatter/tool config filenames that indicate a project-managed code style.
---@field defaults? table<string, any> Fallback `vim.bo` options applied when no project formatter config exists.
---@field apply_defaults? fun(buf: integer) Applies `defaults` to `buf` unless a project config overrides them.
---@field setup? fun() Registers this language's autocmds; called once by `M.setup()` below.
---@field dap_filetypes? string[] Array of filetypes this language's static DAP configs apply to.
---@field dap_configs? FoxDapConfig[] Array of static nvim-dap config tables.
---@field dap_setup? fun(dap: table) Registers this language's DAP adapter(s) dynamically at runtime.
---@field dap_debug_port? integer Custom DAP debug port if used by language adapter (e.g. 9003 for Xdebug).
---@field launch_runtimes? table<string, FoxLaunchRuntime> Launch-profile runtimes this language owns (see lua/fox/launch/runtimes.lua).
---@field bundle_name? string Display name (with icon) for this language's entry in the Language Tooling Manager (`:LanguageManager`).
---@field is_minimal? boolean Marks the always-on core bundle (Lua only); pre-selected and excluded from the "pending" count.
---@field requires? FoxLangRequirement[] System runtimes the bundle needs before Mason packages can install; missing ones block the bundle with a lock icon.
---@field treesitter? string[] Treesitter parser names the Language Tooling Manager installs alongside this language's Mason packages.
---@field bundle_extra_mason_pkgs? string[] Mason package names the bundle installs beyond what `mason_order` resolves -- for tools intentionally absent from `M.mason` (e.g. a DAP tool installed through a different mechanism, a standalone linter).
---@field PRETTIER_CONFIG_FILES? string[] Prettier config file patterns indicating project-managed formatting style.
---@field BIOME_CONFIG_FILES? string[] Biome config file patterns.
---@field ESLINT_CONFIG_FILES? string[] ESLint config file patterns.
---@field DENO_CONFIG_FILES? string[] Deno config file patterns.
---@field FORMATTER_CONFIG_FILES? string[] Aggregated formatter config file patterns checked by project detection.
---@field js_debug_config? fun(profile: table, root: string, ctx: table): table Helper function building js-debug adapter launch configs.
---@field dap_tool? string Custom DAP tool name override (e.g. "delve").
---@field composer? table Submodule reference (e.g. PHP composer helper).
---@field modal? table Submodule reference (e.g. PHP tools modal helper).
---@field php_debug_port? integer Custom PHP debug port alias.

local M = {}

--- Helper to check if an `.editorconfig` file has applied settings to the buffer,
--- or if an `.editorconfig` file exists in the directory hierarchy of the buffer.
--- @param buf integer|nil Buffer handle (defaults to current).
--- @return boolean has_editorconfig
function M.has_editorconfig(buf)
	buf = (buf and buf ~= 0) and buf or vim.api.nvim_get_current_buf()

	-- Check Neovim buffer-local editorconfig flags
	if vim.b[buf].editorconfig ~= nil or vim.b[buf].editorconfig_applied then
		return true
	end

	-- Check if an .editorconfig file exists in the buffer's folder hierarchy
	local name = vim.api.nvim_buf_get_name(buf)
	if name and name ~= "" then
		local dir = vim.fs.dirname(name)
		if dir and dir ~= "" then
			local found = vim.fs.find(".editorconfig", { upward = true, path = dir })
			if found and #found > 0 then
				return true
			end
		end
	end

	return false
end

--- Helper to check whether a buffer belongs to a project with EditorConfig or any
--- specific formatter/tool configuration files (e.g. Prettier, Biome, ESLint, Deno, Pint).
--- @param buf integer|nil Buffer handle (defaults to current).
--- @param config_files table|nil Optional list of formatter/tool config filenames to look for.
--- @return boolean has_config
function M.has_project_config(buf, config_files)
	buf = (buf and buf ~= 0) and buf or vim.api.nvim_get_current_buf()

	if vim.b[buf].editorconfig ~= nil or vim.b[buf].editorconfig_applied then
		return true
	end

	local name = vim.api.nvim_buf_get_name(buf)
	if name ~= "" then
		local markers = { ".editorconfig" }
		vim.list_extend(markers, config_files or {})
		return #vim.fs.find(markers, { upward = true, path = vim.fs.dirname(name) }) > 0
	end

	return false
end

--- Registered per-language configuration submodules.
---@type table<string, FoxLangModule>
M.langs = {
	php = require("fox.langs.php"),
	typescript = require("fox.langs.typescript"),
	web = require("fox.langs.web"),
	astro = require("fox.langs.astro"),
	web_ui = require("fox.langs.web_ui"),
	csharp = require("fox.langs.csharp"),
	go = require("fox.langs.go"),
	rust = require("fox.langs.rust"),
	python = require("fox.langs.python"),
	lua = require("fox.langs.lua"),
	bash = require("fox.langs.bash"),
	docker = require("fox.langs.docker"),
	proto = require("fox.langs.proto"),
	cpp = require("fox.langs.cpp"),
	ruby = require("fox.langs.ruby"),
	haskell = require("fox.langs.haskell"),
	teal = require("fox.langs.teal"),
	github = require("fox.langs.github"),
	zig = require("fox.langs.zig"),
}

--- Display order for `M.langs` in the Language Tooling Manager (`:LanguageManager`)
--- -- `pairs()` over `M.langs` has no stable order, and this is otherwise the only
--- language-agnostic thing left to declare once; everything else per bundle
--- (name, requires, Mason packages, Treesitter parsers) comes from the module
--- itself, see lua/fox/core/installer.lua's `M.language_bundles`.
M.lang_order = {
	"lua",
	"php",
	"go",
	"rust",
	"python",
	"csharp",
	"cpp",
	"zig",
	"ruby",
	"haskell",
	"teal",
	"github",
	"web",
	"astro",
	"web_ui",
	"docker",
	"proto",
	"bash",
}

--- Initialize all per-language configuration submodules.
function M.setup()
	for _, lang in pairs(M.langs) do
		if type(lang) == "table" and type(lang.setup) == "function" then
			lang.setup()
		end
	end
end

return M
