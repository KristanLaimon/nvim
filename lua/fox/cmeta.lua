-- ============================================================================
-- FOX CMETA: C Project Metadata (.krsnvim/c.json)
-- ============================================================================
-- WHAT IT DOES
--   Provides per-project C metadata (standard, compiler, includes, defines) stored
--   in .krsnvim/c.json at the project root. Integrates with clangd to inject
--   the correct --std= flag. Exposes a command palette entry "C Project Metadata".
-- ============================================================================

local M = {}

---@class FoxCMetaConfig
---@field c table
---@field c.standard string C standard: c89|c90|c95|c99|c11|c17|c23|gnu89|gnu90|gnu99|gnu11|gnu17|gnu23
---@field c.compiler string Compiler identifier: clang|gcc|msvc
---@field c.include_dirs string[] Additional include directories
---@field c.defines string[] Preprocessor defines

local defaults = {
	c = {
		standard = "c99",
		compiler = "clang",
		include_dirs = {},
		defines = {},
	},
}

local standards = {
	"c89",
	"c90",
	"c95",
	"c99",
	"c11",
	"c17",
	"c23",
	"gnu89",
	"gnu90",
	"gnu99",
	"gnu11",
	"gnu17",
	"gnu23",
}

---Find project root by looking for markers.
---@return string
local function project_root()
	local root = vim.fs.root(
		0,
		{ ".git", ".krsnvim", "Makefile", "CMakeLists.txt", "compile_commands.json", "meson.build", "build.ninja" }
	)
	if not root then
		root = vim.fn.getcwd()
	end
	return root
end

---Path to the metadata file.
---@return string
function M.filepath()
	return vim.fs.joinpath(project_root(), ".krsnvim", "c.json")
end

---Load metadata from file, merging with defaults.
---@return FoxCMetaConfig
function M.load()
	local path = M.filepath()
	if vim.fn.filereadable(path) == 0 then
		return vim.deepcopy(defaults)
	end
	local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok or type(data) ~= "table" then
		vim.notify("[fox.cmeta] Invalid .krsnvim/c.json, using defaults", vim.log.levels.WARN)
		return vim.deepcopy(defaults)
	end
	data.c = data.c or {}
	if not data.c.standard then
		data.c.standard = defaults.c.standard
	end
	if not data.c.compiler then
		data.c.compiler = defaults.c.compiler
	end
	if not data.c.include_dirs then
		data.c.include_dirs = defaults.c.include_dirs
	end
	if not data.c.defines then
		data.c.defines = defaults.c.defines
	end
	return data
end

---Save metadata to file.
---@param data FoxCMetaConfig
---@return boolean
function M.save(data)
	local path = M.filepath()
	local dir = vim.fs.dirname(path)
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	local ok, txt = pcall(vim.json.encode, data, { indent = 2, newline = "\n" })
	if not ok then
		vim.notify("[fox.cmeta] Failed to encode JSON", vim.log.levels.ERROR)
		return false
	end
	vim.fn.writefile(vim.split(txt, "\n", { plain = true }), path)
	vim.notify("[fox.cmeta] Saved: " .. path, vim.log.levels.INFO)
	return true
end

---Get current C standard.
---@return string
function M.get_standard()
	local cfg = M.load()
	return cfg.c.standard or "c99"
end

---Set C standard and save.
---@param std string
function M.set_standard(std)
	local cfg = M.load()
	cfg.c.standard = std
	M.save(cfg)
end

---Get current compiler.
---@return string
function M.get_compiler()
	local cfg = M.load()
	return cfg.c.compiler or "clang"
end

---Set compiler and save.
---@param compiler string
function M.set_compiler(compiler)
	local cfg = M.load()
	cfg.c.compiler = compiler
	M.save(cfg)
end

---Get clangd --std= argument for current standard.
---@return string
function M.get_clangd_std_arg()
	return "--std=" .. M.get_standard()
end

