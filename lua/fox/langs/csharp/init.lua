-- ============================================================================
-- FOX CSHARP: Centralized C# / .NET Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard Microsoft C# 4-space indentation defaults for C# buffers when no
--   .editorconfig file specifies buffer settings. Also owns the omnisharp (primary)
--   and csharp_ls (disabled alternative) LSP servers, netcoredbg (DAP), and the
--   csharpier formatter.
-- ============================================================================

---@type FoxLangModule
local M = {}

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "omnisharp", "csharp_ls" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	omnisharp = {
		cmd = { "omnisharp", "--languageserver", "--hostPID", tostring(vim.fn.getpid()) },
		enable_roslyn_analyzers = true,
		organize_imports_on_format = true,
		enable_import_completion = true,
		root_dir = function(bufnr, on_dir)
			local util = require("lspconfig.util")
			local fname = vim.api.nvim_buf_get_name(bufnr)
			-- 1. Check for classic .sln
			-- 2. Anchor to the closest .csproj (vital for .slnx and monorepo subprojects)
			local root = util.root_pattern("*.sln")(fname)
				or util.root_pattern("*.csproj", "omnisharp.json", "global.json")(fname)
			if root then
				on_dir(root)
			else
				on_dir(vim.fs.dirname(fname))
			end
		end,
		settings = {
			FormattingOptions = {
				EnableEditorConfigSupport = true,
				OrganizeImports = true,
			},
			MsBuild = {
				LoadProjectsOnDemand = false,
			},
			RoslynExtensionsOptions = {
				EnableAnalyzersSupport = true,
				EnableImportCompletion = true,
				AnalyzeOpenDocumentsOnly = false,
				DiagnosticWorkersThreadCount = 4,
			},
			Sdk = {
				IncludePrereleases = true,
			},
			InlayHintsOptions = {
				EnableForParameters = true,
				ForLiteralParameters = true,
				ForIndexerParameters = true,
				ForObjectCreationParameters = true,
				ForOtherParameters = true,
				SuppressForParametersThatDifferOnlyBySuffix = false,
				SuppressForParametersThatMatchMethodIntent = false,
				SuppressForParametersThatMatchArgumentName = false,
				EnableForTypes = true,
				ForImplicitVariableTypes = true,
				ForLambdaParameterTypes = true,
				ForImplicitObjectCreation = true,
			},
		},
	},
	csharp_ls = {
		enabled = false,
		root_dir = function(bufnr, on_dir)
			local util = require("lspconfig.util")
			local fname = vim.api.nvim_buf_get_name(bufnr)
			local root = util.root_pattern("*.sln")(fname) or util.root_pattern("*.csproj")(fname)
			if root then
				on_dir(root)
			else
				on_dir(vim.fs.dirname(fname))
			end
		end,
	},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	omnisharp = { mason = "omnisharp", lang = "C#", type = "lsp", cmd = "OmniSharp" },
	netcoredbg = { mason = "netcoredbg", lang = "C# Debugger", type = "dap", cmd = "netcoredbg" },
	csharpier = { mason = "csharpier", name = "csharpier", type = "formatter", cmd = "csharpier" },
}

M.mason_order = { "omnisharp", "netcoredbg", "csharpier" }

--- Language Tooling Manager bundle metadata (see lua/fox/core/installer.lua).
M.bundle_name = "🎯 C# / .NET"
M.requires = {
	{ cmd = "dotnet", name = ".NET SDK", hint = "https://dot.net" },
}
M.treesitter = { "c_sharp" }
M.dotnet_tools = { "csharp-ls" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	cs = { "csharpier" },
}

