-- ANSI output for DAP buffers. This is a text highlighter, not a terminal emulator.
local M = { namespace = vim.api.nvim_create_namespace("fox_dap_ansi") }
local buffers, groups = {}, {}
local palette = {
	"#000000",
	"#cd0000",
	"#00cd00",
	"#cdcd00",
	"#0000ee",
	"#cd00cd",
	"#00cdcd",
	"#e5e5e5",
	"#7f7f7f",
	"#ff0000",
	"#00ff00",
	"#ffff00",
	"#5c5cff",
	"#ff00ff",
	"#00ffff",
	"#ffffff",
}

local function color(n)
	if n < 16 then
		return vim.g["terminal_color_" .. n] or palette[n + 1]
	elseif n < 232 then
		local levels = { 0, 95, 135, 175, 215, 255 }
		n = n - 16
		return string.format(
			"#%02x%02x%02x",
			levels[math.floor(n / 36) + 1],
			levels[math.floor(n / 6) % 6 + 1],
			levels[n % 6 + 1]
		)
	end
	local gray = 8 + (n - 232) * 10
	return string.format("#%02x%02x%02x", gray, gray, gray)
end

local function sgr(style, params)
	local values = vim.split(params:gsub(":", ";"), ";", { plain = true })
	local i = 1
	while i <= #values do
		local n = tonumber(values[i]) or 0
		if n == 0 then
			style = {}
		elseif n == 1 then
			style.bold = true
		elseif n == 3 then
			style.italic = true
		elseif n == 4 then
			style.underline = true
		elseif n == 7 then
			style.reverse = true
		elseif n == 9 then
			style.strikethrough = true
		elseif n == 22 then
			style.bold = nil
		elseif n == 23 then
			style.italic = nil
		elseif n == 24 then
			style.underline = nil
		elseif n == 27 then
			style.reverse = nil
		elseif n == 29 then
			style.strikethrough = nil
		elseif n == 39 then
			style.fg = nil
		elseif n == 49 then
			style.bg = nil
		elseif (n >= 30 and n <= 37) or (n >= 90 and n <= 97) then
			style.fg = color(n >= 90 and n - 82 or n - 30)
		elseif (n >= 40 and n <= 47) or (n >= 100 and n <= 107) then
			style.bg = color(n >= 100 and n - 92 or n - 40)
		elseif n == 38 or n == 48 then
			local key = n == 38 and "fg" or "bg"
			local mode = tonumber(values[i + 1])
			local count = mode == 5 and 1 or (mode == 2 and 3 or 0)
			local channels = {}
			for j = 1, count do
				channels[j] = tonumber(values[i + 1 + j])
			end
			if count > 0 and #channels == count then
				local valid = true
				for _, channel in ipairs(channels) do
					valid = valid and channel >= 0 and channel <= 255
				end
				if valid then
					style[key] = count == 1 and color(channels[1]) or string.format("#%02x%02x%02x", unpack(channels))
				end
			end
			i = i + 1 + count
		end
		i = i + 1
	end
	return style
end

