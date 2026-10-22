local M = {}
local namespace = vim.api.nvim_create_namespace("fox_dap_virtual_text")
local listener = "fox_dap_virtual_text"
local dap, owner, reason
local enabled, running = true, true
local current, previous = {}, {}

local function clear()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
		end
	end
end

local function commented(buf, text)
	local template = vim.bo[buf].commentstring
	return template:find("%s", 1, true) and template:gsub("%%s", function()
		return text
	end) or text
end

local function render(buf, frame, baseline)
	local variables, values = {}, {}
	local php = vim.bo[buf].filetype == "php"
	for _, scope in ipairs(frame.scopes or {}) do
		for _, variable in pairs(scope.variables or {}) do
			if type(variable.name) == "string" and type(variable.value) == "string" then
				local name = php and variable.name:gsub("^%$", "") or variable.name
				if not variables[name] or scope.presentationHint == "locals" then
					variables[name] = variable
					values[name] = variable.value
				end
			end
		end
	end

	local ok, parser = pcall(vim.treesitter.get_parser, buf)
	if not ok or not parser then
		return values
	end
	parser:parse()
	local rows, seen = {}, {}
	parser:for_each_tree(function(tree, language)
		local query = vim.treesitter.query.get(language:lang(), "locals")
		if not query then
			return
		end
		local scopes, references = {}, {}
		for id, node in query:iter_captures(tree:root(), buf) do
			local capture = query.captures[id]
			if capture == "local.scope" then
				table.insert(scopes, node)
			elseif capture == "local.reference" or capture:match("^local%.definition") then
				table.insert(references, node)
			end
		end
		for _, node in ipairs(references) do
			local name = vim.treesitter.get_node_text(node, buf)
			name = php and name:gsub("^%$", "") or name
			local variable = variables[name]
			local row, col = node:start()
			local in_scope = true
			for _, scope in ipairs(scopes) do
				if
					vim.treesitter.is_in_node_range(scope, row, col)
					and not vim.treesitter.is_in_node_range(scope, frame.line - 1, math.max(0, (frame.column or 1) - 1))
				then
					in_scope = false
					break
				end
			end
			local key = row .. ":" .. name
			if variable and in_scope and not seen[key] and not variable.value:find("<module", 1, true) then
				seen[key] = true
				local value = variable.value:gsub("[%c%s]+", " ")
				if vim.fn.strchars(value) > 60 then
					value = vim.fn.strcharpart(value, 0, 59) .. "…"
				end
				local changed = baseline[name] ~= nil and baseline[name] ~= variable.value
				local text = commented(buf, variable.name .. " = " .. value)
				rows[row] = rows[row] or {}
				table.insert(rows[row], { "  " .. text, changed and "NvimDapVirtualTextChanged" or "NvimDapVirtualText" })
			end
		end
	end)
	for row, chunks in pairs(rows) do
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
		local width = vim.api.nvim_buf_call(buf, function()
			return vim.fn.strdisplaywidth(line)
		end)
		vim.api.nvim_buf_set_extmark(buf, namespace, row, 0, {
			virt_text = chunks,
			virt_text_pos = "eol",
			virt_text_win_col = math.max(80, width + 1),
			hl_mode = "combine",
		})
	end
	return values
end

function M.refresh()
	clear()
	local session = dap and dap.session()
	local frame = session and session.current_frame
	if not enabled or running or not session or session ~= owner or not session.stopped_thread_id or not frame then
		return
	end
	local source = frame.source
	if not source or not source.path or not frame.line then
		return
	end
	local buf = vim.fn.bufnr(source.path)
	if buf < 0 or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	local key = source.path .. ":" .. tostring(frame.id)
	current[key] = render(buf, frame, previous[key] or {})
	if reason and frame.line > 0 and frame.line <= vim.api.nvim_buf_line_count(buf) then
		vim.api.nvim_buf_set_extmark(buf, namespace, frame.line - 1, 0, {
			virt_text = { { commented(buf, reason[1]:gsub("[%c%s]+", " ")), reason[2] } },
			virt_text_pos = "eol",
		})
	end
end

function M.enable()
	enabled = true
	M.refresh()
end

function M.disable()
	enabled = false
	clear()
end

function M.toggle()
	if enabled then
		M.disable()
	else
		M.enable()
	end
end

function M.setup(debugger)
	dap = debugger
	local function reset(session)
		clear()
		owner = session
		running = not (session and session.stopped_thread_id)
		current, previous, reason = {}, {}, nil
	end
	reset(dap.session())
	for group, link in pairs({
		NvimDapVirtualText = "Comment",
		NvimDapVirtualTextChanged = "DiagnosticVirtualTextWarn",
		NvimDapVirtualTextError = "DiagnosticVirtualTextError",
		NvimDapVirtualTextInfo = "DiagnosticVirtualTextInfo",
	}) do
		vim.api.nvim_set_hl(0, group, { link = link, default = true })
	end
	for command, action in pairs({
		DapVirtualTextEnable = M.enable,
		DapVirtualTextDisable = M.disable,
		DapVirtualTextToggle = M.toggle,
		DapVirtualTextForceRefresh = M.refresh,
	}) do
		vim.api.nvim_create_user_command(command, action, { desc = command, force = true })
	end
	dap.listeners.on_session[listener] = function(_, session)
		reset(session)
		M.refresh()
	end
	dap.listeners.before.event_stopped[listener] = function(session, event)
		if session == dap.session() then
			if owner ~= session then
				reset(session)
			end
			clear()
			previous, current, running = current, {}, false
			reason = nil
			if event and event.reason == "exception" then
				reason = { "Stopped due to exception", "NvimDapVirtualTextError" }
			elseif event and event.reason == "data breakpoint" then
				reason = { "Stopped due to data breakpoint", "NvimDapVirtualTextInfo" }
			end
		end
	end
	local function refresh(session)
		if session == dap.session() then
			M.refresh()
		end
	end
	for _, event in ipairs({ "stackTrace", "scopes", "variables" }) do
		dap.listeners.after[event][listener] = refresh
	end
	dap.listeners.after.exceptionInfo[listener] = function(session, err, response)
		if session == dap.session() and not err and response then
			if response.description then
				reason = { response.description, "NvimDapVirtualTextError" }
			end
			M.refresh()
		end
	end
	for _, event in ipairs({ "continue", "next", "stepIn", "stepOut", "stepBack", "reverseContinue", "event_continued" }) do
		dap.listeners.before[event][listener] = function(session)
			if session == owner then
				running, reason = true, nil
				clear()
			end
		end
	end
	for _, event in ipairs({ "event_terminated", "event_exited", "disconnect" }) do
		dap.listeners.after[event][listener] = function(session)
			if session == owner then
				reset(nil)
			end
		end
	end
end

return M
