local M = {}
local managed_servers = {}
local missing_notified = {}

function M.missing_tool(category, name, missing)
	local key = category .. ":" .. name
	if not missing then
		missing_notified[key] = nil
	elseif not missing_notified[key] then
		missing_notified[key] = true
		vim.schedule(function()
			vim.notify(
				category .. " " .. name .. " not installed yet. Install it using Command Palette: Per Language Bundles.",
				vim.log.levels.INFO
			)
		end)
	end
end

function M.register_server(name)
	managed_servers[name] = true
end

local function object(value)
	return type(value) == "table" and value or {}
end

function M.context(buf)
	buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
	local root = require("fox.core.project").root(buf)
	return {
		buf = buf,
		root = root,
		ft = vim.bo[buf].filetype,
		path = vim.fs.joinpath(root, ".foxnvim", "toolchain.json"),
	}
end

function M.global_context(ctx)
	return vim.tbl_extend("force", ctx, { path = vim.fs.joinpath(vim.fn.stdpath("data"), "toolchain.json") })
end

function M.read(ctx, scope_only)
	local store = require("fox.core.store")
	local local_state = object(store.load(ctx.path)[ctx.ft])
	if scope_only then
		return local_state
	end
	local global = object(store.load(M.global_context(ctx).path)[ctx.ft])
	local state = vim.tbl_extend("force", global, local_state)
	state.markers = vim.tbl_extend("force", object(global.markers), object(local_state.markers))
	return state
end

function M.save(ctx, key, value)
	local store = require("fox.core.store")
	local data = store.load(ctx.path, false)
	if vim.uv.fs_stat(ctx.path) and (not data or vim.islist(data) and next(data)) then
		return nil, "Invalid toolchain.json. Fix it before saving."
	end
	data = data or {}
	data[ctx.ft] = object(data[ctx.ft])
	data[ctx.ft][key] = value
	local dir = vim.fs.dirname(ctx.path)
	local made, failure = pcall(vim.fn.mkdir, dir, "p")
	if not made then
		return nil, tostring(failure)
	end
	local temporary = ctx.path .. "." .. vim.uv.os_getpid() .. ".tmp"
	local ok, err = pcall(vim.fn.writefile, { vim.json.encode(data) }, temporary)
	if ok and err == 0 then
		ok, err = vim.uv.fs_rename(temporary, ctx.path)
		if ok then
			return true
		end
	end
	vim.uv.fs_unlink(temporary)
	return nil, tostring(err)
end

