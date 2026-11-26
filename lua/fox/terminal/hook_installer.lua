local M = {}
local asset_directory = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")

local function read(path)
	local handle = io.open(path, "rb")
	if not handle then
		if vim.uv.fs_stat(path) then
			error("Cannot read " .. path)
		end
		return nil
	end
	local content = handle:read("*a")
	handle:close()
	return content
end

local function write(path, content)
	local old = read(path)
	if old == content then
		return
	end
	if old and path:sub(-5) == ".json" and vim.deep_equal(vim.json.decode(old), vim.json.decode(content)) then
		return
	end
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local function save(target, text)
		local handle = assert(vim.uv.fs_open(target, "wx", 384))
		local count, err = vim.uv.fs_write(handle, text)
		local closed, close_err = vim.uv.fs_close(handle)
		if count ~= #text or not closed then
			vim.uv.fs_unlink(target)
			error(err or close_err or ("Incomplete write to " .. target))
		end
	end
	if old and not vim.uv.fs_stat(path .. ".foxvim-backup") then
		save(path .. ".foxvim-backup", old)
	end
	local temporary = path .. ".foxvim-" .. vim.fn.getpid() .. ".tmp"
	save(temporary, content)
	local ok, err = vim.uv.fs_rename(temporary, path)
	if not ok then
		os.remove(temporary)
		error(err)
	end
end

local function object(path)
	local text = read(path)
	assert(not text or text:match("^%s*{"), "Expected JSON object: " .. path)
	local result = text and vim.json.decode(text) or vim.empty_dict()
	assert(type(result) == "table" and (not vim.islist(result) or next(result) == nil), "Expected JSON object: " .. path)
	return result
end

local function hook_command(agent, options)
	local function quote(value)
		return "'" .. value:gsub("'", "'\\''") .. "'"
	end
	local windows = options.windows
	if windows == nil then
		windows = vim.fn.has("win32") == 1
	end
	if windows then
		local function powershell_quote(value)
			return "'" .. value:gsub("'", "''") .. "'"
		end
		local command = "& "
			.. powershell_quote(options.nvim or vim.v.progpath)
			.. " --headless -u NONE -l "
			.. powershell_quote(asset_directory .. "/session_hook.lua")
			.. " "
			.. agent
		return "powershell.exe -NoProfile -NonInteractive -EncodedCommand "
			.. vim.base64.encode(vim.iconv(command, "utf-8", "utf-16le"))
	end
	return quote(options.nvim or vim.v.progpath)
		.. " --headless -u NONE -l "
		.. quote(asset_directory .. "/session_hook.lua")
		.. " "
		.. agent
end

