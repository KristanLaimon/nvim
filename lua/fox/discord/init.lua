local M = {}
local names = {}
for _, name in ipairs(require("fox.discord.ai_cli_names")) do
	if name ~= "cmd" or vim.fn.has("win32") == 0 then
		names[name] = true
	end
end
local messages = require("fox.discord.loading_msgs")
local git_icon_url =
	"https://raw.githubusercontent.com/KristanLaimon/nvim-config/main/config/discord-theme-icons/minecraft/dark/git.png"
local fox_icons_url =
	"https://raw.githubusercontent.com/KristanLaimon/nvim-config/main/config/discord-theme-icons/minecraft/fox-custom/"
local fox_icons = {
	"fox-arctic-looking-straight",
	"fox-arctic-sleeping",
	"fox-arctic-with-emerald-in-mouth",
	"fox-orange-looking-left",
	"fox-orange-looking-right",
	"fox-orange-looking-upwards",
	"fox-orange-sleeping",
	"fox-orange-with-emerald-in-mouth",
}
local rotation = {}
local session, timer, manager, polling
local agents = {}
local last_poll = {}
local state_file = vim.fn.stdpath("state") .. "/discord-session.json"
local project = require("fox.core.project")
local places = require("fox.discord.places")
local privacy_levels = { none = "No Censure", project = "ProjectName Only", full = "Full" }
local place = places[math.random(#places)]

-- Only inspect loaded dashboards; presence must never load Git UI modules.
function M.git_activity()
	local win = vim.api.nvim_get_current_win()
	local center = package.loaded["plugins.fox.git.git_center.config"]
	local root = center and center.get_active_target() or nil
	root = root and root.full_path or nil
	if vim.bo.filetype == "fox_git_diff_menu" then
		return "Selecting how to review project...", vim.b.fox_git_root or project.root()
	end
	local log = package.loaded["plugins.fox.git.log_diff"]
	if log and log.state.is_open then
		for _, key in ipairs({ "files_win", "logs_win", "before_win", "after_win" }) do
			if log.state[key] == win then
				return "Reviewing commit log...", log.state.cwd
			end
		end
	end
	if center then
		for _, key in ipairs({
			"main_win",
			"preview_win",
			"tab_win",
			"diff_modal_win",
			"log_win",
			"log_right_win",
			"branch_win",
			"graph_win",
			"graph_right_win",
		}) do
			if center[key] == win then
				return "Gitting around...", root or vim.fn.getcwd()
			end
		end
	end
	local diff = package.loaded["plugins.fox.git.diff_mode"]
	local state = diff and diff.state
	if state and state.is_active then
		for _, key in ipairs({ "file_list_win", "editor_win", "dual_left_win", "dual_right_win" }) do
			if state[key] == win then
				local text = "Reviewing Working Tree vs HEAD"
				if state.mode == "between_branches" then
					text = "Reviewing a whole branch..."
				elseif state.custom_commits then
					text = "Reviewing selected commits..."
				elseif state.base_ref ~= "HEAD" and state.commits_behind == 0 then
					text = "Reviewing a whole branch..."
				elseif state.commits_behind > 0 then
					text = "Reviewing last " .. state.commits_behind .. (state.commits_behind == 1 and " commit" or " commits")
				end
				return text, state.cwd
			end
		end
	end
end

function M.privacy(root)
	local file, exists = project.config_path("discord.json", root)
	if not exists then
		return "none"
	end
	local ok, config = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
	end)
	-- A broken privacy file must not accidentally publish project details.
	return ok and type(config) == "table" and privacy_levels[config.censure] and config.censure or "full"
end

function M.select_privacy()
	local _, root = M.git_activity()
	root = root or project.root()
	vim.ui.select({ "none", "project", "full" }, {
		prompt = "Discord privacy for this project (current: " .. privacy_levels[M.privacy(root)] .. ")",
		format_item = function(level)
			return privacy_levels[level]
		end,
	}, function(level)
		if not level then
			return
		end
		local ok, err = pcall(function()
			local file = project.config_path("discord.json", root)
			vim.fn.mkdir(vim.fs.dirname(file), "p")
			assert(vim.fn.writefile({ vim.json.encode({ censure = level }) }, file) == 0)
		end)
		if not ok then
			vim.notify("Could not save Discord privacy: " .. tostring(err), vim.log.levels.ERROR)
		elseif manager and not manager.is_paused then
			manager:queue_update(true)
		end
	end)
end

local function basename(value)
	return (value:lower():gsub("\\", "/"):match("([^/]+)$") or "")
		:gsub("%.exe$", "")
		:gsub("%.cmd$", "")
		:gsub("%.js$", "")
		:gsub("%.mjs$", "")
		:gsub("%.py$", "")
end

function M.process_agent(name, command)
	name = basename(name)
	if names[name] then
		return name
	end
	if
		not ({ node = true, bun = true, deno = true, python = true, python3 = true, npx = true, uv = true, uvx = true })[name]
	then
		return nil
	end
	-- Inspect script paths too: npm's agent processes often have node.exe as their name.
	command = type(command) == "string" and command or ""
	command = command:gsub("([\"'])(.-)%1", function(_, value)
		return value:gsub("%s", "\1")
	end)
	local first = true
	for token in command:gmatch("%S+") do
		token = token:gsub("\1", " ")
		local candidate = basename(token)
		if first then
			first = false
		elseif token:sub(1, 1) ~= "-" then
			local path = token:lower():gsub("\\", "/")
			if path:find("@anthropic-ai/claude-code/", 1, true) then
				return "claude"
			end
			if path:find("@google/gemini-cli/", 1, true) then
				return "gemini"
			end
			for part in path:gmatch("[^/]+") do
				if names[part] then
					return part
				end
			end
			return names[candidate] and candidate or nil
		end
	end
end

function M.find_agent(processes, root)
	local children = {}
	for _, process in ipairs(processes) do
		if process.pid == root then
			local agent = M.process_agent(process.name, process.command)
			if agent then
				return agent
			end
		end
		children[process.ppid] = children[process.ppid] or {}
		table.insert(children[process.ppid], process)
	end
	local seen = {}
	local function visit(pid)
		if seen[pid] then
			return nil
		end
		seen[pid] = true
		for _, process in ipairs(children[pid] or {}) do
			local agent = M.process_agent(process.name, process.command) or visit(process.pid)
			if agent then
				return agent
			end
		end
	end
	return visit(root)
end

function M.resume(saved, now)
	if
		type(saved) == "table"
		and type(saved.start) == "number"
		and type(saved.last_seen) == "number"
		and saved.start > 0
		and saved.start <= saved.last_seen
		and saved.last_seen <= now
		and now - saved.last_seen < 600
	then
		return { start = saved.start, last_seen = now }
	end
	return { start = now, last_seen = now }
end

local function save()
	if not session then
		return
	end
	session.last_seen = os.time()
	pcall(function()
		vim.fn.mkdir(vim.fn.stdpath("state"), "p")
		local temporary = state_file .. "." .. vim.fn.getpid()
		vim.fn.writefile({ vim.json.encode(session) }, temporary)
		vim.uv.fs_rename(temporary, state_file)
	end)
end

local function refresh()
	if manager and not manager.is_paused then
		manager:queue_update(true)
	end
end

local function poll()
	local buf = vim.api.nvim_get_current_buf()
	if not timer or polling or vim.bo[buf].buftype ~= "terminal" then
		return
	end
	if last_poll[buf] and vim.uv.now() - last_poll[buf] < 3000 then
		return
	end
	last_poll[buf] = vim.uv.now()
	local channel = vim.b[buf].terminal_job_id
	local ok, pid = pcall(vim.fn.jobpid, channel or -1)
	if not ok or pid <= 0 then
		agents[buf] = nil
		return
	end
	local windows = vim.fn.has("win32") == 1
	local command = windows
			and {
				"powershell.exe",
				"-NoLogo",
				"-NoProfile",
				"-NonInteractive",
				"-Command",
				"[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,Name,CommandLine | ConvertTo-Json -Compress",
			}
		or { "ps", "-eo", "pid=,ppid=,comm=,args=" }
	polling = true
	local started = pcall(
		vim.system,
		command,
		{ text = true, timeout = 10000 },
		vim.schedule_wrap(function(result)
			polling = false
			if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].terminal_job_id ~= channel then
				return
			end
			if result.code ~= 0 then
				agents[buf] = nil
				if vim.api.nvim_get_current_buf() == buf then
					refresh()
				end
				return
			end
			local processes = {}
			if windows then
				local decoded, rows = pcall(vim.json.decode, result.stdout)
				if not decoded or type(rows) ~= "table" then
					return
				end
				if rows.ProcessId then
					rows = { rows }
				end
				for _, row in ipairs(rows) do
					processes[#processes + 1] =
						{ pid = row.ProcessId, ppid = row.ParentProcessId, name = row.Name or "", command = row.CommandLine }
				end
			else
				for line in result.stdout:gmatch("[^\n]+") do
					local child, parent, name, args = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s*(.*)$")
					if child then
						processes[#processes + 1] = { pid = tonumber(child), ppid = tonumber(parent), name = name, command = args }
					end
				end
			end
			local agent = M.find_agent(processes, pid)
			local previous = agents[buf]
			agents[buf] = agent and { name = agent, channel = channel } or nil
			if vim.api.nvim_get_current_buf() == buf and (previous and previous.name or nil) ~= agent then
				refresh()
			end
		end)
	)
	if not started then
		polling = false
	end
end

local function ai_activity()
	local buf = vim.api.nvim_get_current_buf()
	local agent = agents[buf]
	if vim.bo[buf].buftype == "terminal" and agent and agent.channel == vim.b[buf].terminal_job_id then
		local index = (math.floor(os.time() / 15) + buf) % #messages + 1
		if rotation.message ~= index then
			local icon = math.random(#fox_icons - (rotation.icon and 1 or 0))
			if rotation.icon and icon >= rotation.icon then
				icon = icon + 1
			end
			rotation = { message = index, icon = icon }
		end
		return messages[index] .. "...", fox_icons_url .. fox_icons[rotation.icon] .. ".png"
	end
end

function M.terminal_text()
	return ai_activity() or "Running commands in nvim terminal"
end

function M.post_activity(opts, activity)
	if session and activity then
		-- Match Cord's native os.time() timestamps; Discord advances elapsed time itself.
		activity.timestamps = { start = session.start }
	end
	if activity and activity.assets and not opts.is_idle and not activity.is_idle then
		local _, icon = ai_activity()
		if icon then
			activity.assets.large_image = icon
		end
	end
	if not activity then
		return
	end
	local text, root = M.git_activity()
	root = root or opts.workspace_dir or project.root()
	if text and not opts.is_idle and not activity.is_idle then
		activity.details = text
		activity.state = "in " .. vim.fs.basename(root)
		activity.buttons = nil
		activity.assets = activity.assets or {}
		activity.assets.large_image = git_icon_url
		activity.assets.large_text = "Git"
	end
	local privacy = M.privacy(root)
	if privacy ~= "none" then
		activity.state = privacy == "project" and ("in " .. place) or nil
		activity.buttons = nil
		-- Cord tooltips normally describe the language; keep them free of custom paths.
		if activity.assets then
			activity.assets.large_text = text and "Git" or opts.filetype or "Foxnvim"
			activity.assets.small_text = "Foxnvim"
		end
		if privacy == "full" then
			activity.details = text or (opts.is_idle and "Idle" or "Editing code")
		elseif not text then
			-- Rebuild file text without a workspace prefix or repository name.
			activity.details = vim.bo.buftype == "terminal" and M.terminal_text()
				or ("Editing " .. vim.fs.basename(vim.api.nvim_buf_get_name(0)))
		end
	end
end

function M.stop()
	save()
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	manager = nil
	pcall(vim.api.nvim_del_augroup_by_name, "FoxDiscord")
end

function M.setup()
	M.stop()
	local ok, saved = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(state_file), "\n"))
	end)
	session = M.resume(session or (ok and saved or nil), os.time())
	save()
	local group = vim.api.nvim_create_augroup("FoxDiscord", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "TermEnter", "TermRequest" }, {
		group = group,
		callback = function()
			vim.schedule(poll)
		end,
	})
	vim.api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, {
		group = group,
		callback = function(event)
			agents[event.buf] = nil
			last_poll[event.buf] = nil
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = M.stop,
	})
	timer = vim.uv.new_timer()
	timer:start(
		0,
		15000,
		vim.schedule_wrap(function()
			if not timer then
				return
			end
			save()
			poll()
			local buf = vim.api.nvim_get_current_buf()
			if vim.bo[buf].buftype == "terminal" and agents[buf] or M.git_activity() then
				refresh()
			end
		end)
	)
end

function M.ready(value)
	manager = value
end

function M.shutdown()
	manager = nil
end

return M
