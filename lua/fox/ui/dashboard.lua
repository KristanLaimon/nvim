-- Native scratch-buffer dashboard. Keep the alpha filetype and Ex commands
-- because workspace, pin and buffer-cleaner modules already use that contract.
local M = {}
local ns = vim.api.nvim_create_namespace("fox_dashboard")
local state = {}

function M.layout()
	local d = {
		section = {
			header = { val = {}, opts = {} },
			buttons = { val = {}, opts = { spacing = 1 } },
			footer = {
				val = "",
				opts = {},
			},
		},
	}
	d.opts = { layout = { { val = 1 } }, sections = d.section }
	function d.button(key, label, command)
		return { key = key, label = label, command = command }
	end
	return d
end

local function value(v)
	return type(v) == "function" and v() or v
end

local function random_index(count)
	local bytes = vim.uv.random(4)
	if not bytes then
		return math.random(count)
	end
	local a, b, c, d = bytes:byte(1, 4)
	return (a * 16777216 + b * 65536 + c * 256 + d) % count + 1
end

local function execute(button)
	if button then
		vim.cmd(button.command:gsub("^:", ""):gsub("<CR>$", ""))
	end
end

function M.draw()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local win = vim.fn.bufwinid(state.buf)
	if win == -1 then
		return
	end
	local window_width = vim.api.nvim_win_get_width(win)
	local height = vim.api.nvim_win_get_height(win)
	local art = state.opts.artwork
	local wide = art and window_width >= 100 and height >= 22
	local large = wide and window_width >= 140 and height >= 32 and state.opts.large_header
	local width = wide and (large and 100 or 50) or window_width
	local left_width = wide and math.min(34, window_width - width - 4) or window_width
	local outer = wide and math.floor((window_width - width - left_width - 4) / 2) or 0
	local sections = state.opts.sections
	local lines, highlights, rows = {}, {}, {}
	local function add(text, hl)
		local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(text)) / 2))
		lines[#lines + 1] = string.rep(" ", pad) .. text
		if hl then
			highlights[#highlights + 1] = { #lines - 1, pad, hl, #lines[#lines] }
		end
		return pad
	end
	for _ = 1, value(state.opts.layout[1].val) do
		add("")
	end
	local compact = art and height < #sections.buttons.val + 12
	local header = large or value(sections.header.val)
	if art and (width < 50 or compact) then
		header = { "F O X V I M" }
	end
	local header_width = 0
	for _, line in ipairs(header) do
		header_width = math.max(header_width, vim.fn.strdisplaywidth(line))
	end
	for _, line in ipairs(header) do
		add(line .. string.rep(" ", header_width - vim.fn.strdisplaywidth(line)), sections.header.opts.hl)
	end
	if not compact then
		add("")
		add("")
	end
	local spacing = sections.buttons.opts.spacing or 1
	local count = #sections.buttons.val
	if compact or #lines + count + math.max(0, count - 1) * spacing + (art and 6 or 2) > height then
		spacing = 0
	end
	for i, button in ipairs(sections.buttons.val) do
		local label = value(button.label)
		if art then
			while vim.fn.strdisplaywidth(label .. " " .. button.key) > width and vim.fn.strchars(label) > 0 do
				label = vim.fn.strcharpart(label, 0, vim.fn.strchars(label) - 1)
			end
		end
		local gap = math.max(1, math.min(50, width) - vim.fn.strdisplaywidth(label .. button.key))
		local text = label .. string.rep(" ", gap) .. button.key
		local pad = add(text)
		highlights[#highlights + 1] = { #lines - 1, pad + #text - #button.key, "Keyword", pad + #text }
		rows[#rows + 1] = {
			line = #lines,
			column = pad + 3,
			first_column = pad + 1,
			last_column = pad + vim.fn.strdisplaywidth(text),
			button = button,
		}
		if i < #sections.buttons.val then
			for _ = 1, spacing do
				add("")
			end
		end
	end
	if not compact then
		add("")
		add(value(sections.footer.val), "Number")
	end
	if art then
		local left = {}
		local quote_index = state.quote_index or random_index(#art.quotes)
		state.quote_index = quote_index
		local quote = art.quotes[quote_index]
		local fox = state.fox or art.foxes[random_index(#art.foxes)]
		state.fox = fox
		local function left_add(text)
			if vim.fn.strdisplaywidth(text) <= left_width then
				left[#left + 1] = string.rep(" ", math.max(0, math.floor((left_width - vim.fn.strdisplaywidth(text)) / 2)))
					.. text
			end
		end
		local quote_line = ""
		for word in quote:gmatch("%S+") do
			local next_line = quote_line == "" and word or quote_line .. " " .. word
			if vim.fn.strdisplaywidth(next_line) > left_width and quote_line ~= "" then
				left_add(quote_line)
				quote_line = word
			else
				quote_line = next_line
			end
		end
		left_add(quote_line)
		local author = art.authors and art.authors[quote_index]
		left_add("- " .. (author or "A random fox"))
		if wide then
			left_add("")
			left_add("")
			local fox_width = 0
			for _, line in ipairs(fox) do
				fox_width = math.max(fox_width, vim.fn.strdisplaywidth(line))
			end
			if fox_width <= left_width and #left + #fox <= height then
				local padding = string.rep(" ", math.floor((left_width - fox_width) / 2))
				for _, line in ipairs(fox) do
					left[#left + 1] = padding .. line
				end
			end
			local left_top = math.max(0, math.floor((#lines - #left) / 2))
			for _ = 1, left_top do
				table.insert(left, 1, "")
			end
			local offset = outer + left_width + 4
			for i = 1, math.max(#lines, #left) do
				local prefix = string.rep(" ", outer) .. (left[i] or "")
				prefix = prefix .. string.rep(" ", math.max(0, offset - vim.fn.strdisplaywidth(prefix)))
				lines[i] = prefix .. (lines[i] or "")
			end
			-- Prefixes contain Unicode art, so highlights use byte offsets and mouse targets use cells.
			for _, hl in ipairs(highlights) do
				local prefix = string.rep(" ", outer) .. (left[hl[1] + 1] or "")
				local bytes = #prefix + math.max(0, offset - vim.fn.strdisplaywidth(prefix))
				hl[2], hl[4] = hl[2] + bytes, hl[4] + bytes
			end
			for _, row in ipairs(rows) do
				local prefix = string.rep(" ", outer) .. (left[row.line] or "")
				local bytes = #prefix + math.max(0, offset - vim.fn.strdisplaywidth(prefix))
				row.column = row.column + bytes
				row.first_column, row.last_column = row.first_column + offset, row.last_column + offset
			end
		else
			local prefix = {}
			for _, line in ipairs(left) do
				prefix[#prefix + 1] = line
			end
			if height >= #lines + #prefix + #fox + 1 then
				local fox_width = 0
				for _, line in ipairs(fox) do
					fox_width = math.max(fox_width, vim.fn.strdisplaywidth(line))
				end
				if fox_width <= width then
					local padding = string.rep(" ", math.floor((width - fox_width) / 2))
					for _, line in ipairs(fox) do
						prefix[#prefix + 1] = padding .. line
					end
				end
			end
			for i = #prefix, 1, -1 do
				table.insert(lines, 1, prefix[i])
			end
			for _, hl in ipairs(highlights) do
				hl[1] = hl[1] + #prefix
			end
			for _, row in ipairs(rows) do
				row.line = row.line + #prefix
			end
		end
		local top = math.max(0, math.floor((height - #lines) / 2))
		for _ = 1, top do
			table.insert(lines, 1, "")
		end
		for _, hl in ipairs(highlights) do
			hl[1] = hl[1] + top
		end
		for _, row in ipairs(rows) do
			row.line = row.line + top
		end
	end
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for _, hl in ipairs(highlights) do
		vim.api.nvim_buf_set_extmark(state.buf, ns, hl[1], hl[2], { end_col = hl[4], hl_group = hl[3] })
	end
	state.rows = rows
	local selected = math.min(state.selected or 1, #rows)
	if rows[selected] then
		vim.api.nvim_win_set_cursor(win, { rows[selected].line, rows[selected].column })
		if #lines <= height then
			vim.api.nvim_win_call(win, function()
				vim.fn.winrestview({ topline = 1 })
			end)
		end
	end
end
M.redraw = M.draw

function M.start()
	if not state.opts then
		return
	end
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].bufhidden = "wipe"
		vim.bo[state.buf].filetype = "alpha"
		vim.bo[state.buf].swapfile = false
		local function move(delta)
			local rows = state.rows or {}
			if #rows == 0 then
				return
			end
			state.selected = ((state.selected or 1) - 1 + delta) % #rows + 1
			M.draw()
		end
		for _, key in ipairs({ "j", "<Down>", "<Tab>" }) do
			vim.keymap.set("n", key, function()
				move(1)
			end, { buffer = state.buf })
		end
		for _, key in ipairs({ "k", "<Up>", "<S-Tab>" }) do
			vim.keymap.set("n", key, function()
				move(-1)
			end, { buffer = state.buf })
		end
		vim.keymap.set("n", "<CR>", function()
			local row = vim.api.nvim_win_get_cursor(0)[1]
			for _, entry in ipairs(state.rows or {}) do
				if entry.line == row then
					execute(entry.button)
					return
				end
			end
		end, { buffer = state.buf })
		local function click_button(key)
			local mouse = vim.fn.getmousepos()
			if mouse.winid == 0 or vim.api.nvim_win_get_buf(mouse.winid) ~= state.buf then
				-- Buffer-local mouse maps also receive clicks aimed at other windows.
				vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
				return
			end
			for index, entry in ipairs(state.rows or {}) do
				if mouse.line == entry.line and mouse.column >= entry.first_column and mouse.column <= entry.last_column then
					state.selected = index
					vim.api.nvim_set_current_win(mouse.winid)
					execute(entry.button)
					return
				end
			end
		end
		for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>" }) do
			vim.keymap.set("n", key, function()
				click_button(key)
			end, { buffer = state.buf, desc = "Click dashboard button" })
		end
		for _, button in ipairs(state.opts.sections.buttons.val) do
			vim.keymap.set("n", button.key, function()
				execute(button)
			end, { buffer = state.buf, desc = value(button.label) })
		end
	end
	state.selected = 1
	state.quote_index, state.fox = nil, nil
	vim.cmd.stopinsert()
	vim.api.nvim_win_set_buf(0, state.buf)
	M.draw()
	vim.api.nvim_exec_autocmds("User", { pattern = "AlphaReady", modeline = false })
end

function M.setup(opts)
	state.opts = opts
	vim.api.nvim_create_user_command("Alpha", M.start, { desc = "Open FoxVim dashboard" })
	vim.api.nvim_create_user_command("AlphaRedraw", M.draw, { desc = "Refresh FoxVim dashboard" })
	local group = vim.api.nvim_create_augroup("fox_dashboard", { clear = true })
	local saved = {}
	vim.api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		callback = function(ev)
			if ev.buf ~= state.buf then
				return
			end
			local win = vim.api.nvim_get_current_win()
			saved[win] = {
				number = vim.wo.number,
				relativenumber = vim.wo.relativenumber,
				signcolumn = vim.wo.signcolumn,
				wrap = vim.wo.wrap,
				cursorline = vim.wo.cursorline,
				cursorcolumn = vim.wo.cursorcolumn,
			}
			vim.wo.number = false
			vim.wo.relativenumber = false
			vim.wo.signcolumn = "no"
			vim.wo.wrap = false
			vim.wo.cursorline = false
			vim.wo.cursorcolumn = false
		end,
	})
	vim.api.nvim_create_autocmd("BufWinLeave", {
		group = group,
		callback = function(ev)
			if ev.buf ~= state.buf then
				return
			end
			local win = vim.api.nvim_get_current_win()
			for key, v in pairs(saved[win] or {}) do
				vim.api.nvim_set_option_value(key, v, { win = win })
			end
			saved[win] = nil
		end,
	})
	if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" and not vim.bo.modified and vim.bo.buftype == "" then
		M.start()
	end
end
return M