local function add_session_hook(config, event, command)
	config.hooks = config.hooks or vim.empty_dict()
	assert(
		type(config.hooks) == "table" and (not vim.islist(config.hooks) or next(config.hooks) == nil),
		"hooks must be an object"
	)
	local entries = config.hooks[event] or {}
	assert(type(entries) == "table" and vim.islist(entries), event .. " must be an array")
	for _, entry in ipairs(entries) do
		for _, hook in ipairs(type(entry) == "table" and type(entry.hooks) == "table" and entry.hooks or {}) do
			if hook.command == command then
				return
			end
		end
	end
	entries[#entries + 1] = { hooks = { { type = "command", command = command, timeout = 10 } } }
	config.hooks[event] = entries
end

local function codex_features(content)
	local lines = vim.split(content or "", "\n", { plain = true })
	local section, features_index, hooks_configured
	for index, line in ipairs(lines) do
		local header = line:match("^%s*%[([^%]]+)%]%s*#?.*$")
		if header then
			section = header
			if section == "features" then
				features_index = index
			end
		elseif section == "features" and (line:match("^%s*hooks%s*=") or line:match("^%s*codex_hooks%s*=")) then
			assert(
				line:match("=%s*true%s*$") or line:match("=%s*true%s*#"),
				"Codex hooks are explicitly disabled or unsupported; config.toml was preserved"
			)
			hooks_configured = true
		end
	end
	if hooks_configured then
		return content
	elseif features_index then
		table.insert(lines, features_index + 1, "hooks = true")
	else
		lines[#lines + 1] = "[features]"
		lines[#lines + 1] = "hooks = true"
	end
	return table.concat(lines, "\n"):gsub("\n*$", "\n")
end

--- options.home/dirs allow isolated installation and tests.
--- Existing JSON values survive; malformed JSON/JSONC is refused before writing.
function M.install(agent, options)
	options = options or {}
	local home = options.home or vim.fn.expand("~")
	local directories = {
		codex = (not options.home and vim.env.CODEX_HOME) or home .. "/.codex",
		claude = (not options.home and vim.env.CLAUDE_CONFIG_DIR) or home .. "/.claude",
		opencode = (not options.home and vim.env.XDG_CONFIG_HOME or home .. "/.config") .. "/opencode",
		agy = home .. "/.gemini/config",
	}
	local directory = options.dirs and options.dirs[agent] or directories[agent]
	assert(directories[agent] and directory, "Unknown agent: " .. tostring(agent))
	local changed = {}
	local function save(path, content)
		write(path, content)
		changed[#changed + 1] = path
	end
	if agent == "opencode" then
		assert(
			not read(directory .. "/tui.jsonc"),
			"OpenCode tui.jsonc requires manual plugin registration; existing JSONC was preserved"
		)
		local tui_path, cli_path = directory .. "/tui.json", directory .. "/cli.json"
		local state_home = options.state_home or (not options.home and vim.env.XDG_STATE_HOME) or home .. "/.local/state"
		assert(
			read(cli_path) or not (read(tui_path) or read(state_home .. "/opencode/kv.json")),
			"OpenCode V2 preferences migration is pending; start OpenCode once before installing hooks"
		)
		local tui, cli = object(tui_path), object(cli_path)
		for _, item in ipairs({ { tui, "./foxvim-session.js", "plugin" }, { cli, "./foxvim-session", "plugins" } }) do
			item[1][item[3]] = item[1][item[3]] or {}
			assert(vim.islist(item[1][item[3]]), "OpenCode plugin must be an array")
			if not vim.tbl_contains(item[1][item[3]], item[2]) then
				table.insert(item[1][item[3]], item[2])
			end
		end
		local plugin_path = directory .. "/foxvim-session.js"
		local existing = read(plugin_path)
		assert(
			not existing or existing:find("FoxVim session integration", 1, true),
			"Refusing to overwrite " .. plugin_path
		)
		local entry_path = directory .. "/foxvim-session/tui.js"
		local entry = read(entry_path)
		assert(not entry or entry:find("FoxVim session integration", 1, true), "Refusing to overwrite " .. entry_path)
		save(plugin_path, assert(read(asset_directory .. "/opencode_hook.js")))
		save(entry_path, '// FoxVim session integration\nexport { default } from "../foxvim-session.js";\n')
		save(tui_path, vim.json.encode(tui) .. "\n")
		save(cli_path, vim.json.encode(cli) .. "\n")
	else
		local path = directory .. (agent == "claude" and "/settings.json" or "/hooks.json")
		local config = object(path)
		local command = hook_command(agent, options)
		if agent == "agy" then
			assert(config.foxvim == nil or type(config.foxvim) == "table", "foxvim hook block must be an object")
			config.foxvim = config.foxvim or vim.empty_dict()
			local entries = config.foxvim.PreInvocation or {}
			assert(type(entries) == "table" and vim.islist(entries), "PreInvocation must be an array")
			local exists = false
			for _, entry in ipairs(entries) do
				if type(entry) == "table" and entry.command == command then
					exists = true
				end
			end
			if not exists then
				entries[#entries + 1] = { type = "command", command = command, timeout = 10 }
			end
			config.foxvim.PreInvocation = entries
		else
			add_session_hook(config, "SessionStart", command)
			if agent == "claude" then
				add_session_hook(config, "SessionEnd", command)
			end
		end
		local toml_path = directory .. "/config.toml"
		local toml = agent == "codex" and not options.register_only and codex_features(read(toml_path)) or nil
		save(path, vim.json.encode(config) .. "\n")
		if toml then
			save(toml_path, toml)
		end
	end
	return changed
end

return M
