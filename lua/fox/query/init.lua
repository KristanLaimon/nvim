local M = { states = {} }
local storage = require("fox.query.storage")
local sql = require("fox.query.sql")
local render = require("fox.query.render")
local client = require("fox.query.client")
local ns = vim.api.nvim_create_namespace("fox_query")
local group = vim.api.nvim_create_augroup("FoxQuery", { clear = true })

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "FoxQuerier" })
end

function M.state(root)
	root = storage.root(root)
	if not M.states[root] then
		M.states[root] = {
			root = root,
			view = "standard",
			metadata = { tables = {}, relations = {} },
			consoles = {},
			filter = "",
			depth = 3,
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

local function panel(state, key)
	if not valid(state[key], "buf") then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden, vim.bo[buf].swapfile, vim.bo[buf].filetype = "hide", false, "foxquery"
		vim.b[buf].fox_query_root, state[key] = state.root, buf
	end
	return state[key]
end

local function set_lines(buf, lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, require("fox.core.ui").sanitize_lines(lines))
	vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
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

local function current_metadata(state)
	local item = console(state)
	if item and item.metadata then
		state.metadata = item.metadata
	elseif item then
		state.metadata, state.note_keys = { tables = {}, relations = {} }, {}
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

function M.refresh_view(state)
	state = state or M.state()
	if not valid(state.tab, "tab") or vim.api.nvim_get_current_tabpage() ~= state.tab then
		return
	end
	local active = console(state)
	current_metadata(state)
	local label = active and active.profile and active.profile.id or "no connection"
	local connected = active and active.client and active.client.connected
	local status = "[QUERY / "
		.. state.view:upper()
		.. "] "
		.. label
		.. " | "
		.. (connected and "READ ONLY" or "disconnected")
		.. " | "
		.. (active and active.status or "idle")
	if valid(state.sql_win, "win") then
		vim.wo[state.sql_win].winbar = status:gsub("%%", "%%%%")
	end
	if state.view == "visual" then
		local text, offset = text_at_cursor(state)
		if state.pinned and state.pinned.buf == state.active then
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
			valid(state.side_win, "win") and vim.api.nvim_win_get_width(state.side_win) or vim.o.columns
		)
		set_lines(panel(state, "side_buf"), lines)
		state.objects = objects
		vim.api.nvim_buf_clear_namespace(state.side_buf, ns, 0, -1)
		for _, highlight in ipairs(highlights) do
			local opts = highlight[3] and { hl_group = highlight[2], end_col = highlight[4] }
				or { line_hl_group = highlight[2] }
			vim.api.nvim_buf_set_extmark(state.side_buf, ns, highlight[1], highlight[3] or 0, opts)
		end
	else
		local lines, objects = render.explorer(state.metadata, state.filter, state.selected, state.note_keys)
		state.objects = objects
		if state.selected then
			local item = sql.table(state.metadata, state.selected)
			if item then
				vim.list_extend(lines, { "", unpack(render.inspect(item, state.metadata)) })
			end
		end
		set_lines(panel(state, "side_buf"), lines)
	end
	local result_lines = {
		"RESULTS | " .. (active and active.result_label or "No execution"),
		"Enter: expand row | y: copy row | e: export | gR: follow foreign key",
	}
	if active and active.result then
		active.result_lines = active.result_lines or render.results(active.result)
		vim.list_extend(result_lines, active.result_lines)
	end
	set_lines(panel(state, "result_buf"), result_lines)
	set_lines(panel(state, "activity_buf"), {
		"ACTIVITY | " .. (active and active.status or "idle"),
		active and active.executed_sql or "SQL is never executed while typing",
	})
end

local function map(buf, key, action)
	vim.keymap.set("n", key, action, { buffer = buf, silent = true })
end

