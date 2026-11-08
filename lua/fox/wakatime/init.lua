local M = {}
local last_file, last_time = "", 0
local warned = {}
local manual, attached = {}, {}
local input_buffer
local syncing = false
local ai_enabled = false
local timer

local function warn(message)
	if not warned[message] then
		warned[message] = true
		vim.notify("WakaTime: " .. message, vim.log.levels.WARN)
	end
end

function M.cli()
	local suffix = vim.fn.has("win32") == 1 and ".exe" or ""
	for _, path in ipairs({
		"wakatime-cli",
		(vim.env.WAKATIME_HOME or vim.fn.expand("~")) .. "/.wakatime/wakatime-cli" .. suffix,
	}) do
		if vim.fn.executable(path) == 1 then
			return path
		end
	end
end

local function config_path()
	if vim.env.WAKATIME_HOME and vim.env.WAKATIME_HOME ~= "" then
		return vim.env.WAKATIME_HOME .. "/.wakatime.cfg"
	end
	local legacy = vim.fn.expand("~/.wakatime.cfg")
	if vim.fn.filereadable(legacy) == 1 then
		return legacy
	end
	return (vim.env.XDG_CONFIG_HOME or vim.fn.expand("~/.config")) .. "/wakatime/wakatime.cfg"
end

function M.set_api_key()
	local ok, key = pcall(vim.fn.inputsecret, "WakaTime API key: ")
	vim.cmd("redraw")
	if not ok or key == "" then
		return
	end
	if not key:match("^[%x]+%-%x+%-%x+%-%x+%-%x+$") or #key ~= 36 then
		vim.notify("WakaTime: invalid API key.", vim.log.levels.ERROR)
		return
	end
	local path = config_path()
	path = vim.uv.fs_realpath(path) or path
	local success, err = pcall(function()
		local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
		local output, settings, found = {}, false, false
		for _, line in ipairs(lines) do
			if line:match("^%s*%[") then
				if settings and not found then
					table.insert(output, "api_key = " .. key)
					found = true
				end
				settings = line:match("^%s*%[settings%]%s*$") ~= nil
			end
			if settings and line:match("^%s*api_?key%s*=") then
				if not found then
					table.insert(output, "api_key = " .. key)
					found = true
				end
			else
				table.insert(output, line)
			end
		end
		if not found then
			if not settings then
				table.insert(output, "[settings]")
			end
			table.insert(output, "api_key = " .. key)
		end
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p", "0o700")
		local temporary = path .. "." .. vim.fn.getpid() .. ".tmp"
		local fd = assert(vim.uv.fs_open(temporary, "wx", 384))
		local content = table.concat(output, "\n") .. "\n"
		local wrote, write_err = vim.uv.fs_write(fd, content)
		vim.uv.fs_close(fd)
		if wrote ~= #content then
			vim.uv.fs_unlink(temporary)
			error(write_err or "Incomplete configuration write")
		end
		local renamed, rename_err = vim.uv.fs_rename(temporary, path)
		if not renamed then
			vim.uv.fs_unlink(temporary)
			error(rename_err)
		end
	end)
	if success then
		warned = {}
		vim.notify("WakaTime: API key saved.")
	else
		vim.notify("WakaTime: could not save API key: " .. tostring(err), vim.log.levels.ERROR)
	end
end

function M.attach(buf)
	if attached[buf] or vim.bo[buf].buftype ~= "" then
		return
	end
	attached[buf] = vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, changed_buf, _, _, old_end, new_end)
			if input_buffer == changed_buf then
				manual[changed_buf] = (manual[changed_buf] or 0) + new_end - old_end
			end
		end,
		on_detach = function(_, detached)
			attached[detached], manual[detached] = nil, nil
		end,
	})
end

function M.sync_ai()
	if syncing then
		return
	end
	local cli = M.cli()
	if not cli then
		return
	end
	syncing = true
	local options = { text = true, detach = vim.fn.has("win32") == 0, timeout = 45000 }
	local function delivered(result)
		syncing = false
		if result.code ~= 0 then
			vim.schedule(function()
				warn("AI sync failed (exit " .. result.code .. "); check the WakaTime CLI log.")
			end)
		end
	end
	local ok = pcall(
		vim.system,
		{
			cli,
			"--sync-ai-activity",
			"--timeout",
			"30",
		},
		options,
		function(result)
			if result.code ~= 0 then
				delivered(result)
				return
			end
			-- AI parsing only queues events; combining both CLI flags skips parsing.
			local sent = pcall(vim.system, {
				cli,
				"--sync-offline-activity",
				"0",
				"--timeout",
				"30",
			}, options, delivered)
			if not sent then
				syncing = false
				vim.schedule(function()
					warn("could not start AI activity delivery.")
				end)
			end
		end
	)
	if not ok then
		syncing = false
		warn("could not start AI synchronization.")
	end
