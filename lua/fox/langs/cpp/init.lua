-- ============================================================================
-- FOX CPP: Centralized C / C++ Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Configures clangd LSP server, clang-format, cpplint, cppcheck static checkers,
--   codelldb DAP debugger, and launch profile runtimes for C/C++.
--   Integrates with fox.cmeta for per-project C standard via .krsnvim/c.json.
-- ============================================================================

---@type FoxLangModule
local M = {}

local cmeta = require("fox.cmeta")

M.lsp_server = { "clangd" }

---@type table<string, vim.lsp.Config>
M.lsp_config = {
	clangd = {
		filetypes = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
		capabilities = {
			offsetEncoding = { "utf-16" },
		},
		before_init = function(_, config)
			-- Inject per-project C standard and extra args from .krsnvim/c.json
			local args = cmeta.get_clangd_extra_args()
			if #args > 0 then
				config.cmd = config.cmd or { "clangd" }
				-- Avoid duplicating --std= if already present
				local has_std = false
				for _, a in ipairs(config.cmd) do
					if a:match("^%-%-std=") then
						has_std = true
						break
					end
				end
				for _, arg in ipairs(args) do
					local dup = false
					for _, a in ipairs(config.cmd) do
						if a == arg then
							dup = true
							break
						end
					end
					if not dup then
						table.insert(config.cmd, arg)
					end
				end
			end
		end,
	},
}

M.mason = {
	clangd = { mason = "clangd", lang = "C / C++", type = "lsp", cmd = "clangd" },
	["clang-format"] = { mason = "clang-format", name = "clang-format", type = "formatter", cmd = "clang-format" },
	cpplint = { mason = "cpplint", name = "cpplint", type = "formatter", cmd = "cpplint" },
	cppcheck = { mason = "cppcheck", name = "cppcheck", type = "formatter", cmd = "cppcheck" },
	codelldb = { mason = "codelldb", lang = "LLDB Debugger", type = "dap", cmd = "codelldb" },
}

M.mason_order = { "clangd", "clang-format", "cpplint", "cppcheck", "codelldb" }

M.bundle_name = "⚡ C / C++"
M.requires = {
	{
		cmd = "gcc",
		name = "C/C++ Compiler (gcc/clang)",
		alt = "clang",
		hint = "apt install build-essential / brew install gcc",
	},
	{ cmd = "make", name = "Make / CMake build tools", alt = "cmake", hint = "apt install make cmake" },
}
M.treesitter = { "c", "cpp", "make", "cmake" }

M.formatters_by_ft = {
	c = { "clang-format" },
	cpp = { "clang-format" },
}

M.conform_formatters = {
	["clang-format"] = {
		condition = function()
			return vim.fn.executable("clang-format") == 1
		end,
	},
	cpplint = {
		condition = function()
			return vim.fn.executable("cpplint") == 1
		end,
	},
	cppcheck = {
		condition = function()
			return vim.fn.executable("cppcheck") == 1
		end,
	},
}

M.dap_filetypes = { "c", "cpp" }

---@param dap table
function M.dap_setup(dap)
	dap.adapters.codelldb = {
		type = "server",
		port = "${port}",
		executable = {
			command = "codelldb",
			args = { "--port", "${port}" },
		},
	}

	dap.configurations.cpp = {
		{
			name = "🚀 Launch C/C++ (codelldb)",
			type = "codelldb",
			request = "launch",
			program = function()
				return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
			end,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
		},
	}
	dap.configurations.c = dap.configurations.cpp
end

M.launch_runtimes = {
	cpp = {
		command = "g++ -g -o /tmp/a.out ${file} && /tmp/a.out",
		dap = function(profile, root, ctx)
			return {
				type = "codelldb",
				request = "launch",
				name = profile.name,
				program = ctx.full_entry,
				cwd = root,
			}
		end,
	},
}

M.defaults = {
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 4,
	autoindent = true,
}

function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "c", "cpp" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
	cmeta.setup_commands()
	cmeta.register_palette()
end

return M
