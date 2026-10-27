local M = { states = {} }
local storage = require("fox.query.storage")
local sql = require("fox.query.sql")
local render = require("fox.query.render")
local client = require("fox.query.client")
local layout = require("fox.query.layout")
local ns = vim.api.nvim_create_namespace("fox_query")
local statement_ns = vim.api.nvim_create_namespace("fox_query_statement")
local group = vim.api.nvim_create_augroup("FoxQuery", { clear = true })

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "FoxQuerier" })
end

function M.state(root)
	root = storage.root(root)
	if not M.states[root] then
		local settings, err = storage.load(root, "settings.json", {})
		if err then
			notify(err, vim.log.levels.WARN)
		end
		local limit = settings and settings.diagram_columns
		local tab_pins, pin_err = storage.load(root, "private/tab-pins.json", {})
		if pin_err or type(tab_pins) ~= "table" or not vim.islist(tab_pins) then
			notify(pin_err or "Invalid Query tab pins", vim.log.levels.WARN)
			tab_pins = {}
		end
		M.states[root] = {
			root = root,
			view = "standard",
			metadata = { tables = {}, relations = {} },
			consoles = {},
			depth = 3,
			autorun = false,
			diagram_columns = type(limit) == "number" and limit >= 1 and limit <= 200 and limit % 1 == 0 and limit or 15,
			connection_status = {},
			tab_pins = tab_pins,
		}
	end
	return M.states[root]
end

local function valid(handle, kind)
	return handle
		and (
			kind == "tab" and vim.api.nvim_tabpage_is_valid(handle)
			or kind == "win" and vim.api.nvim_win_is_valid(handle)
			or kind == "buf" and vim.api.nvim_buf_is_valid(handle)
		)
end

local function query_keys(buf)
	vim.keymap.set({ "n", "i", "v" }, "<LeftMouse>", function()
		local mouse = vim.fn.getmousepos()
		local state = M.states[vim.b[buf].fox_query_root]
		if state and mouse.winid == state.activity_win then
			M.copy_activity(state)
		else
			vim.api.nvim_feedkeys(vim.keycode("<LeftMouse>"), "n", false)
		end
	end, { buffer = buf, silent = true })
	for key, direction in pairs({ ["<A-h>"] = -1, ["<A-l>"] = 1, ["<A-Left>"] = -1, ["<A-Right>"] = 1 }) do
		vim.keymap.set("n", key, function()
			M.cycle(direction)
		end, { buffer = buf, silent = true, desc = "Query: switch SQL tab" })
	end
	vim.keymap.set({ "n", "i", "v" }, "<S-F3>", function()
		M.show(M.state().view == "visual" and "standard" or "visual")
	end, { buffer = buf, silent = true, desc = "Query: toggle live diagram" })
	for _, direction in ipairs({ "h", "j", "k", "l" }) do
		vim.keymap.set({ "n", "i", "v" }, "<C-" .. direction .. ">", function()
			vim.cmd("wincmd " .. direction)
		end, { buffer = buf, silent = true, desc = "Query: focus " .. direction })
	end
	local actions = {
		gC = {
			function()
				M.profile()
			end,
			"Connections",
		},
		gV = {
			function()
				M.show(M.state().view == "visual" and "standard" or "visual")
			end,
			"Standard / Visual",
		},
		gR = {
			function()
				local state = M.states[vim.b[buf].fox_query_root]
				if state and state.result_buf == buf then
					M.follow_row()
				else
					M.results()
				end
			end,
			"Results / follow foreign key",
		},
		gE = {
			function()
				M.focus_panel("side")
			end,
			"Explorer / diagram",
		},
		gN = {
			function()
				M.create()
			end,
			"New query",
		},
		["<F1>"] = {
			function()
				M.help()
			end,
			"Help",
		},
	}
	for key, action in pairs(actions) do
		vim.keymap.set("n", key, action[1], { buffer = buf, silent = true, desc = "Query: " .. action[2] })
	end
end

function M.complete()
	if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "i" then
		vim.cmd("startinsert")
		vim.schedule(M.complete)
		return
	end
	local ok, lazy = pcall(require, "lazy")
	if ok then
		lazy.load({ plugins = { "blink.cmp" } })
	end
	local loaded, blink = pcall(require, "blink.cmp")
	if loaded then
		local shown, err = pcall(blink.show, { providers = { "fox_query" } })
		if not shown then
			notify("Completion unavailable: " .. tostring(err), vim.log.levels.WARN)
		end
	else
		notify("Database completion requires blink.cmp", vim.log.levels.WARN)
	end
end

local function panel(state, key)
	if not valid(state[key], "buf") then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = "hide", false, "foxquery"
		vim.b[buf].fox_query_root, state[key] = state.root, buf
		query_keys(buf)
	end
	return state[key]
end

local function set_lines(buf, lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, require("fox.core.ui").sanitize_lines(lines))
	vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
end

local function set_highlights(buf, highlights)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, highlight in ipairs(highlights) do
		local opts = highlight[3] and { hl_group = highlight[2], end_col = highlight[4] }
			or { line_hl_group = highlight[2] }
		vim.api.nvim_buf_set_extmark(buf, ns, highlight[1], highlight[3] or 0, opts)
	end
end

local function console(state)
	if valid(state.active, "buf") and state.consoles[state.active] then
		return state.consoles[state.active], state.active
	end
	for buf, item in pairs(state.consoles) do
		if valid(buf, "buf") then
			state.active = buf
			return item, buf
		end
	end
end

