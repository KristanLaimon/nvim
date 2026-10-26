-- Native toast queue shared by vim.notify, progress messages and compatibility callers.
local M = { active_wins = {}, _progress_toasts = {} }
local uv = vim.uv
local records, history, items, queue = {}, {}, {}, {}
local serial, timer, last_editor, configured = 0
local ns = vim.api.nvim_create_namespace("fox_notify")
local names = { [0] = "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
local icons = { TRACE = "✎", DEBUG = "", INFO = "", WARN = "", ERROR = "", OFF = "" }
local config = { timeout = 3000, stages = "fade_in_slide_out", render = "default", fps = 30, level = 2 }
local function now()
	return uv.hrtime() / 1e6
end
local function safe(callback, ...)
	if type(callback) == "function" then
		local ok, err = pcall(callback, ...)
		if not ok then
			vim.api.nvim_echo({ { tostring(err), "ErrorMsg" } }, true, {})
		end
	end
end
local function level_number(level)
	return type(level) == "number" and level or vim.log.levels[tostring(level or "INFO"):upper()] or 2
end
local function message_lines(message)
	if type(message) == "table" then
		message = table.concat(message, "\n")
	end
	return vim.split(tostring(message or ""), "\n", { plain = true })
end
local function limit(value, fallback)
	if type(value) == "function" then
		local ok, result = pcall(value)
		return ok and tonumber(result) or fallback
	end
	return tonumber(value) or fallback
end
function M.highlights()
	for _, name in pairs(names) do
		local diagnostic = ({ ERROR = "Error", WARN = "Warn", INFO = "Info", DEBUG = "Hint", TRACE = "Hint", OFF = "Info" })[name]
		for _, part in ipairs({ "Border", "Icon", "Title" }) do
			vim.api.nvim_set_hl(0, "Notify" .. name .. part, { link = "Diagnostic" .. diagnostic })
		end
		vim.api.nvim_set_hl(0, "Notify" .. name .. "Body", { link = "NormalFloat" })
	end
end
-- Wrap by display cells, preserving blank lines and the original full message for copying.
function M.wrap(lines, width)
	local result = {}
	for _, line in ipairs(lines) do
		local current = ""
		for index = 0, vim.fn.strchars(line) - 1 do
			local char = vim.fn.strcharpart(line, index, 1)
			if char == "\t" then
				char = string.rep(" ", 4 - vim.fn.strdisplaywidth(current) % 4)
			end
			if current ~= "" and vim.fn.strdisplaywidth(current .. char) > width then
				result[#result + 1] = current
				current = ""
			end
			current = current .. char
		end
		result[#result + 1] = current
	end
	return result
end
local function geometry(record)
	local max_width = math.max(1, math.min(vim.o.columns - 4, limit(record.options.max_width or config.max_width, 80)))
	local raw = vim.deepcopy(record.message)
	if config.render == "compact" then
		raw[1] = record.icon .. " | " .. record.title[1] .. ": " .. raw[1]
	else
		table.insert(raw, 1, record.icon .. " " .. record.title[1])
		table.insert(raw, 2, "")
	end
	local width = 1
	for _, line in ipairs(raw) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	width = math.min(max_width, math.max(math.min(20, max_width), width))
	local lines = M.wrap(raw, width)
	if config.render ~= "compact" and lines[2] == "" then
		lines[2] = string.rep("━", width)
	end
	local max_height =
		math.max(1, math.min(vim.o.lines - vim.o.cmdheight - 5, limit(record.options.max_height or config.max_height, 12)))
	local height = math.min(#lines, max_height)
	local shown = vim.list_slice(lines, 1, height)
	if #lines > height then
		shown[height] = "… (full text: click or :Notifications)"
		shown[height] = M.wrap({ shown[height] }, width)[1]
	end
	return shown, width, height
end
local function restore_focus(item)
	if item.win and vim.api.nvim_get_current_win() == item.win then
		local target = last_editor or item.origin
		if target and vim.api.nvim_win_is_valid(target) then
			pcall(vim.api.nvim_set_current_win, target)
		end
	end
end
local function stop_timer()
	if timer then
		local old = timer
		timer = nil
		old:stop()
		old:close()
	end
end
local function remove(item)
	if item.closed then
		return
	end
	item.closed = true
	restore_focus(item)
	if item.win and vim.api.nvim_win_is_valid(item.win) then
		pcall(vim.api.nvim_win_close, item.win, true)
	end
	if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
		pcall(vim.api.nvim_buf_delete, item.buf, { force = true })
	end
	for key, record in pairs(M._progress_toasts) do
		if items[record.id] == item then
			M._progress_toasts[key] = nil
		end
	end
	for id, value in pairs(items) do
		if value == item then
			items[id] = nil
		end
	end
	for index = #M.active_wins, 1, -1 do
		if M.active_wins[index] == item then
			table.remove(M.active_wins, index)
		end
	end
	safe(item.record.options.on_close, item.win)
end
local function animated(item)
	return config.stages ~= "static" and item.record.options.animate ~= false
end
local function exit(item)
	if not item.win or not vim.api.nvim_win_is_valid(item.win) or not animated(item) then
		remove(item)
	elseif not item.exiting then
		item.exiting = now()
		local base = math.max(0, vim.o.columns - item.width - 2)
		item.exit_offset = math.max(0, (item.layout and item.layout.col or base) - base)
		item.exit_blend = vim.wo[item.win].winblend
	end
end
local function arm(item)
	local timeout = item.record.options.timeout
	if timeout == nil then
		timeout = config.timeout
	end
	local entry = config.stages ~= "static"
			and item.record.options.animate ~= false
			and math.max(0, 150 - (now() - item.opened))
		or 0
	item.deadline = type(timeout) == "number" and timeout > 0 and now() + timeout + entry or nil
end
local function paint(item)
	local lines, width, height = geometry(item.record)
	item.width, item.height = width, height
	vim.bo[item.buf].modifiable = true
	vim.api.nvim_buf_set_lines(item.buf, 0, -1, false, lines)
	vim.bo[item.buf].modifiable = false
	vim.b[item.buf].fox_notify_id = item.record.id
	if item.win and vim.api.nvim_win_is_valid(item.win) then
		vim.wo[item.win].winhl = "Normal:Notify"
			.. item.record.level
			.. "Body,FloatBorder:Notify"
			.. item.record.level
			.. "Border"
	end
	vim.api.nvim_buf_clear_namespace(item.buf, ns, 0, -1)
	if config.render ~= "compact" then
		vim.api.nvim_buf_set_extmark(
			item.buf,
			ns,
			0,
			0,
			{ end_row = 1, hl_group = "Notify" .. item.record.level .. "Title" }
		)
	end
end
local function open(item, row)
	item.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[item.buf].bufhidden = "wipe"
	vim.bo[item.buf].filetype = "notify"
	item.origin = vim.api.nvim_get_current_win()
	paint(item)
	local ok, win = pcall(vim.api.nvim_open_win, item.buf, false, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		row = row,
		col = math.max(0, vim.o.columns - item.width - 2),
		width = item.width,
		height = item.height,
		focusable = false,
		mouse = true,
		noautocmd = true,
		zindex = 60,
	})
	if not ok then
		vim.api.nvim_echo({ { table.concat(item.record.message, "\n"), "WarningMsg" } }, true, {})
		remove(item)
		return false
	end
	item.win, item.row, item.opened = win, row, now()
	item.layout = nil
	vim.wo[win].wrap = false
	vim.wo[win].winhl = "Normal:Notify" .. item.record.level .. "Body,FloatBorder:Notify" .. item.record.level .. "Border"
	vim.keymap.set({ "n", "v", "i" }, "<LeftMouse>", function()
		M.copy(item.record, true)
	end, { buffer = item.buf, silent = true })
	vim.keymap.set({ "n", "v", "i" }, "<2-LeftMouse>", function()
		M.copy(item.record, true)
	end, { buffer = item.buf, silent = true })
	M.active_wins[#M.active_wins + 1] = item
	arm(item)
	safe(item.record.options.on_open, win)
	if not vim.api.nvim_win_is_valid(win) then
		remove(item)
		return false
	end
	vim.api.nvim_win_set_config(win, { focusable = false, mouse = true })
	restore_focus(item)
	return not item.closed
end
local function animate(item, row, stamp)
	local duration = animated(item) and (item.exiting and 250 or 150) or 0
	local progress = duration == 0 and 1 or math.max(0, math.min(1, (stamp - (item.exiting or item.opened)) / duration))
	if item.exiting and progress == 1 then
		remove(item)
		return
	end
	local ease = progress * progress * (3 - 2 * progress)
	local fade = item.exiting and ease or 1 - ease
	item.row = math.abs(item.row - row) < 0.1 and row or item.row + (row - item.row) * 0.5
	local offset = math.min(20, item.width) * fade
	if item.exiting then
		local initial = item.exit_offset or 0
		offset = initial + (item.width + 2 - initial) * ease
	end
	local col = math.max(0, vim.o.columns - item.width - 2) + math.floor(offset)
	local layout = {
		relative = "editor",
		row = math.max(0, item.row),
		col = col,
		-- Otherwise Neovim shifts the float back inside the editor, hiding the
		-- horizontal motion. Keep its left edge fixed and crop the right edge.
		fixed = true,
		width = item.width,
		height = item.height,
		focusable = false,
		mouse = true,
	}
	if not vim.deep_equal(item.layout, layout) then
		vim.api.nvim_win_set_config(item.win, layout)
		item.layout = layout
	end
	local blend = item.exiting and math.floor((item.exit_blend or 0) + (100 - (item.exit_blend or 0)) * ease)
		or math.floor(fade * 80)
	if vim.wo[item.win].winblend ~= blend then
		vim.wo[item.win].winblend = blend
	end
end
local pumping = false
local function tick()
	local stamp, row = now(), 1
	local bottom = vim.o.lines - vim.o.cmdheight - 2
	for _, item in ipairs(vim.list_slice(M.active_wins)) do
		if not vim.api.nvim_win_is_valid(item.win) or not vim.api.nvim_buf_is_valid(item.buf) then
			remove(item)
		else
			if not item.exiting and item.deadline and stamp >= item.deadline then
				local keep = false
				if item.record.options.keep then
					local ok, value = pcall(item.record.options.keep)
					keep = ok and value
				end
				if not keep then
					exit(item)
				end
			end
			if row + item.height + 2 > bottom then
				-- A resize can make an existing window too large: requeue it intact.
				restore_focus(item)
				pcall(vim.api.nvim_win_close, item.win, true)
				if vim.api.nvim_buf_is_valid(item.buf) then
					pcall(vim.api.nvim_buf_delete, item.buf, { force = true })
				end
				item.win, item.buf = nil, nil
				for i, value in ipairs(M.active_wins) do
					if value == item then
						table.remove(M.active_wins, i)
						break
					end
				end
				table.insert(queue, 1, item)
			elseif not item.closed and vim.api.nvim_win_is_valid(item.win) then
				animate(item, row, stamp)
				row = row + item.height + 3
			end
		end
	end
	while #queue > 0 do
		local item = queue[1]
		local _, _, height = geometry(item.record)
		if item.closed then
			table.remove(queue, 1)
		elseif row + height + 2 > bottom then
			break
		else
			table.remove(queue, 1)
			if open(item, row) then
				animate(item, row, stamp)
				row = row + item.height + 3
			end
		end
	end
	if #M.active_wins == 0 and #queue == 0 then
		stop_timer()
	end
end
function M._tick()
	if pumping then
		return
	end
	pumping = true
	local ok, err = pcall(tick)
	pumping = false
	if not ok then
		M.dismiss_all()
		vim.api.nvim_echo({ { "Notification rendering failed: " .. tostring(err), "ErrorMsg" } }, true, {})
	end
end
local function start()
	if not timer then
		local running = uv.new_timer()
		timer = running
		running:start(
			0,
			math.max(10, math.floor(1000 / config.fps)),
			vim.schedule_wrap(function()
				if timer == running then
					M._tick()
				end
			end)
		)
	end
end
function M.notify(message, level, opts)
	if not configured and not vim.in_fast_event() then
		M.setup()
	end
	if vim.in_fast_event() then
		vim.schedule(function()
			M.notify(message, level, opts)
		end)
		return
	end
	opts = type(opts) == "string" and { title = opts } or vim.deepcopy(opts or {})
	local previous_id = type(opts.replace) == "table" and opts.replace.id or opts.replace
	local previous = previous_id and (items[previous_id] and items[previous_id].record or records[previous_id])
	if previous then
		opts = vim.tbl_extend("force", previous.options, opts)
		if message == nil then
			message = previous.message
		end
		level = level or previous.level
	end
	opts.replace = previous_id
	serial = serial + 1
	local title = opts.title or "Neovim"
	local numeric = level_number(level)
	local record = {
		id = serial,
		message = message_lines(message),
		level = names[numeric] or "INFO",
		title = type(title) == "table" and title or { title, "" },
		time = os.time(),
		options = opts,
	}
	record.icon = opts.icon or icons[record.level]
	record.hide_from_history = opts.hide_from_history
	records[record.id] = record
	history[#history + 1] = record
	local item = previous_id and items[previous_id]
	if item then
		item.record, item.exiting = record, nil
		items[record.id] = item
		if item.win and vim.api.nvim_win_is_valid(item.win) and vim.api.nvim_buf_is_valid(item.buf) then
			paint(item)
			arm(item)
		end
	elseif numeric >= level_number(config.level) then
		item = { record = record }
		items[record.id] = item
		queue[#queue + 1] = item
	end
	if item then
		start()
	end
	return vim.deepcopy(record)
end
function M.history(opts)
	local result = {}
	for _, record in ipairs(history) do
		if not record.hide_from_history or opts and opts.include_hidden then
			result[#result + 1] = vim.deepcopy(record)
		end
	end
	return result
end
function M.clear_history()
	history = {}
	records = {}
end
function M.pending()
	local result = {}
	for _, item in ipairs(queue) do
		if not item.closed then
			result[#result + 1] = item.record.id
		end
	end
	return result
end
function M.close(record)
	local item = items[type(record) == "table" and record.id or record]
	if item then
		exit(item)
		start()
	end
end
function M.dismiss(opts)
	opts = opts or {}
	if opts.pending then
		local pending = queue
		queue = {}
		for _, item in ipairs(pending) do
			remove(item)
		end
	end
	for _, item in ipairs(vim.list_slice(M.active_wins)) do
		if opts.immediate then
			remove(item)
		else
			exit(item)
		end
	end
	if #queue > 0 or #M.active_wins > 0 then
		start()
	else
		stop_timer()
	end
end
function M.dismiss_all()
	M.dismiss({ pending = true, silent = true, immediate = true })
end
function M.copy(record, close)
	record = type(record) == "table" and record or records[record]
	if not record then
		return false
	end
	local ok, result = pcall(vim.fn.setreg, "+", table.concat(record.message, "\n"), "v")
	if not ok or result ~= 0 then
		vim.api.nvim_echo({ { "Could not copy notification to clipboard", "ErrorMsg" } }, true, {})
		return false
	end
	if close then
		M.close(record)
	end
	return true
end
function M.copy_last()
	local list = M.history()
	if #list > 0 then
		return M.copy(list[#list])
	end
	vim.api.nvim_echo({ { "No recent notifications", "WarningMsg" } }, false, {})
end
function M.open(record, opts)
	opts = opts or {}
	record = type(record) == "table" and record or records[record]
	if not record then
		return
	end
	local buf = opts.buffer or vim.api.nvim_create_buf(false, true)
	local lines =
		vim.list_extend({ record.icon .. " " .. table.concat(record.title, " "), "" }, vim.deepcopy(record.message))
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "notify_history"
	vim.bo[buf].modifiable = false
	return {
		buffer = buf,
		width = math.min(opts.max_width or 100, vim.o.columns - 4),
		height = #lines,
		highlights = { body = "Notify" .. record.level .. "Body", border = "Notify" .. record.level .. "Border" },
	}
end
function M.open_history()
	local lines = {}
	for _, record in ipairs(M.history()) do
		lines[#lines + 1] = os.date("%H:%M:%S", record.time)
			.. " "
			.. record.level
			.. " "
			.. table.concat(record.title, " ")
		vim.list_extend(lines, record.message)
		lines[#lines + 1] = ""
	end
	if #lines == 0 then
		lines = { "No notifications" }
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].filetype = "notify_history"
	vim.bo[buf].modifiable = false
	vim.api.nvim_set_current_buf(buf)
	vim.keymap.set("n", "q", "<Cmd>bd!<CR>", { buffer = buf, silent = true })
end
function M.notify_progress(id, message, level, opts)
	opts = vim.tbl_extend("force", opts or {}, { replace = M._progress_toasts[id], timeout = false })
	local record = M.notify(message, level, opts)
	M._progress_toasts[id] = record
	return record
end
function M.finish_progress(id, timeout)
	local record = M._progress_toasts[id]
	M._progress_toasts[id] = nil
	if record and items[record.id] then
		return M.notify(nil, nil, { replace = record, timeout = timeout or 2500 })
	end
end
function M.dismiss_progress(id)
	local record = M._progress_toasts[id]
	M._progress_toasts[id] = nil
	if record then
		M.close(record)
	end
end
function M.setup(opts)
	M.dismiss_all()
	local env = require("fox.core.environment").detect()
	local mobile = env.is_mobile or env.is_termux or env.is_proot
	config = vim.tbl_extend("force", {
		timeout = mobile and 1800 or 3000,
		stages = mobile and "static" or "fade_in_slide_out",
		render = mobile and "compact" or "default",
		fps = mobile and 5 or 30,
		level = 2,
		max_width = function()
			return math.max(
				mobile and 25 or 40,
				math.min(mobile and 45 or 120, math.floor(vim.o.columns * (mobile and 0.7 or 0.8)))
			)
		end,
		max_height = function()
			return math.max(
				mobile and 3 or 8,
				math.min(mobile and 6 or 20, math.floor(vim.o.lines * (mobile and 0.25 or 0.4)))
			)
		end,
	}, opts or {})
	config.fps = math.max(1, tonumber(config.fps) or 30)
	M.highlights()
	vim.notify = M
	last_editor = vim.api.nvim_get_current_win()
	local group = vim.api.nvim_create_augroup("FoxNativeNotify", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.highlights })
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			for _, item in ipairs(M.active_wins) do
				if vim.api.nvim_buf_is_valid(item.buf) then
					paint(item)
				end
			end
			start()
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.dismiss_all })
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if vim.bo.filetype ~= "notify" then
				last_editor = win
			end
		end,
	})
	for name, callback in pairs({
		NotifyDismiss = function()
			M.dismiss({ pending = true })
		end,
		ClearToasts = M.dismiss_all,
		NotifyCopyLast = M.copy_last,
		Notifications = M.open_history,
		NotificationsClear = M.clear_history,
	}) do
		vim.api.nvim_create_user_command(name, callback, {})
	end
	-- Retain existing shortcuts; new actions are exposed through the Command Palette.
	vim.keymap.set("n", "<leader>nc", M.copy_last, { desc = "Copy last notification full text" })
	for _, key in ipairs({ "<leader>nd", "<leader>un" }) do
		vim.keymap.set("n", key, function()
			M.dismiss({ pending = true })
		end, { desc = "Dismiss active notifications" })
	end
	local mouse_keys = {
		[vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true)] = true,
		[vim.api.nvim_replace_termcodes("<2-LeftMouse>", true, false, true)] = true,
	}
	vim.on_key(function(key, typed)
		if not mouse_keys[key] and not mouse_keys[typed] then
			return
		end
		local position = vim.fn.getmousepos()
		for _, item in ipairs(M.active_wins) do
			if position.winid == item.win then
				local record = item.record
				vim.schedule(function()
					M.copy(record, true)
				end)
				return ""
			end
		end
	end, ns)
	configured = true
end
return setmetatable(M, {
	__call = function(_, ...)
		if not configured then
			M.setup()
		end
		return M.notify(...)
	end,
})