--- Finds the newest built assembly for a `.csproj` (or project directory) entry.
--- netcoredbg launches the DLL, not the project, so this has to resolve it.
--- @param root string Project root.
--- @param entry string Entry point: a `.dll`, a `.csproj`, or a directory.
--- @return string|nil dll Absolute path to the newest matching DLL.
local function find_dotnet_dll(root, entry)
	local path = require("fox.core.path")
	local full = path.join(root, entry)
	if entry:match("%.dll$") then
		return full
	end

	local proj_dir = entry:match("%.csproj$") and vim.fn.fnamemodify(full, ":h") or full
	local name = entry:match("([^/\\]+)%.csproj$") or vim.fn.fnamemodify(proj_dir, ":t")

	local newest, newest_time = nil, -1
	for _, dll in ipairs(vim.fn.glob(proj_dir .. "/bin/**/" .. name .. ".dll", false, true)) do
		local mtime = vim.fn.getftime(dll)
		if mtime > newest_time then
			newest, newest_time = path.normalize(dll), mtime
		end
	end
	return newest
end

--- Filetypes the DAP configurations below attach to.
M.dap_filetypes = { "cs" }

--- Static nvim-dap configurations, appended by lua/plugins/editor/dap.lua.
M.dap_configs = {
	{
		type = "coreclr",
		request = "launch",
		name = "🎯 Launch .NET Assembly DLL (C#)",
		program = function()
			local root = vim.fn.getcwd()
			local dlls = vim.fn.glob(root .. "/bin/Debug/**/*.dll", false, true)
			if #dlls == 1 then
				return dlls[1]
			elseif #dlls > 1 then
				return vim.fn.input("Path to assembly DLL: ", dlls[1], "file")
			end
			return vim.fn.input("Path to assembly DLL: ", root .. "/bin/Debug/", "file")
		end,
		cwd = "${workspaceFolder}",
		stopAtEntry = false,
	},
	{
		type = "coreclr",
		request = "launch",
		name = "🌐 Launch & Debug Blazor Server App",
		program = function()
			local root = vim.fn.getcwd()
			local dlls = vim.fn.glob(root .. "/bin/Debug/**/*.dll", false, true)
			for _, dll in ipairs(dlls) do
				if not dll:match("%.Views%.dll$") and not dll:match("%.resources%.dll$") then
					return dll
				end
			end
			return vim.fn.input("Path to Blazor app DLL: ", root .. "/bin/Debug/", "file")
		end,
		cwd = "${workspaceFolder}",
		env = {
			ASPNETCORE_ENVIRONMENT = "Development",
		},
		stopAtEntry = false,
	},
	{
		type = "coreclr",
		request = "attach",
		name = "🔌 Attach to Running .NET / Blazor Process",
		processId = function()
			return require("dap.utils").pick_process()
		end,
	},
}

--- Launch-profile runtimes this language owns (see lua/fox/launch/runtimes.lua).
--- With auto_build enabled, `dotnet build` already ran as a pre-launch task, so
--- the DLL is on disk by the time this runs.
M.launch_runtimes = {
	dotnet = {
		command = "dotnet run --project",
		dap = function(profile, root, ctx)
			local dll = find_dotnet_dll(root, ctx.entry)
			if not dll then
				vim.notify(
					"❌ No built DLL found for "
						.. ctx.entry
						.. ".\n  Enable Auto Build on the profile, or point the entry point at bin/Debug/<tfm>/App.dll.",
					vim.log.levels.ERROR,
					{ title = "Launch Profiles Debugger" }
				)
				return nil
			end
			return {
				type = "coreclr",
				request = "launch",
				name = profile.name,
				program = dll,
				cwd = root,
			}
		end,
	},
}

--- Standard C# / .NET defaults (4 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 4,
	tabstop = 4,
	softtabstop = 4,
	autoindent = true,
}

--- Apply C# language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Forces workstation GC under proot Termux: Server GC reserves 256GB of virtual
--- address space per core, which fails under proot's ulimit -v cap even though
--- nothing is actually used ("GC: reserving (256 gb) for the regions range failed").
local function apply_proot_gc_workaround()
	local ok, env_mod = pcall(require, "fox.core.environment")
	if ok and env_mod.detect().is_proot then
		vim.env.DOTNET_gcServer = "0"
	end
