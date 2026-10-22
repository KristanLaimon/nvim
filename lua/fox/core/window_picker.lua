local M = {}

local selection_chars = "FJDKSLA;CMRUEIWOQP"
local excluded_filetypes = { "NvimTree", "neo-tree", "neo-tree-popup", "notify", "snacks_notif" }

--- Synchronous target selection for Neo-tree; never changes the focused window.
---@return integer|nil
function M.pick_window()
	local current = vim.api.nvim_get_current_win()
	local windows = {}
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local config = vim.api.nvim_win_get_config(win)
		local buf = vim.api.nvim_win_get_buf(win)
		if
			win ~= current
			and config.relative == ""
			and config.focusable ~= false
			and not vim.tbl_contains(excluded_filetypes, vim.bo[buf].filetype)
			and not vim.tbl_contains({ "terminal", "quickfix" }, vim.bo[buf].buftype)
		then
			table.insert(windows, win)
		end
	end
	if #windows < 2 then
		return windows[1]
	end

	local labels, saved = {}, {}
	local width = 1
	while (#selection_chars) ^ width < #windows do
		width = width + 1
	end
	local ok, selected = pcall(function()
		for index, win in ipairs(windows) do
			local number, label = index - 1, ""
			for _ = 1, width do
				local digit = number % #selection_chars + 1
				label = selection_chars:sub(digit, digit) .. label
				number = math.floor(number / #selection_chars)
			end
			labels[label] = win
			saved[win] = vim.api.nvim_get_option_value("winbar", { win = win, scope = "local" })
			vim.api.nvim_set_option_value("winbar", "%=%#IncSearch# " .. label .. " %*%=", { win = win })
		end
		vim.cmd("redraw")
		vim.api.nvim_echo({ { "Pick window (Esc to cancel): ", "Question" } }, false, {})
		local input = ""
		for _ = 1, width do
			local char = vim.fn.getcharstr()
			if not selection_chars:find(char:upper(), 1, true) or #char ~= 1 then
				return nil
			end
			input = input .. char:upper()
		end
		return labels[input]
	end)
	for win, winbar in pairs(saved) do
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_option_value("winbar", winbar, { win = win })
		end
	end
	vim.api.nvim_echo({}, false, {})
	vim.cmd("redraw")
	if ok and selected and vim.api.nvim_win_is_valid(selected) then
		return selected
	end
end

return M
