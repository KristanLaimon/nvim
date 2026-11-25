local M = {}
local dock = require("fox.core.dock")
local layouts = {}

local function editor_tree(layout)
	local kind, value = unpack(layout)
	if kind == "leaf" then
		if dock.is_code_win(value) and not vim.wo[value].diff and not vim.wo[value].winfixbuf then
			return { win = value, key = tostring(value) }
		end
		return
	end

	local children, keys = {}, {}
	for _, child in ipairs(value) do
		local node = editor_tree(child)
		if node then
			children[#children + 1], keys[#keys + 1] = node, node.key
		end
	end
	if #children < 2 then
		return children[1]
	end
	return { axis = kind == "row" and 2 or 1, children = children, key = kind .. "(" .. table.concat(keys, ",") .. ")" }
end

-- The edge window gives Neovim a handle on the separator of a subtree.
local function bounds(node, axis)
	if node.win then
		local win = node.win
		local start = vim.api.nvim_win_get_position(win)[axis]
		local size = axis == 2 and vim.api.nvim_win_get_width(win) or vim.api.nvim_win_get_height(win)
		if axis == 1 and vim.wo[win].winbar ~= "" then
			size = size + 1
		end
		return start, start + size, win
	end
	local start, last, edge = math.huge, -math.huge, nil
	for _, child in ipairs(node.children) do
		local first, finish, win = bounds(child, axis)
		start = math.min(start, first)
		if finish > last then
			last, edge = finish, win
		end
	end
	return start, last, edge
end

local function measure(node, sizes)
	if not node.children then
		return
	end
	local lengths = {}
	for i, child in ipairs(node.children) do
		local first, last = bounds(child, node.axis)
		lengths[i] = last - first
		measure(child, sizes)
	end
	sizes[node.key] = lengths
end

local function restore(node, sizes)
	if not node.children then
		return
	end
	local axis, preferred = node.axis, sizes[node.key]
	local total, weight, previous = 0, 0, nil
	local gaps, targets = {}, {}
	for i, child in ipairs(node.children) do
		local first, last = bounds(child, axis)
		gaps[i] = previous and first - previous or 0
		total, weight = total + last - first, weight + preferred[i]
		previous = last
	end

	local start = bounds(node, axis)
	local offset, cumulative = 0, 0
	for i = 1, #node.children - 1 do
		offset, cumulative = offset + gaps[i], cumulative + preferred[i]
		targets[i] = start + offset + math.floor(total * cumulative / weight + 0.5)
	end

	local move = axis == 2 and vim.fn.win_move_separator or vim.fn.win_move_statusline
	local function adjust(i, sign)
		local _, edge, win = bounds(node.children[i], axis)
		local delta = targets[i] - edge
		if delta * sign > 0 then
			move(vim.fn.win_id2win(win), delta)
		end
	end
	-- Give growing siblings room before moving their other edge.
	for i = 1, #targets do
		adjust(i, -1)
	end
	for i = #targets, 1, -1 do
		adjust(i, 1)
	end
	for _, child in ipairs(node.children) do
		restore(child, sizes)
	end
end

local function reconcile()
	local tab = vim.api.nvim_get_current_tabpage()
	if vim.t[tab].fox_query_root then
		layouts[tab] = nil
		return
	end
	local layout = vim.fn.winlayout()
	local root = editor_tree(layout)
	if not root or not root.children then
		layouts[tab] = nil
		return
	end

	local left, right = bounds(root, 2)
	local top, bottom = bounds(root, 1)
	local viewport = { left, right, top, bottom, vim.o.columns, vim.o.lines, layout }
	local current = {}
	measure(root, current)
	local previous = layouts[tab]
	if not previous or previous.key ~= root.key then
		layouts[tab] = { key = root.key, viewport = viewport, preferred = current, applied = current }
	elseif not vim.deep_equal(previous.viewport, viewport) then
		restore(root, previous.preferred)
		local applied = {}
		measure(root, applied)
		previous.viewport, previous.applied = viewport, applied
	elseif not vim.deep_equal(previous.applied, current) then
		previous.preferred, previous.applied = current, current
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("FoxSplitProportions", { clear = true })
	local queued = false
	vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "WinNew", "WinClosed", "TabEnter", "FileType" }, {
		group = group,
		callback = function()
			if queued then
				return
			end
			queued = true
			-- Let the sidebar and dock finish setting their own dimensions first.
			vim.schedule(function()
				vim.schedule(function()
					queued = false
					for tab in pairs(layouts) do
						if not vim.api.nvim_tabpage_is_valid(tab) then
							layouts[tab] = nil
						end
					end
					reconcile()
				end)
			end)
		end,
	})
end

return M