local function selected_object(state)
	local buf = vim.api.nvim_get_current_buf()
	local line = vim.api.nvim_win_get_cursor(0)[1]
	if buf == state.side_buf and state.objects then
		return render.object_at(state.objects, line, vim.fn.virtcol(".") - 1)
	end
	if state.selected then
		return sql.table(state.metadata, state.selected)
	end
end

local function show_document(state, relative, filetype)
	local buf = storage.document_buffer(state.root, relative, filetype)
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
	local width, height = math.max(1, math.min(90, vim.o.columns - 4)), math.max(1, math.min(30, vim.o.lines - 6))
	set_lines(buf, render.inspect(item, state.metadata))
	local _, win = require("fox.core.ui").float(
		buf,
		{ width = width, height = height, title = " Table: " .. item.name:gsub("[%c]", " ") .. " " }
	)
	map(buf, "q", function()
		vim.api.nvim_win_close(win, true)
	end)
	map(buf, "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end)
	map(buf, "J", function()
		vim.api.nvim_win_close(win, true)
		M.insert_join(item)
	end)
	map(buf, "n", function()
		vim.api.nvim_win_close(win, true)
		M.notes(item)
	end)
	map(buf, "g", function()
		vim.api.nvim_win_close(win, true)
		M.graph(false)
	end)
	map(buf, "b", function()
		vim.api.nvim_win_close(win, true)
		M.browse(item)
	end)
end

function M.hide(state)
	state = state or M.state()
	if valid(state.tab, "tab") then
		local active, buf = console(state)
		if active and valid(state.sql_win, "win") and vim.api.nvim_win_get_buf(state.sql_win) == buf then
			active.cursor = vim.api.nvim_win_get_cursor(state.sql_win)
		end
		state.widths = state.widths or {}
		if valid(state.side_win, "win") then
			state.widths[state.view] = vim.api.nvim_win_get_width(state.side_win)
		end
		if valid(state.result_win, "win") then
			state.result_height = vim.api.nvim_win_get_height(state.result_win)
		end
		local current = vim.api.nvim_get_current_tabpage()
		vim.api.nvim_set_current_tabpage(state.tab)
		vim.cmd("tabclose")
		state.tab, state.sql_win, state.side_win, state.result_win, state.activity_win = nil, nil, nil, nil, nil
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
	M.privacy_enter(state)
	state.editor_tab = vim.api.nvim_get_current_tabpage()
	vim.cmd("tabnew")
	state.tab, state.sql_win = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_win()
	local _, buf = console(state)
	if not buf then
		M.new()
		_, buf = console(state)
	end
	vim.api.nvim_win_set_buf(state.sql_win, buf)
	state.compact = vim.o.columns < 72 or vim.o.lines < 20
	panel(state, "side_buf")
	if not state.compact then
		vim.cmd("botright vsplit")
		state.side_win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.side_win, panel(state, "side_buf"))
		vim.api.nvim_win_set_width(
			state.side_win,
			math.min(
				vim.o.columns - 12,
				state.widths and state.widths[state.view]
					or math.max(24, math.floor(vim.o.columns * (state.view == "visual" and 0.5 or 0.3)))
			)
		)
		vim.wo[state.side_win].wrap = false
		vim.api.nvim_set_current_win(state.sql_win)
		if state.view == "standard" then
			vim.cmd("belowright split")
			state.result_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(state.result_win, panel(state, "result_buf"))
			vim.api.nvim_win_set_height(state.result_win, state.result_height or math.max(3, math.floor(vim.o.lines * 0.25)))
			vim.wo[state.result_win].wrap = false
			vim.cmd("belowright split")
			state.activity_win = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(state.activity_win, panel(state, "activity_buf"))
			vim.api.nvim_win_set_height(state.activity_win, 2)
		end
	end
	map(state.side_buf, "/", function()
		if state.view == "visual" then
			vim.ui.select(state.metadata.tables, {
				prompt = "Inspect cached table",
				format_item = function(item)
					return item.key
				end,
			}, function(item)
				if item then
					M.inspect(item, state)
				end
			end)
			return
		end
		vim.ui.input({ prompt = "Find cached table: " }, function(value)
			if value then
				state.filter = value
				M.refresh_view(state)
			end
		end)
	end)
	map(state.side_buf, "<CR>", function()
		M.inspect(nil, state)
	end)
	map(state.side_buf, "J", function()
		M.insert_join(selected_object(state))
	end)
	map(state.side_buf, "n", function()
		M.notes(selected_object(state))
	end)
	map(state.side_buf, "b", function()
		M.browse(selected_object(state))
	end)
	map(state.side_buf, "q", function()
		vim.api.nvim_set_current_win(state.sql_win)
		if state.compact then
			vim.api.nvim_win_set_buf(state.sql_win, state.active)
		end
	end)
	map(state.side_buf, "?", M.help)
	map(state.result_buf or panel(state, "result_buf"), "<CR>", M.expand_row)
	map(state.result_buf, "y", M.copy_row)
	map(state.result_buf, "e", M.export)
	map(state.result_buf, "gR", M.follow_row)
	map(state.result_buf, "q", function()
		vim.api.nvim_set_current_win(state.sql_win)
		if state.compact then
			vim.api.nvim_win_set_buf(state.sql_win, state.active)
		end
	end)
	map(state.result_buf, "?", M.help)
	vim.api.nvim_set_current_win(state.sql_win)
	local active = console(state)
	if active and active.cursor then
		pcall(vim.api.nvim_win_set_cursor, state.sql_win, active.cursor)
	end
	M.refresh_view(state)
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
		vim.ui.select(
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
		replacement = M.new()
	end
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == buf then
			vim.api.nvim_win_set_buf(win, replacement)
		end
	end
	vim.api.nvim_buf_delete(buf, { force = true })
	M.refresh_view(state)
end

function M.new(relative)
	local state = M.state()
	if relative and not relative:match("^[%w_-]+%.sql$") then
		notify("Use a simple query-name.sql", vim.log.levels.ERROR)
		return
	end
	state.next_query = (state.next_query or 0) + 1
	relative = "queries/" .. (relative or ("query-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. state.next_query .. ".sql"))
	local buf = storage.document_buffer(state.root, relative, "sql")
	state.consoles[buf] = state.consoles[buf] or { status = "idle", params = {} }
	state.active = buf
	if state.consoles[buf].metadata then
		state.metadata = state.consoles[buf].metadata
	end
	if valid(state.sql_win, "win") then
		vim.api.nvim_win_set_buf(state.sql_win, buf)
	end
	vim.b[buf].fox_env_slot = _G._fox_active_env_slot or 1
	map(buf, "<F1>", M.help)
	M.refresh_view(state)
	return buf
end

function M.open()
	local state, files = M.state(), {}
	for _, file in ipairs(vim.fn.glob(storage.path(state.root, "queries/*.sql"), false, true)) do
		files[#files + 1] = vim.fn.fnamemodify(file, ":t")
	end
	for buf in pairs(state.consoles) do
		if valid(buf, "buf") then
			local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
			if not vim.tbl_contains(files, name) then
				files[#files + 1] = name
			end
		end
	end
	vim.ui.select(files, { prompt = "Saved / open project queries" }, function(file)
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
			active.status = "disconnected"
			M.refresh_view(state)
		end
		return
	end
	local profiles, err = storage.profiles(state.root)
	if not profiles then
		notify(err, vim.log.levels.ERROR)
		return
	end
	local choices = { "+ Add connection", "Edit connection profiles", "Disconnect current console" }
	for _, profile in ipairs(profiles) do
		choices[#choices + 1] = profile.id
			.. " ("
			.. profile.engine
			.. ") "
			.. (profile.path or (profile.host .. ":" .. profile.port .. "/" .. profile.database))
	end
	vim.ui.select(choices, { prompt = "Project database connections" }, function(choice, index)
		if not choice then
			return
		end
		if index == 1 then
			M.add_profile()
			return
		end
		if index == 2 then
			storage.prepare(state.root)
			if not storage.read(state.root, "connections.json") then
				storage.save(state.root, "connections.json", { profiles = {} })
			end
			show_document(state, "connections.json", "json")
			return
		end
		if index == 3 then
			M.profile("disconnect")
			return
		end
		M.connect(profiles[index - 3], state)
	end)
end

function M.add_profile()
	local state, profile = M.state(), {}
	vim.ui.select({ "sqlite", "mysql", "postgres" }, { prompt = "Database engine" }, function(engine)
		if not engine then
			return
		end
		profile.engine = engine
		local fields = engine == "sqlite" and { "id", "path" }
			or { "id", "host", "port", "database", "user", "password_env" }
		local defaults = { host = "127.0.0.1", port = engine == "mysql" and "3306" or "5432" }
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
				for _, existing in ipairs(profiles) do
					if existing.id == profile.id then
						notify("Profile id already exists", vim.log.levels.ERROR)
						return
					end
				end
				profiles[#profiles + 1] = profile
				storage.prepare(state.root)
				local saved, save_err = storage.save(state.root, "connections.json", { profiles = profiles })
				if not saved then
					notify(save_err, vim.log.levels.ERROR)
					return
				end
				M.connect(profile, state)
				return
			end
			vim.ui.input({
				prompt = key == "password_env" and "Password environment variable (blank: prompt in RAM): " or key .. ": ",
				default = defaults[key],
			}, function(value)
				if value == nil then
					return
				end
				if key == "port" then
					profile[key] = tonumber(value)
				elseif value ~= "" then
					profile[key] = value
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
	item.params, item.profile = {}, vim.deepcopy(profile)
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
	if profile.engine ~= "sqlite" and not secret then
		local ok, value = pcall(vim.fn.inputsecret, "Database password (RAM only): ")
		if not ok then
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
			item.status = err
			notify(err, vim.log.levels.ERROR)
		else
			connection.connected, item.status = true, "connected | " .. result.engine .. " " .. result.version
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
	end)
end

function M.run(kind, supplied_sql, supplied_params, source_table)
	if kind and not vim.tbl_contains({ "statement", "selection", "section", "file" }, kind) then
		notify("Choose statement, selection, section, or file", vim.log.levels.WARN)
		return
	end
	local state = M.state()
	local item, buf = console(state)
	if not item or not item.client or not item.client.connected then
		notify("Connect this SQL console first", vim.log.levels.WARN)
		return
	end
	if item.client.busy then
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
		query, scope_err = sql.scope(text, offset, kind or "statement", selection, item.syntax or item.profile.engine)
	end
	if not query then
		notify(scope_err, vim.log.levels.WARN)
		return
	end
	local connection = item.client
	connection.busy, item.status = true, "validating " .. (kind or "statement")
	connection:request("prepare", { sql = query }, function(prepared, prepare_err)
		if prepare_err then
			connection.busy = false
			item.status = prepare_err
			M.refresh_view(state)
			return
		end
		local params = supplied_params or {}
		local function execute()
			if item.client ~= connection or not valid(buf, "buf") then
				connection.busy = false
				return
			end
			item.params, item.executed_sql = params, query
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
				item.error_detail = detail ~= vim.NIL and detail or nil
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
			end)
			local function elapsed()
				if item.execution ~= execution or not connection.busy or item.client ~= connection then
					return
				end
				item.status = string.format("running / fetching | %.1fs", ((vim.uv or vim.loop).hrtime() - item.started) / 1e9)
				if valid(state.activity_buf, "buf") then
					set_lines(state.activity_buf, { "ACTIVITY | " .. item.status, query })
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
			vim.ui.select({ "Run with these RAM parameters", "Cancel" }, {
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
		item.status = "cancellation requested; reconnect may be required"
		item.client:cancel()
		M.refresh_view(state)
	end
end

function M.notes(item)
	local state = M.state()
	item = item or selected_object(state)
	local active = console(state)
	if not item or not active or not active.profile then
		notify("Select a table with a connection first", vim.log.levels.WARN)
		return
	end
	local key = storage.fingerprint(active.profile) .. "/" .. vim.fn.sha256(item.key):sub(1, 24) .. ".md"
	state.note_keys = state.note_keys or {}
	state.note_keys[item.key] = true
	local buf = show_document(state, "notes/" .. key, "markdown")
	if vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
		vim.api.nvim_buf_set_lines(
			buf,
			0,
			-1,
			false,
			{ "# " .. item.key, "", "## Business rules", "", "## Example queries", "" }
		)
	end
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

function M.browse(item)
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
	M.run("statement", "SELECT * FROM " .. name .. order .. " LIMIT 200", {}, item.key)
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
	vim.ui.select(candidates, {
		prompt = "Choose foreign key mapping",
		format_item = function(candidate)
			return candidate.node.alias .. " -> " .. candidate.target .. " (" .. candidate.relation.name .. ")"
		end,
	}, function(candidate)
		if not candidate then
			return
		end
		vim.ui.input({ prompt = "Target alias: ", default = "t" .. (#graph.nodes + 1) }, function(alias)
			if not alias then
				return
			end
			for _, node in ipairs(graph.nodes) do
				if node.alias:lower() == alias:lower() then
					notify("Alias already used", vim.log.levels.WARN)
					return
				end
			end
			vim.ui.select({ "INNER", "LEFT" }, { prompt = "JOIN type" }, function(kind)
				if not kind then
					return
				end
				local join, join_err = sql.join_sql(candidate, alias, kind, active.profile.engine)
				if not join then
					notify(join_err, vim.log.levels.WARN)
					return
				end
				vim.ui.select({ "Insert this JOIN", "Cancel" }, { prompt = join }, function(choice)
					if choice ~= "Insert this JOIN" then
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
		end)
	end)
end

function M.graph(all)
	local state = M.state()
	local key = not all and state.selected or nil
	local buf = vim.api.nvim_create_buf(false, true)
	vim.b[buf].fox_query_root = state.root
	vim.cmd("botright split")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.wo[win].wrap = false
	local function draw()
		local lines, objects = render.map(state.metadata, key, state.depth, vim.api.nvim_win_get_width(win))
		set_lines(buf, lines)
		map(buf, "<CR>", function()
			local item = render.object_at(objects, vim.api.nvim_win_get_cursor(win)[1], vim.fn.virtcol(".") - 1)
			if item then
				key, state.selected = item.key, item.key
				draw()
			end
		end)
	end
	draw()
	map(buf, "+", function()
		state.depth = math.min(8, state.depth + 1)
		draw()
	end)
	map(buf, "-", function()
		state.depth = math.max(1, state.depth - 1)
		draw()
	end)
	map(buf, "/", function()
		vim.ui.select(state.metadata.tables, {
			prompt = "Find / recenter table",
			format_item = function(item)
				return item.key
			end,
		}, function(item)
			if item then
				key, state.selected = item.key, item.key
				draw()
			end
		end)
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
	if state.compact then
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
	local buf, win = require("fox.core.ui").float({
		width = math.min(78, vim.o.columns - 4),
		height = math.min(18, vim.o.lines - 4),
		title = " FoxQuerier ",
		lines = {
			"FoxMode: Editor / Query | FoxQueryView: Standard / Visual",
			"FoxQueryConnections: add, edit, connect, disconnect",
			"FoxQueryNew / FoxQueryOpen: SQL tabs; :write saves locally",
			"FoxQueryRun statement / selection / section / file",
			"FoxQueryCancel: cancel; reconnect if session is uncertain",
			"FoxQueryResults / FoxQueryActivity: results / submitted SQL",
			"Explorer/diagram: Enter inspect, J Insert JOIN, n notes, b browse",
			"Results: Enter expand row, y copy, e export, gR follow FK",
			"Map: / table search, Enter recenter, +/- depth, zh/zl pan, q back",
			"Visual: * SELECT column, k JOIN key, f filter; dim means context",
			"Parameters: Ctrl-C cancels; NULL is null; text:NULL is literal text",
			"Workspaces: save SQL first; explicit saves restore disconnected",
			"No SQL executes while typing. All state stays in .foxnvim/query/.",
		},
	})
	vim.b[buf].fox_query_root = M.state().root
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
	local item = console(M.state())
	if not item or not item.result then
		return
	end
	local line = vim.api.nvim_win_get_cursor(0)[1] - 2
	for _, set in ipairs(item.result.sets) do
		if line >= 3 and line <= #set.rows + 2 then
			return set, set.rows[line - 2]
		end
		line = line - #set.rows - 3
	end
end

function M.expand_row()
	local set, row = M.row()
	if not row then
		return
	end
	local lines = {}
	for index, column in ipairs(set.columns) do
		lines[#lines + 1] = column
			.. " = "
			.. (
				row[index] == vim.NIL and "NULL"
				or type(row[index]) == "table" and vim.json.encode(row[index])
				or tostring(row[index])
			)
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.b[buf].fox_query_root = M.state().root
	set_lines(buf, lines)
	vim.cmd("belowright split")
	vim.api.nvim_set_current_buf(buf)
	map(buf, "q", function()
		vim.cmd("close")
	end)
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
	vim.ui.select(
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
	vim.ui.select(candidates, {
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
		vim.ui.select({ "Run related-row query", "Cancel" }, { prompt = query }, function(choice)
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
				file = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"),
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
		active = state.active and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(state.active), ":t"),
		widths = state.widths,
		result_height = state.result_height,
	})
end

function M.workspace_load(id)
	local state = M.state()
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
			and document.file:match("^[%w_-]+%.sql$")
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
	if type(saved.widths) == "table" then
		state.widths = {}
		for _, view in ipairs({ "standard", "visual" }) do
			if type(saved.widths[view]) == "number" then
				state.widths[view] = math.max(12, math.min(vim.o.columns - 12, saved.widths[view]))
			end
		end
	end
	if type(saved.result_height) == "number" then
		state.result_height = math.max(2, math.min(vim.o.lines - 10, saved.result_height))
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

function M.install_drivers()
	local state = M.state()
	vim.ui.select(
		{ "Install project MySQL + PostgreSQL drivers", "Cancel" },
		{ prompt = "Install PyMySQL and psycopg[binary] under .foxnvim/query/private/drivers?" },
		function(choice)
			if choice ~= "Install project MySQL + PostgreSQL drivers" then
				return
			end
			local python = client.python()
			if not python then
				notify("Python 3 required", vim.log.levels.ERROR)
				return
			end
			storage.prepare(state.root)
			local temporary = storage.path(state.root, "cache/pip-tmp")
			vim.fn.mkdir(temporary, "p")
			vim.system(
				{
					python,
					"-m",
					"pip",
					"install",
					"--disable-pip-version-check",
					"--no-compile",
					"--no-cache-dir",
					"--target",
					storage.path(state.root, "private/drivers"),
					"PyMySQL>=1.1,<2",
					"psycopg[binary]>=3.2,<4",
				},
				{ text = true, env = { TMP = temporary, TEMP = temporary, TMPDIR = temporary } },
				vim.schedule_wrap(function(result)
					notify(
						result.code == 0 and "Project database drivers installed"
							or "Driver install failed; check Python/pip and network access",
						result.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
					)
				end)
			)
		end
	)
end

function M.setup()
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
				for _, name in ipairs({ "side", "result", "activity" }) do
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
					M.hide(state)
					M.show(state.view)
					break
				end
			end
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