function M.select(items, opts, callback)
	if #items == 0 then
		callback(nil)
		return
	end
	vim.cmd("stopinsert")
	local prompt = (opts.prompt or "Choose"):gsub("[%c]", " ")
	local lines, width = { prompt, "" }, vim.fn.strdisplaywidth(prompt)
	for _, item in ipairs(items) do
		local label = (opts.format_item and opts.format_item(item) or tostring(item)):gsub("[%c]", " ")
		lines[#lines + 1] = label
		width = math.max(width, vim.fn.strdisplaywidth(label))
	end
	width = math.max(1, math.min(math.max(24, width), 90, vim.o.columns - 4))
	lines[2] = string.rep("-", width)
	local height = 0
	for _, line in ipairs(lines) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
	end
	local buf, win = require("fox.core.ui").float({
		title = " Query ",
		lines = lines,
		width = width,
		height = math.max(1, math.min(height, vim.o.lines - 6)),
	})
	vim.b[buf].fox_query_root = M.state().root
	vim.wo[win].wrap, vim.wo[win].cursorline = true, true
	vim.api.nvim_win_set_cursor(win, { 3, 0 })
	local resolved = false
	local function finish(item, index)
		if resolved then
			return
		end
		resolved = true
		if valid(win, "win") and vim.api.nvim_win_get_buf(win) == buf then
			vim.api.nvim_win_close(win, true)
		end
		callback(item, index)
	end
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			if not resolved then
				vim.schedule(function()
					finish(nil)
				end)
			end
		end,
	})
	for _, key in ipairs({ "q", "<Esc>", "<C-c>" }) do
		vim.keymap.set("n", key, function()
			finish(nil)
		end, { buffer = buf, silent = true, nowait = true })
	end
	vim.keymap.set("n", "<CR>", function()
		local index = vim.api.nvim_win_get_cursor(win)[1] - 2
		if items[index] then
			finish(items[index], index)
		end
	end, { buffer = buf, silent = true })
	for key, direction in pairs({ j = 1, k = -1, ["<Down>"] = 1, ["<Up>"] = -1, ["<C-n>"] = 1, ["<C-p>"] = -1 }) do
		vim.keymap.set("n", key, function()
			local row = math.max(3, math.min(#lines, vim.api.nvim_win_get_cursor(win)[1] + direction))
			vim.api.nvim_win_set_cursor(win, { row, 0 })
		end, { buffer = buf, silent = true })
	end
end

function M.empty(state)
	local buf = panel(state, "empty_buf")
	set_lines(buf, { "Select a SQL tab or create a new one with gN (:FoxQueryNew)." })
	return buf
end

function M.cycle(direction)
	local state, buffers = M.state(), {}
	for _, buf in ipairs(require("fox.ui.tabline").buffers()) do
		if state.consoles[buf] and vim.bo[buf].buflisted then
			buffers[#buffers + 1] = buf
		end
	end
	if #buffers == 0 or not valid(state.sql_win, "win") then
		return
	end
	local index = 1
	for at, buf in ipairs(buffers) do
		if buf == state.active then
			index = at
		end
	end
	state.active = buffers[(index - 1 + direction) % #buffers + 1]
	vim.api.nvim_set_current_win(state.sql_win)
	vim.api.nvim_win_set_buf(state.sql_win, state.active or M.empty(state))
	M.refresh_view(state)
end

function M.column_limit()
	local state = M.state()
	vim.ui.input({ prompt = "Diagram columns (1-200): ", default = tostring(state.diagram_columns) }, function(value)
		if value == nil then
			return
		end
		local count = tonumber(value)
		if not count or count < 1 or count > 200 or count % 1 ~= 0 then
			notify("Enter a whole column count from 1 to 200", vim.log.levels.WARN)
			return
		end
		local settings, err = storage.load(state.root, "settings.json", {})
		if not settings then
			notify(err, vim.log.levels.ERROR)
			return
		end
		settings.diagram_columns = count
		local ok, save_err = storage.save(state.root, "settings.json", settings)
		if not ok then
			notify(save_err, vim.log.levels.ERROR)
			return
		end
		state.diagram_columns = count
		M.refresh_view(state)
	end)
end

function M.draw_activity(state)
	local active = console(state)
	state.activity_text = "ACTIVITY | "
		.. (active and active.status or "idle")
		.. " | "
		.. (active and (active.error_detail or active.executed_sql) or "Waiting for SELECT SQL")
	local buf = panel(state, "activity_buf")
	set_lines(buf, { (state.activity_text:gsub("[\r\n]+", " | ")) })
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
		virt_text = { { state.view == "visual" and " [Default | Visually*] " or " [Default* | Visually] ", "StatusLine" } },
		virt_text_pos = "right_align",
	})
	vim.keymap.set("n", "y", function()
		M.copy_activity(state)
	end, { buffer = buf, silent = true })
	vim.keymap.set("n", "<CR>", M.error_details, { buffer = buf, silent = true })
end

function M.copy_activity(state)
	state = state or M.state()
	local active = console(state)
	local text = active and active.error_detail or state.activity_text or "idle"
	vim.fn.setreg('"', text)
	vim.fn.setreg("+", text)
	notify("Query status copied")
end

function M.draw_queries(state)
	local entries = require("fox.query.files").list(state)
	local files = {}
	state.query_expanded = state.query_expanded or {}
	for _, entry in ipairs(entries) do
		if not entry.directory then
			files[#files + 1] = entry.relative
		end
	end
	state.query_files = files
	local tree = require("fox.query.tree")
	tree.draw(state, entries)
	local buf = panel(state, "queries_buf")
	query_keys(buf)
	vim.keymap.set("n", "<CR>", function()
		local entry = tree.selected(state)
		if entry and entry.directory then
			tree.toggle(state)
		elseif entry then
			M.new(entry.relative)
		end
	end, { buffer = buf, silent = true })
	for key, action in pairs({ a = "create", A = "folder", r = "rename", d = "delete" }) do
		vim.keymap.set("n", key, function()
			M.file_action(action)
		end, { buffer = buf, silent = true })
	end
end

function M.file_action(action)
	local state, files = M.state(), require("fox.query.files")
	if action and not vim.tbl_contains({ "create", "folder", "rename", "delete" }, action) then
		notify("Choose create, folder, rename, or delete", vim.log.levels.WARN)
		return
	end
	if not action then
		M.focus_panel("queries")
		return
	end
	local win = valid(state.queries_win, "win") and state.queries_win or state.sql_win
	local entry = valid(win, "win") and require("fox.query.tree").selected(state)
	if (action == "rename" or action == "delete") and not entry then
		notify("Select a SQL file or folder first", vim.log.levels.WARN)
		return
	end
	local function finish(ok, err)
		if not ok then
			notify(tostring(err), vim.log.levels.ERROR)
		end
		M.refresh_view(state)
	end
	if action == "delete" then
		M.select(
			{ "Delete", "Cancel" },
			{ prompt = "Delete " .. entry.relative .. (entry.directory and " and its contents?" or "?") },
			function(choice)
				if M.states[state.root] ~= state or storage.root() ~= state.root then
					return
				end
				if choice == "Delete" then
					finish(files.delete(state, entry.relative))
				end
			end
		)
		return
	end
	local parent = entry and (entry.directory and entry.relative or vim.fs.dirname(entry.relative)) or "."
	local prefix = parent == "." and "" or parent .. "/"
	vim.ui.input({
		prompt = action == "rename" and "Rename to: " or action == "folder" and "New folder: " or "New SQL file: ",
		default = action == "rename" and entry.relative or prefix,
	}, function(value)
		if M.states[state.root] ~= state or storage.root() ~= state.root then
			return
		end
		if not value or value == "" then
			return
		end
		if action == "rename" then
			finish(files.rename(state, entry.relative, value))
			return
		end
		if action == "create" and not value:match("%.sql$") then
			value = value .. ".sql"
		end
		local function create(name)
			if action == "create" and not name then
				return
			end
			local ok, err = files.create(state, value, action == "folder")
			if ok then
				local folder = vim.fs.dirname(value)
				while folder ~= "." do
					state.query_expanded[folder] = true
					folder = vim.fs.dirname(folder)
				end
			end
			if ok and action == "folder" then
				state.query_expanded[value] = true
			end
			if ok and action == "create" then
				M.new(value, name)
			end
			finish(ok, err)
		end
		if action == "create" then
			M.choose_dialect(state, create)
		else
			create()
		end
	end)
end

local function current_metadata(state)
	local item = console(state)
	if item and item.metadata then
		state.metadata = item.metadata
	elseif item then
		state.metadata, state.note_keys = { tables = {}, relations = {} }, {}
	end
	if valid(state.active, "buf") then
		local dialect = require("fox.langs.sql.dialect").read(state.active)
		if dialect then
			state.metadata = vim.tbl_extend("force", state.metadata, { syntax = dialect })
		end
	end
	return state.metadata
end

local function text_at_cursor(state)
	local active, buf = console(state)
	if not buf then
		return "", 1
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local position = valid(state.sql_win, "win")
			and vim.api.nvim_win_get_buf(state.sql_win) == buf
			and vim.api.nvim_win_get_cursor(state.sql_win)
		or active.cursor
		or { 1, 0 }
	position[1] = math.min(#lines, position[1])
	local offset = position[2] + 1
	for line = 1, position[1] - 1 do
		offset = offset + #lines[line] + 1
	end
	return table.concat(lines, "\n"), offset
end

local function mark_statement(state)
	local active, buf = console(state)
	if not active then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, statement_ns, 0, -1)
	local text, offset = text_at_cursor(state)
	-- shortcut: outline SQL buffers up to 128 KiB; use incremental parsing for larger files.
	if #text > 128 * 1024 then
		return
	end
	local engine = require("fox.langs.sql.dialect").read(buf)
		or vim.b[buf].fox_sql_dialect
		or active.syntax
		or active.profile and active.profile.engine
	for _, statement in ipairs(sql.statements(text, engine) or {}) do
		if offset >= statement.first and offset <= statement.last then
			local first = statement.first + (statement.sql:find("%S") or 1) - 1
			local last = math.min(#text, statement.last)
			last = first + (text:sub(first, last):find("%s*$") or 1) - 2
			local first_row = select(2, text:sub(1, first - 1):gsub("\n", ""))
			local last_row = select(2, text:sub(1, last - 1):gsub("\n", ""))
			local width = math.max(1, vim.api.nvim_win_get_width(state.sql_win) - 2)
			for _, edge in ipairs({ { first_row, true }, { last_row, false } }) do
				vim.api.nvim_buf_set_extmark(buf, statement_ns, edge[1], 0, {
					virt_lines = { { { string.rep("─", width), "DiagnosticInfo" } } },
					virt_lines_above = edge[2],
				})
			end
			return
		end
	end
end

local function result_header(state)
	local active = console(state)
	for _, name in ipairs({ "result_win", "sql_win", "result_popup" }) do
		local win = state[name]
		if valid(win, "win") and vim.api.nvim_win_get_buf(win) == state.result_buf then
			local info = vim.fn.getwininfo(win)[1]
			local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
			local header
			for _, entry in ipairs(active and active.result and active.result_headers or {}) do
				if entry.first < view.topline then
					header = entry.text
				else
					break
				end
			end
			local text, column = string.rep(" ", info.textoff), 0
			local width = vim.api.nvim_win_get_width(win) - info.textoff
			for index = 0, vim.fn.strchars(header or "") - 1 do
				local char = vim.fn.strcharpart(header, index, 1)
				local cells = vim.fn.strdisplaywidth(char)
				local first, last = math.max(column, view.leftcol), math.min(column + cells, view.leftcol + width)
				if first < last then
					text = text .. (last - first == cells and char or string.rep(" ", last - first))
				end
				column = column + cells
				if column >= view.leftcol + width then
					break
				end
			end
			vim.wo[win].winbar = header and text:gsub("%%", "%%%%") or ""
		end
	end
end

function M.refresh_view(state)
	state = state or M.state()
	if not valid(state.tab, "tab") or vim.api.nvim_get_current_tabpage() ~= state.tab then
		return
	end
	local active = console(state)
	if active then
		local file = vim.b[state.active].fox_query_document:sub(#"queries/" + 1)
		if state.last_query ~= file then
			local ok, err = storage.save(state.root, "private/last-query.json", { file = file })
			if ok then
				state.last_query = file
			else
				notify(err, vim.log.levels.WARN)
			end
		end
	end
	current_metadata(state)
	if valid(state.sql_win, "win") then
		mark_statement(state)
	end
	local label = active and active.profile and active.profile.id or "no connection"
	local connected = active and active.client and active.client.connected
	local status = "[QUERY / "
		.. state.view:upper()
		.. "] "
		.. label
		.. " | "
		.. (active and require("fox.langs.sql.dialect").read(state.active) or "SQL")
		.. " | "
		.. (connected and "READ ONLY" or "disconnected")
		.. " | "
		.. (active and active.status or "idle")
		.. (state.autorun and " | Auto SELECT" or " | Manual")
	if valid(state.sql_win, "win") then
		vim.wo[state.sql_win].winbar = status:gsub("%%", "%%%%") .. " %= Ctrl+Enter Run / F5 | Shift+F3 Diagram | F1 Help"
	end
	if valid(state.side_win, "win") then
		vim.wo[state.side_win].winbar = state.view == "visual" and "Diagram | C Columns | F1 Help" or "Tables | F1 Help"
	end
	if valid(state.connections_buf, "buf") then
		M.draw_connections(state)
	end
	if state.view == "visual" then
		local text, offset = text_at_cursor(state)
		if active and state.pinned and state.pinned.buf == state.active then
			local mark = vim.api.nvim_buf_get_extmark_by_id(state.active, ns, state.pinned.id, {})
			if #mark == 2 then
				local lines = vim.api.nvim_buf_get_lines(state.active, 0, mark[1], false)
				offset = mark[2] + 1
				for _, line in ipairs(lines) do
					offset = offset + #line + 1
				end
			end
		end
		local statement
		if #text <= 128 * 1024 then
			statement = sql.scope(text, offset, "statement", nil, state.metadata.syntax or state.metadata.engine)
		end
		local graph = sql.analyze(statement or text, state.metadata)
		if not statement then
			graph.partial = true
		end
		state.graph = graph
		local lines, highlights, objects = render.graph(
			graph,
			state.metadata,
			valid(state.side_win, "win") and vim.api.nvim_win_get_width(state.side_win) or vim.o.columns,
			state.diagram_columns
		)
		set_lines(panel(state, "side_buf"), lines)
		state.objects = objects
		set_highlights(state.side_buf, highlights)
	else
		local lines, objects = render.explorer(
			state.metadata,
			state.selected,
			state.note_keys,
			valid(state.side_win, "win") and vim.api.nvim_win_get_height(state.side_win) or 0
		)
		state.objects = objects
		set_lines(panel(state, "side_buf"), lines)
	end
	local result_lines = {}
	if active and active.result then
		if not active.result_lines or not active.result_rows or not active.result_headers then
			active.result_lines, active.result_rows, active.result_headers = render.results(active.result)
		end
		vim.list_extend(result_lines, active.result_lines)
	else
		vim.list_extend(result_lines, {
			"",
			"1. gC: choose a connection in the left sidebar; a adds one.",
			"2. Write SELECT SQL above; Ctrl+Space opens column/table completion in Insert mode.",
			"3. Press Ctrl+Enter to run the statement at the cursor; results appear here.",
			"Ctrl+Enter or F5 runs manually. Ctrl+Space or Ctrl+X Ctrl+O opens completion.",
			"gV: Standard / Visual | gN: new query | F3: Editor / Query | F1: help",
		})
	end
	vim.list_extend(result_lines, {
		"RESULTS | " .. (active and active.result_label or "No execution"),
		"Enter: expand row | y: copy row | e: export | gR: follow foreign key",
	})
	set_lines(panel(state, "result_buf"), result_lines)
	result_header(state)
	M.draw_activity(state)
	if valid(state.queries_buf, "buf") then
		M.draw_queries(state)
	end
end

local function map(buf, key, action)
	vim.keymap.set("n", key, action, { buffer = buf, silent = true })
end

local function selected_object(state)
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	local inspector = state.inspectors and state.inspectors[vim.api.nvim_get_current_win()]
	if inspector then
		return render.object_at(inspector, line, vim.fn.virtcol(".") - 1)
	end
	if buf == state.side_buf and state.objects then
		return render.object_at(state.objects, line, vim.fn.virtcol(".") - 1)
	end
	if state.selected then
		return sql.table(state.metadata, state.selected)
	end
end

local function show_document(state, relative, filetype)
	local buf = storage.document_buffer(state.root, relative, filetype)
	query_keys(buf)
	if valid(state.sql_win, "win") then
		vim.api.nvim_set_current_win(state.sql_win)
	end
	vim.api.nvim_set_current_buf(buf)
	return buf
end

function M.inspect(item, state)
	state = state or M.state()
	item = item or selected_object(state)
	if not item then
		notify("Select a table in the explorer or diagram", vim.log.levels.WARN)
		return
	end
	state.selected = item.key
	local buf = vim.api.nvim_create_buf(false, true)
	vim.b[buf].fox_query_root = state.root
	query_keys(buf)
	local lines, highlights, objects = render.inspect(item, state.metadata)
	local width = math.min(vim.o.columns - 4, vim.fn.strdisplaywidth(lines[1]))
	local height = math.min(vim.o.lines - 6, #lines)
	set_lines(buf, lines)
	set_highlights(buf, highlights)
	local previous = vim.api.nvim_get_current_win()
	local _, win = require("fox.core.ui").float(buf, {
		width = width,
		height = height,
		title = " Table: " .. item.name:gsub("[%c]", " ") .. " ",
		parent = previous,
	})
	vim.bo[buf].bufhidden = "wipe"
	state.inspectors = state.inspectors or {}
	state.inspectors[win] = objects
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			state.inspectors[win] = nil
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		callback = function()
			vim.schedule(function()
				if state.inspectors[vim.api.nvim_get_current_win()] then
					return
				end
				for _, inspector in ipairs(vim.tbl_keys(state.inspectors)) do
					if valid(inspector, "win") then
						vim.api.nvim_win_close(inspector, true)
					end
				end
			end)
		end,
	})
	local function close()
		if valid(win, "win") then
			vim.api.nvim_win_close(win, true)
		end
		if valid(previous, "win") then
			vim.api.nvim_set_current_win(previous)
		end
	end
	vim.wo[win].wrap = false
	vim.wo[win].winbar = "Enter Inspect | J Insert JOIN | b Browse | B Browse popup | n Notes | g Relations | q Close"
	map(buf, "q", close)
	map(buf, "<Esc>", close)
	map(buf, "<CR>", function()
		local selected = selected_object(state)
		if selected then
			M.inspect(selected, state)
		end
	end)
	local actions = {
		J = M.insert_join,
		n = M.notes,
		g = function(selected)
			state.selected = selected.key
			M.graph(false)
		end,
		b = M.browse,
		B = function(selected)
			M.browse(selected, true)
		end,
	}
	for key, action in pairs(actions) do
		map(buf, key, function()
			local selected = selected_object(state)
			if selected then
				close()
				action(selected)
			end
		end)
	end
end

function M.hide(state)
	state = state or M.state()
	if valid(state.tab, "tab") then
		local active, buf = console(state)
		if active and valid(state.sql_win, "win") and vim.api.nvim_win_get_buf(state.sql_win) == buf then
			active.cursor = vim.api.nvim_win_get_cursor(state.sql_win)
		end
		if not state.resizing then
			local ok, err = layout.save(state)
			if not ok then
				notify("Could not save Query layout: " .. tostring(err), vim.log.levels.WARN)
			end
		end
		local current = vim.api.nvim_get_current_tabpage()
		vim.api.nvim_set_current_tabpage(state.tab)
		vim.cmd("tabclose")
		state.tab, state.sql_win, state.side_win, state.result_win, state.activity_win = nil, nil, nil, nil, nil
		state.connections_win, state.queries_win = nil, nil
		if current ~= state.tab and valid(state.editor_tab, "tab") then
			vim.api.nvim_set_current_tabpage(state.editor_tab)
		end
	end
	state.mode = "editor"
	M.privacy_leave(state)
end

function M.show(view)
	local state = M.state()
	if view and view ~= "standard" and view ~= "visual" then
		notify("Choose standard or visual", vim.log.levels.ERROR)
		return
	end
	if valid(state.tab, "tab") then
		if not view or view == state.view then
			vim.api.nvim_set_current_tabpage(state.tab)
			return
		end
		M.hide(state)
	end
	state.view, state.mode = view or state.view, "query"
	require("fox.query.tree").setup()
	M.privacy_enter(state)
	state.editor_tab = vim.api.nvim_get_current_tabpage()
	vim.cmd("tabnew")
	state.tab, state.sql_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
	vim.t[state.tab].fox_query_root = state.root
	local _, buf = console(state)
	if not buf then
		if not state.opened then
			M.draw_queries(state)
			local saved = storage.load(state.root, "private/last-query.json", {})
			for _, document in ipairs(state.tab_pins) do
				local file = type(document) == "string" and document:match("^queries/(.+)$")
				if file and vim.tbl_contains(state.query_files, file) then
					M.new(file)
				end
			end
			local file = saved and saved.file
			M.new(vim.tbl_contains(state.query_files, file) and file or state.query_files[1])
			_, buf = console(state)
		else
			buf = M.empty(state)
		end
	end
	state.opened = true
	vim.api.nvim_win_set_buf(state.sql_win, buf)
	state.compact = vim.o.columns < 72 or vim.o.lines < 20
	local sizes = layout.load(state.view)
	panel(state, "side_buf")
	if not state.compact then
		vim.cmd("botright vsplit")
		state.side_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.side_win, panel(state, "side_buf"))
		vim.api.nvim_win_set_width(
			state.side_win,
			math.min(vim.o.columns - 12, math.max(12, math.floor(vim.o.columns * (sizes.side or 0.3))))
		)
		vim.wo[state.side_win].wrap = false
		vim.wo[state.side_win].winfixwidth = true
		if state.view == "standard" and not sizes.side then
			local width = 24
			for _, item in ipairs(state.metadata.tables or {}) do
				width = math.max(width, vim.fn.strdisplaywidth(item.key) + 4)
			end
			vim.api.nvim_win_set_width(state.side_win, math.min(width, math.floor(vim.o.columns * 0.35)))
		end
		vim.api.nvim_set_current_win(state.sql_win)
		do
			vim.cmd("belowright split")
			state.result_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(state.result_win, panel(state, "result_buf"))
			vim.api.nvim_win_set_height(state.result_win, math.max(3, math.floor(vim.o.lines * sizes.results)))
			vim.wo[state.result_win].wrap = false
		end
		if state.view == "standard" then
			vim.api.nvim_set_current_win(state.sql_win)
			vim.cmd("topleft vsplit")
			state.queries_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(state.queries_win, panel(state, "queries_buf"))
			vim.api.nvim_win_set_width(state.queries_win, math.max(12, math.floor(vim.o.columns * sizes.connections)))
			vim.wo[state.queries_win].wrap = false
			state.connections_win = vim.api.nvim_open_win(panel(state, "connections_buf"), true, {
				split = "below",
				win = state.queries_win,
			})
			vim.wo[state.connections_win].wrap = false
		end
	end
	vim.cmd("botright split")
	state.activity_win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(state.activity_win, panel(state, "activity_buf"))
	vim.api.nvim_win_set_height(state.activity_win, 1)
	vim.wo[state.activity_win].winbar = ""
	vim.wo[state.activity_win].winfixheight = true
	vim.wo[state.activity_win].wrap = false
	vim.wo[state.activity_win].number = false
	vim.wo[state.activity_win].relativenumber = false
	vim.wo[state.activity_win].signcolumn = "no"
	if valid(state.result_win, "win") then
		vim.api.nvim_win_set_height(state.result_win, math.max(3, math.floor(vim.o.lines * sizes.results)))
	end
	map(state.side_buf, "C", M.column_limit)
	map(state.side_buf, "<CR>", function()
		M.inspect(nil, state)
	end)
	map(state.side_buf, "J", function()
		M.insert_join(selected_object(state))
	end)
	map(state.side_buf, "gn", function()
		M.notes(selected_object(state))
	end)
	map(state.side_buf, "b", function()
		M.browse(selected_object(state))
	end)
	map(state.side_buf, "B", function()
		M.browse(selected_object(state), true)
	end)
	map(state.side_buf, "q", function()
		vim.api.nvim_set_current_win(state.sql_win)
		if state.compact then
			vim.api.nvim_win_set_buf(state.sql_win, state.active or M.empty(state))
		end
	end)
	map(state.result_buf or panel(state, "result_buf"), "<CR>", M.expand_row)
	map(state.result_buf, "y", M.copy_row)
	map(state.result_buf, "e", M.export)
	map(state.result_buf, "q", function()
		if valid(state.result_popup, "win") and vim.api.nvim_get_current_win() == state.result_popup then
			vim.api.nvim_win_close(state.result_popup, true)
			state.result_popup = nil
			return
		end
		vim.api.nvim_set_current_win(state.sql_win)
		if state.compact then
			vim.api.nvim_win_set_buf(state.sql_win, state.active or M.empty(state))
		end
	end)
	map(state.result_buf, "<Esc>", function()
		if valid(state.result_popup, "win") and vim.api.nvim_get_current_win() == state.result_popup then
			vim.api.nvim_win_close(state.result_popup, true)
			state.result_popup = nil
		end
	end)
	for key, direction in pairs({ H = "left", L = "right", J = "down", K = "up" }) do
		map(state.result_buf, key, function()
			M.move_cell(direction)
		end)
	end
	vim.api.nvim_set_current_win(state.sql_win)
	local active = console(state)
	if active and active.cursor then
		pcall(vim.api.nvim_win_set_cursor, state.sql_win, active.cursor)
	end
	M.refresh_view(state)
	M.restore_connection(state)
end

function M.buffer_visible(buf)
	for _, state in pairs(M.states) do
		if state.tab == vim.api.nvim_get_current_tabpage() then
			return state.consoles[buf] ~= nil
		end
	end
	if vim.b[buf].fox_query_root then
		return false
	end
	return nil
end

function M.buffer_label(buf)
	local state = M.states[vim.b[buf].fox_query_root or ""]
	local item = state and state.consoles[buf]
	if item then
		return (item.profile and item.profile.id or "SQL")
			.. "/"
			.. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
	end
end

function M.toggle_tab_pin(buf)
	local state = M.states[vim.b[buf].fox_query_root or ""]
	if not state or not state.consoles[buf] then
		return
	end
	local document = vim.b[buf].fox_query_document
	local pins = vim.deepcopy(state.tab_pins)
	local index = vim.fn.index(pins, document)
	if index >= 0 then
		table.remove(pins, index + 1)
	else
		pins[#pins + 1] = document
	end
	local ok, err = storage.save(state.root, "private/tab-pins.json", pins)
	if not ok then
		notify("Cannot save Query tab pins: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	state.tab_pins = pins
	require("fox.ui.tabline").set_pin(buf, index < 0)
end

function M.pin()
	local state = M.state()
	if state.pinned then
		if valid(state.pinned.buf, "buf") then
			pcall(vim.api.nvim_buf_del_extmark, state.pinned.buf, ns, state.pinned.id)
		end
		state.pinned = nil
	elseif valid(state.sql_win, "win") and state.active then
		local cursor = vim.api.nvim_win_get_cursor(state.sql_win)
		state.pinned = {
			buf = state.active,
			id = vim.api.nvim_buf_set_extmark(state.active, ns, cursor[1] - 1, cursor[2], { right_gravity = false }),
		}
	end
	M.refresh_view(state)
end

function M.close_buffer(buf, force)
	local state = M.states[vim.b[buf].fox_query_root]
	if not state then
		return
	end
	local item = state.consoles[buf]
	if item and item.client and item.client.busy then
		notify("Cancel or wait before closing this query", vim.log.levels.WARN)
		return
	end
	if vim.bo[buf].modified and not force then
		M.select(
			{ "Save and close", "Discard and close", "Cancel" },
			{ prompt = "Unsaved query document" },
			function(choice)
				if choice == "Save and close" then
					local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
						vim.cmd("write")
					end)
					if not ok then
						notify(tostring(err), vim.log.levels.ERROR)
						return
					end
					M.close_buffer(buf, true)
				elseif choice == "Discard and close" then
					M.close_buffer(buf, true)
				end
			end
		)
		return
	end
	if not vim.b[buf].fox_query_document then
		if valid(state.sql_win, "win") then
			vim.api.nvim_set_current_win(state.sql_win)
		end
		return
	end
	if item and item.client then
		item.client:close()
	end
	state.consoles[buf] = nil
	if state.active == buf then
		state.active = nil
	end
	local _, replacement = console(state)
	if not replacement then
		replacement = M.empty(state)
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			vim.api.nvim_win_set_buf(win, replacement)
		end
	end
	vim.api.nvim_buf_delete(buf, { force = true })
	M.refresh_view(state)
end

function M.choose_dialect(state, callback)
	local dialect = require("fox.langs.sql.dialect")
	local options, err = dialect.options(state.root)
	if not options then
		notify(err, vim.log.levels.ERROR)
		return
	end
	M.select(options, {
		prompt = "SQL dialect",
		format_item = function(name)
			return dialect.names[name]
		end,
	}, function(name)
		if M.states[state.root] == state and storage.root() == state.root then
			callback(name)
		end
	end)
end

function M.create(relative)
	local state = M.state()
	M.choose_dialect(state, function(name)
		if name then
			M.new(relative, name)
		end
	end)
end

function M.dialect(name)
	local state = M.state(vim.b.fox_sql_root or vim.b.fox_query_root)
	local buf = vim.api.nvim_get_current_buf()
	if vim.bo[buf].filetype ~= "sql" then
		local _
		_, buf = console(state)
	end
	if not buf then
		return
	end
	local function apply(choice)
		if not choice or not valid(buf, "buf") then
			return
		end
		local ok, err = require("fox.langs.sql.dialect").set(buf, choice, state.root)
		if not ok then
			notify(err, vim.log.levels.ERROR)
			return
		end
		require("fox.langs.sql.diagnostics").check(buf)
		M.refresh_view(state)
	end
	if name and name ~= "" then
		apply(name)
	else
		M.choose_dialect(state, apply)
	end
end

function M.syntax_check()
	local state = M.state(vim.b.fox_sql_root or vim.b.fox_query_root)
	local settings, err = storage.load(state.root, "settings.json", {})
	if not settings then
		notify(err, vim.log.levels.ERROR)
		return
	end
	settings.sql_syntax_check = settings.sql_syntax_check ~= true
	local saved, save_err = storage.save(state.root, "settings.json", settings)
	if not saved then
		notify(save_err, vim.log.levels.ERROR)
		return
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].fox_sql_root == state.root then
			require("fox.langs.sql.diagnostics").check(buf)
		end
	end
	notify(
		"General SQL syntax checking "
			.. (settings.sql_syntax_check and "on" or "off")
			.. "; dialect checks always on"
			.. (
				settings.sql_syntax_check
					and vim.fn.executable("sqlfluff") ~= 1
					and ". Install SQLFluff using :LanguageManager"
				or ""
			)
	)
end

function M.new(relative, dialect)
	local state = M.state()
	if relative and (not relative:match("%.sql$") or not require("fox.query.files").path(state.root, relative)) then
		notify("Use a relative .sql path inside the queries folder", vim.log.levels.ERROR)
		return
	end
	state.next_query = (state.next_query or 0) + 1
	relative = "queries/" .. (relative or ("query-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. state.next_query .. ".sql"))
	local buf = storage.document_buffer(state.root, relative, "sql")
	if dialect then
		local ok, err = require("fox.langs.sql.dialect").set(buf, dialect, state.root)
		if not ok then
			notify(err, vim.log.levels.ERROR)
		end
	end
	require("fox.langs.sql").attach(buf, state.root)
	state.consoles[buf] = state.consoles[buf] or { status = "idle", params = {} }
	require("fox.ui.tabline").set_pin(buf, vim.tbl_contains(state.tab_pins, relative))
	state.active = buf
	if state.consoles[buf].metadata then
		state.metadata = state.consoles[buf].metadata
	end
	if valid(state.sql_win, "win") then
		vim.api.nvim_set_current_win(state.sql_win)
		vim.api.nvim_win_set_buf(state.sql_win, buf)
	end
	vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
	query_keys(buf)
	for _, key in ipairs({ "<C-CR>", "<F5>", "\27[13;5u", "\27[27;5;13~" }) do
		vim.keymap.set({ "n", "i" }, key, function()
			M.run("statement")
		end, { buffer = buf, silent = true, desc = "Query: run statement" })
	end
	for _, key in ipairs({ "<C-S-CR>", "\27[13;6u", "\27[27;6;13~" }) do
		vim.keymap.set({ "n", "i" }, key, function()
			M.run_popup("statement")
		end, { buffer = buf, silent = true, desc = "Query: run statement in popup" })
	end
	for _, key in ipairs({ "<C-Space>", "<C-@>", "<C-x><C-o>", "\27[32;5u", "\27[27;5;32~" }) do
		vim.keymap.set("i", key, M.complete, { buffer = buf, silent = true, desc = "Query: database completion" })
	end
	M.refresh_view(state)
	M.restore_connection(state)
	return buf
end

function M.open()
	local state = M.state()
	M.draw_queries(state)
	M.select(state.query_files, { prompt = "Saved / open project queries" }, function(file)
		if file then
			M.new(file)
		end
	end)
end

function M.profile(action)
	local state = M.state()
	local active = console(state)
	if action == "disconnect" then
		if active and active.client then
			active.client:close()
			active.params = {}
			active.pending_run = nil
			active.status = "disconnected"
			M.refresh_view(state)
		end
		return
	end
	if not valid(state.tab, "tab") then
		M.show()
	end
	local buf = panel(state, "connections_buf")
	M.draw_connections(state)
	if valid(state.connections_win, "win") then
		vim.api.nvim_set_current_win(state.connections_win)
	elseif state.compact then
		vim.api.nvim_win_set_buf(state.sql_win, buf)
	else
		local width, height = layout.popup("connections", math.min(65, vim.o.columns - 4), math.min(20, vim.o.lines - 4))
		local _, win = require("fox.core.ui").float(buf, { title = " Connections ", width = width, height = height })
		layout.watch(win, "connections")
		require("fox.core.ui").close_on_keys(buf, win)
	end
end

function M.draw_connections(state)
	local buf = panel(state, "connections_buf")
	local profiles, err = storage.profiles(state.root)
	local active = console(state)
	local lines, objects = { "CONNECTIONS" }, {}
	if not profiles then
		lines[#lines + 1] = err
	end
	for _, profile in ipairs(profiles or {}) do
		local status = state.connection_status[profile.id]
		local selected = active and active.profile and active.profile.id == profile.id
		lines[#lines + 1] = (status == "failed" and "[Can't connect] " or selected and "* " or "  ")
			.. ({ sqlite = "", postgres = "", mysql = "" })[profile.engine]
			.. " "
			.. profile.id
		objects[#lines] = profile
	end
	if profiles and #profiles == 0 then
		lines[#lines + 1] = "No connections. Press a."
	end
	local height = valid(state.connections_win, "win") and vim.api.nvim_win_get_height(state.connections_win) or 0
	while #lines < height - 3 do
		lines[#lines + 1] = ""
	end
	vim.list_extend(lines, { "------", "a Add  e Edit  d Delete", "Enter Details  D Disconnect" })
	set_lines(buf, lines)
	local function selected()
		return objects[vim.api.nvim_win_get_cursor(0)[1]]
	end
	map(buf, "a", M.add_profile)
	map(buf, "<CR>", function()
		if selected() then
			M.connection_details(selected(), state)
		else
			M.add_profile()
		end
	end)
	map(buf, "e", function()
		if selected() then
			M.add_profile(selected())
		end
	end)
	map(buf, "d", function()
		if selected() then
			M.delete_profile(selected(), state)
		end
	end)
	map(buf, "D", function()
		M.profile("disconnect")
	end)
	map(buf, "q", function()
		if valid(state.sql_win, "win") then
			vim.api.nvim_set_current_win(state.sql_win)
			if state.compact then
				vim.api.nvim_win_set_buf(state.sql_win, state.active or M.empty(state))
			end
		end
	end)
end

function M.connection_details(profile, state)
	state = state or M.state()
	local lines = {}
	for _, key in ipairs({
		"id",
		"engine",
		"path",
		"host",
		"port",
		"database",
		"user",
		"schema",
		"schemas",
		"sslmode",
		"sslrootcert",
		"ssl_ca",
		"password_env",
	}) do
		local value = profile[key]
		if value ~= nil then
			lines[#lines + 1] = key
				.. ": "
				.. (type(value) == "table" and table.concat(value, ", ") or tostring(value)):gsub("[%c]", " ")
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Enter: connect | q / Esc: back"
	local buf, win = require("fox.core.ui").float({
		title = " Connection details ",
		lines = lines,
		width = math.min(80, vim.o.columns - 4),
		height = math.min(#lines, vim.o.lines - 6),
		close_keys = { "q", "<Esc>", "<C-c>" },
	})
	vim.b[buf].fox_query_root = state.root
	map(buf, "<CR>", function()
		vim.api.nvim_win_close(win, true)
		M.connect(profile, state)
	end)
end

function M.delete_profile(profile, state)
	state = state or M.state()
	for _, item in pairs(state.consoles) do
		if item.profile and item.profile.id == profile.id and item.client and item.client.busy then
			notify("Cancel or wait before deleting a busy connection", vim.log.levels.WARN)
			return
		end
	end
	M.select(
		{ "Delete connection", "Cancel" },
		{ prompt = "Delete profile " .. profile.id .. "? Database files and notes are kept." },
		function(choice)
			if choice ~= "Delete connection" then
				return
			end
			local profiles, err = storage.profiles(state.root)
			if not profiles then
				notify(err, vim.log.levels.ERROR)
				return
			end
			profiles = vim.tbl_filter(function(item)
				return item.id ~= profile.id
			end, profiles)
			local ok, save_err = storage.save(state.root, "connections.json", { profiles = profiles })
			if not ok then
				notify(save_err, vim.log.levels.ERROR)
				return
			end
			for _, item in pairs(state.consoles) do
				if item.profile and item.profile.id == profile.id then
					if item.client then
						item.client:close()
					end
					item.client, item.profile, item.metadata, item.params = nil, nil, nil, {}
					item.restore_attempted = true
				end
			end
			state.connection_status[profile.id] = nil
			M.refresh_view(state)
		end
	)
end

local function connection_profile(state, item)
	if item.profile then
		return item.profile
	end
	local profiles = storage.profiles(state.root)
	local saved = storage.load(state.root, "private/session.json", {})
	if not profiles or type(saved) ~= "table" then
		return
	end
	if saved.profile then
		for _, profile in ipairs(profiles) do
			if profile.id == saved.profile and storage.fingerprint(profile) == saved.fingerprint then
				return profile
			end
		end
	elseif #profiles == 1 then
		return profiles[1]
	end
end

function M.restore_connection(state)
	local item = console(state)
	if not item or item.profile or item.restore_attempted or state.restore_disconnected then
		return
	end
	item.restore_attempted = true
	local profile = connection_profile(state, item)
	if profile then
		M.connect(profile, state)
	end
end

function M.add_profile(existing)
	local state, profile, password = M.state(), {}, nil
	if existing then
		for _, item in pairs(state.consoles) do
			if item.profile and item.profile.id == existing.id and item.client and item.client.busy then
				notify("Cancel or wait before editing a busy connection", vim.log.levels.WARN)
				return
			end
		end
	end
	M.select({ "sqlite", "mysql", "postgres" }, {
		prompt = "Database engine",
		format_item = function(engine)
			return engine == "mysql" and "MySQL / MariaDB" or engine
		end,
	}, function(engine)
		if not engine then
			return
		end
		profile.engine = engine
		local fields = engine == "sqlite" and { "id", "path" }
			or { "id", "host", "port", "database", "user", "password_env", "password" }
		local defaults = { host = "127.0.0.1", port = engine == "mysql" and "3306" or "5432" }
		if existing then
			profile = vim.tbl_extend("force", existing, { engine = engine })
			profile.path = engine == "sqlite" and existing.path or nil
			defaults = vim.tbl_extend("force", defaults, existing)
		end
		local function ask(index)
			local key = fields[index]
			if not key then
				local ok, err = storage.validate(profile)
				if not ok then
					notify(err, vim.log.levels.ERROR)
					return
				end
				local profiles, load_err = storage.profiles(state.root)
				if not profiles then
					notify(load_err, vim.log.levels.ERROR)
					return
				end
				for _, entry in ipairs(profiles) do
					if entry.id == profile.id and not (existing and entry.id == existing.id) then
						notify("Profile id already exists", vim.log.levels.ERROR)
						return
					end
				end
				local replaced = false
				for at, entry in ipairs(profiles) do
					if existing and entry.id == existing.id then
						profiles[at], replaced = profile, true
					end
				end
				if not replaced then
					profiles[#profiles + 1] = profile
				end
				if password ~= nil then
					local saved, save_err = storage.password(state.root, profile, password)
					if not saved then
						notify(save_err, vim.log.levels.ERROR)
						return
					end
				end
				storage.prepare(state.root)
				local saved, save_err = storage.save(state.root, "connections.json", { profiles = profiles })
				if not saved then
					notify(save_err, vim.log.levels.ERROR)
					return
				end
				if existing then
					for _, item in pairs(state.consoles) do
						if item.profile and item.profile.id == existing.id then
							if item.client then
								item.client:close()
							end
							item.client, item.profile, item.metadata, item.params = nil, nil, nil, {}
						end
					end
				end
				M.connect(profile, state)
				return
			end
			if key == "path" then
				require("lazy").load({ plugins = { "telescope.nvim" } })
				require("plugins.fox.tools.file_explorer").open_desktop_explorer({
					path = state.root,
					prompt_title = " Select SQLite database ",
					on_select_file = function(filename)
						if vim.fn.filereadable(filename) ~= 1 then
							notify("Choose an existing readable SQLite database", vim.log.levels.WARN)
							return
						end
						profile.path = filename
						ask(index + 1)
					end,
				})
				return
			end
			if key == "password" then
				if not profile.password_env then
					local ok, value = pcall(vim.fn.inputsecret, "Password (saved locally; blank keeps existing): ")
					if not ok then
						return
					end
					if value == "" and existing then
						local load_err
						password, load_err = storage.password(state.root, existing)
						if load_err then
							notify(load_err, vim.log.levels.ERROR)
							return
						end
					else
						password = value
					end
				end
				ask(index + 1)
				return
			end
			vim.ui.input({
				prompt = key == "password_env" and "Password environment variable (blank: save password locally): "
					or key .. ": ",
				default = defaults[key] ~= nil and tostring(defaults[key]) or nil,
			}, function(value)
				if value == nil then
					return
				end
				if key == "port" then
					profile[key] = tonumber(value)
				else
					profile[key] = value ~= "" and value or nil
				end
				ask(index + 1)
			end)
		end
		ask(1)
	end)
end

function M.connect(profile, state)
	state = state or M.state()
	if M.states[state.root] ~= state or state.root ~= storage.root() then
		notify("Project changed; choose the connection again", vim.log.levels.WARN)
		return
	end
	local count = 0
	for _, entry in pairs(state.consoles) do
		if entry.client and (entry.client.connected or entry.client.connecting) then
			count = count + 1
		end
	end
	local item, buf = console(state)
	if not item then
		M.new()
		item, buf = console(state)
	end
	if item.client and item.client.busy then
		notify("Console is busy; cancel or wait before changing connections", vim.log.levels.WARN)
		return
	end
	if count >= 4 and not (item.client and item.client.connected) then
		notify("Project limit: four database sessions; disconnect an idle console first", vim.log.levels.WARN)
		return
	end
	if item.client then
		item.client:close()
	end
	item.params, item.profile, item.restore_attempted = {}, vim.deepcopy(profile), true
	item.error_detail = nil
	state.restore_disconnected = false
	item.auto_sql, item.auto_connection = nil, nil
	state.connection_status[profile.id] = "connecting"
	item.result, item.result_lines, item.result_label, item.result_table, item.executed_sql = nil, nil, nil, nil, nil
	local fingerprint = storage.fingerprint(profile)
	local cached, cache_err = storage.cache(state.root, fingerprint)
	if cache_err then
		notify(cache_err, vim.log.levels.WARN)
	end
	state.metadata = cached or { tables = {}, relations = {} }
	item.metadata = state.metadata
	M.note_badges(state, profile)
	local secret = profile.password_env and vim.env[profile.password_env]
	if profile.engine ~= "sqlite" and secret == nil then
		local load_err
		secret, load_err = storage.password(state.root, profile)
		if load_err then
			notify(load_err, vim.log.levels.ERROR)
			return
		end
	end
	if profile.engine ~= "sqlite" and secret == nil then
		local ok, value = pcall(vim.fn.inputsecret, "Database password (saved locally in .foxnvim/query/private/): ")
		if not ok then
			return
		end
		local saved, save_err = storage.password(state.root, profile, value)
		if not saved then
			notify(save_err, vim.log.levels.ERROR)
			return
		end
		secret = value
	end
	local bridge_profile = vim.tbl_extend("force", profile, { password = secret })
	item.status = "connecting"
	item.client = client.new(state.root, function(response)
		item.status = "fetching " .. response.rows .. " rows"
		M.refresh_view(state)
	end)
	local connection = item.client
	connection.connecting = true
	connection:request("connect", { profile = bridge_profile, root = state.root }, function(result, err)
		connection.connecting = false
		bridge_profile.password = nil
		if item.client ~= connection or not valid(buf, "buf") then
			connection:close()
			return
		end
		if err then
			item.pending_run = nil
			item.status = err
			state.connection_status[profile.id] = "failed"
			local error_buf, error_win = require("fox.core.ui").float({
				title = " Connection failed ",
				width = math.min(72, vim.o.columns - 4),
				height = 6,
				lines = {
					"Can't connect: " .. profile.id,
					tostring(err),
					"",
					"",
					"Connection sidebar: e edit, Enter retry; q closes this message.",
				},
			})
			vim.b[error_buf].fox_query_root = state.root
			require("fox.core.ui").close_on_keys(error_buf, error_win)
		else
			connection.connected, item.status = true, "connected | " .. result.engine .. " " .. result.version
			state.connection_status[profile.id] = "connected"
			storage.prepare(state.root)
			local saved, save_err = storage.save(
				state.root,
				"private/session.json",
				{ profile = profile.id, fingerprint = storage.fingerprint(profile) }
			)
			if not saved then
				notify(save_err, vim.log.levels.WARN)
			end
			item.syntax = result.syntax
			M.refresh_metadata(state, item)
		end
		M.refresh_view(state)
	end)
	M.refresh_view(state)
end

function M.refresh_metadata(state, item)
	state = state or M.state()
	item = item or console(state)
	if not item or not item.client or not item.client.connected then
		notify("Connect first", vim.log.levels.WARN)
		return
	end
	if item.client.busy then
		notify("Console is busy; refresh after completion", vim.log.levels.WARN)
		return
	end
	local connection, fingerprint = item.client, storage.fingerprint(item.profile)
	connection.busy, item.status = true, "reading schema metadata (no table rows)"
	connection:request("metadata", {}, function(result, err)
		connection.busy = false
		if err then
			item.status = err
		else
			item.metadata = result
			if console(state) == item then
				state.metadata = result
				M.note_badges(state, item.profile)
			end
			storage.prepare(state.root)
			local ok, save_err = storage.save(state.root, "cache/" .. fingerprint .. ".json", result)
			item.status = ok and "ready | " .. #result.tables .. " visible tables/views"
				or "ready; cache not saved: " .. tostring(save_err)
		end
		M.refresh_view(state)
		local pending = item.pending_run
		item.pending_run = nil
		if pending then
			pending()
		elseif item.auto_pending then
			item.auto_pending = nil
			M.autorun(state)
		end
	end)
end

function M.autorun(state)
	state = state or M.state()
	if
		not state.autorun
		or state.mode ~= "query"
		or state.root ~= storage.root()
		or not valid(state.tab, "tab")
		or vim.api.nvim_get_current_tabpage() ~= state.tab
	then
		return
	end
	local item = console(state)
	if not item or not item.client or not item.client.connected then
		return
	end
	local text, offset = text_at_cursor(state)
	if #text > 128 * 1024 then
		return
	end
	local engine = require("fox.langs.sql.dialect").read(state.active)
		or vim.b[state.active].fox_sql_dialect
		or item.syntax
		or item.profile.engine
	local statement = sql.scope(text, offset, "statement", nil, engine)
	if not statement then
		return
	end
	local tokens, incomplete = sql.tokens(statement, engine)
	if incomplete or not tokens[1] or tokens[1].kind ~= "word" or tokens[1].upper ~= "SELECT" then
		return
	end
	for _, edge in ipairs(sql.analyze(statement, item.metadata or state.metadata).edges) do
		if edge.kind:upper() ~= "CROSS" and (not edge.predicate or vim.trim(edge.predicate) == "") then
			return
		end
	end
	if item.auto_sql == statement and item.auto_connection == item.client then
		return
	end
	if item.client.busy then
		item.auto_pending = true
		return
	end
	item.auto_sql, item.auto_connection, item.auto_pending = statement, item.client, nil
	M.run("statement", statement, nil, nil, true)
end

function M.run(kind, supplied_sql, supplied_params, source_table, automatic, popup)
	if kind and not vim.tbl_contains({ "statement", "selection", "section", "file" }, kind) then
		notify("Choose statement, selection, section, or file", vim.log.levels.WARN)
		return
	end
	local state = M.state()
	local item, buf = console(state)
	local connected = item and item.client and item.client.connected
	if not connected and automatic then
		return
	end
	local profile = item and connection_profile(state, item)
	if not profile then
		M.profile()
		notify("Select a connection and press Enter, then run this SQL again")
		return
	end
	if connected and item.client.busy then
		notify("Console is busy; cancel or wait", vim.log.levels.WARN)
		return
	end
	local text, offset = text_at_cursor(state)
	local selection
	if kind == "selection" then
		if vim.fn.visualmode() == "\22" then
			notify("Block selections are unsupported", vim.log.levels.WARN)
			return
		end
		local first, last = vim.api.nvim_buf_get_mark(buf, "<"), vim.api.nvim_buf_get_mark(buf, ">")
		if first[1] == 0 or last[1] == 0 then
			notify("Select SQL first", vim.log.levels.WARN)
			return
		end
		local lines = vim.api.nvim_buf_get_lines(buf, first[1] - 1, last[1], false)
		if vim.fn.visualmode() ~= "V" then
			lines[#lines] = lines[#lines]:sub(1, last[2] + 1)
			lines[1] = lines[1]:sub(first[2] + 1)
		end
		selection = table.concat(lines, "\n")
	end
	local query, scope_err
	if supplied_sql then
		query = supplied_sql
	else
		local engine = require("fox.langs.sql.dialect").read(buf)
			or vim.b[buf].fox_sql_dialect
			or item.syntax
			or profile.engine
		query, scope_err = sql.scope(text, offset, kind or "statement", selection, engine)
	end
	if not query then
		notify(scope_err, vim.log.levels.WARN)
		return
	end
	if not connected then
		item.pending_run = function()
			if
				M.states[state.root] == state
				and storage.root() == state.root
				and console(state) == item
				and valid(buf, "buf")
				and item.client
				and item.client.connected
				and storage.fingerprint(item.profile) == storage.fingerprint(profile)
			then
				M.run(kind, query, supplied_params, source_table, automatic, popup)
			end
		end
		if not (item.client and item.client.connecting) then
			M.connect(profile, state)
			if not (item.client and item.client.connecting) then
				item.pending_run = nil
			end
		end
		return
	end
	local connection = item.client
	connection.busy, item.status = true, "validating " .. (kind or "statement")
	connection:request("prepare", { sql = query }, function(prepared, prepare_err, prepare_detail)
		if prepare_err then
			connection.busy = false
			item.status = prepare_err
			item.error_detail = prepare_detail and prepare_detail ~= vim.NIL and prepare_detail or prepare_err
			notify(item.error_detail, vim.log.levels.ERROR)
			M.refresh_view(state)
			if item.auto_pending then
				item.auto_pending = nil
				M.autorun(state)
			end
			return
		end
		if automatic and prepared.parameters > 0 then
			connection.busy, item.status = false, "Parameters needed: Ctrl+Enter / F5 runs with values"
			M.refresh_view(state)
			return
		end
		item.auto_sql, item.auto_connection = query, connection
		local params = supplied_params or {}
		local function execute()
			if item.client ~= connection or not valid(buf, "buf") then
				connection.busy = false
				return
			end
			item.params, item.executed_sql = params, query
			item.error_detail = nil
			item.started, item.status = (vim.uv or vim.loop).hrtime(), "running " .. prepared.statements .. " statement(s)"
			item.execution = (item.execution or 0) + 1
			local execution = item.execution
			local result_label = "run #"
				.. execution
				.. " | "
				.. item.profile.id
				.. " | "
				.. os.date("%H:%M:%S")
				.. " | "
				.. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
			connection:request("execute", { sql = query, params = params }, function(result, err, detail)
				connection.busy = false
				item.error_detail = err and (detail and detail ~= vim.NIL and detail or err) or nil
				if err then
					notify(item.error_detail, vim.log.levels.ERROR)
				end
				local seconds = ((vim.uv or vim.loop).hrtime() - item.started) / 1e9
				item.status = (err or "completed") .. string.format(" | %.2fs", seconds)
				if result then
					item.result = result
					item.result_lines, item.result_label = nil, result_label
					item.result_table = source_table
					if result.disconnected then
						connection.connected = false
					end
				end
				M.refresh_view(state)
				if result and popup then
					M.results_popup(state, item)
				end
				if item.auto_pending then
					item.auto_pending = nil
					M.autorun(state)
				end
			end)
			local function elapsed()
				if item.execution ~= execution or not connection.busy or item.client ~= connection then
					return
				end
				item.status = string.format("running / fetching | %.1fs", ((vim.uv or vim.loop).hrtime() - item.started) / 1e9)
				if valid(state.activity_buf, "buf") then
					M.draw_activity(state)
				end
				vim.defer_fn(elapsed, 500)
			end
			vim.defer_fn(elapsed, 500)
			M.refresh_view(state)
		end
		if supplied_params then
			execute()
			return
		end
		for index = 1, prepared.parameters do
			local previous = item.executed_sql == query and item.params[index] or nil
			local default = previous == vim.NIL and "NULL" or previous and tostring(previous) or ""
			local ok, value =
				pcall(vim.fn.inputsecret, "Parameter " .. index .. " (NULL/null; blank/empty; Ctrl-C cancels): ", default)
			if not ok then
				connection.busy = false
				item.status = "input canceled"
				M.refresh_view(state)
				return
			end
			params[index] = value == "NULL" and vim.NIL or value:gsub("^text:", "")
		end
		if prepared.parameters > 0 then
			M.select({ "Run with these RAM parameters", "Cancel" }, {
				prompt = "Execute "
					.. prepared.statements
					.. " statement(s) with "
					.. prepared.parameters
					.. " bound value(s)?",
			}, function(choice)
				if choice == "Run with these RAM parameters" then
					execute()
				else
					connection.busy = false
					item.status = "input canceled"
					M.refresh_view(state)
				end
			end)
		else
			execute()
		end
	end)
	M.refresh_view(state)
end

function M.cancel()
	local state, item = M.state(), console(M.state())
	if item and item.client and item.client.busy then
		item.auto_pending = nil
		item.auto_revision = (item.auto_revision or 0) + 1
		item.status = "cancellation requested; reconnect may be required"
		item.client:cancel()
		M.refresh_view(state)
	end
end

function M.notes(item, action)
	local state = M.state()
	local document = vim.b.fox_query_document
	local opened = action == "delete" and type(document) == "string" and document:match("^notes/")
	if opened then
		item = { key = vim.b.fox_query_note_key }
	end
	item = item or selected_object(state)
	local active = console(state)
	if not item or not item.key or not active or not active.profile then
		notify("Select a table with a connection first", vim.log.levels.WARN)
		return
	end
	local key = storage.fingerprint(active.profile) .. "/" .. vim.fn.sha256(item.key):sub(1, 24) .. ".md"
	local relative = opened and document or "notes/" .. key
	if action == "delete" then
		local path = storage.path(state.root, relative)
		local buf = vim.fn.bufnr(path)
		local function unchanged()
			if valid(buf, "buf") then
				if vim.bo[buf].modified then
					notify("Save the note before deleting it", vim.log.levels.WARN)
					return false
				end
				if (storage.read(state.root, relative) or "") ~= vim.b[buf].fox_query_disk then
					notify("Note changed externally; reload it before deleting", vim.log.levels.WARN)
					return false
				end
			end
			return true
		end
		if not unchanged() then
			return
		end
		M.select({ "Delete note", "Cancel" }, { prompt = "Delete note for " .. item.key .. "?" }, function(choice)
			if choice ~= "Delete note" or not unchanged() then
				return
			end
			local ok, err, code = (vim.uv or vim.loop).fs_unlink(path)
			if not ok and code ~= "ENOENT" then
				notify(err, vim.log.levels.ERROR)
				return
			end
			if valid(buf, "buf") then
				if valid(state.sql_win, "win") and valid(state.active, "buf") then
					vim.api.nvim_win_set_buf(state.sql_win, state.active)
				end
				vim.api.nvim_buf_delete(buf, { force = false })
			end
			M.note_badges(state, active.profile)
			M.refresh_view(state)
		end)
		return
	end
	state.note_keys = state.note_keys or {}
	state.note_keys[item.key] = true
	local buf = show_document(state, relative, "markdown")
	vim.b[buf].fox_query_note_key = item.key
end

function M.note_badges(state, profile)
	local found = {}
	for _, filename in
		ipairs(vim.fn.glob(storage.path(state.root, "notes/" .. storage.fingerprint(profile) .. "/*.md"), false, true))
	do
		found[vim.fn.fnamemodify(filename, ":t:r")] = true
	end
	state.note_keys = {}
	for _, item in ipairs(state.metadata.tables or {}) do
		if found[vim.fn.sha256(item.key):sub(1, 24)] then
			state.note_keys[item.key] = true
		end
	end
end

function M.run_popup(kind)
	M.run(kind or "statement", nil, nil, nil, nil, true)
end

function M.browse(item, popup)
	local state, active = M.state(), console(M.state())
	item = item or selected_object(state)
	if not item or not active or not active.profile then
		notify("Select a table first", vim.log.levels.WARN)
		return
	end
	local name = item.schema and sql.quote(item.schema, active.profile.engine) .. "." or ""
	name = name .. sql.quote(item.name, active.profile.engine)
	local ordering = {}
	for _, column in ipairs(item.columns) do
		if column.pk then
			ordering[#ordering + 1] = sql.quote(column.name, active.profile.engine)
		end
	end
	local order = #ordering > 0 and (" ORDER BY " .. table.concat(ordering, ", ")) or ""
	M.run("statement", "SELECT * FROM " .. name .. order .. " LIMIT 200", {}, item.key, nil, popup)
end

function M.insert_join(target)
	local state, active = M.state(), console(M.state())
	local text, offset = text_at_cursor(state)
	local statement, err = sql.scope(text, offset, "statement", nil, state.metadata.syntax or state.metadata.engine)
	if not statement or not active or not active.profile then
		notify(err or "Choose a connected SQL statement", vim.log.levels.WARN)
		return
	end
	local graph = sql.analyze(statement, state.metadata)
	local candidates = sql.join_candidates(state.metadata, graph)
	if target then
		candidates = vim.tbl_filter(function(candidate)
			return candidate.target == target.key
		end, candidates)
	end
	local function choose(candidate)
		if not candidate then
			return
		end
		vim.ui.input({
			prompt = "Target alias: ",
			default = sql.suggest_alias(candidate.target_table or { name = candidate.target }, graph),
		}, function(alias)
			if not alias then
				return
			end
			for _, node in ipairs(graph.nodes) do
				if node.alias:lower() == alias:lower() then
					notify("Alias already used", vim.log.levels.WARN)
					return
				end
			end
			local joins = {}
			for _, kind in ipairs({ "INNER", "LEFT" }) do
				local join, join_err = sql.join_sql(candidate, alias, kind, active.profile.engine)
				if not join then
					notify(join_err, vim.log.levels.WARN)
					return
				end
				joins[#joins + 1] = join
			end
			M.select(joins, { prompt = "Insert JOIN (Enter inserts the selected SQL; Esc cancels)" }, function(join)
				if not join then
					return
				end
				local current = text_at_cursor(state)
				if current ~= text then
					notify("SQL changed while reviewing; choose the JOIN again", vim.log.levels.WARN)
					return
				end
				local statements = sql.statements(text, state.metadata.syntax or state.metadata.engine)
				local first, last = 1, #text + 1
				for _, entry in ipairs(statements or {}) do
					if offset >= entry.first and offset <= entry.last then
						first, last = entry.first, entry.last
						break
					end
				end
				local at = last
				for _, token in ipairs(sql.tokens(statement)) do
					if
						token.kind == "word"
						and vim.tbl_contains({ "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "UNION" }, token.upper)
					then
						at = first + token.first - 1
						break
					end
				end
				local prefix = text:sub(1, at - 1)
				local row = select(2, prefix:gsub("\n", ""))
				local column = #(prefix:match("[^\n]*$") or "")
				vim.api.nvim_buf_set_text(state.active, row, column, row, column, { "", join, "" })
				M.refresh_view(state)
			end)
		end)
	end
	if #candidates == 1 then
		choose(candidates[1])
	else
		M.select(candidates, { prompt = "Choose foreign key mapping", format_item = sql.join_label }, choose)
	end
end

function M.graph(all)
	local state = M.state()
	local key = not all and state.selected or nil
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.b[buf].fox_query_root = state.root
	query_keys(buf)
	local width, height = layout.popup("relationships", math.max(1, vim.o.columns - 4), math.max(1, vim.o.lines - 6))
	local _, win = require("fox.core.ui").float(buf, { title = " Relationships ", width = width, height = height })
	layout.watch(win, "relationships")
	vim.wo[win].wrap = false
	local drawn_width
	local function draw()
		drawn_width = vim.api.nvim_win_get_width(win)
		local lines, objects, highlights = render.map(state.metadata, key, state.depth, drawn_width, state.diagram_columns)
		set_lines(buf, lines)
		set_highlights(buf, highlights)
		vim.api.nvim_win_call(win, function()
			vim.fn.winrestview({ topline = 1, lnum = #lines >= 5 and 5 or 1, col = 2, leftcol = 0 })
		end)
		map(buf, "<CR>", function()
			local item = render.object_at(objects, vim.api.nvim_win_get_cursor(win)[1], vim.fn.virtcol(".") - 1)
			if item then
				key, state.selected = item.key, item.key
				draw()
			end
		end)
	end
	draw()
	local resize = vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			if valid(win, "win") and vim.api.nvim_win_get_width(win) ~= drawn_width then
				draw()
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		pattern = tostring(win),
		once = true,
		callback = function()
			pcall(vim.api.nvim_del_autocmd, resize)
		end,
	})
	map(buf, "+", function()
		state.depth = math.min(8, state.depth + 1)
		draw()
	end)
	map(buf, "-", function()
		state.depth = math.max(1, state.depth - 1)
		draw()
	end)
	map(buf, "q", function()
		vim.api.nvim_win_close(win, true)
	end)
	map(buf, "i", function()
		if key then
			M.inspect(sql.table(state.metadata, key), state)
		end
	end)
end

function M.results_popup(state, item)
	state = state or M.state()
	item = item or console(state)
	if
		not valid(state.tab, "tab")
		or vim.api.nvim_get_current_tabpage() ~= state.tab
		or console(state) ~= item
		or not item
		or not item.result
	then
		return
	end
	M.refresh_view(state)
	if valid(state.result_popup, "win") then
		vim.api.nvim_win_close(state.result_popup, true)
	end
	local _, win = require("fox.core.ui").float(panel(state, "result_buf"), {
		width = 0.9,
		height = 0.9,
		title = " Query results | q / Esc close ",
	})
	state.result_popup = win
	vim.wo[win].wrap = false
	result_header(state)
end

function M.results()
	local state = M.state()
	if not valid(state.sql_win, "win") then
		M.show()
		state = M.state()
	end
	if state.compact then
		vim.api.nvim_win_set_buf(state.sql_win, panel(state, "result_buf"))
		M.refresh_view(state)
		return
	end
	if not valid(state.result_win, "win") then
		vim.api.nvim_set_current_win(state.sql_win)
		vim.cmd("belowright split")
		state.result_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.result_win, panel(state, "result_buf"))
	else
		vim.api.nvim_set_current_win(state.result_win)
	end
	M.refresh_view(state)
end

function M.focus_panel(kind)
	local state = M.state()
	if not valid(state.sql_win, "win") then
		M.show()
		state = M.state()
	end
	local buf = panel(state, kind .. "_buf")
	local win = state[kind .. "_win"]
	if state.compact and kind ~= "activity" then
		win = state.sql_win
	elseif not valid(win, "win") then
		vim.api.nvim_set_current_win(state.sql_win)
		vim.cmd("belowright split")
		win = vim.api.nvim_get_current_win()
		state[kind .. "_win"] = win
	end
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
	M.refresh_view(state)
end

function M.help()
	local width, height = layout.popup("help", math.min(78, vim.o.columns - 4), math.min(18, vim.o.lines - 4))
	local buf, win = require("fox.core.ui").float({
		width = width,
		height = height,
		title = " FoxQuerier ",
		lines = {
			"F3: Editor / Query | Shift+F3 or gV: toggle diagram | gC: connections sidebar",
			"Ctrl+Enter or F5: run (Normal / Insert); Ctrl+Space or Ctrl+X Ctrl+O: complete (Insert)",
			"Ctrl+Shift+Enter: run in a 90% results popup; B: browse table in popup; q / Esc: close popup",
			"Ctrl+h/j/k/l: focus pane | gN: new query | gE: explorer/diagram",
			"Connections pane: a add, e edit, d delete profile, Enter connect, D disconnect",
			"FoxQueryNew / FoxQueryOpen: SQL tabs; :write saves locally",
			"FoxQueryRun statement / selection / section / file",
			"FoxQueryCancel: cancel; reconnect if session is uncertain",
			"FoxQueryResults / FoxQueryActivity: results / submitted SQL",
			"Explorer/diagram: Enter inspect, J Insert JOIN, C column limit, b browse; / ? n N search; gn notes",
			"SQL files: Enter opens/toggles folders; a SQL, A folder, r rename, d delete; Alt+h/l tabs",
			"Status: click/y copies; Enter error details",
			"Results: H/L columns, J/K rows, Enter expand row, y copy, e export, gR follow FK",
			"Map: / native search, Enter recenter, +/- depth, zh/zl pan, q back",
			"Diagram markers: * selected, k JOIN, f filter, ? candidate FK; dim unused",
			"Parameters: Ctrl-C cancels; NULL is null; text:NULL is literal text",
			"Workspaces: save SQL first; explicit saves restore disconnected",
			"Manual execution by default; FoxQueryAutoRun explicitly enables automatic SELECT.",
		},
	})
	vim.b[buf].fox_query_root = M.state().root
	layout.watch(win, "help")
	require("fox.core.ui").close_on_keys(buf, win)
end

function M.error_details()
	local item = console(M.state())
	if not item or not item.error_detail then
		notify("No execution error details available")
		return
	end
	local buf, win = require("fox.core.ui").float({
		width = math.min(90, vim.o.columns - 4),
		height = math.min(20, vim.o.lines - 4),
		title = " Database error details (RAM only) ",
		lines = vim.split(item.error_detail, "\n", { plain = true }),
	})
	vim.b[buf].fox_query_root = M.state().root
	require("fox.core.ui").close_on_keys(buf, win)
end

function M.row()
	local state = M.state()
	local item = console(state)
	if not item or not item.result or vim.api.nvim_get_current_buf() ~= state.result_buf then
		return
	end
	if not item.result_rows then
		item.result_lines, item.result_rows, item.result_headers = render.results(item.result)
	end
	local entry = item.result_rows[vim.api.nvim_win_get_cursor(0)[1]]
	if entry then
		return entry.set, entry.row, entry.strings
	end
end

function M.move_cell(direction)
	local state = M.state()
	local item = console(state)
	if not item or not item.result or vim.api.nvim_get_current_buf() ~= state.result_buf then
		return
	end
	if not item.result_rows then
		item.result_lines, item.result_rows, item.result_headers = render.results(item.result)
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local rows = vim.tbl_keys(item.result_rows)
	table.sort(rows)
	if #rows == 0 then
		return
	end
	local row = cursor[1]
	if direction == "up" then
		row = rows[1]
		for _, at in ipairs(rows) do
			if at >= cursor[1] then
				break
			end
			row = at
		end
	elseif direction == "down" then
		row = rows[#rows]
		for _, at in ipairs(rows) do
			if at > cursor[1] then
				row = at
				break
			end
		end
	elseif not item.result_rows[row] then
		row = rows[1]
	end
	local widths = item.result_rows[row].widths
	local starts, cell, position = {}, 1, vim.fn.virtcol(".") - 1
	local offset = 2
	for at, width in ipairs(widths) do
		starts[at] = offset
		if position >= offset then
			cell = at
		end
		offset = offset + width + 3
	end
	if direction == "left" or direction == "right" then
		cell = math.max(1, math.min(#widths, cell + (direction == "left" and -1 or 1)))
	end
	local text = vim.api.nvim_buf_get_lines(state.result_buf, row - 1, row, false)[1]
	local byte, display = 0, 0
	for at = 0, vim.fn.strchars(text) - 1 do
		if display >= starts[cell] then
			break
		end
		local char = vim.fn.strcharpart(text, at, 1)
		byte, display = byte + #char, display + vim.fn.strdisplaywidth(char)
	end
	vim.api.nvim_win_set_cursor(0, { row, byte })
	vim.cmd("normal! zv")
end

function M.expand_row()
	local set, row, strings = M.row()
	if not row then
		return
	end
	local lines = {}
	for index, column in ipairs(set.columns) do
		lines[#lines + 1] = column .. " = " .. render.value(row[index], strings and strings[index])
	end
	local ui = require("fox.core.ui")
	local width, height = require("plugins.fox.dev.terminal").float_size()
	local buf, win = ui.float({ title = " Row details ", lines = lines, width = width, height = height })
	vim.b[buf].fox_query_root = M.state().root
	vim.wo[win].wrap = true
	ui.close_on_keys(buf, win)
end

function M.copy_row()
	local _, row = M.row()
	if row then
		vim.fn.setreg('"', vim.json.encode(row))
	end
end

function M.export()
	local state, item = M.state(), console(M.state())
	if not item or not item.result then
		return
	end
	local name = "exports/run-" .. os.date("%Y%m%d-%H%M%S") .. ".json"
	M.select(
		{ "Export loaded rows", "Cancel" },
		{ prompt = "Export loaded rows only to " .. name .. "?" },
		function(choice)
			if choice ~= "Export loaded rows" then
				return
			end
			if storage.read(state.root, name) then
				notify("Export exists; choose another time/name", vim.log.levels.WARN)
				return
			end
			storage.prepare(state.root)
			local ok, err = storage.save(state.root, name, item.result)
			notify(ok and ("Exported loaded rows to .foxnvim/query/" .. name) or err)
		end
	)
end

function M.follow_row()
	local state, active = M.state(), console(M.state())
	local set, row = M.row()
	local item = active and active.result_table and sql.table(state.metadata, active.result_table)
	if not row or not item or not active then
		notify("FK navigation requires a table-browse result with verified source columns", vim.log.levels.WARN)
		return
	end
	local candidates = vim.tbl_filter(function(relation)
		return relation.source == item.key
	end, state.metadata.relations)
	M.select(candidates, {
		prompt = "Follow foreign key",
		format_item = function(relation)
			return relation.target .. " / " .. relation.name
		end,
	}, function(relation)
		if not relation then
			return
		end
		local target = sql.table(state.metadata, relation.target)
		if not target then
			notify("Target not introspected", vim.log.levels.WARN)
			return
		end
		local params, predicates = {}, {}
		for _, pair in ipairs(relation.columns) do
			local index
			for at, column in ipairs(set.columns) do
				if column == pair.source then
					index = at
				end
			end
			if not index or row[index] == vim.NIL or type(row[index]) == "table" then
				notify("Required key is unavailable/NULL", vim.log.levels.WARN)
				return
			end
			params[#params + 1] = row[index]
			predicates[#predicates + 1] = sql.quote(pair.target, active.profile.engine) .. " = ?"
		end
		local name = (target.schema and sql.quote(target.schema, active.profile.engine) .. "." or "")
			.. sql.quote(target.name, active.profile.engine)
		local query = "SELECT * FROM " .. name .. " WHERE " .. table.concat(predicates, " AND ") .. " LIMIT 200"
		M.select({ "Run related-row query", "Cancel" }, { prompt = query }, function(choice)
			if choice == "Run related-row query" then
				M.run("statement", query, params, target.key)
			end
		end)
	end)
end

function M.privacy_enter(state)
	if state.privacy then
		return
	end
	state.privacy = { shada = vim.o.shada, registers = {}, histories = {} }
	for name in ('"0123456789abcdefghijklmnopqrstuvwxyz-/'):gmatch(".") do
		state.privacy.registers[name] = vim.fn.getreginfo(name)
	end
	for _, kind in ipairs({ "cmd", "search", "input", "expr" }) do
		local entries = {}
		for index = 1, vim.fn.histnr(kind) do
			local entry = vim.fn.histget(kind, index)
			if entry ~= "" then
				entries[#entries + 1] = entry
			end
		end
		state.privacy.histories[kind] = entries
	end
	vim.o.shada = ""
end

function M.privacy_leave(state)
	if not state.privacy then
		return
	end
	local privacy = state.privacy
	for name, value in pairs(privacy.registers) do
		pcall(vim.fn.setreg, name, value)
	end
	for kind, entries in pairs(privacy.histories) do
		vim.fn.histdel(kind)
		for _, entry in ipairs(entries) do
			vim.fn.histadd(kind, entry)
		end
	end
	vim.o.shada, state.privacy = privacy.shada, nil
	for root in pairs(M.states) do
		local excluded = "r" .. storage.path(root, "")
		if not vim.tbl_contains(vim.opt.shada:get(), excluded) then
			vim.opt.shada:append(excluded)
		end
	end
end

function M.suspend()
	local restore, buffers = {}, {}
	for _, state in pairs(M.states) do
		if valid(state.tab, "tab") then
			restore[#restore + 1] = state
			M.hide(state)
		end
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].fox_query_root then
			buffers[#buffers + 1] = { buf, vim.bo[buf].buflisted, vim.bo[buf].buftype }
			vim.bo[buf].buflisted, vim.bo[buf].buftype = false, "nofile"
		end
	end
	return function(reopen)
		for _, saved in ipairs(buffers) do
			if valid(saved[1], "buf") then
				vim.bo[saved[1]].buflisted, vim.bo[saved[1]].buftype = saved[2], saved[3]
			end
		end
		if reopen ~= false then
			for _, state in ipairs(restore) do
				if state.root == storage.root() then
					M.show(state.view)
				end
			end
		end
	end
end

function M.workspace_save(id)
	local state, documents = M.state(), {}
	for buf, item in pairs(state.consoles) do
		if valid(buf, "buf") then
			if vim.bo[buf].modified then
				return nil, "Save modified query documents before saving this workspace"
			end
			documents[#documents + 1] = {
				file = vim.b[buf].fox_query_document:sub(#"queries/" + 1),
				profile = item.profile and item.profile.id,
				fingerprint = item.profile and storage.fingerprint(item.profile),
				cursor = item.cursor,
			}
		end
	end
	if #documents == 0 then
		return true
	end
	table.sort(documents, function(a, b)
		return a.file < b.file
	end)
	return storage.save(state.root, "private/workspaces/" .. vim.fn.sha256(id):sub(1, 24) .. ".json", {
		view = state.view,
		mode = state.mode,
		queries = documents,
		selected = state.selected,
		depth = state.depth,
		active = state.active and vim.b[state.active].fox_query_document:sub(#"queries/" + 1),
	})
end

function M.workspace_load(id)
	local state = M.state()
	state.restore_disconnected = true
	local saved, err = storage.load(state.root, "private/workspaces/" .. vim.fn.sha256(id):sub(1, 24) .. ".json", nil)
	if err then
		notify(err, vim.log.levels.WARN)
		return
	end
	if not saved then
		return
	end
	if type(saved.queries) ~= "table" or not vim.islist(saved.queries) then
		notify("Invalid query workspace; original file preserved", vim.log.levels.WARN)
		return
	end
	if not M.can_replace(state.root) then
		return
	end
	M.hide(state)
	local previous = state.consoles
	state.consoles, state.active, state.pinned, state.metadata = {}, nil, nil, { tables = {}, relations = {} }
	for buf, item in pairs(previous) do
		if item.client then
			item.client:close()
		end
		if valid(buf, "buf") then
			vim.api.nvim_buf_delete(buf, { force = false })
		end
	end
	local profiles = storage.profiles(state.root) or {}
	local selected_buffer
	for _, document in ipairs(saved.queries or {}) do
		if
			type(document) == "table"
			and type(document.file) == "string"
			and document.file:match("%.sql$")
			and require("fox.query.files").path(state.root, document.file)
			and storage.read(state.root, "queries/" .. document.file)
		then
			local buf = M.new(document.file)
			local item = state.consoles[buf]
			if item.client then
				item.client:close()
			end
			item.params, item.result, item.client, item.status = {}, nil, nil, "disconnected (workspace restored)"
			for _, profile in ipairs(profiles) do
				if profile.id == document.profile and storage.fingerprint(profile) == document.fingerprint then
					item.profile = profile
					item.metadata = storage.cache(state.root, document.fingerprint)
				end
			end
			if document.file == saved.active then
				selected_buffer = buf
			end
			if
				type(document.cursor) == "table"
				and type(document.cursor[1]) == "number"
				and type(document.cursor[2]) == "number"
			then
				item.cursor = document.cursor
			end
		else
			notify("Workspace query file missing or invalid; skipped", vim.log.levels.WARN)
		end
	end
	state.selected, state.depth =
		type(saved.selected) == "string" and saved.selected or nil, math.max(1, math.min(8, tonumber(saved.depth) or 3))
	if selected_buffer then
		state.active = selected_buffer
	end
	if saved.mode == "query" then
		M.show(saved.view == "visual" and "visual" or "standard")
	end
end

function M.close_root(root)
	local state = M.states[storage.root(root)]
	if not state then
		return true
	end
	for buf, item in pairs(state.consoles) do
		if valid(buf, "buf") and vim.bo[buf].modified then
			notify("Save or discard modified SQL before closing this environment", vim.log.levels.WARN)
			return false
		end
		if item.client and item.client.busy then
			notify("Cancel or wait for the query before closing this environment", vim.log.levels.WARN)
			return false
		end
	end
	M.hide(state)
	for _, item in pairs(state.consoles) do
		if item.client then
			item.client:close()
		end
	end
	M.states[state.root] = nil
	return true
end

function M.can_replace(root)
	local state = M.states[storage.root(root)]
	if not state then
		return true
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.b[buf].fox_query_root == state.root and vim.bo[buf].modified then
			notify(
				"Save or discard modified query documents before loading a workspace or closing the environment",
				vim.log.levels.WARN
			)
			return false
		end
	end
	for _, item in pairs(state.consoles) do
		if item.client and item.client.busy then
			notify("Cancel or wait for SQL before loading a workspace or closing the environment", vim.log.levels.WARN)
			return false
		end
	end
	return true
end

function M.setup()
	vim.api.nvim_clear_autocmds({ group = group })
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			local root = vim.b[args.buf].fox_query_root
			local state = root and M.states[root]
			if
				not state
				or not state.consoles[args.buf]
				or not valid(state.sql_win, "win")
				or vim.api.nvim_get_current_tabpage() ~= state.tab
			then
				return
			end
			state.active = args.buf
			local win = vim.api.nvim_get_current_win()
			if not state.compact and win ~= state.sql_win then
				for _, name in ipairs({ "side", "result", "activity", "connections", "queries" }) do
					if state[name .. "_win"] == win then
						vim.api.nvim_win_set_buf(win, panel(state, name .. "_buf"))
					end
				end
				vim.api.nvim_win_set_buf(state.sql_win, args.buf)
				vim.api.nvim_set_current_win(state.sql_win)
			end
			M.refresh_view(state)
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			for _, state in pairs(M.states) do
				if state.mode == "query" and not valid(state.tab, "tab") then
					state.mode = "editor"
					M.privacy_leave(state)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			for _, state in pairs(M.states) do
				if valid(state.tab, "tab") and vim.api.nvim_get_current_tabpage() == state.tab then
					state.resizing = true
					M.hide(state)
					M.show(state.view)
					state.resizing = nil
					break
				end
			end
		end,
	})
	local layout_revision = 0
	vim.api.nvim_create_autocmd("WinScrolled", {
		group = group,
		callback = function()
			for _, state in pairs(M.states) do
				if state.tab == vim.api.nvim_get_current_tabpage() then
					result_header(state)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			layout_revision = layout_revision + 1
			local revision = layout_revision
			vim.defer_fn(function()
				if revision ~= layout_revision then
					return
				end
				for _, state in pairs(M.states) do
					if valid(state.tab, "tab") and vim.api.nvim_get_current_tabpage() == state.tab and not state.resizing then
						local ok, err = layout.save(state)
						if not ok then
							notify("Could not save Query layout: " .. tostring(err), vim.log.levels.WARN)
						end
						M.refresh_view(state)
					end
				end
			end, 150)
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI" }, {
		group = group,
		callback = function(args)
			local root = vim.b[args.buf].fox_query_root
			local state = root and M.states[root]
			if not state or state.mode ~= "query" or not state.consoles[args.buf] then
				return
			end
			state.active = args.buf
			local active = state.consoles[args.buf]
			do
				active.auto_revision = (active.auto_revision or 0) + 1
				local revision = active.auto_revision
				vim.defer_fn(function()
					if state.active == args.buf and valid(args.buf, "buf") and active.auto_revision == revision then
						M.autorun(state)
					end
				end, 900)
			end
			if active.metadata then
				state.metadata = active.metadata
			end
			state.revision = (state.revision or 0) + 1
			local revision = state.revision
			vim.defer_fn(function()
				if state.revision == revision then
					M.refresh_view(state)
				end
			end, 200)
		end,
	})
	vim.api.nvim_create_autocmd("BufUnload", {
		group = group,
		callback = function(args)
			local root = vim.b[args.buf].fox_query_root
			local state = root and M.states[root]
			if state and state.consoles[args.buf] then
				local item = state.consoles[args.buf]
				if item.client then
					item.client:close()
				end
				state.consoles[args.buf] = nil
			end
		end,
	})
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			for _, state in pairs(M.states) do
				if state.root ~= storage.root() and valid(state.tab, "tab") then
					M.hide(state)
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for _, state in pairs(M.states) do
				M.privacy_leave(state)
				for _, item in pairs(state.consoles) do
					if item.client then
						item.client:close()
					end
				end
			end
		end,
	})
end

return M
