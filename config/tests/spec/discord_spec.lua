local t = require("fox.lib.foxnvim.test")
local discord = require("fox.discord")

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
			local activity = {}
			feature.post_activity({}, activity)
			t.expect(activity.timestamps.start).toBe(saved_start)
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
