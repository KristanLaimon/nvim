local M = { states = {} }
local reducer = require("fox.agentic.state")
local path = require("fox.core.path")
local provider = require("fox.agentic.providers.codex")
local current
local highlights = vim.api.nvim_create_namespace("fox_agentic")

local function valid(id, kind)
	return type(id) == "number" and vim.api["nvim_" .. (kind == "tab" and "tabpage" or kind) .. "_is_valid"](id)
end

local function text(value)
	return tostring(value or "Unavailable"):gsub("[%z\1-\31\127]", " ")
end

local function lines(buf, content)
	if valid(buf, "buf") then
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
		vim.bo[buf].modifiable = false
	end
end

local function label(state, filename)
	local root = path.normalize(state.session.cwd or state.root):gsub("/$", "")
	return filename:sub(1, #root + 1) == root .. "/" and filename:sub(#root + 2) or filename
end

function M.active()
	local tab = vim.api.nvim_get_current_tabpage()
	for _, state in pairs(M.states) do
		if state.tab == tab then
			current = state
			return true
		end
	end
	return false
end

function M.state()
	return current
end

function M.subeditor_active()
	return current
			and current.excursion
			and valid(current.editor_tab, "tab")
			and current.editor_tab == vim.api.nvim_get_current_tabpage()
			and not vim.b.fox_term_num
		or false
end

function M.focus_panel(index)
	local state = current
	if not state or not valid(state.wins[index], "win") then
		return
	end
	local win = state.wins[index]
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_buf(win, state.bufs[index])
	vim.wo[win].winbar = state.titles[index] .. " | F2 Editor | F1 Help"
end

function M.render(state)
	if not valid(state.tab, "tab") then
		return
	end
	local cards, contexts, changed = {}, {}, {}
	local estimated_total, estimated_files, read_total = 0, 0, 0
	local selections = {}
	for index, win in ipairs(state.wins) do
		if valid(win, "win") and vim.api.nvim_win_get_buf(win) == state.bufs[index] and state.rows then
			local row = vim.api.nvim_win_get_cursor(win)[1]
			selections[index] = state.rows[index] and state.rows[index][row] and state.rows[index][row].path
		end
	end
	state.rows = { {}, {}, {} }
	local display_files, known = {}, {}
	local windows = vim.fn.has("win32") == 1
	for _, key in ipairs(state.order) do
		local file = state.files[key]
		display_files[#display_files + 1] = file
		known[windows and file.path:lower() or file.path] = true
	end
	for _, change in ipairs(state.changes or {}) do
		local filename = path.normalize(state.root .. "/" .. change.file)
		if not known[windows and filename:lower() or filename] then
			display_files[#display_files + 1] =
				{ path = filename, reads = 0, writes = 0, added = 0, removed = 0, workspace = change.status }
		end
	end
	for _, file in ipairs(display_files) do
		local title = label(state, file.path)
		local row = #cards + 1
		local estimate = file.estimated_tokens and ("~" .. file.estimated_tokens .. " output tokens")
			or "tokens unavailable"
		estimated_total = estimated_total + (file.estimated_tokens or 0)
		if file.estimated_tokens then
			estimated_files = estimated_files + 1
		end
		read_total = read_total + file.reads
		cards[#cards + 1] = "+-- " .. text(title)
		cards[#cards + 1] = file.workspace and "| Workspace change; agent attribution unavailable"
			or "| Reads x" .. file.reads .. "  Edits x" .. file.writes
		cards[#cards + 1] = file.workspace and ("| Git status: " .. text(file.workspace))
			or "| Observed patch lines +" .. file.added .. " -" .. file.removed .. " | " .. estimate
		cards[#cards + 1] = "+----------------------"
		cards[#cards + 1] = ""
		for index = row, #cards do
			state.rows[1][index] = file
		end
		if file.reads > 0 then
			contexts[#contexts + 1] = (file.context and "[Context] " or "[Read] ") .. text(title)
			state.rows[2][#contexts] = file
			contexts[#contexts + 1] = "  x" .. file.reads .. " | " .. estimate
			state.rows[2][#contexts] = file
		end
	end
	contexts[#contexts + 1] = ""
	contexts[#contexts + 1] = "Reads: "
		.. read_total
		.. " | "
		.. (estimated_files > 0 and ("~" .. estimated_total .. " estimated output tokens") or "tokens unavailable")
	contexts[#contexts + 1] = "Estimate: returned characters / 4."
	contexts[#contexts + 1] = "Formatting included; billing excluded."
	for _, change in ipairs(state.changes or {}) do
		changed[#changed + 1] = text(change.status) .. " " .. text(change.file)
		state.rows[3][#changed] = { path = state.root .. "/" .. change.file, changed = true, target_type = change.type }
	end
	if #cards == 0 then
		cards = {
			"Agentic / Codex",
			"",
			state.session.id and "No file operations reported for this session yet." or "No Codex session attached.",
			"",
			state.scan and ("History: " .. state.scan.turns .. " turns / " .. state.scan.items .. " items scanned")
				or "Waiting for session history.",
			"Press s to choose this terminal's Codex session.",
			"F1: help | F2: Editor | F3: Query",
		}
	end
	if #contexts == 0 then
		contexts = { "No reported reads.", "", "Read classification is best effort.", "Skill activation: unavailable." }
	end
	if #changed == 0 then
		changed = { state.git_error or "No current Git changes." }
	end
	vim.list_extend(changed, {
		"",
		"Session: " .. text(state.session.name or state.session.id),
		"Session ID: " .. text(state.session.id),
		"Terminal: " .. state.slot,
		"Root: " .. text(state.root),
		"Model: " .. text(state.session.model),
		"Mode: " .. text(state.session.mode),
	})
	local usage = state.usage
	if type(usage) == "table" and type(usage.total) == "table" then
		changed[#changed + 1] = "Reported total: " .. text(usage.total.totalTokens)
		changed[#changed + 1] = "Input: "
			.. text(usage.total.inputTokens)
			.. " / Output: "
			.. text(usage.total.outputTokens)
		changed[#changed + 1] = "Cached input: " .. text(usage.total.cachedInputTokens)
		local capacity = usage.modelContextWindow
		local occupied = type(usage.last) == "table" and usage.last.totalTokens
		changed[#changed + 1] = type(capacity) == "number"
				and capacity > 0
				and type(occupied) == "number"
				and string.format("Last request / context: %d / %d", occupied, capacity)
			or "Context: unavailable"
	else
		changed[#changed + 1] = "Reported usage: unavailable"
		changed[#changed + 1] = "Context: unavailable"
	end
	changed[#changed + 1] = "Reads are not billable totals."
	changed[#changed + 1] = "Workspace changes include human edits."
	changed[#changed + 1] = text(state.status)
	changed[#changed + 1] = "Updated: " .. (state.updated and os.date("%H:%M:%S", state.updated) or "never")
	for index, content in ipairs({ cards, contexts, changed }) do
		local win = state.wins[index]
		local view = valid(win, "win")
			and vim.api.nvim_win_get_buf(win) == state.bufs[index]
			and vim.api.nvim_win_call(win, vim.fn.winsaveview)
		lines(state.bufs[index], content)
		vim.api.nvim_buf_clear_namespace(state.bufs[index], highlights, 0, -1)
		for row, file in pairs(state.rows[index]) do
			if file.reads and file.reads > 1 then
				vim.api.nvim_buf_set_extmark(state.bufs[index], highlights, row - 1, 0, { line_hl_group = "DiagnosticOk" })
			end
		end
		if view then
			view.lnum = math.min(view.lnum, #content)
			local selected = selections[index]
			if selected and (not state.rows[index][view.lnum] or state.rows[index][view.lnum].path ~= selected) then
				for row, file in ipairs(state.rows[index]) do
					if file.path == selected then
						view.lnum = row
						break
					end
				end
			end
			vim.api.nvim_win_call(win, function()
				vim.fn.winrestview(view)
			end)
		end
	end
end

function M.queue_render(state)
	if state.render_pending then
		return
	end
	state.render_pending = true
	vim.defer_fn(function()
		state.render_pending = false
		M.render(state)
	end, 50)
end

function M.refresh_git(state)
	state = state or current
	if not state or state.git_busy then
		return
	end
	if vim.fn.executable("git") ~= 1 or vim.fn.isdirectory(state.root) ~= 1 then
		state.changes, state.git_error = {}, "Git executable or project directory is unavailable."
		M.render(state)
		return
	end
	state.git_busy = true
	local root = state.root
	vim.system(
		{ "git", "-c", "core.quotepath=false", "status", "--porcelain=v1", "-z", "--untracked-files=normal" },
		{
			cwd = state.root,
		},
		vim.schedule_wrap(function(result)
			state.git_busy = false
			if state.root ~= root then
				return
			end
			state.changes = {}
			state.git_error = result.code ~= 0 and "Git unavailable in this folder." or nil
			if result.code == 0 then
				local records = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
				local index = 1
				while index <= #records do
					local record = records[index]
					local status, filename = record:sub(1, 2), record:sub(4)
					local target_type = status == "??" and "untracked" or status:sub(2, 2) ~= " " and "unstaged" or "staged"
					state.changes[#state.changes + 1] = { file = filename, status = status, type = target_type }
					index = index + (status:find("[RC]") and 2 or 1)
				end
			end
			M.render(state)
		end)
	)
end

function M.bind(session, state)
	state = state or current
	if not state or type(session) ~= "table" or type(session.id) ~= "string" or session.id == "" then
		return
	end
	if state.subscription then
		state.subscription.detach()
	end
	local fresh = reducer.new(session)
	for _, key in ipairs({ "files", "order", "seen", "status", "session" }) do
		state[key] = fresh[key]
	end
	state.usage = nil
	if valid(state.terminal, "buf") then
		vim.b[state.terminal].fox_agentic_session = session.id
	end
	state.subscription = provider.attach(state.connection, session, function(event)
		reducer.reduce(state, event)
		if event.kind == "session" and type(event.session.cwd) == "string" then
			local root = path.normalize(event.session.cwd)
			if root ~= state.root then
				state.changes = {}
				state.root = root
			end
		end
		M.queue_render(state)
	end, function(status)
		reducer.reduce(state, { kind = "status", status = status })
		M.render(state)
	end)
end

function M.sessions()
	local state = current
	if not state or not state.connection or not state.connection.ready or state.connection.closed then
		vim.notify("Codex observer is not connected; use :FoxAgenticRefresh after starting Codex", vim.log.levels.WARN)
		return
	end
	provider.list_sessions(state.connection, state.root, function(sessions, err)
		if err then
			state.status = err
			M.render(state)
			return
		end
		if #sessions == 0 then
			state.status = "No CLI sessions in this exact directory. Use :FoxAgenticBind with the ID from Codex /status."
			M.render(state)
			return
		end
		vim.ui.select(sessions, {
			prompt = "Bind Codex session to terminal " .. state.slot .. " (no automatic guessing)",
			format_item = function(session)
				return session.name .. " [" .. session.id .. "]"
			end,
		}, function(session)
			if session then
				M.bind(session, state)
			end
		end)
	end)
end

function M.connect(state)
	if state.subscription then
		state.subscription.detach()
	end
	if state.connection then
		state.connection.detach()
	end
	state.connection = provider.connect(function(connection)
		state.connection = connection
		if state.session.id then
			M.bind(state.session, state)
		else
			state.status = state.automatic and "Run plain codex in this terminal; tracking starts automatically."
				or "Connected. Select this terminal's session with s."
			M.render(state)
			if not state.automatic and M.active() and current == state then
				M.sessions()
			end
		end
	end, function(event)
		if event.session_id ~= state.session.id then
			return
		end
		reducer.reduce(state, event)
		M.queue_render(state)
	end, function(status)
		state.status = status
		M.render(state)
	end)
end

function M.hide(state)
	state = state or current
	if not state then
		return
	end
	local original_tab, original_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
	local closing_current = original_tab == state.tab
	if valid(state.tab, "tab") then
		state.views = state.views or {}
		for index, win in ipairs(state.wins or {}) do
			if valid(win, "win") and vim.api.nvim_win_get_buf(win) == state.bufs[index] then
				state.views[index] = vim.api.nvim_win_call(win, vim.fn.winsaveview)
				if win == vim.api.nvim_get_current_win() then
					state.focus = index
				end
			end
		end
		vim.api.nvim_set_current_tabpage(state.tab)
		if #vim.api.nvim_list_tabpages() == 1 then
			vim.cmd("tabnew")
			vim.api.nvim_set_current_tabpage(state.tab)
		end
		vim.cmd("tabclose!")
		state.tab = nil
		for _, buf in ipairs(state.bufs or {}) do
			if valid(buf, "buf") then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
	end
	if not closing_current and valid(original_tab, "tab") then
		vim.api.nvim_set_current_tabpage(original_tab)
		if valid(original_win, "win") then
			vim.api.nvim_set_current_win(original_win)
		end
		return
	end
	if valid(state.editor_tab, "tab") then
		vim.api.nvim_set_current_tabpage(state.editor_tab)
		if valid(state.editor_win, "win") then
			vim.api.nvim_set_current_win(state.editor_win)
		end
	end
end

function M.suspend()
	local displayed = M.active() and current
	for _, state in pairs(M.states) do
		if valid(state.tab, "tab") then
			M.hide(state)
		end
	end
	return function(reopen)
		if reopen ~= false and displayed and valid(displayed.terminal, "buf") then
			M.show(displayed)
		end
	end
end

function M.open_file(index)
	local state = current
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local file = state and state.rows[index] and state.rows[index][row]
	if not file then
		return
	end
	local changed
	for _, change in ipairs(state.changes or {}) do
		if path.normalize(state.root .. "/" .. change.file) == file.path then
			changed = change
			break
		end
	end
	if changed then
		require("plugins.fox.git.git_center.modals").open_diff_modal(changed.file, changed.type, state.root, nil, nil, {
			agentic = true,
		})
		return
	end
	if vim.fn.filereadable(file.path) ~= 1 then
		vim.notify("File is unavailable: " .. text(file.path), vim.log.levels.WARN)
		return
	end
	M.hide()
	state.excursion = true
	vim.cmd((vim.bo.modified and "split " or "edit ") .. vim.fn.fnameescape(file.path))
end

function M.help()
	vim.notify(
		table.concat({
			"Agentic: F2 Editor / return | F3 Query | s bind session | r refresh | Enter inspect",
			"j/k scroll, gg/G and Ctrl-d/u; Tab cycles panels; Ctrl-h/j/k/l navigates panes.",
			"Each terminal BUFFER owns its Codex binding. No folder/recency auto-selection.",
			"Reads: best-effort Codex classification; per-file tokens estimated as single-read output characters / 4.",
			"Skill activation is unavailable. Session usage/model use a bounded local transcript telemetry fallback.",
			"Changes: all current Git changes. Patch counts on cards are cumulative observed edits.",
			"Observer reads persisted history, never sends turns, resumes threads, or answers approvals.",
		}, "\n"),
		vim.log.levels.INFO,
		{ title = "Agentic Mode" }
	)
end

function M.setup()
	if M.initialized then
		return
	end
	M.initialized = true
	local group = vim.api.nvim_create_augroup("FoxAgentic", { clear = true })
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if M.active() and vim.bo.filetype == "fox_agentic" then
				local state = current
				M.hide()
				M.show(state)
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for _, state in pairs(M.states) do
				M.detach(state)
				if state.timer then
					state.timer:stop()
					state.timer:close()
					state.timer = nil
				end
			end
			local background = package.loaded["fox.agentic.background"]
			if background then
				background.dispose()
			end
		end,
	})
end

function M.observe(context)
	M.setup()
	local state = M.states[context.buf]
	if not state then
		state = reducer.new({ id = context.session, cwd = context.root })
		state.root = context.root
		M.states[context.buf] = state
	elseif context.session and state.session.id ~= context.session then
		M.detach(state)
		local fresh = reducer.new({ id = context.session, cwd = context.root })
		for _, key in ipairs({ "session", "files", "order", "seen", "status" }) do
			state[key] = fresh[key]
		end
		state.usage, state.finished, state.views, state.changes = nil, nil, {}, {}
		state.root, state.scan = context.root, nil
	end
	state.terminal, state.slot = context.buf, context.slot
	state.automatic = state.automatic or context.automatic
	if state.session.id and not state.finished and (not state.connection or state.connection.closed) then
		M.connect(state)
	end
	if not state.timer then
		state.timer = vim.uv.new_timer()
		state.timer:start(
			2000,
			2000,
			vim.schedule_wrap(function()
				if valid(state.terminal, "buf") then
					if valid(state.tab, "tab") then
						M.refresh_git(state)
					end
				else
					M.detach(state)
					M.hide(state)
					state.timer:stop()
					state.timer:close()
					state.timer = nil
					M.states[state.terminal] = nil
				end
			end)
		)
	end
	return state
end

function M.show(state)
	local query = package.loaded["fox.query"]
	if query then
		for _, query_state in pairs(query.states) do
			if query_state.tab == vim.api.nvim_get_current_tabpage() then
				query.hide(query_state)
				break
			end
		end
	end
	local context = not state and require("plugins.fox.dev.terminal").agentic_context() or nil
	if context then
		state = M.observe(context)
	end
	if not state then
		vim.notify("Open a FoxVim terminal first, then press F2", vim.log.levels.WARN)
		return
	end
	current = state
	if valid(state.tab, "tab") then
		vim.api.nvim_set_current_tabpage(state.tab)
		require("plugins.fox.dev.terminal").hide_terminal()
		vim.api.nvim_set_current_win(state.wins[state.focus or 1])
		return
	end
	require("plugins.fox.dev.terminal").hide_terminal()
	state.editor_tab, state.editor_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
	state.excursion = nil
	vim.cmd("stopinsert")
	vim.cmd("tabnew")
	state.tab = vim.api.nvim_get_current_tabpage()
	vim.t.fox_agentic = true
	state.wins, state.bufs = {}, {}
	state.titles = { "Agentic / Codex", "Context / observed reads", "Files Changed / Session" }
	local compact = vim.o.columns < 100
	local base = vim.api.nvim_get_current_win()
	for index, title in ipairs(state.titles) do
		if index > 1 and not compact then
			vim.cmd("rightbelow vsplit")
		end
		local win, buf = compact and base or vim.api.nvim_get_current_win(), vim.api.nvim_create_buf(false, true)
		state.wins[index], state.bufs[index] = win, buf
		vim.api.nvim_win_set_buf(win, buf)
		vim.bo[buf].bufhidden = "hide"
		vim.bo[buf].filetype = "fox_agentic"
		vim.bo[buf].swapfile = false
		vim.bo[buf].modeline = false
		vim.wo[win].number, vim.wo[win].relativenumber = false, false
		vim.wo[win].signcolumn = "no"
		vim.wo[win].wrap = false
		vim.wo[win].cursorline = true
		vim.wo[win].winbar = title .. " | F2 Editor | F1 Help"
		local options = { buffer = buf, silent = true }
		vim.keymap.set("n", "<CR>", function()
			M.open_file(index)
		end, options)
		vim.keymap.set("n", "s", M.sessions, options)
		vim.keymap.set("n", "r", M.refresh, options)
		vim.keymap.set("n", "<F1>", M.help, options)
		vim.keymap.set("n", "<Tab>", function()
			M.focus_panel(index % 3 + 1)
		end, options)
		vim.keymap.set("n", "<S-Tab>", function()
			M.focus_panel((index + 1) % 3 + 1)
		end, options)
		for key, command in pairs({ h = "h", j = "j", k = "k", l = "l" }) do
			vim.keymap.set("n", "<C-" .. key .. ">", "<Cmd>wincmd " .. command .. "<CR>", options)
		end
	end
	-- Compact panels share a window, so hidden panel buffers must survive switching.
	if compact then
		for _, buf in ipairs(state.bufs) do
			vim.bo[buf].bufhidden = "hide"
		end
		vim.api.nvim_win_set_buf(base, state.bufs[1])
	end
	if vim.o.columns >= 110 then
		vim.api.nvim_win_set_width(state.wins[1], math.floor(vim.o.columns * 0.52))
		vim.api.nvim_win_set_width(state.wins[2], math.floor(vim.o.columns * 0.23))
	end
	vim.api.nvim_set_current_win(state.wins[1])
	M.render(state)
	for index, view in pairs(state.views or {}) do
		local win = state.wins[index]
		if not compact or index == (state.focus or 1) then
			vim.api.nvim_win_set_buf(win, state.bufs[index])
			vim.api.nvim_win_call(win, function()
				vim.fn.winrestview(view)
			end)
		end
	end
	M.focus_panel(state.focus or 1)
	M.refresh_git(state)
	if not state.finished and (not state.connection or state.connection.closed) then
		M.connect(state)
	end
end

function M.start_codex()
	local root = require("fox.core.project").root()
	local connection
	connection = provider.connect(function(ready)
		provider.create_session(ready, root, function(session, err)
			if err or not session then
				vim.notify(err or "Could not create Codex session", vim.log.levels.ERROR)
			else
				ready.detach(true)
				local context, launch_err = require("plugins.fox.dev.terminal").launch_codex(session.id)
				if not context then
					vim.notify(launch_err, vim.log.levels.WARN)
				end
			end
			ready.detach()
		end)
	end, function() end, function(status)
		vim.notify(status, vim.log.levels.WARN)
	end)
	return connection
end

function M.toggle()
	if vim.b.fox_term_num then
		if M.active() then
			M.hide()
		end
		M.show()
	elseif M.active() then
		M.hide()
	elseif
		current
		and current.excursion
		and valid(current.editor_tab, "tab")
		and current.editor_tab == vim.api.nvim_get_current_tabpage()
	then
		M.show(current)
	else
		M.show(nil)
	end
end

function M.detach(state)
	state = state or current
	if state then
		if state.subscription then
			state.subscription.detach()
		end
		if state.connection then
			state.connection.detach()
		end
		state.status = "Detached; Codex continues running"
		M.render(state)
	end
end

function M.refresh()
	if current then
		if not current.connection or current.connection.closed then
			M.connect(current)
		elseif current.subscription then
			current.subscription.refresh()
		end
		M.refresh_git(current)
	end
end

return M
