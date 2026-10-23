local store = require("fox.core.store")
local M = {
	path = (vim.g.fox_testing or _G.fox_testing) and (vim.fn.tempname() .. ".json")
		or (vim.fn.stdpath("data") .. "/fox/query-layout.json"),
	windows = {},
}

local function bounded(value, minimum, maximum, fallback)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.max(minimum, math.min(maximum, value))
end

function M.load(view)
	local data = store.load(M.path, {})
	local values = type(data[view]) == "table" and data[view] or {}
	return {
		side = bounded(values.side, 0.15, 0.85, view == "visual" and 0.7 or nil),
		connections = bounded(values.connections, 0.1, 0.35, 0.22),
		results = bounded(values.results, 0.1, 0.65, 0.25),
		activity = bounded(values.activity, 1, 8, 2),
	}
end

function M.popup(kind, width, height)
	local data = store.load(M.path, {})
	local values = type(data.menus) == "table" and data.menus[kind] or nil
	values = type(values) == "table" and values or {}
	return math.floor(bounded(values.width, 8, math.max(8, vim.o.columns - 4), width)),
		math.floor(bounded(values.height, 1, math.max(1, vim.o.lines - 4), height))
end

function M.watch(win, kind)
	M.windows[win] = { kind = kind, width = vim.api.nvim_win_get_width(win), height = vim.api.nvim_win_get_height(win) }
end

function M.save(state)
	local data, changed = store.load(M.path, {}), false
	if not state.compact and state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
		local sizes = {}
		for key, field in pairs({ side = "side_win", connections = "connections_win" }) do
			if state[field] and vim.api.nvim_win_is_valid(state[field]) then
				sizes[key] = vim.api.nvim_win_get_width(state[field]) / vim.o.columns
			end
		end
		if state.result_win and vim.api.nvim_win_is_valid(state.result_win) then
			sizes.results = vim.api.nvim_win_get_height(state.result_win) / vim.o.lines
		end
		if state.activity_win and vim.api.nvim_win_is_valid(state.activity_win) then
			sizes.activity = vim.api.nvim_win_get_height(state.activity_win)
		end
		if not vim.deep_equal(data[state.view], sizes) then
			data[state.view], changed = sizes, true
		end
	end
	for win, previous in pairs(M.windows) do
		if not vim.api.nvim_win_is_valid(win) then
			M.windows[win] = nil
		else
			local width, height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
			if width ~= previous.width or height ~= previous.height then
				data.menus = type(data.menus) == "table" and data.menus or {}
				data.menus[previous.kind], changed = { width = width, height = height }, true
				previous.width, previous.height = width, height
			end
		end
	end
	if changed then
		return store.save(M.path, data)
	end
	return true
end

return M
