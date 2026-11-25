local M = {}
local views = {}
local ui = require("fox.core.ui")
local render = require("fox.query.render")

local function attached(view)
	return vim.api.nvim_win_is_valid(view.sql_win)
		and vim.api.nvim_buf_is_valid(view.active)
		and view.consoles[view.active] ~= nil
end

local function shown(view)
	return attached(view)
		and vim.api.nvim_win_get_buf(view.sql_win) == view.active
		and vim.api.nvim_win_get_tabpage(view.sql_win) == vim.api.nvim_get_current_tabpage()
end

function M.current()
	local win = vim.api.nvim_get_current_win()
	local view = views[win]
	if view and shown(view) then
		return view
	end
	for _, candidate in pairs(views) do
		if (candidate.result_win == win or candidate.result_popup == win) and shown(candidate) then
			return candidate
		end
	end
end

function M.owns(win, buf)
	return views[win] ~= nil and views[win].active == buf and attached(views[win])
end

local function hide(view)
	local win = view.result_win
	view.result_win = nil
	ui.close(win)
end

function M.refresh(view)
	local item = view.consoles[view.active]
	if not shown(view) then
		hide(view)
		return
	end
	if not item.result then
		hide(view)
		ui.close(view.result_popup)
		view.result_popup, view.result_seen = nil, nil
		return
	end
	if view.result_seen ~= item.result then
		view.result_seen, view.results_hidden = item.result, false
		local lines = { "  QUERY / RESULTS  |  " .. (item.result_label or item.status), "  [q] Back to SQL", "" }
		local rows = render.results(item.result)
		vim.list_extend(lines, rows)
		if not view.result_buf or not vim.api.nvim_buf_is_valid(view.result_buf) then
			view.result_buf = ui.scratch_buffer({ filetype = "foxquery" })
			vim.bo[view.result_buf].bufhidden = "hide"
			vim.b[view.result_buf].fox_query_root = view.root
			for _, key in ipairs(ui.close_keys) do
				vim.keymap.set("n", key, function()
					if vim.api.nvim_get_current_win() == view.result_popup then
						ui.close(view.result_popup)
						view.result_popup = nil
					else
						view.results_hidden = true
						hide(view)
					end
					if shown(view) then
						vim.api.nvim_set_current_win(view.sql_win)
					end
				end, { buffer = view.result_buf, silent = true })
			end
		end
		vim.bo[view.result_buf].modifiable = true
		vim.api.nvim_buf_set_lines(view.result_buf, 0, -1, false, ui.sanitize_lines(lines))
		vim.bo[view.result_buf].modifiable = false
	end
	local height = vim.api.nvim_win_get_height(view.sql_win)
	if view.results_hidden or height < 4 then
		hide(view)
		return
	end
	local config = {
		relative = "win",
		win = view.sql_win,
		anchor = "SW",
		row = height + (vim.wo[view.sql_win].winbar ~= "" and 1 or 0),
		col = 0,
		width = vim.api.nvim_win_get_width(view.sql_win),
		height = math.min(12, math.max(2, math.floor(height / 3))),
		style = "minimal",
		border = "none",
		zindex = 45,
	}
	if view.result_win and vim.api.nvim_win_is_valid(view.result_win) then
		vim.api.nvim_win_set_config(view.result_win, config)
	else
		view.result_win = vim.api.nvim_open_win(view.result_buf, false, config)
		vim.wo[view.result_win].wrap = false
	end
end

function M.popup(view)
	if not shown(view) then
		return
	end
	M.refresh(view)
	if not view.result_buf or not vim.api.nvim_buf_is_valid(view.result_buf) then
		return
	end
	ui.close(view.result_popup)
	local _, win = ui.float(view.result_buf, { width = 0.9, height = 0.9, title = " Query results | q / Esc close " })
	view.result_popup = win
	vim.wo[win].wrap = false
end

function M.focus_results(view)
	view.result_seen, view.results_hidden = nil, false
	M.refresh(view)
	if view.result_win then
		vim.api.nvim_set_current_win(view.result_win)
	end
end

function M.attach(workspace, win, buf)
	local view = {
		inline = true,
		workspace = workspace,
		root = workspace.root,
		active = buf,
		sql_win = win,
		consoles = workspace.consoles,
		connection_status = workspace.connection_status,
		metadata = {},
	}
	views[win] = view
	return view
end

function M.detach(win)
	local view = views[win]
	if not view then
		return
	end
	views[win] = nil
	hide(view)
	ui.close(view.result_popup)
	if view.result_buf and vim.api.nvim_buf_is_valid(view.result_buf) then
		vim.api.nvim_buf_delete(view.result_buf, { force = true })
	end
end

function M.leave_environment(root)
	local resume = {}
	for win, view in pairs(views) do
		if view.root == root and shown(view) then
			resume[#resume + 1] = view
			hide(view)
			local placeholder = vim.api.nvim_create_buf(false, false)
			vim.bo[placeholder].bufhidden = "wipe"
			vim.api.nvim_win_set_buf(win, placeholder)
		end
	end
	return resume
end

function M.enter_environment(resume)
	for _, view in ipairs(resume or {}) do
		if views[view.sql_win] == view and attached(view) then
			vim.api.nvim_win_set_buf(view.sql_win, view.active)
			M.refresh(view)
		end
	end
end

function M.close_root(root)
	for win, view in pairs(views) do
		if view.root == root then
			M.detach(win)
		end
	end
end

function M.update()
	for win, view in pairs(views) do
		if not attached(view) then
			M.detach(win)
		else
			M.refresh(view)
		end
	end
end

return M