function M.selection(state, category, defaults)
	local names = object(state)[category]
	if type(names) ~= "table" or not vim.islist(names) then
		return vim.deepcopy(defaults)
	end
	local seen, selected = {}, {}
	for _, name in ipairs(names) do
		if type(name) == "string" and not seen[name] then
			seen[name] = true
			selected[#selected + 1] = name
		end
	end
	return selected
end

function M.metadata(name)
	for _, lang in pairs(require("fox.langs").langs) do
		local spec = (lang.toolchain or {})[name]
		if spec then
			return spec
		end
	end
	return {}
end

function M.linters(ft)
	local tools = {}
	for _, lang in pairs(require("fox.langs").langs) do
		for name, spec in pairs(lang.toolchain or {}) do
			if spec.lint and vim.tbl_contains(spec.lint.filetypes, ft) then
				tools[name] = spec.lint
			end
		end
	end
	return tools
end

function M.catalog(ctx)
	local defaults = require("plugins.lsp.formatting")[1].opts().formatters_by_ft[ctx.ft] or {}
	local formatters = { available = {}, enabled = {}, servers = {}, fallback = defaults.stop_after_first }
	local linters = { available = vim.tbl_keys(M.linters(ctx.ft)), enabled = {}, servers = {} }
	local servers = { available = {}, enabled = {}, servers = {} }
	for _, name in ipairs(defaults) do
		formatters.available[#formatters.available + 1] = name
		formatters.enabled[#formatters.enabled + 1] = name
	end
	for name in pairs(managed_servers) do
		local config = vim.lsp.config[name]
		if vim.lsp.is_enabled(name) and vim.tbl_contains(config.filetypes or {}, ctx.ft) then
			local group = M.server_category(name) == "linters" and linters or servers
			group.available[#group.available + 1] = name
			group.enabled[#group.enabled + 1] = name
			group.servers[name] = true
		end
	end
	for _, group in ipairs({ linters, servers }) do
		table.sort(group.available)
		table.sort(group.enabled)
	end
	return { formatters = formatters, linters = linters, servers = servers }
end

function M.valid_filename(name)
	return type(name) == "string"
		and name ~= ""
		and not name:find('[%c/\\:*?"<>|]')
		and name ~= "."
		and name ~= ".."
		and not name:match("[. ]$")
end

function M.markers(state, category, name)
	local list = object(state.markers)[category .. "/" .. name]
	if type(list) == "table" and vim.islist(list) then
		return vim.tbl_filter(M.valid_filename, list)
	end
end

function M.find_config(ctx, names)
	if not names or #names == 0 then
		return
	end
	local filename = vim.api.nvim_buf_get_name(ctx.buf)
	local dir = filename ~= "" and vim.fs.dirname(filename) or ctx.root
	return vim.fs.find(names, { path = dir, upward = true, type = "file" })[1]
		or vim.fs.find(names, { path = ctx.root, type = "file" })[1]
end

function M.formatter_override(buf, name, base)
	local ctx = M.context(buf)
	local state = M.read(ctx)
	local spec = M.metadata(name)
	local markers = M.markers(state, "formatters", name)
	if not markers or #markers == 0 then
		return base
	end
	local config_file = M.find_config(ctx, markers)
	local override = vim.tbl_extend("force", {}, base, {
		condition = function(self, formatter_ctx)
			return config_file ~= nil
				and (
					spec.config_args ~= nil
					or spec.config_env ~= nil
					or not base.condition
					or base.condition(self, formatter_ctx)
				)
		end,
	})
	if config_file and (spec.config_args or spec.config_env) then
		local ok, builtin = pcall(require, "conform.formatters." .. (base.inherit or name))
		builtin = ok and builtin or {}
		if spec.config_env then
			override.env = function(self, formatter_ctx)
				local env = base.env or builtin.env
				env = type(env) == "function" and env(self, formatter_ctx) or env
				return vim.tbl_extend("force", {}, env or {}, { [spec.config_env] = config_file })
			end
		end
		if spec.replace_append_args then
			override.append_args = {}
		end
		for _, field in ipairs({ "args", "range_args" }) do
			local original = base[field] or builtin[field]
			if spec.config_args and original then
				override[field] = function(self, formatter_ctx)
					local args = type(original) == "function" and original(self, formatter_ctx) or original
					local prefix = vim.tbl_map(function(arg)
						return arg == "$CONFIG" and config_file or arg
					end, spec.config_args)
					if spec.config_after_subcommand then
						table.insert(prefix, 1, args[1])
						return vim.list_extend(prefix, args, 2)
					end
					return vim.list_extend(prefix, args)
				end
			end
		end
	end
	return override
end

function M.server_category(name)
	return M.metadata(name).diagnostics and "linters" or "servers"
end

function M.allow_lsp_format(buf, client)
	local selected = M.read(M.context(buf)).servers
	if type(selected) ~= "table" or not vim.islist(selected) then
		return true
	end
	for _, name in ipairs(selected) do
		for _, attached in ipairs(vim.lsp.get_clients({ bufnr = buf, name = name, method = "textDocument/formatting" })) do
			if attached.name ~= "biome" or vim.bo[buf].filetype ~= "svelte" then
				return attached.id == client.id
			end
		end
	end
	return true
end

function M.settings_path(root, name)
	return vim.fs.joinpath(root and vim.fs.joinpath(root, ".foxnvim") or vim.fn.stdpath("data"), "lsp", name .. ".json")
end

function M.settings(name, defaults, root)
	local settings = vim.deepcopy(defaults or vim.empty_dict())
	for _, filename in ipairs({ M.settings_path(nil, name), root and M.settings_path(root, name) }) do
		if vim.uv.fs_stat(filename) then
			local override = require("fox.core.store").load(filename, false)
			if not override or vim.islist(override) and next(override) then
				vim.notify("Invalid LSP settings: " .. filename, vim.log.levels.ERROR)
			else
				settings = vim.tbl_deep_extend("force", settings, override)
			end
		end
	end
	return settings
end

function M.wrap_init(name, original)
	return function(params, config)
		local path = config.root_dir
			and vim.fs.find(function(dir, parent)
				return dir == ".foxnvim" and vim.uv.fs_stat(M.settings_path(parent, name)) ~= nil
			end, { path = config.root_dir, upward = true, type = "directory" })[1]
		for key, value in pairs(M.settings(name, config.settings, path and vim.fs.dirname(path))) do
			config.settings[key] = value
		end
		for _, callback in ipairs(type(original) == "table" and original or { original }) do
			callback(params, config)
		end
	end
end

function M.wrap_root(name, config)
	return function(buf, on_dir)
		local ctx = M.context(buf)
		local state = M.read(ctx)
		local category = M.server_category(name)
		if not vim.tbl_contains(M.selection(state, category, { name }), name) then
			return
		end
		local markers = M.markers(state, category, name)
		local detected = M.find_config(ctx, markers)
		local function start(root)
			local cmd = type(config.cmd) == "table" and config.cmd[1]
			if type(config.cmd) == "function" then
				local tool = require("fox.core.installer").tools[name]
				cmd = tool and tool.cmd
			end
			if type(cmd) == "string" then
				local missing = vim.fn.executable(cmd) ~= 1
				if missing and root and type(config.cmd) == "function" then
					for _, directory in ipairs({ "node_modules/.bin", "vendor/bin" }) do
						if vim.fn.executable(vim.fs.joinpath(root, directory, cmd)) == 1 then
							missing = false
							break
						end
					end
				end
				M.missing_tool(category == "linters" and "Linter" or "LSP", name, missing)
				if missing then
					return
				end
			end
			if vim.uv.fs_stat(M.settings_path(ctx.root, name)) and (not root or not vim.fs.relpath(ctx.root, root)) then
				root = ctx.root
			end
			on_dir(root)
		end
		if detected then
			start(vim.fs.dirname(detected))
		elseif not markers or #markers == 0 then
			if type(config.root_dir) == "function" then
				config.root_dir(buf, start)
			else
				local root = config.root_dir or (config.root_markers and vim.fs.root(buf, config.root_markers))
				if root or config.workspace_required ~= true then
					start(root)
				end
			end
		end
	end
end

function M.refresh(ctx, name, global)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and (name or vim.bo[buf].filetype == ctx.ft) then
			local current = M.context(buf)
			if global or current.root == ctx.root then
				local state = M.read(current)
				for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, _uninitialized = true })) do
					local category = M.server_category(client.name)
					if
						client.name == name or not vim.tbl_contains(M.selection(state, category, { client.name }), client.name)
					then
						vim.lsp.buf_detach_client(buf, client.id)
						if not next(client.attached_buffers) then
							client:stop()
						end
					end
				end
				pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = buf, group = "nvim.lsp.enable" })
				require("fox.langs.toolchain_lint").run(buf)
			end
		end
	end
end

return M
