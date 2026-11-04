-- A temporary buffer tab shared by file browsers; edits and pins keep the file.
local M = {}

function M.new(owner, win)
	return { owner = owner, win = win, original = vim.api.nvim_win_get_buf(win), owned = {} }
end

local function release(session, buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not session.owned[buf] then
		return
	end
	local tabs = package.loaded["fox.ui.tabline"]
	local pinned = tabs and tabs.is_pinned(buf)
	if not vim.bo[buf].modified and not pinned and #vim.fn.win_findbuf(buf) == 0 then
		vim.bo[buf].buflisted = false
	end
	vim.b[buf].fox_preview_owner = nil
	session.owned[buf] = nil
end

function M.show(session, filename, win)
	win = win or session.win
	assert(vim.api.nvim_win_is_valid(win), "Preview editor window was closed")
	if win ~= session.win then
		session.original = vim.api.nvim_win_get_buf(win)
	end
	local buf = vim.fn.bufadd(filename)
	vim.fn.bufload(buf)
	local previous = session.current
	if not vim.bo[buf].buflisted then
		session.owned[buf] = true
		vim.b[buf].fox_preview_owner = session.owner
	end
	vim.bo[buf].buflisted = true
	vim.api.nvim_win_set_buf(win, buf)
	session.win, session.current = win, buf
	if previous ~= buf then
		release(session, previous)
	end
	vim.cmd("redrawtabline")
	return buf
end

function M.keep(session)
	local buf = session.current
	if buf and vim.api.nvim_buf_is_valid(buf) then
		session.owned[buf] = nil
		vim.b[buf].fox_preview_owner = nil
		vim.bo[buf].buflisted = true
		session.original = buf
	end
end

function M.close(session)
	if not session then
		return
	end
	local win, buf = session.win, session.current
	if
		buf
		and session.owned[buf]
		and vim.api.nvim_buf_is_valid(buf)
		and not vim.bo[buf].modified
		and vim.api.nvim_win_is_valid(win)
		and vim.api.nvim_win_get_buf(win) == buf
		and vim.api.nvim_buf_is_valid(session.original)
	then
		vim.api.nvim_win_set_buf(win, session.original)
	end
	for owned in pairs(session.owned) do
		release(session, owned)
	end
	session.current = nil
	vim.cmd("redrawtabline")
end

return M
