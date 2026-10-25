-- Syntax-tree based tag closing and paired rename, without a plugin runtime.
local M = {}
local ns = vim.api.nvim_create_namespace("fox_autotag")
local states = {}
local opening = { start_tag = true, STag = true, jsx_opening_element = true }
local closing = { end_tag = true, ETag = true, jsx_closing_element = true }
local void = {}
for name in ("area base br col embed hr img input link meta param source track wbr"):gmatch("%S+") do
	void[name] = true
end
local function name_node(node)
	for child in node:iter_children() do
		if child:named() and not child:missing() then
			return child
		end
	end
end
local function parser(buf)
	local ft = vim.bo[buf].filetype
	local aliases =
		{ typescriptreact = "tsx", tsx = "tsx", javascriptreact = "javascript", jsx = "javascript", blade = "html" }
	local ok, p = pcall(vim.treesitter.get_parser, buf, aliases[ft])
	if ok and p then
		local parsed = pcall(p.parse, p)
		if parsed then
			return p
		end
	end
end
local function children(node)
	local start, finish
	for child in node:iter_children() do
		if opening[child:type()] then
			start = child
		elseif closing[child:type()] and not child:missing() then
			finish = child
		end
	end
	return start, finish
end
local function text(buf, node)
	return vim.treesitter.get_node_text(node, buf)
end
function M.snapshot(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local pairs = {}
	states[buf] = pairs
	local p = parser(buf)
	if not p then
		return
	end
	local function visit(node)
		local a, b = children(node)
		if a and b then
			a, b = name_node(a), name_node(b)
			if a and b and text(buf, a) == text(buf, b) then
				local function mark(n)
					local sr, sc, er, ec = n:range()
					return vim.api.nvim_buf_set_extmark(
						buf,
						ns,
						sr,
						sc,
						{ end_row = er, end_col = ec, right_gravity = false, end_right_gravity = true }
					)
				end
				pairs[#pairs + 1] = { a = mark(a), b = mark(b), name = text(buf, a) }
			end
		end
		for child in node:iter_children() do
			if child:named() then
				visit(child)
			end
		end
	end
	p:for_each_tree(function(tree)
		visit(tree:root())
	end)
end
local function marked(buf, id)
	local m = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
	if #m == 0 or m[3].invalid then
		return
	end
	local r, c, er, ec = m[1], m[2], m[3].end_row, m[3].end_col
	local ok, lines = pcall(vim.api.nvim_buf_get_text, buf, r, c, er, ec, {})
	if not ok then
		return
	end
	return table.concat(lines, "\n"), { r, c, er, ec }
end
function M.rename(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable then
		return
	end
	for _, pair in ipairs(states[buf] or {}) do
		local a, ar = marked(buf, pair.a)
		local b, br = marked(buf, pair.b)
		local new, target
		if a and b then
			if a ~= pair.name and b == pair.name then
				new, target = a, br
			elseif b ~= pair.name and a == pair.name then
				new, target = b, ar
			end
		end
		if new and new:match("^[%a_][%w_%.:%-]*$") then
			vim.api.nvim_buf_call(buf, function()
				pcall(vim.cmd, "undojoin")
			end)
			vim.api.nvim_buf_set_text(buf, target[1], target[2], target[3], target[4], { new })
			pair.name = new
		end
	end
end
function M.close(buf, row, col)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].modifiable or not parser(buf) or col < 1 then
		return false
	end
	local p = parser(buf)
	local ok, node =
		pcall(vim.treesitter.get_node, { bufnr = buf, lang = p:lang(), pos = { row, col - 1 }, ignore_injections = false })
	if not ok then
		return false
	end
	while node and not opening[node:type()] do
		node = node:parent()
	end
	if not node then
		return false
	end
	local _, _, er, ec = node:range()
	if er ~= row or ec ~= col then
		return false
	end
	local source = text(buf, node)
	if source:match("/%s*>$") then
		return false
	end
	local n = name_node(node)
	local name = n and text(buf, n) or ""
	if name ~= "" and not name:match("^[%a_][%w_%.:%-]*$") then
		return false
	end
	local ft = vim.bo[buf].filetype
	if ft ~= "xml" and node:type() ~= "jsx_opening_element" and void[name:lower()] then
		return false
	end
	local parent = node:parent()
	local finish
	if parent then
		local start
		start, finish = children(parent)
	end
	if finish then
		return false
	end
	local after = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]:sub(col + 1)
	if after:sub(1, #name + 3) == "</" .. name .. ">" then
		return false
	end
	vim.api.nvim_buf_call(buf, function()
		pcall(vim.cmd, "undojoin")
	end)
	local cursor = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_win_get_cursor(0)
	vim.api.nvim_buf_set_text(buf, row, col, row, col, { "</" .. name .. ">" })
	if cursor then
		vim.api.nvim_win_set_cursor(0, cursor)
	end
	M.snapshot(buf)
	return true
end
function M.setup()
	local group = vim.api.nvim_create_augroup("fox_autotag", { clear = true })
	local fts = {
		html = true,
		xml = true,
		javascriptreact = true,
		typescriptreact = true,
		javascript = true,
		typescript = true,
		vue = true,
		svelte = true,
		astro = true,
		php = true,
		blade = true,
		jsx = true,
		tsx = true,
		markdown = true,
	}
	vim.api.nvim_create_autocmd("InsertEnter", {
		group = group,
		callback = function(ev)
			if fts[vim.bo[ev.buf].filetype] then
				M.snapshot(ev.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "TextChangedI", "InsertLeave" }, {
		group = group,
		callback = function(ev)
			if fts[vim.bo[ev.buf].filetype] then
				M.rename(ev.buf)
			end
		end,
	})
	vim.api.nvim_create_autocmd("InsertCharPre", {
		group = group,
		callback = function(ev)
			if vim.v.char ~= ">" or not fts[vim.bo[ev.buf].filetype] then
				return
			end
			local win = vim.api.nvim_get_current_win()
			local pos = vim.api.nvim_win_get_cursor(win)
			vim.schedule(function()
				if
					vim.api.nvim_win_is_valid(win)
					and vim.api.nvim_win_get_buf(win) == ev.buf
					and vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
				then
					local cursor = vim.api.nvim_win_get_cursor(win)
					if cursor[1] == pos[1] and cursor[2] == pos[2] + 1 then
						M.close(ev.buf, cursor[1] - 1, cursor[2])
					end
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(ev)
			states[ev.buf] = nil
		end,
	})
end
return M
