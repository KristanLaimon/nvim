local t = require("fox.lib.foxnvim.test")

t.describe("agent terminal restoration", function()
	t.it.os("linux", "registers Codex on first use and resumes the same session in slot 1 after a restart", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory .. "/bin", "p")
		vim.fn.mkdir(directory .. "/project", "p")
		vim.fn.mkdir(directory .. "/codex", "p")
		local codex_config = directory .. "/codex/config.toml"
		vim.fn.writefile({ "features = { hooks = true }" }, codex_config)
		local codex = directory .. "/bin/codex"
		vim.fn.writefile({ "#!/bin/sh", [[printf '%s\n' "$@" > "$FOX_TEST_RESUME"]], "exec sleep 30" }, codex)
		assert(vim.uv.fs_chmod(codex, 448))

		local channel
		local function lua(code)
			return vim.rpcrequest(channel, "nvim_exec_lua", code, {})
		end
		local function start()
			channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, {
				rpc = true,
				cwd = directory .. "/project",
				env = {
					PATH = directory .. "/bin:/usr/bin:/bin",
					XDG_STATE_HOME = directory .. "/state",
					XDG_DATA_HOME = directory .. "/data",
					CODEX_HOME = directory .. "/codex",
					CODEX_THREAD_ID = "test-session",
					FOX_TEST_RESUME = directory .. "/resume",
					FOX_TEST_CONFIG = vim.fn.stdpath("config"),
				},
			})
			assert(channel > 0)
			vim.rpcrequest(channel, "nvim_ui_attach", 80, 24, {})
			lua([[
				vim.opt.rtp:prepend(vim.env.FOX_TEST_CONFIG)
				vim.env.SHELL, vim.env.ENV = nil, nil
				vim.o.shell = "/bin/sh"
				require("plugins.fox.dev.terminal").setup()
			]])
		end
		local function stop()
			if channel then
				pcall(vim.rpcrequest, channel, "nvim_command", "qa!")
				assert(vim.fn.jobwait({ channel }, 3000)[1] ~= -1, "Neovim did not exit")
				channel = nil
			end
		end

		local ok, err = xpcall(function()
			start()
			lua([[
				require("plugins.fox.dev.terminal").open_terminal(1, false)
				local hook_file = vim.env.CODEX_HOME .. "/hooks.json"
				local hook = vim.json.decode(table.concat(vim.fn.readfile(hook_file), "\n")).hooks.SessionStart[1].hooks[1]
				local payload = vim.json.encode({ hook_event_name = "SessionStart", session_id = "test-session" })
				vim.api.nvim_chan_send(vim.bo.channel, "printf '%s\\n' " .. vim.fn.shellescape(payload) .. " | " .. hook.command .. "\n")
				local sessions = require("fox.terminal.agent_sessions")
				assert(vim.wait(3000, function()
					return vim.deep_equal(sessions.load(vim.fn.getcwd()), { { slot = 1, agent = "codex", id = "test-session" } })
				end), "Codex session was not recorded")
			]])
			t.expect(vim.fn.readfile(codex_config)).toEqual({ "features = { hooks = true }" })
			stop()
			start()
			assert(
				vim.wait(3000, function()
					return (vim.uv.fs_stat(directory .. "/resume") or { size = 0 }).size > 0
				end),
				"Codex was not resumed"
			)
			t.expect(vim.fn.readfile(directory .. "/resume")).toEqual({ "resume", "test-session" })
			t.expect(lua([[
				local restored = assert(_G._fox_terminals[1].buf)
				require("plugins.fox.dev.terminal").open_terminal(1, false)
				return vim.api.nvim_get_current_buf() == restored and vim.b[restored].fox_term_num == 1
			]])).toBe(true)
		end, debug.traceback)
		stop()
		vim.fn.delete(directory, "rf")
		assert(ok, err)
	end)
end)
