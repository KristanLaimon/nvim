local t = require("fox.lib.foxnvim.test")
local background = require("fox.agentic.background")
local agentic = require("fox.agentic")

t.describe("Agentic automatic background tracking", function()
	t.it("persists a blank session before handing its ID to the terminal launcher", function()
		local provider = require("fox.agentic.providers.codex")
		local methods, result = {}, nil
		provider.create_session(
			{
				request = function(method, params, callback)
					methods[#methods + 1] = method
					if method == "thread/start" then
						callback({ thread = { id = "fixture-id", cwd = "/project" } })
					else
						assert(params.threadId == "fixture-id" and params.name == "Codex / project")
						callback({})
					end
				end,
			},
			"/project",
			function(session)
				result = session
			end
		)
		assert(result.id == "fixture-id" and #methods == 2 and methods[2] == "thread/name/set")
		local failed
		provider.create_session(
			{
				request = function(method, _, callback)
					if method == "thread/start" then
						callback({ thread = { id = "fixture-id" } })
					else
						callback(nil, "persist failed")
					end
				end,
			},
			"/project",
			function(session, err)
				assert(session == nil)
				failed = err
			end
		)
		assert(failed == "persist failed")
	end)

	t.it("registers the real launcher bridge over local Neovim RPC without opening a view", function()
		local old_connect = agentic.connect
		local terminal_buf = vim.api.nvim_create_buf(false, true)
		local server = vim.fn.serverstart()
		vim.b[terminal_buf].terminal_job_id = 54321
		background.register("rpc-token", { buf = terminal_buf, slot = 1, job = 54321, root = vim.fn.getcwd() })
		local ok, err = pcall(function()
			agentic.connect = function(state)
				state.connection = { closed = false, detach = function() end }
			end
			local result
			local process = vim.system({
				vim.v.progpath,
				"--headless",
				"-u",
				"NONE",
				"-i",
				"NONE",
				"-n",
				"-l",
				vim.fn.getcwd() .. "/config/tools/foxagentic/bridge.lua",
				"attach",
				"rpc-fixture",
			}, { env = { FOX_AGENTIC_SERVER = server, FOX_AGENTIC_TOKEN = "rpc-token" }, text = true }, function(completed)
				result = completed
			end)
			if not vim.wait(10000, function()
				return result ~= nil
			end, 10) then
				process:kill(15)
				error("Launcher RPC timed out")
			end
			assert(result.code == 0, result.stderr)
			assert(agentic.states[terminal_buf].session.id == "rpc-fixture" and not agentic.active())
		end)
		local state = agentic.states[terminal_buf]
		if state then
			agentic.detach(state)
			if state.timer then
				state.timer:stop()
				state.timer:close()
			end
			agentic.states[terminal_buf] = nil
		end
		vim.api.nvim_buf_delete(terminal_buf, { force = true })
		vim.fn.serverstop(server)
		agentic.connect = old_connect
		background.dispose()
		assert(ok, err)
	end)

	t.it("binds two terminal jobs without opening or focusing the dashboard", function()
		local old_connect = agentic.connect
		local buffers = { vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true) }
		local tab, win, buf =
			vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
		local connections = 0
		local ok, err = pcall(function()
			agentic.connect = function(state)
				connections = connections + 1
				state.connection = { closed = false, detach = function() end }
				require("fox.agentic.state").reduce(state, {
					kind = "file",
					action = "read",
					id = "read",
					path = "/project/" .. state.session.id .. ".lua",
				})
			end
			for index, terminal_buf in ipairs(buffers) do
				vim.b[terminal_buf].terminal_job_id = index + 100
				background.register(
					"token-" .. index,
					{ buf = terminal_buf, slot = index, job = index + 100, root = "/project" }
				)
				assert(background.accept("token-" .. index, "session-" .. index, "/project", false))
			end
			assert(connections == 2 and not agentic.active())
			assert(
				vim.api.nvim_get_current_tabpage() == tab
					and vim.api.nvim_get_current_win() == win
					and vim.api.nvim_get_current_buf() == buf
			)
			assert(
				agentic.states[buffers[1]].session.id == "session-1" and agentic.states[buffers[2]].session.id == "session-2"
			)
			assert(#agentic.states[buffers[1]].order == 1 and #agentic.states[buffers[2]].order == 1)
			assert(background.accept("token-1", "session-1", "/project", false) and connections == 2)
			assert(not background.accept("unknown", "session-1", "/project", false))
			assert(background.accept("token-1", "session-1", "/project", true))
			assert(agentic.states[buffers[1]].finished and not agentic.states[buffers[2]].finished)
			vim.b[buffers[2]].terminal_job_id = 999
			assert(not background.accept("token-2", "wrong-session", "/project", false))
		end)
		for _, terminal_buf in ipairs(buffers) do
			local state = agentic.states[terminal_buf]
			if state then
				agentic.detach(state)
				if state.timer then
					state.timer:stop()
					state.timer:close()
				end
				agentic.states[terminal_buf] = nil
			end
			vim.api.nvim_buf_delete(terminal_buf, { force = true })
		end
		agentic.connect = old_connect
		background.dispose()
		assert(ok, err)
	end)

	t.it("shows workspace cards when Codex has not reported attributable file operations", function()
		local old_git = agentic.refresh_git
		local terminal_buf = vim.api.nvim_create_buf(false, true)
		local state = require("fox.agentic.state").new({ id = "fixture", cwd = vim.fn.getcwd() })
		state.root, state.terminal, state.slot = vim.fn.getcwd(), terminal_buf, 1
		state.connection = { closed = false, ready = true, detach = function() end }
		state.changes = { { file = "changed-file.lua", status = " M", type = "unstaged" } }
		agentic.states[terminal_buf] = state
		local ok, err = pcall(function()
			agentic.refresh_git = function() end
			agentic.show(state)
			local content = table.concat(vim.api.nvim_buf_get_lines(state.bufs[1], 0, -1, false), "\n")
			assert(content:find("changed-file.lua", 1, true))
			assert(content:find("agent attribution unavailable", 1, true))
			assert(#state.order == 0 and next(state.files) == nil)
		end)
		agentic.hide(state)
		agentic.detach(state)
		agentic.states[terminal_buf] = nil
		vim.api.nvim_buf_delete(terminal_buf, { force = true })
		agentic.refresh_git = old_git
		assert(ok, err)
	end)

	for _, shell in ipairs({ "bash", "powershell.exe" }) do
		if vim.fn.executable(shell) == 1 then
			t.it("preserves arguments, exit status and terminal token isolation through " .. shell, function()
				local root = vim.fn.tempname() .. " launch fixture"
				vim.fn.mkdir(root, "p")
				local bridge = root .. "/bridge.lua"
				local log = root .. "/bridge.log"
				vim.fn.writefile({
					"vim.fn.writefile({arg[1]}, vim.env.FOX_TEST_LOG, 'a')",
					"if arg[1] == 'create' then if vim.env.FOX_TEST_FAIL == '1' then os.exit(1) end; io.stdout:write('fixture-session\\n') end",
					"os.exit(0)",
				}, bridge)
				local powershell = shell == "powershell.exe"
				local fake = root .. (powershell and "/real-codex.ps1" or "/real-codex.sh")
				vim.fn.writefile(powershell and {
					"foreach ($item in $args) { [Console]::Out.WriteLine($item) }",
					"if ($env:FOX_AGENTIC_TOKEN) { [Console]::Out.WriteLine('TOKEN_LEAK') }",
					"exit 7",
				} or {
					"#!/bin/sh",
					"for item do printf '%s\\n' \"$item\"; done",
					'[ -z "$FOX_AGENTIC_TOKEN" ] || echo TOKEN_LEAK',
					"exit 7",
				}, fake)
				vim.uv.fs_chmod(fake, 493)
				local env = {
					FOX_AGENTIC_NVIM = vim.v.progpath:gsub("\\", "/"),
					FOX_AGENTIC_BRIDGE = bridge:gsub("\\", "/"),
					FOX_AGENTIC_REAL_CODEX = fake:gsub("\\", "/"),
					FOX_AGENTIC_SERVER = "fixture",
					FOX_AGENTIC_TOKEN = "private",
					FOX_TEST_LOG = log,
					FOX_TEST_FAIL = "0",
				}
				local wrapper = vim.fn.getcwd() .. "/config/tools/foxagentic/" .. (powershell and "codex.ps1" or "codex.sh")
				local command = powershell and { shell, "-NoProfile", "-File", wrapper } or { shell, wrapper }
				local ok, err = pcall(function()
					if vim.fn.executable("codex") == 1 then
						local original_shell, original_path = vim.o.shell, vim.env.PATH
						vim.o.shell = vim.fn.exepath(shell)
						local prepared_ok, prepared = pcall(background.prepare)
						vim.o.shell = original_shell
						assert(prepared_ok and prepared, "Terminal launcher environment was not prepared")
						assert(vim.env.PATH == original_path, "Preparing a terminal changed the editor's PATH")
						local lookup = powershell and { shell, "-NoProfile", "-Command", "(Get-Command codex).Path" }
							or { shell, "--noprofile", "--norc", "-c", "command -v codex" }
						local found = vim.system(lookup, { env = prepared, text = true }):wait(10000)
						assert(found.code == 0, found.stderr)
						local resolved = found.stdout:gsub("\\", "/")
						assert(
							powershell and resolved:find("/foxagentic/codex.ps1", 1, true)
								or not powershell and resolved:find("-fox-agentic/codex", 1, true),
							"Wrong codex resolution: " .. resolved
						)
						background.dispose()
					end
					local result = vim.system(command, { env = env, text = true }):wait(15000)
					assert(result.code == 7, (result.stderr or "") .. " status=" .. tostring(result.code))
					assert(result.stdout == "resume\nfixture-session\n", result.stdout)
					assert(table.concat(vim.fn.readfile(log), ",") == "create,finish")
					vim.fn.writefile({}, log)
					local passthrough = vim.deepcopy(command)
					vim.list_extend(passthrough, { "--help", "two words" })
					result = vim.system(passthrough, { env = env, text = true }):wait(15000)
					assert(result.code == 7 and result.stdout == "--help\ntwo words\n", result.stdout)
					assert(#vim.fn.readfile(log) == 0)
					env.FOX_TEST_FAIL = "1"
					result = vim.system(command, { env = env, text = true }):wait(15000)
					assert(result.code == 7 and result.stdout == "", result.stdout)
				end)
				vim.fn.delete(root, "rf")
				assert(ok, err)
			end)
		end
	end
end)