-- State crosses output events and lines, including incomplete CSI/OSC sequences.
function M.parse(text, seed)
	local state = vim.deepcopy(seed or { style = {}, pending = "" })
	text = state.pending .. text
	state.pending = ""
	local chunks, spans, col, i = {}, {}, 0, 1
	while i <= #text do
		if text:byte(i) == 27 then
			local kind = text:sub(i + 1, i + 1)
			local finish
			if kind == "[" then
				finish = text:find("[@-~]", i + 2)
				if finish and text:sub(finish, finish) == "m" then
					state.style = sgr(state.style, text:sub(i + 2, finish - 1))
				end
			elseif kind == "]" then
				local bell = text:find("\7", i + 2, true)
				local st = text:find("\27\\", i + 2, true)
				finish = bell and (not st or bell < st) and bell or (st and st + 1)
			elseif kind ~= "" then
				finish = i + 1
			end
			if not finish then
				state.pending = text:sub(i)
				break
			end
			i = finish + 1
		else
			local finish = (text:find("\27", i, true) or (#text + 1)) - 1
			local chunk = text:sub(i, finish)
			chunks[#chunks + 1] = chunk
			if next(state.style) then
				spans[#spans + 1] = { col, col + #chunk, vim.deepcopy(state.style) }
			end
			col = col + #chunk
			i = finish + 1
		end
	end
	return table.concat(chunks), spans, state
end

local function group(style)
	local key = vim.inspect(style)
	if not groups[key] then
		local name = "FoxDapAnsi" .. tostring(vim.tbl_count(groups) + 1)
		vim.api.nvim_set_hl(0, name, style)
		groups[key] = name
	end
	return groups[key]
end

local function queue(buf, data, first)
	data.dirty = math.min(data.dirty or first, first)
	if data.queued then
		return
	end
	data.queued = true
	vim.schedule(function()
		data.queued = false
		if buffers[buf] ~= data or not vim.api.nvim_buf_is_loaded(buf) then
			return
		end
		local start = data.dirty
		data.dirty = nil
		local seed = start > 1 and data.lines[start - 1].state or nil
		local clean = {}
		for row = start, #data.lines do
			local line = data.lines[row]
			line.text, line.spans, line.state = M.parse(line.raw, seed)
			seed = line.state
			clean[#clean + 1] = line.text
		end
		data.internal = true
		local modifiable = vim.bo[buf].modifiable
		local ok, err = pcall(function()
			local current = vim.api.nvim_buf_get_lines(buf, start - 1, -1, false)
			if not vim.deep_equal(current, clean) then
				vim.bo[buf].modifiable = true
				-- Keep the DAP prompt's ':' mark on its own row; replacing the
				-- whole suffix with set_lines moves it into the output.
				for idx, line in ipairs(clean) do
					if line ~= current[idx] then
						local row = start + idx - 2
						vim.api.nvim_buf_set_text(buf, row, 0, row, #current[idx], { line })
					end
				end
			end
			vim.api.nvim_buf_clear_namespace(buf, M.namespace, start - 1, -1)
			for row = start, #data.lines do
				local line = data.lines[row]
				line.visible = line.text
				for _, span in ipairs(line.spans) do
					vim.api.nvim_buf_set_extmark(buf, M.namespace, row - 1, span[1], {
						end_col = span[2],
						hl_group = group(span[3]),
						priority = 120,
					})
				end
			end
		end)
		vim.bo[buf].modifiable = modifiable
		data.internal = false
		if not ok then
			vim.notify("DAP ANSI: " .. tostring(err), vim.log.levels.WARN)
		end
	end)
end

function M.attach(buf)
	if buffers[buf] then
		return
	end
	local data = { lines = {} }
	buffers[buf] = data
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		data.lines[#data.lines + 1] = { raw = line, visible = line }
	end
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function(_, _, _, first, last, new_last)
			if buffers[buf] ~= data then
				return true
			end
			if data.internal then
				return
			end
			local incoming = vim.api.nvim_buf_get_lines(buf, first, new_last, false)
			local old = data.lines[first + 1]
			local cleared = first == 0 and last == #data.lines and #incoming == 1 and incoming[1] == ""
			for _ = first + 1, last do
				table.remove(data.lines, first + 1)
			end
			for idx, line in ipairs(incoming) do
				local raw = line
				-- DAP rewrites its last line to append chunks. Retain stripped codes.
				if not cleared and idx == 1 and first < last and old and line:sub(1, #old.visible) == old.visible then
					raw = old.raw .. line:sub(#old.visible + 1)
				end
				table.insert(data.lines, first + idx, { raw = raw, visible = line })
			end
			queue(buf, data, first + 1)
		end,
		on_detach = function()
			if buffers[buf] == data then
				buffers[buf] = nil
			end
		end,
		on_reload = function()
			buffers[buf] = nil
			vim.schedule(function()
				if vim.api.nvim_buf_is_loaded(buf) then
					M.attach(buf)
				end
			end)
		end,
	})
	queue(buf, data, 1)
end

function M.setup()
	local augroup = vim.api.nvim_create_augroup("FoxDapAnsi", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = augroup,
		pattern = { "dap-repl", "dapui_console" },
		callback = function(args)
			M.attach(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = function()
			groups = {}
			for buf, data in pairs(buffers) do
				queue(buf, data, 1)
			end
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains({ "dap-repl", "dapui_console" }, vim.bo[buf].filetype) then
			M.attach(buf)
		end
	end
end

return M