end

-- C# file templates stay here with the rest of the language configuration.
M.type_templates = {
	"Class",
	"Interface",
	"Record",
	"Struct",
	"Record struct",
	"Enum",
	"Static class",
	"Abstract class",
	"Sealed class",
	"Delegate",
	"Empty file",
}

local keywords = {}
for word in
	(
		"abstract as base bool break byte case catch char checked class const continue decimal default delegate "
		.. "do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int "
		.. "interface internal is lock long namespace new null object operator out override params private protected "
		.. "public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw "
		.. "true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while"
	):gmatch("%S+")
do
	keywords[word] = true
end

local function identifier(name)
	name = name:gsub("[^%w_]", "_")
	if name:match("^%d") then
		name = "_" .. name
	end
	return keywords[name] and ("@" .. name) or name
end

M.identifier = identifier

--- Infer the namespace following Visual Studio standards (.csproj or Program.cs upward).
function M.file_namespace(filename)
	local dir = vim.fs.dirname(filename)
	local project = vim.fs.find(function(name)
		return name:match("%.csproj$") ~= nil
	end, { path = dir, upward = true, type = "file" })[1]

	local base_namespace = nil
	local base_dir = nil

	if project then
		base_dir = vim.fs.dirname(project)
		local project_name = vim.fn.fnamemodify(project, ":t:r")
		local ok, lines = pcall(vim.fn.readfile, project)
		local xml = ok and table.concat(lines, "\n"):gsub("<!%-%-.-%-%->", "") or ""
		-- ponytail: literal RootNamespace and MSBuildProjectName only; use MSBuild
		-- evaluation if imported/conditional properties need to be resolved.
		local namespace = xml:match("<RootNamespace>%s*(.-)%s*</RootNamespace>") or project_name
		namespace = namespace:gsub("%$%(MSBuildProjectName%)", function()
			return project_name
		end)
		if namespace:find("%$%(") then
			namespace = project_name
		end
		base_namespace = namespace
	else
		-- Search upward for Program.cs or other .cs files with a namespace declaration
		local current_base = vim.fn.fnamemodify(filename, ":t")
		local candidate = vim.fs.find(function(name)
			return name == "Program.cs" or (name:match("%.cs$") and name ~= current_base)
		end, { path = dir, upward = true, type = "file" })[1]

		if candidate then
			base_dir = vim.fs.dirname(candidate)
			local ok, lines = pcall(vim.fn.readfile, candidate)
			if ok then
				local content = table.concat(lines, "\n"):gsub("<!%-%-.-%-%->", "")
				local ns = content:match("namespace%s+([%w_%.]+)")
				if ns then
					base_namespace = ns
				end
			end
		end
	end

	if not base_namespace then
		return nil
	end

	local relative = require("fox.core.path").relative_to(dir, base_dir)
	if relative and relative ~= "" then
		base_namespace = base_namespace .. (base_namespace ~= "" and "." or "") .. relative:gsub("[/\\]+", ".")
	end
	local parts = {}
	for part in base_namespace:gmatch("[^.]+") do
		parts[#parts + 1] = identifier(part:gsub("^@", ""))
	end
	return #parts > 0 and table.concat(parts, ".") or nil
end

--- Return C#-specific variables for the template engine.
function M.template_variables(filename)
	return {
		csharp_namespace = M.file_namespace(filename),
		csharp_identifier = identifier(vim.fn.fnamemodify(filename, ":t:r")),
	}
end

--- Generate a type named after the file. Block namespaces also work before C# 10.
function M.type_lines(filename, template)
	if template == "Empty file" then
		return { "" }
	end
	local name = identifier(vim.fn.fnamemodify(filename, ":t:r"))
	local declaration = "internal " .. template:lower() .. " " .. name
	local lines = template == "Delegate" and { "internal delegate void " .. name .. "();" } or { declaration, "{", "}" }
	local namespace = M.file_namespace(filename)
	if namespace then
		local wrapped = { "namespace " .. namespace, "{" }
		for _, line in ipairs(lines) do
			wrapped[#wrapped + 1] = "    " .. line
		end
		wrapped[#wrapped + 1] = "}"
		return wrapped
	end
	return lines
end

local function empty_csharp_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.api.nvim_buf_is_loaded(buf)
		and vim.bo[buf].buftype == ""
		and vim.bo[buf].modifiable
		and vim.api.nvim_buf_get_name(buf):match("%.cs$")
		and vim.api.nvim_buf_line_count(buf) == 1
		and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

--- Show a floating template menu; never replace content typed while it is open.
function M.new_type(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not empty_csharp_buffer(buf) or vim.b[buf].csharp_template_pending then
		return
	end
	local tmpl_mod = require("fox.core.templates")
	local available = tmpl_mod.get_templates("cs")
	if #available == 0 then
		return
	end
	local options = {}
	for _, template in ipairs(available) do
		options[#options + 1] = {
			name = template.name,
			label = template.description and (template.name .. "  (" .. template.description .. ")") or template.name,
			template = template,
		}
	end
	vim.b[buf].csharp_template_pending = true
	local filename = vim.api.nvim_buf_get_name(buf)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	require("fox.lib.foxnvim.cli").menu(
		{ title = "C# Type", compact_header = true, width = 96, min_height = 18 },
		options,
		function(choice)
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			vim.b[buf].csharp_template_pending = nil
			if
				choice
				and empty_csharp_buffer(buf)
				and vim.api.nvim_buf_get_name(buf) == filename
				and vim.api.nvim_buf_get_changedtick(buf) == tick
			then
				local choice_name = type(choice) == "table" and (choice.name or choice[1] or choice.label) or tostring(choice)
				local matched = nil
				for _, t in ipairs(available) do
					if t.name:lower() == choice_name:lower() then
						matched = t
						break
					end
				end
				if matched then
					tmpl_mod.apply_template_to_buffer(buf, matched, filename)
				end
			end
		end
	)
end

local recent_created = {}

--- Initialize C# language configuration autocmds.
function M.setup()
	apply_proot_gc_workaround()
	local group = vim.api.nvim_create_augroup("FoxCsharp", { clear = true })
	vim.api.nvim_create_user_command("CsharpNewType", function()
		M.new_type()
	end, { desc = "Choose a C# template for the current empty .cs buffer" })
	vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
		group = group,
		pattern = "*.cs",
		callback = function(args)
			vim.schedule(function()
				if empty_csharp_buffer(args.buf) and not vim.b[args.buf].csharp_template_offered then
					vim.b[args.buf].csharp_template_offered = true
					M.new_type(args.buf)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "FoxFileCreated",
		callback = function(args)
			local filename = args.data and args.data.path
			if not filename or not filename:match("%.cs$") then
				return
			end
			if recent_created[filename] then
				return
			end
			recent_created[filename] = true
			vim.defer_fn(function()
				recent_created[filename] = nil
			end, 2000)

			vim.schedule(function()
				if vim.fn.getfsize(filename) ~= 0 then
					return
				end
				local bufnr = vim.fn.bufnr(filename)
				if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
					local current_win = vim.api.nvim_get_current_win()
					if vim.api.nvim_win_get_config(current_win).relative ~= "" then
						for _, w in ipairs(vim.api.nvim_list_wins()) do
							if vim.api.nvim_win_get_config(w).relative == "" then
								vim.api.nvim_set_current_win(w)
								break
							end
						end
					end
					vim.cmd("edit " .. vim.fn.fnameescape(filename))
					bufnr = vim.api.nvim_get_current_buf()
				end
				if not vim.b[bufnr].csharp_template_offered then
					vim.b[bufnr].csharp_template_offered = true
					M.new_type(bufnr)
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = { "cs" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
