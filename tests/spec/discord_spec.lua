local t = require("fox.lib.foxnvim.test")
local discord = require("fox.discord")

t.describe("Discord Git activity and privacy", function()
	local root, original, buf, saved, select
	local modules = { "plugins.fox.git.diff_mode", "plugins.fox.git.log_diff", "plugins.fox.git.git_center.config" }
	t.beforeEach(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/.foxnvim", "p")
		original = vim.api.nvim_get_current_buf()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, root .. "/private.lua")
		vim.api.nvim_set_current_buf(buf)
		saved = {}
		for _, module in ipairs(modules) do
			saved[module] = package.loaded[module]
			package.loaded[module] = nil
		end
		select = vim.ui.select
	end)
	t.afterEach(function()
		vim.ui.select = select
		for _, module in ipairs(modules) do
			package.loaded[module] = saved[module]
		end
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(root, "rf")
	end)
	t.it("reports Git scopes without branch names, hashes or file paths and follows focus", function()
		local win = vim.api.nvim_get_current_win()
		local state = { is_active = true, editor_win = win, cwd = root, commits_behind = 0, base_ref = "HEAD" }
		package.loaded[modules[1]] = { state = state }
		t.expect(discord.git_activity()).toBe("Reviewing Working Tree vs HEAD")
		state.commits_behind = 7
		t.expect(discord.git_activity()).toBe("Reviewing last 7 commits")
		state.commits_behind, state.base_ref = 0, "sensitive-branch"
		t.expect(discord.git_activity()).toBe("Reviewing a whole branch...")
		state.custom_commits = true
		t.expect(discord.git_activity()).toBe("Reviewing selected commits...")
		package.loaded[modules[2]] = { state = { is_open = true, after_win = win, cwd = root } }
		t.expect(discord.git_activity()).toBe("Reviewing commit log...")
		vim.bo.filetype = "fox_git_diff_menu"
		t.expect(discord.git_activity()).toBe("Selecting how to review project...")
		vim.bo.filetype = "lua"
		package.loaded[modules[2]] = nil
		package.loaded[modules[3]] = {
			main_win = win,
			get_active_target = function()
				return { full_path = root }
			end,
		}
		t.expect(discord.git_activity()).toBe("Gitting around...")
		package.loaded[modules[3]] = nil
		state.editor_win = nil
		t.expect(discord.git_activity()).toBe(nil)
	end)
	t.it("persists all three levels, strips private fields, and fails closed for invalid config", function()
		local function activity()
			local value = {
				details = "Editing " .. root .. "/private.lua",
				state = "In secret-project",
				buttons = { { label = "Repository", url = "https://private.example/repo" } },
				assets = { large_image = "lua-icon", large_text = root, small_text = root },
			}
			discord.post_activity({ workspace_dir = root, filetype = "lua" }, value)
			return value
		end
		t.expect(discord.privacy(root)).toBe("none")
		t.expect(activity().state).toBe("In secret-project")
		for _, level in ipairs({ "project", "full", "none" }) do
			vim.ui.select = function(_, _, callback)
				callback(level)
			end
			discord.select_privacy()
			t.expect(discord.privacy(root)).toBe(level)
			local value = activity()
			if level ~= "none" then
				t.expect(value.buttons).toBe(nil)
				t.expect(value.assets.large_text).toBe("lua")
				t.expect(value.assets.large_image).toBe("lua-icon")
				t.expect(vim.json.encode(value):find(root, 1, true)).toBe(nil)
			end
			if level == "full" then
				t.expect(value.details).toBe("Editing code")
				t.expect(value.state).toBe(nil)
			elseif level == "project" then
				t.expect(value.details).toBe("Editing private.lua")
				t.expect(value.state:sub(1, 3)).toBe("in ")
			end
		end
		vim.fn.writefile({ "broken JSON" }, root .. "/.foxnvim/discord.json")
		t.expect(discord.privacy(root)).toBe("full")
		vim.ui.select = function(_, _, callback)
			callback(nil)
		end
		discord.select_privacy()
		t.expect(discord.privacy(root)).toBe("full")
	end)
end)

