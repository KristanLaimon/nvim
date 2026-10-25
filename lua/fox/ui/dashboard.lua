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
	local width = vim.api.nvim_win_get_width(win)
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
	for _, line in ipairs(value(sections.header.val)) do
		add(line, sections.header.opts.hl)
	end
	add("")
	add("")
	for i, button in ipairs(sections.buttons.val) do
		local gap = math.max(0, math.min(50, width) - vim.fn.strdisplaywidth(button.label .. button.key))
		local text = button.label .. string.rep(" ", gap) .. button.key
		local pad = add(text)
		highlights[#highlights + 1] = { #lines - 1, pad + #text - #button.key, "Keyword", pad + #text }
		rows[#rows + 1] = { line = #lines, column = pad + 3, button = button }
		if i < #sections.buttons.val then
			for _ = 1, sections.buttons.opts.spacing or 1 do
				add("")
			end
		end
	end
	add("")
	add(value(sections.footer.val), "Number")
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
		for _, button in ipairs(state.opts.sections.buttons.val) do
			vim.keymap.set("n", button.key, function()
				execute(button)
			end, { buffer = state.buf, desc = button.label })
		end
	end
	state.selected = 1
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
	vim.schedule(function()
		if vim.fn.argc() == 0 and vim.api.nvim_buf_get_name(0) == "" and not vim.bo.modified and vim.bo.buftype == "" then
			M.start()
		end
	end)
end
return M
