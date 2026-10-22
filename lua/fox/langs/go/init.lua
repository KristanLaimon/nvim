-- ============================================================================
-- FOX GO: Centralized Go Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard `gofmt` hard-tab indentation defaults (tabs, width 4) for Go buffers
--   when no .editorconfig file specifies buffer settings. Also owns the gopls LSP
--   server and the gofumpt/goimports formatters: settings, Mason names, filetypes.
-- ============================================================================

---@type FoxLangModule
local M = {}

local env_ok, env_mod = pcall(require, "fox.core.environment")
local is_low_resource
if env_ok then
	local env = env_mod.detect()
	is_low_resource = env.is_termux or env.is_proot or env.is_mobile
else
	is_low_resource = vim.env.TERMUX_VERSION ~= nil or vim.fn.isdirectory("/data/data/com.termux") == 1
end

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "gopls" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	gopls = {
		cmd_env = is_low_resource and { GOMEMLIMIT = "512MiB" } or nil,
		settings = {
			gopls = {
				codelenses = {
					gc_details = false,
					generate = not is_low_resource,
					regenerate_cgo = not is_low_resource,
					run_govulncheck = not is_low_resource,
					test = true,
					tidy = true,
					upgrade_dependency = not is_low_resource,
					vendor = true,
				},
				hints = is_low_resource and {
					assignVariableTypes = false,
					compositeLiteralFields = false,
					compositeLiteralTypes = false,
					constantValues = false,
					functionTypeParameters = false,
					parameterNames = true,
					rangeVariableTypes = false,
				} or {
					assignVariableTypes = true,
					compositeLiteralFields = true,
					compositeLiteralTypes = true,
					constantValues = true,
					functionTypeParameters = true,
					parameterNames = true,
					rangeVariableTypes = true,
				},
				analyses = {
					unusedparams = true,
					shadow = false,
					nilness = true,
					unusedwrite = true,
				},
				staticcheck = false,
				gofumpt = true,
				completeUnimported = true,
				deepCompletion = true,
				matcher = "Fuzzy",
				usePlaceholders = true,
			},
		},
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	gopls = { mason = "gopls", lang = "Go", type = "lsp", cmd = "gopls" },
	gofumpt = { mason = "gofumpt", name = "gofumpt", type = "formatter", cmd = "gofumpt" },
	goimports = { mason = "goimports", name = "goimports", type = "formatter", cmd = "goimports" },
}

M.mason_order = { "gopls", "gofumpt", "goimports" }

--- Language Tooling Manager bundle metadata (see lua/fox/core/installer.lua).
M.bundle_name = "🟦 Go"
M.requires = {
	{ cmd = "go", name = "Go runtime", hint = "https://go.dev/dl" },
}
M.treesitter = { "go", "gomod", "gowork", "gosum" }
M.bundle_extra_mason_pkgs = { "delve" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	go = is_low_resource and { "gofmt" } or { "goimports", "gofumpt" },
}

--- Delve is an optional extra Mason package in the Go language bundle.
M.dap_tool = "delve"

---@param dap table
function M.dap_setup(dap)
	dap.adapters.go = function(callback, config)
		local host, port = config.host or "127.0.0.1", config.port or "${port}"
		local binary = vim.fn.stdpath("data") .. "/mason/packages/delve/dlv" .. (vim.fn.has("win32") == 1 and ".exe" or "")
		callback({
			type = "server",
			host = host,
			port = port,
			executable = {
				command = vim.fn.filereadable(binary) == 1 and binary or "dlv",
				args = { "dap", "-l", host .. ":" .. port },
				-- Delve on Windows must stay attached to its parent process.
				detached = vim.fn.has("win32") == 0,
			},
			options = { initialize_timeout_sec = 20 },
		})
	end

	local function prompt_arguments(prompt)
		return coroutine.create(function(co)
			vim.ui.input({ prompt = prompt }, function(input)
				local result = input ~= nil and require("dap.utils").splitstr(input) or dap.ABORT
				assert(coroutine.resume(co, result))
			end)
		end)
	end
	local function arguments()
		return prompt_arguments("Args: ")
	end
	local function build_flags()
		return prompt_arguments("Build Flags: ")
	end

	dap.configurations.go = {
		{ name = "Debug", program = "${file}" },
		{ name = "Debug (Arguments)", program = "${file}", args = arguments },
		{ name = "Debug (Arguments & Build Flags)", program = "${file}", args = arguments, buildFlags = build_flags },
		{ name = "Debug Package", program = "${fileDirname}" },
		{
			name = "Attach",
			request = "attach",
			mode = "local",
			processId = function()
				return require("dap.utils").pick_process()
			end,
		},
		{ name = "Debug test", mode = "test", program = "${file}" },
		{ name = "Debug test (go.mod)", mode = "test", program = "./${relativeFileDirname}" },
	}
	for _, config in ipairs(dap.configurations.go) do
		config.type = "go"
		config.request = config.request or "launch"
		config.buildFlags = config.buildFlags or ""
		if config.request == "launch" then
			config.outputMode = "remote"
		end
	end
end

--- Launch-profile runtimes this language owns (see lua/fox/launch/runtimes.lua).
M.launch_runtimes = {
	go = {
		command = "go run",
		dap = function(profile, root, ctx)
			return {
				type = "go",
				request = "launch",
				name = profile.name,
				mode = "debug",
				program = ctx.full_entry,
				cwd = root,
			}
		end,
	},
}

--- Standard `gofmt` defaults for Go (hard tabs, width 4).
M.defaults = {
	expandtab = false,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 0,
	autoindent = true,
}

--- Apply Go language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Go language configuration autocmds.
function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "go", "gomod", "gowork" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