t.describe("Discord application identity", function()
	t.it("applies config to the existing Cord modules before restarting its server", function()
		local modules = {
			"cord",
			"cord.api.config",
			"cord.api.icon",
			"cord.api.command",
			"fox.discord",
			"plugins.ui.discord",
			"fox.discord.ai_cli_names",
			"fox.discord.loading_msgs",
		}
		local saved = {}
		for _, name in ipairs(modules) do
			saved[name] = package.loaded[name]
		end
		local preload, notify = package.preload["fox.discord"], vim.notify
		local applied, stopped, restarted = false, false, false
		local icons = { ICONS_URL = "upstream" }
		local icons_url = "https://raw.githubusercontent.com/KristanLaimon/nvim-config/main/config/discord-theme-icons/"
		local config = {
			verify = function(opts)
				assert(opts.editor.client == "1566816819879092294")
				assert(icons.ICONS_URL == icons_url, "icon source must change before Cord resolves its defaults")
				assert(opts.editor.icon == icons_url .. "minecraft/dark/neovim.png")
				assert(opts.idle.icon == icons_url .. "minecraft/dark/idle.png")
				assert(opts.advanced.server.pipe_path == nil, "Cord's global server lock requires the shared IPC path")
				applied = true
				return opts
			end,
		}
		package.loaded["cord.api.config"] = config
		package.loaded["cord.api.icon"] = icons
		package.loaded["cord"] = {
			setup = function()
				assert(applied)
				assert(icons.ICONS_URL == icons_url)
			end,
		}
		package.loaded["cord.api.command"] = {
			restart = function()
				assert(applied and stopped)
				restarted = true
			end,
		}
		package.loaded["fox.discord"] = {
			stop = function()
				stopped = true
			end,
		}
		package.preload["fox.discord"] = function()
			return { setup = function() end }
		end
		vim.notify = function() end
		local ok, err = pcall(function()
			package.loaded["plugins.ui.discord"] = nil
			local spec = require("plugins.ui.discord")
			vim.cmd("CordReload")
			t.expect(restarted).toBe(true)
			t.expect(package.loaded["cord.api.config"] == config).toBe(true)
			icons.ICONS_URL = "upstream"
			spec.config(nil, spec.opts)
			t.expect(icons.ICONS_URL).toBe(icons_url)
		end)
		vim.notify, package.preload["fox.discord"] = notify, preload
		for _, name in ipairs(modules) do
			package.loaded[name] = saved[name]
		end
		vim.api.nvim_del_user_command("CordReload")
		vim.api.nvim_del_user_command("DiscordReload")
		if not ok then
			error(err)
		end
	end)
end)

t.describe("Discord AI activity", function()
	t.it("finds native executables and npm script agents", function()
		t.expect(discord.process_agent("codex.exe", "")).toBe("codex")
		t.expect(discord.process_agent("node.exe", [[node "C:\npm\claude.js" --resume]])).toBe("claude")
		t.expect(discord.process_agent("node.exe", [["C:\Program Files\nodejs\node.exe" "C:\My Tools\codex.js"]]))
			.toBe("codex")
		t.expect(discord.process_agent("node.exe", [[node C:\npm\@anthropic-ai\claude-code\cli.js]])).toBe("claude")
		t.expect(discord.process_agent("node.exe", "node server.js --prompt codex")).toBe(nil)
		t.expect(discord.process_agent("node.exe", vim.NIL)).toBe(nil)
		t.expect(discord.process_agent("powershell.exe", "echo codex")).toBe(nil)
		if vim.fn.has("win32") == 1 then
			t.expect(discord.process_agent("cmd.exe", "cmd /c dir")).toBe(nil)
		end
	end)
	t.it("scopes detection to the terminal process tree and clears after exit", function()
		local processes = {
			{ pid = 10, ppid = 1, name = "powershell.exe" },
			{ pid = 11, ppid = 10, name = "node.exe", command = "node codex.js" },
			{ pid = 20, ppid = 1, name = "bash" },
		}
		t.expect(discord.find_agent(processes, 10)).toBe("codex")
		t.expect(discord.find_agent(processes, 20)).toBe(nil)
		t.expect(discord.find_agent(processes, 11)).toBe("codex")
		table.remove(processes, 2)
		t.expect(discord.find_agent(processes, 10)).toBe(nil)
	end)
	t.it("resumes within ten minutes and resets at the boundary", function()
		local saved = { start = 100, last_seen = 1000 }
		t.expect(discord.resume(saved, 1599).start).toBe(100)
		t.expect(discord.resume(saved, 1600).start).toBe(1600)
		t.expect(discord.resume(saved, 999).start).toBe(999)
		t.expect(discord.resume({ start = "broken" }, 1600).start).toBe(1600)
		t.expect(discord.resume(nil, 1600).start).toBe(1600)
	end)
end)

