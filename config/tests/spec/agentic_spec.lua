local t = require("fox.lib.foxnvim.test")
local state = require("fox.agentic.state")
local codex = require("fox.agentic.providers.codex")

t.describe("Agentic Codex observation", function()
	t.it("counts repeated reads once per operation despite replay, without inventing tokens", function()
		local observed = state.new({ id = "one", cwd = "/project" })
		local item = {
			id = "read1",
			type = "commandExecution",
			status = "completed",
			exitCode = 0,
			cwd = "/project",
			commandActions = { { type = "read", path = "AGENTS.md" } },
		}
		local event = codex.item_events(item, "/project", "turn")[1]
		state.reduce(observed, event)
		state.reduce(observed, event)
		item.id = "read2"
		state.reduce(observed, codex.item_events(item, "/project", "turn")[1])
		local file = observed.files[observed.order[1]]
		assert(file.reads == 2 and file.context and file.writes == 0)
		assert(observed.usage == nil and file.tokens == nil)
		item.exitCode = 1
		assert(#codex.item_events(item, "/project", "turn") == 0)
		item.exitCode, item.status = 0, "inProgress"
		assert(#codex.item_events(item, "/project", "turn") == 0)
	end)

	t.it("does not classify listings/searches as reads or pending patches as applied", function()
		local item = {
			id = "cmd",
			type = "commandExecution",
			status = "completed",
			exitCode = 0,
			commandActions = { { type = "listFiles", path = "src" }, { type = "search", path = "src" } },
		}
		assert(#codex.item_events(item, "/project") == 0)
		local patch = {
			id = "patch",
			type = "fileChange",
			status = "inProgress",
			changes = { { path = "src/a.lua", kind = { type = "update" }, diff = "--- a\n+++ b\n-old\n+new\n+more" } },
		}
		assert(#codex.item_events(patch, "/project") == 0)
		patch.status = "completed"
		local event = codex.item_events(patch, "/project")[1]
		assert(event.added == 2 and event.removed == 1 and event.path == "/project/src/a.lua")
	end)

	t.it("replaces absolute usage snapshots and keeps session state isolated", function()
		local one, two = state.new({ id = "one" }), state.new({ id = "two" })
		state.reduce(one, { kind = "usage", usage = { total = { totalTokens = 100 } } })
		state.reduce(one, { kind = "usage", usage = { total = { totalTokens = 120 } } })
		assert(one.usage.total.totalTokens == 120 and two.usage == nil)
	end)

	t.it("reads reported transcript usage without summing cache and reasoning twice", function()
		local usage, model, mode = codex.telemetry(table.concat({
			'{"type":"turn_context","payload":{"model":"fixture-model","collaboration_mode":{"mode":"plan"}}}',
			'{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":30,"output_tokens":20,"reasoning_output_tokens":10,"total_tokens":100},"last_token_usage":{"total_tokens":40},"model_context_window":200}}}',
			'{"type":"event_msg","payload":',
		}, "\n"))
		assert(
			model == "fixture-model"
				and mode == "plan"
				and usage.total.totalTokens == 100
				and usage.total.cachedInputTokens == 30
		)
		assert(usage.last.totalTokens == 40 and usage.modelContextWindow == 200)
		local item = {
			id = "one",
			type = "commandExecution",
			status = "completed",
			exitCode = 0,
			commandActions = { { type = "read", path = "a.lua" } },
			aggregatedOutput = "12345678",
		}
		assert(codex.item_events(item, "/project")[1].estimated_tokens == 2)
		item.commandActions[2] = { type = "read", path = "b.lua" }
		assert(codex.item_events(item, "/project")[1].estimated_tokens == nil)
	end)

	t.it("frames partial JSONL messages and never answers approval requests", function()
		local callbacks, sent, stopped, ready, notifications
		sent, stopped, notifications = {}, 0, 0
		local connection = codex.connect(function()
			ready = true
		end, function()
			notifications = notifications + 1
		end, function() end, {
			spawn = function(_, options)
				callbacks = options
				return 42
			end,
			send = function(_, data)
				sent[#sent + 1] = vim.json.decode(data)
			end,
			stop = function()
				stopped = stopped + 1
			end,
		})
		assert(sent[1].method == "initialize")
		callbacks.on_stdout(42, { '{"id":1,"res', 'ult":{}}', "" })
		-- A newline in the middle makes invalid JSON; it must not trigger a callback.
		assert(not ready)
		callbacks.on_stdout(42, { '{"id":1,"res' })
		callbacks.on_stdout(42, { 'ult":{}}', "" })
		assert(ready and sent[2].method == "initialized")
		callbacks.on_stdout(42, { '{"id":99,"method":"item/fileChange/requestApproval","params":{}}', "" })
		assert(#sent == 2 and notifications == 0)
		connection.detach()
		connection.detach()
		assert(stopped == 1)
	end)

	t.it("attaches through read APIs only and stops polling after detach", function()
		local methods, emitted = {}, {}
		local connection = {
			request = function(method, _, callback)
				methods[#methods + 1] = method
				if method == "thread/read" then
					callback({ thread = { id = "one", cwd = "/project", status = { type = "idle" } } })
				else
					callback({
						data = {
							{
								id = "turn",
								items = {
									{
										id = "read",
										type = "commandExecution",
										status = "completed",
										exitCode = 0,
										commandActions = { { type = "read", path = "a.lua" } },
									},
								},
							},
						},
					})
				end
			end,
		}
		local subscription = codex.attach(connection, { id = "one", cwd = "/project" }, function(event)
			emitted[#emitted + 1] = event
		end, function() end)
		subscription.detach()
		subscription.refresh()
		assert(#methods == 2 and methods[1] == "thread/read" and methods[2] == "thread/turns/list")
		assert(emitted[2].action == "read")
	end)
end)

t.describe("Agentic terminal ownership and navigation", function()
	t.it("resolves the focused terminal before the globally selected slot", function()
		local terminal = require("plugins.fox.dev.terminal")
		local original, selected = vim.api.nvim_get_current_buf(), _G._fox_selected_terminal
		local buffer = vim.api.nvim_create_buf(false, true)
		local saved = _G._fox_terminals[8]
		local ok, err = pcall(function()
			vim.b[buffer].fox_term_num = 8
			vim.b[buffer].fox_env_slot = _G._fox_active_env_slot or 1
			vim.b[buffer].fox_is_multi_term = true
			vim.b[buffer].fox_agentic_session = "terminal-eight"
			vim.b[buffer].fox_term_root = vim.fn.getcwd()
			vim.api.nvim_set_current_buf(buffer)
			_G._fox_selected_terminal = 9
			local context = terminal.agentic_context()
			assert(context.buf == buffer and context.slot == 8 and context.session == "terminal-eight")
		end)
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(buffer, { force = true })
		_G._fox_terminals[8], _G._fox_selected_terminal = saved, selected
		assert(ok, err)
	end)

	t.it("selects terminal one's and terminal two's own sessions and restores editor focus", function()
		local agentic = require("fox.agentic")
		local terminal = require("plugins.fox.dev.terminal")
		local old_context, old_hide, old_connect = terminal.agentic_context, terminal.hide_terminal, agentic.connect
		local old_refresh_git = agentic.refresh_git
		local editor, win, selected = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), 1
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local buffers = { vim.api.nvim_create_buf(false, true), vim.api.nvim_create_buf(false, true) }
		local old_columns = vim.o.columns
		local ok, err = pcall(function()
			agentic.refresh_git = function() end
			terminal.agentic_context = function()
				return { buf = buffers[selected], slot = selected, session = "session-" .. selected, root = root }
			end
			terminal.hide_terminal = function() end
			agentic.connect = function(observed)
				observed.connection = { closed = false, ready = true, detach = function() end }
			end
			for _, width in ipairs({ 80, 160 }) do
				vim.o.columns = width
				selected = 1
				agentic.toggle()
				assert(agentic.active() and agentic.state().session.id == "session-1")
				local restore = agentic.suspend()
				assert(not agentic.active())
				restore()
				assert(agentic.active())
				for _, buf in ipairs(agentic.state().bufs) do
					assert(vim.api.nvim_buf_is_valid(buf))
				end
				if width == 80 then
					vim.fn.maparg("<Tab>", "n", false, true).callback()
					assert(vim.api.nvim_get_current_buf() == agentic.state().bufs[2])
				end
				agentic.toggle()
				assert(vim.api.nvim_get_current_buf() == editor and vim.api.nvim_get_current_win() == win)
				selected = 2
				agentic.toggle()
				assert(agentic.state().session.id == "session-2")
				agentic.toggle()
			end
		end)
		agentic.hide()
		for _, buf in ipairs(buffers) do
			local observed = agentic.states[buf]
			if observed then
				agentic.detach(observed)
				if observed.timer then
					observed.timer:stop()
					observed.timer:close()
					observed.timer = nil
				end
				agentic.states[buf] = nil
			end
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.wait(100, function()
			return false
		end, 10)
		terminal.agentic_context, terminal.hide_terminal, agentic.connect = old_context, old_hide, old_connect
		agentic.refresh_git = old_refresh_git
		vim.o.columns = old_columns
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)

	t.it("inspects a read file without overwriting unsaved editor text and returns to the card", function()
		local agentic = require("fox.agentic")
		local terminal = require("plugins.fox.dev.terminal")
		local original_tab = vim.api.nvim_get_current_tabpage()
		local old_hide, old_git = terminal.hide_terminal, agentic.refresh_git
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		local filename = root .. "/context.md"
		vim.fn.writefile({ "Context fixture" }, filename)
		vim.cmd("tabnew")
		local editor_tab, editor = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
		local terminal_buf = vim.api.nvim_create_buf(false, true)
		local observed = state.new({ id = "inspection", cwd = root })
		observed.root, observed.terminal, observed.slot = root, terminal_buf, 1
		observed.connection = { ready = true, closed = false, detach = function() end }
		agentic.states[terminal_buf] = observed
		local ok, err = pcall(function()
			terminal.hide_terminal, agentic.refresh_git = function() end, function() end
			vim.api.nvim_buf_set_lines(editor, 0, -1, false, { "unsaved editor work" })
			state.reduce(observed, { kind = "file", action = "read", id = "read", path = filename })
			agentic.show(observed)
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			agentic.open_file(1)
			assert(agentic.subeditor_active())
			assert(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "Context fixture")
			assert(vim.bo[editor].modified and vim.api.nvim_buf_get_lines(editor, 0, 1, false)[1] == "unsaved editor work")
			agentic.toggle()
			assert(agentic.active() and agentic.state().rows[1][1].path == require("fox.core.path").normalize(filename))
		end)
		agentic.hide(observed)
		agentic.detach(observed)
		if observed.timer then
			observed.timer:stop()
			observed.timer:close()
			observed.timer = nil
		end
		agentic.states[terminal_buf] = nil
		if vim.api.nvim_tabpage_is_valid(editor_tab) then
			vim.api.nvim_set_current_tabpage(editor_tab)
			vim.cmd("tabclose!")
		end
		vim.api.nvim_set_current_tabpage(original_tab)
		for _, buf in ipairs({ editor, terminal_buf, vim.fn.bufnr(filename) }) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		terminal.hide_terminal, agentic.refresh_git = old_hide, old_git
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