---Get all clangd extra args based on metadata.
---@return string[]
function M.get_clangd_extra_args()
	local cfg = M.load()
	local args = {}
	table.insert(args, "--std=" .. cfg.c.standard)
	for _, dir in ipairs(cfg.c.include_dirs or {}) do
		table.insert(args, "-I" .. dir)
	end
	for _, def in ipairs(cfg.c.defines or {}) do
		table.insert(args, "-D" .. def)
	end
	return args
end

---Open the metadata file in editor, creating if needed.
function M.open()
	local path = M.filepath()
	if vim.fn.filereadable(path) == 0 then
		M.save(M.load())
	end
	vim.cmd.edit(path)
end

---Initialize metadata file with defaults.
function M.init()
	M.save(M.load())
	vim.notify(".krsnvim/c.json created with defaults", vim.log.levels.INFO)
end

---Show current metadata in a notification.
function M.show()
	local cfg = M.load()
	local lines = {
		"C Project Metadata:",
		"  Standard: " .. (cfg.c.standard or "c99"),
		"  Compiler: " .. (cfg.c.compiler or "clang"),
		"  Include dirs: " .. #(cfg.c.include_dirs or {}),
		"  Defines: " .. #(cfg.c.defines or {}),
	}
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "C Project Metadata" })
end

---Interactive command palette for C Project Metadata.
function M.open_palette()
	local cfg = M.load()
	local current = cfg.c.standard or "c99"

	vim.ui.select({
		{ label = "Set C Standard (" .. current .. ")", value = "std" },
		{ label = "Set Compiler (" .. (cfg.c.compiler or "clang") .. ")", value = "compiler" },
		{ label = "Open .krsnvim/c.json", value = "open" },
		{ label = "Create .krsnvim/c.json with defaults", value = "init" },
		{ label = "Show current metadata", value = "show" },
	}, {
		prompt = "C Project Metadata",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.value == "show" then
			M.show()
			return
		end

		if choice.value == "open" then
			M.open()
			return
		end

		if choice.value == "init" then
			M.init()
			return
		end

		if choice.value == "std" then
			vim.ui.select(standards, {
				prompt = "Select C Standard (current: " .. current .. ")",
				default = current,
			}, function(std)
				if not std then
					return
				end
				M.set_standard(std)
				vim.notify("C standard set to: " .. std .. " (applies next clangd attach/restart)", vim.log.levels.INFO)
				-- Restart clangd for current buffer if attached
				local clients = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })
				if #clients > 0 then
					vim.cmd.LspRestart("clangd")
				end
			end)
			return
		end

		if choice.value == "compiler" then
			vim.ui.select({ "clang", "gcc", "msvc" }, {
				prompt = "Select Compiler (current: " .. (cfg.c.compiler or "clang") .. ")",
				default = cfg.c.compiler or "clang",
			}, function(compiler)
				if not compiler then
					return
				end
				M.set_compiler(compiler)
				vim.notify("Compiler set to: " .. compiler, vim.log.levels.INFO)
				local clients = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })
				if #clients > 0 then
					vim.cmd.LspRestart("clangd")
				end
			end)
			return
		end
	end)
end

---Setup user commands.
function M.setup_commands()
	vim.api.nvim_create_user_command("CProjectMeta", M.open_palette, { desc = "Open C Project Metadata palette" })
	vim.api.nvim_create_user_command("CStd", function()
		M.open_palette()
	end, { desc = "Quick C standard selector" })
end

---Register command palette entries.
---Safe to call more than once: entries are only added the first time.
function M.register_palette()
	if M._palette_registered then
		return
	end

	local ok, palette = pcall(require, "plugins.fox.tools.command_palette")
	if not ok or type(palette.add_command) ~= "function" then
		return
	end

	palette.add_command({
		name = "⚙️ C Project Metadata (Standard, Compiler, Includes)",
		category = "C / C++",
		cmd = "CProjectMeta",
	})
	palette.add_command({
		name = "📋 Show C Project Metadata",
		category = "C / C++",
		fn = M.show,
	})
	palette.add_command({
		name = "📝 Open .krsnvim/c.json (Project C Metadata)",
		category = "C / C++",
		fn = M.open,
	})
	M._palette_registered = true
end

return M