t.describe("Discord lifecycle", function()
	t.it("rotates only in the agent buffer, restores sessions and cleans up on exit", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local saved_start = os.time() - 3600
		vim.fn.writefile(
			{ vim.json.encode({ start = saved_start, last_seen = os.time() - 20 }) },
			directory .. "/discord-session.json"
		)
		local stdpath, system, jobpid, now = vim.fn.stdpath, vim.system, vim.fn.jobpid, os.time
		local original = vim.api.nvim_get_current_buf()
		local terminal = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_open_term(terminal, {})
		vim.b[terminal].terminal_job_id = 12345
		local updates, checks = 0, 0
		vim.fn.stdpath = function(kind)
			return kind == "state" and directory or stdpath(kind)
		end
		vim.fn.jobpid = function()
			return 10
		end
		vim.system = function(_, _, callback)
			checks = checks + 1
			local output = vim.fn.has("win32") == 1
					and vim.json.encode({
						{ ProcessId = 10, ParentProcessId = 1, Name = "powershell.exe" },
						{ ProcessId = 11, ParentProcessId = 10, Name = "codex.exe" },
					})
				or "10 1 bash bash\n11 10 codex codex"
			callback({ code = 0, stdout = output })
		end
		package.loaded["fox.discord"] = nil
		local feature = require("fox.discord")
		local ok, err = pcall(function()
			vim.api.nvim_set_current_buf(terminal)
			feature.setup()
			feature.ready({
				queue_update = function()
					updates = updates + 1
				end,
			})
			assert(vim.wait(1000, function()
				return updates > 0
			end))
			t.expect(checks).toBe(1)
			local message = feature.terminal_text()
			t.expect(message == "Running commands in nvim terminal").toBe(false)
			rawset(os, "time", function()
				return now() + 15
			end)
			t.expect(feature.terminal_text() == message).toBe(false)
			rawset(os, "time", now)
			vim.api.nvim_set_current_buf(original)
			t.expect(feature.terminal_text()).toBe("Running commands in nvim terminal")
			vim.api.nvim_set_current_buf(terminal)
			t.expect(feature.terminal_text()).toBe(message)
			local activity = { assets = { large_image = "terminal", small_image = "neovim" } }
			feature.post_activity({}, activity)
			t.expect(activity.timestamps.start).toBe(saved_start)
			local icon = activity.assets.large_image
			local filename = icon:match(
				"^https://raw%.githubusercontent%.com/KristanLaimon/nvim%-config/main/config/discord%-theme%-icons/minecraft/fox%-custom/(fox%-[^/]+%.png)$"
			)
			assert(filename, "fox icon must use the public repository's raw URL")
			assert(
				vim.fn.filereadable(stdpath("config") .. "/config/discord-theme-icons/minecraft/fox-custom/" .. filename) == 1
			)
			t.expect(activity.assets.small_image).toBe("neovim")
			local repeated = { assets = { large_image = "terminal" } }
			feature.post_activity({}, repeated)
			t.expect(repeated.assets.large_image).toBe(icon)
			for tick = 1, 32 do
				rawset(os, "time", function()
					return now() + 15 * tick
				end)
				local rotated = { assets = { large_image = "terminal" } }
				feature.post_activity({}, rotated)
				assert(rotated.assets.large_image ~= icon, "consecutive fox icons must differ")
				icon = rotated.assets.large_image
			end
			local idle = { assets = { large_image = "idle" } }
			feature.post_activity({ is_idle = true }, idle)
			t.expect(idle.assets.large_image).toBe("idle")
			vim.api.nvim_set_current_buf(original)
			local editing = { assets = { large_image = "lua" } }
			feature.post_activity({}, editing)
			t.expect(editing.assets.large_image).toBe("lua")
			vim.api.nvim_set_current_buf(terminal)
			vim.b[terminal].terminal_job_id = 54321
			local shell = { assets = { large_image = "terminal" } }
			feature.post_activity({}, shell)
			t.expect(shell.assets.large_image).toBe("terminal")
			vim.b[terminal].terminal_job_id = 12345
			rawset(os, "time", function()
				return now() + 15
			end)
			local next_activity = {}
			feature.post_activity({}, next_activity)
			t.expect(next_activity.timestamps.start).toBe(activity.timestamps.start)
		end)
		rawset(os, "time", now)
		vim.api.nvim_exec_autocmds("VimLeavePre", { group = "FoxDiscord" })
		feature.stop()
		vim.fn.stdpath, vim.system, vim.fn.jobpid = stdpath, system, jobpid
		package.loaded["fox.discord"] = discord
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(terminal, { force = true })
		local saved = vim.json.decode(table.concat(vim.fn.readfile(directory .. "/discord-session.json")))
		vim.fn.delete(directory, "rf")
		if not ok then
			error(err)
		end
		t.expect(saved.start).toBe(saved_start)
	end)
end)