end

function M.heartbeat(write, force)
	if vim.bo.buftype ~= "" then
		return
	end
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" or file:match("^%a[%w+.-]*://") or vim.fn.reg_executing() ~= "" then
		return
	end
	local now = os.time()
	if not force and not write and file == last_file and now - last_time < 120 then
		return
	end
	local cli = M.cli()
	if not cli then
		warn("install wakatime-cli (https://github.com/wakatime/wakatime-cli); tracking is paused.")
		return
	end
	local buf = vim.api.nvim_get_current_buf()
	local changes = manual[buf] or 0
	local cursor = vim.api.nvim_win_get_cursor(0)
	local version = vim.version()
	local args = {
		cli,
		"--entity",
		file,
		"--time",
		tostring(now),
		"--plugin",
		string.format("neovim/%d.%d.%d fox-wakatime/1.0.0", version.major, version.minor, version.patch),
		"--lineno",
		tostring(cursor[1]),
		"--cursorpos",
		tostring(cursor[2] + 1),
		"--lines-in-file",
		tostring(vim.api.nvim_buf_line_count(0)),
	}
	if vim.bo.filetype ~= "" then
		vim.list_extend(args, { "--alternate-language", vim.bo.filetype })
	end
	if write then
		table.insert(args, "--write")
	end
	if not ai_enabled then
		table.insert(args, "--sync-ai-disabled")
	end
	if changes ~= 0 then
		vim.list_extend(args, { "--human-line-changes", tostring(changes) })
	end
	-- Detached Windows processes can open visible consoles for their child commands.
	local ok = pcall(vim.system, args, { text = true, detach = vim.fn.has("win32") == 0 }, function(result)
		if result.code == 103 or result.code == 104 then
			vim.schedule(function()
				warn("check ~/.wakatime.cfg and :WakaTimeApiKey (CLI exit " .. result.code .. ").")
			end)
		end
	end)
	if ok then
		last_file, last_time = file, now
		manual[buf] = nil
	else
		warn("could not start wakatime-cli.")
	end
end

function M.setup(opts)
	ai_enabled = opts ~= nil and opts.sync_ai == true
	vim.api.nvim_create_user_command("WakaTimeInstall", function()
		require("fox.wakatime.install").run()
	end, { desc = "Install the official WakaTime CLI" })
	vim.api.nvim_create_user_command("WakaTimeApiKey", M.set_api_key, { desc = "Set WakaTime tracking API key" })
	local group = vim.api.nvim_create_augroup("FoxWakaTime", { clear = true })
	vim.on_key(function(_, typed)
		input_buffer = nil
		local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
		if typed == "" or (mode ~= "n" and mode ~= "i" and mode ~= "v" and mode ~= "V" and mode ~= "R") then
			return
		end
		local buf = vim.api.nvim_get_current_buf()
		M.attach(buf)
		input_buffer = buf
		-- Only edits in this input dispatch count; reloads and deferred agent edits do not.
		vim.schedule(function()
			input_buffer = nil
		end)
	end, vim.api.nvim_create_namespace("FoxWakaTimeInput"))
	vim.api.nvim_create_autocmd({ "BufLeave", "InsertLeave" }, {
		group = group,
		callback = function(event)
			input_buffer = nil
			if manual[event.buf] and manual[event.buf] ~= 0 then
				M.heartbeat(false, true)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePre", {
		group = group,
		callback = function()
			input_buffer = nil
		end,
	})
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	if ai_enabled then
		timer = vim.uv.new_timer()
		timer:start(30000, 30000, vim.schedule_wrap(M.sync_ai))
	end
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if timer then
				timer:stop()
				timer:close()
				timer = nil
			end
			if manual[vim.api.nvim_get_current_buf()] then
				M.heartbeat(false, true)
			end
			if ai_enabled then
				M.sync_ai()
			end
		end,
	})
	if ai_enabled then
		vim.schedule(M.sync_ai)
	end
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter" }, {
		group = group,
		callback = function()
			M.heartbeat(false)
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function()
			M.heartbeat(true)
		end,
	})
end

return M
