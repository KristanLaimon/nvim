-- FOX buffer tabs: ordered buffers, native mouse targets and bounded rendering.
local M = {}
local order, pins, last_active = {}, {}, {}
local scheduled
local function source(buf)
	return vim.b[buf].fox_media_source or buf
end
local function escape(value)
	return tostring(value):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end
local function hl(name)
	return "%#" .. name .. "#"
end
local function clip(text, width)
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	if width <= 0 then
		return ""
	end
	local result = ""
	for i = 0, vim.fn.strchars(text) - 1 do
		local char = vim.fn.strcharpart(text, i, 1)
		if vim.fn.strdisplaywidth(result .. char .. "…") > width then
			break
		end
		result = result .. char
	end
	return result .. "…"
end
M.clip = clip
function M.visible(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted then
		return false
	end
	buf = source(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	local query = package.loaded["fox.query"]
	local visible = query and query.buffer_visible(buf)
	if visible ~= nil then
		return visible
	end
	if vim.bo[buf].buftype ~= "" then
		return false
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" or name:match("^%a[%a%d+.-]+://") or name:match("^node:") or name:match("[/\\]node_modules[/\\]") then
		return false
	end
	local env = _G.Environments
	return not env or not env.is_buffer_in_current_environment or env.is_buffer_in_current_environment(buf)
end
function M.is_pinned(buf)
	return pins[source(buf)] == true
end
function M.set_pin(buf, value)
	if vim.api.nvim_buf_is_valid(buf) then
		pins[source(buf)] = value or nil
	end
	M.refresh()
end
local function restore_order()
	local ok, paths = pcall(vim.json.decode, vim.g.BufferlinePositions or "")
	if not ok or type(paths) ~= "table" then
		return
	end
	local lookup = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		lookup[vim.api.nvim_buf_get_name(buf)] = buf
	end
	order = {}
	for _, name in ipairs(paths) do
		if lookup[name] then
			order[#order + 1] = lookup[name]
			lookup[name] = nil
		end
	end
end
local function save_order()
	local paths = {}
	for _, buf in ipairs(order) do
		if vim.api.nvim_buf_is_valid(buf) then
			paths[#paths + 1] = vim.api.nvim_buf_get_name(buf)
		end
	end
	vim.g.BufferlinePositions = vim.json.encode(paths)
end
function M.buffers()
	local seen, valid = {}, {}
	for _, buf in ipairs(order) do
		if vim.api.nvim_buf_is_valid(buf) then
			valid[#valid + 1] = buf
			seen[buf] = true
		else
			pins[buf] = nil
		end
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if not seen[buf] then
			valid[#valid + 1] = buf
		end
	end
	order = valid
	local selected, ordinary, sources = {}, {}, {}
	for _, buf in ipairs(order) do
		if M.visible(buf) and not sources[source(buf)] then
			sources[source(buf)] = true
			local list = M.is_pinned(buf) and selected or ordinary
			list[#list + 1] = buf
		end
	end
	return vim.list_extend(selected, ordinary)
end
function M.get_elements()
	local elements = {}
	for _, buf in ipairs(M.buffers()) do
		elements[#elements + 1] = { id = buf }
	end
	return { elements = elements }
end
function M.label(buf)
	local query = package.loaded["fox.query"]
	local label = query and query.buffer_label(buf)
	if label then
		return label
	end
	local name = vim.api.nvim_buf_get_name(source(buf)):gsub("\\", "/")
	return (_G.Is_File_Deleted and _G.Is_File_Deleted(source(buf)) and "[D] " or "") .. (name:match("[^/]+$") or name)
end
function M.focus(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not M.visible(buf) then
		return
	end
	local dock = require("fox.core.dock")
	local win = dock.find_code_win()
	if not win then
		for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local ft = vim.bo[vim.api.nvim_win_get_buf(candidate)].filetype
			if vim.api.nvim_win_get_config(candidate).relative == "" and ft ~= "neo-tree" then
				win = candidate
				break
			end
		end
	end
	if win then
		local ok, err = pcall(function()
			vim.api.nvim_set_current_win(win)
			vim.api.nvim_win_set_buf(win, buf)
		end)
		if not ok then
			vim.notify(tostring(err), vim.log.levels.WARN)
		end
	end
end
function M.close(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	buf = source(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if not _G.Smart_Close_Buffer then
		pcall(require, "plugins.fox.editor.buffer_cleaner")
	end
	if _G.Smart_Close_Buffer then
		_G.Smart_Close_Buffer(buf, false)
	else
		local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = false })
		if not ok then
			vim.notify(tostring(err), vim.log.levels.WARN)
		end
	end
	M.refresh()
end
function M.click(buf, _, button)
	if button == "m" or button == "r" then
		M.close(buf)
	elseif button == "l" then
		M.focus(buf)
	end
end
function M.close_click(buf)
	M.close(buf)
end
function M.cycle(direction)
	local buffers, current = M.buffers(), vim.api.nvim_get_current_buf()
	if #buffers == 0 then
		return
	end
	local index = vim.fn.index(buffers, current)
	M.focus(buffers[((index < 0 and (direction > 0 and -1 or 0) or index) + direction) % #buffers + 1])
end
function M.move(direction)
	local buffers, current = M.buffers(), vim.api.nvim_get_current_buf()
	local index = vim.fn.index(buffers, current) + 1
	local target = buffers[index + direction]
	if not target or index == 0 or M.is_pinned(target) ~= M.is_pinned(current) then
		return
	end
	local a, b = vim.fn.index(order, current) + 1, vim.fn.index(order, target) + 1
	order[a], order[b] = order[b], order[a]
	save_order()
	M.refresh()
end
function M.close_others(direction)
	local buffers = M.buffers()
	local index = vim.fn.index(buffers, vim.api.nvim_get_current_buf()) + 1
	if index == 0 then
		return
	end
	for i, buf in ipairs(buffers) do
		if
			i ~= index
			and not M.is_pinned(buf)
			and (not direction or direction == "left" and i < index or direction == "right" and i > index)
		then
			M.close(buf)
		end
	end
end
function M.pick(close)
	local buffers = M.buffers()
	vim.ui.select(buffers, { prompt = close and "Close buffer:" or "Go to buffer:", format_item = M.label }, function(buf)
		if buf and M.visible(buf) then
			if close then
				M.close(buf)
			else
				M.focus(buf)
			end
		end
	end)
end
local function target(buf, callback, text)
	return "%" .. buf .. "@v:lua.require'fox.ui.tabline'." .. callback .. "@" .. text .. "%X"
end
function M.highlights()
	local fill = vim.api.nvim_get_hl(0, { name = "TabLineFill", link = false })
	local tab = vim.api.nvim_get_hl(0, { name = "TabLine", link = false })
	local sel = vim.api.nvim_get_hl(0, { name = "TabLineSel", link = false })
	vim.api.nvim_set_hl(0, "BufferLineFill", { bg = fill.bg })
	vim.api.nvim_set_hl(0, "BufferLineBackground", { fg = tab.fg, bg = tab.bg })
	vim.api.nvim_set_hl(0, "BufferLineBufferSelected", { fg = "#ffffff", bg = sel.bg, bold = true })
	vim.api.nvim_set_hl(0, "BufferLineBufferVisible", { fg = "#ffffff", bg = tab.bg, bold = true })
	vim.api.nvim_set_hl(0, "BufferLineSeparator", { fg = fill.bg, bg = tab.bg })
	for name, bg in pairs({
		BufferLineBackground = tab.bg or 0x202330,
		BufferLineBufferVisible = tab.bg or 0x202330,
		BufferLineBufferSelected = sel.bg or 0x303548,
	}) do
		vim.api.nvim_set_hl(0, "FoxTabSep" .. name, { fg = fill.bg or 0x181b24, bg = bg })
	end
	vim.api.nvim_set_hl(0, "FoxTabError", { link = "DiagnosticError" })
	vim.api.nvim_set_hl(0, "FoxTabWarn", { link = "DiagnosticWarn" })
end
local function sidebar(width)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if
			vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree"
			and vim.api.nvim_win_get_config(win).relative == ""
			and vim.api.nvim_win_get_position(win)[2] == 0
		then
			local size = math.min(vim.api.nvim_win_get_width(win) + 1, math.max(0, width - 12))
			local text = clip("🦊 Explorer", size)
			return hl("Directory") .. escape(text) .. string.rep(" ", size - vim.fn.strdisplaywidth(text)), size
		end
	end
	return "", 0
end
local function badge(width)
	local ws = package.loaded["plugins.fox.tools.workspaces"]
	if not ws or not ws.get_badge_components then
		return "", 0
	end
	local result, size = {}, 0
	for _, c in ipairs(ws.get_badge_components()) do
		size = size + vim.fn.strdisplaywidth(c.text)
		result[#result + 1] = hl(c.hl or "BufferLineFill") .. escape(c.text)
	end
	if size > width then
		return "", 0
	end
	local pages = vim.api.nvim_list_tabpages()
	if #pages > 1 then
		for index, page in ipairs(pages) do
			local label = " [" .. index .. "] "
			local length = vim.fn.strdisplaywidth(label)
			if size + length <= width then
				local group = page == vim.api.nvim_get_current_tabpage() and "BufferLineBufferSelected"
					or "BufferLineBackground"
				result[#result + 1] = hl(group) .. "%" .. index .. "T" .. label .. "%T"
				size = size + length
			end
		end
	end
	return table.concat(result), size
end
local function card(buf, name, width)
	if width < 8 then
		local text = clip(name, width)
		return hl("BufferLineBufferSelected") .. target(buf, "click", escape(text)), vim.fn.strdisplaywidth(text)
	end
	local group = buf == vim.api.nvim_get_current_buf() and "BufferLineBufferSelected"
		or vim.fn.bufwinid(buf) ~= -1 and "BufferLineBufferVisible"
		or "BufferLineBackground"
	local base = hl(group)
	local icon = require("fox.ui.icons").get("file", vim.api.nvim_buf_get_name(source(buf)))
	local prefix = M.is_pinned(buf) and "📌 " or icon .. " "
	local suffix = vim.bo[source(buf)].modified and " ●" or ""
	local d = vim.diagnostic.count(source(buf))
	local diagnostic = (d[1] or 0) > 0 and "  " .. d[1] or (d[2] or 0) > 0 and "  " .. d[2] or ""
	local overhead = vim.fn.strdisplaywidth(prefix .. suffix .. diagnostic .. " 󰅖  ") + 2
	local label = clip(name, math.max(1, math.min(18, width - overhead)))
	if overhead + vim.fn.strdisplaywidth(label) > width then
		prefix, suffix, diagnostic = "", "", ""
		label = clip(name, math.max(1, width - 5))
	end
	local body = " " .. prefix .. label .. suffix
	local result = hl("FoxTabSep" .. group) .. "" .. base .. target(buf, "click", escape(body))
	if diagnostic ~= "" then
		result = result
			.. hl((d[1] or 0) > 0 and "FoxTabError" or "FoxTabWarn")
			.. target(buf, "click", escape(diagnostic))
			.. base
	end
	result = result .. target(buf, "close_click", " 󰅖 ") .. hl("FoxTabSep" .. group) .. ""
	return result, vim.fn.strdisplaywidth(body .. diagnostic .. " 󰅖 ") + 2
end
function M.render()
	local width = vim.o.columns
	local left, offset = sidebar(width)
	local right, badge_width = badge(math.max(0, math.floor((width - offset) / 3)))
	local budget = math.max(1, width - offset - badge_width)
	local buffers, labels, counts = M.buffers(), {}, {}
	for _, buf in ipairs(buffers) do
		local name = M.label(buf)
		labels[buf] = name
		counts[name] = (counts[name] or 0) + 1
	end
	for _, buf in ipairs(buffers) do
		if counts[labels[buf]] > 1 then
			local name = vim.api.nvim_buf_get_name(source(buf)):gsub("\\", "/")
			local deleted = labels[buf]:sub(1, 4) == "[D] " and "[D] " or ""
			labels[buf] = deleted .. (name:match("([^/]+/[^/]+)$") or name)
		end
	end
	local tab, active = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
	local current = vim.fn.index(buffers, active) + 1
	if current > 0 then
		last_active[tab] = active
	else
		current = math.max(1, vim.fn.index(buffers, last_active[tab] or -1) + 1)
	end
	local cards, sizes, chosen, used = {}, {}, {}, 0
	-- Reserve room for overflow markers. The active tab is allocated first.
	local reserve = 2 * (#tostring(#buffers) + 3)
	local overflow = #buffers > 1 and budget > reserve + 4
	local room = overflow and budget - reserve or budget
	for i, buf in ipairs(buffers) do
		cards[i], sizes[i] = card(buf, labels[buf], room)
	end
	local function add(i)
		if chosen[i] then
			return true
		end
		if buffers[i] and used + sizes[i] <= room then
			chosen[i] = true
			used = used + sizes[i]
			return true
		end
	end
	add(current)
	for i, buf in ipairs(buffers) do
		if not M.is_pinned(buf) or not add(i) then
			break
		end
	end
	local left_open, right_open = true, true
	for distance = 1, #buffers do
		if left_open then
			left_open = add(current - distance)
		end
		if right_open then
			right_open = add(current + distance)
		end
	end
	local result, hidden = {}, 0
	for i in ipairs(buffers) do
		if chosen[i] then
			if hidden > 0 and overflow then
				result[#result + 1] = hl("BufferLineFill") .. target(buffers[i - 1], "click", escape(" ‹" .. hidden .. " "))
				hidden = 0
			end
			result[#result + 1] = cards[i]
		else
			hidden = hidden + 1
		end
	end
	if hidden > 0 and overflow then
		result[#result + 1] = hl("BufferLineFill")
			.. target(buffers[#buffers - hidden + 1], "click", escape(" " .. hidden .. "› "))
	end
	return left .. table.concat(result) .. hl("BufferLineFill") .. "%<%=" .. right
end
function M.refresh()
	if scheduled then
		return
	end
	scheduled = true
	vim.schedule(function()
		scheduled = false
		vim.cmd.redrawtabline()
	end)
end
function M.setup()
	pcall(require, "plugins.fox.tools.workspaces")
	restore_order()
	M.highlights()
	vim.o.showtabline = 2
	vim.o.tabline = "%!v:lua.require'fox.ui.tabline'.render()"
	local group = vim.api.nvim_create_augroup("FoxNativeTabline", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			M.highlights()
			M.refresh()
		end,
	})
	vim.api.nvim_create_autocmd({
		"BufAdd",
		"BufDelete",
		"BufEnter",
		"BufFilePost",
		"BufModifiedSet",
		"DiagnosticChanged",
		"WinEnter",
		"WinClosed",
		"VimResized",
		"DirChanged",
		"SessionLoadPost",
	}, { group = group, callback = M.refresh })
	vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = restore_order })
	for name, fn in pairs({
		BufferLineCycleNext = function()
			M.cycle(1)
		end,
		BufferLineCyclePrev = function()
			M.cycle(-1)
		end,
		BufferLineMoveNext = function()
			M.move(1)
		end,
		BufferLineMovePrev = function()
			M.move(-1)
		end,
		BufferLinePick = function()
			M.pick(false)
		end,
		BufferLinePickClose = function()
			M.pick(true)
		end,
		BufferLineCloseOthers = function()
			M.close_others()
		end,
		BufferLineCloseLeft = function()
			M.close_others("left")
		end,
		BufferLineCloseRight = function()
			M.close_others("right")
		end,
		BufferLineTogglePin = function()
			require("plugins.fox.ui.pinned_tabs").toggle_pin()
		end,
	}) do
		vim.api.nvim_create_user_command(name, fn, {})
	end
	vim.api.nvim_create_user_command("BufferLineGoToBuffer", function(args)
		local buffers = M.buffers()
		local index = tonumber(args.args)
		local buf = index == -1 and buffers[#buffers] or buffers[index]
		if buf then
			M.focus(buf)
		end
	end, { nargs = 1 })
	M.refresh()
end
return M
