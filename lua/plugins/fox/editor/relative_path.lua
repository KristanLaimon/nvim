-- ============================================================================
-- FOX PLUGIN: Relative Path Copier (Copy active file relative path to clipboard).
-- ============================================================================
-- WHAT IT DOES
--   Copies the relative path of the currently active/focused file (from cwd)
--   to the system clipboard.
--
-- BEHAVIOR
--   - If focused on an editor tab/split, copies the relative path of that focused buffer.
--   - If multiple tabs/windows are open, prioritizes the currently focused tab/window.
--   - If only 1 file is open, defaults to that one.
--   - If focus is currently in a sidebar or transient UI (e.g. neo-tree, terminal),
--     intelligently resolves the active editor file buffer in the current tabpage.
-- ============================================================================

local M = {}

--- Checks if a buffer represents an actual file on disk.
--- @param buf integer
--- @return boolean
local function is_file_buffer(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype ~= "" then
		return false
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return false
	end
	local ft = vim.bo[buf].filetype
	local non_file_fts = {
		alpha = true,
		dashboard = true,
		["neo-tree"] = true,
		toggleterm = true,
		fox_diff_sidebar = true,
		fox_todo_sidebar = true,
		TelescopePrompt = true,
		help = true,
	}
	if non_file_fts[ft] then
		return false
	end
	return true
end

--- Resolves the currently focused or active file buffer in the editor.
--- @return integer|nil bufnr
local function resolve_active_buffer()
	-- 1. Check current window buffer
	local cur_win = vim.api.nvim_get_current_win()
	if vim.api.nvim_win_is_valid(cur_win) then
		local cur_buf = vim.api.nvim_win_get_buf(cur_win)
		if is_file_buffer(cur_buf) then
			return cur_buf
		end
	end

	-- 2. Check alternate buffer (#)
	local alt_buf = vim.fn.bufnr("#")
	if alt_buf and alt_buf > 0 and is_file_buffer(alt_buf) then
		return alt_buf
	end

	-- 3. Check other windows in the current tabpage
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local b = vim.api.nvim_win_get_buf(win)
			if is_file_buffer(b) then
				return b
			end
		end
	end

	-- 4. Check visual tabs from bufferline or listed buffers
	local has_bl, bl = pcall(require, "bufferline")
	if has_bl and type(bl.get_elements) == "function" then
		local res = bl.get_elements()
		local elements = res and res.elements
		if elements and type(elements) == "table" then
			for _, elem in ipairs(elements) do
				if elem and elem.id and is_file_buffer(elem.id) then
					return elem.id
				end
			end
		end
	end

	-- 5. Fallback to any listed real file buffer
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.fn.buflisted(b) == 1 and is_file_buffer(b) then
			return b
		end
	end

	return nil
end

--- Returns the relative path of the active file buffer from the current working directory.
--- @return string|nil rel_path
--- @return string|nil full_path
--- @return integer|nil bufnr
function M.get_active_relative_path()
	local buf = resolve_active_buffer()
	if not buf then
		return nil, nil, nil
	end

	local full_path = vim.api.nvim_buf_get_name(buf)
	if not full_path or full_path == "" then
		return nil, nil, nil
	end

	local rel_path = vim.fn.fnamemodify(full_path, ":.")
	-- Normalize backslashes to forward slashes for clean cross-platform path formatting
	rel_path = rel_path:gsub("\\", "/")

	return rel_path, full_path, buf
end

--- Copies the relative path of the active file to the system clipboard and notifies.
--- @return string|nil copied_path
function M.copy_relative_path()
	local rel_path, _, _ = M.get_active_relative_path()
	if not rel_path or rel_path == "" then
		vim.notify("No active file buffer to copy relative path from", vim.log.levels.WARN, {
			title = "Copy Relative Path",
		})
		return nil
	end

	pcall(vim.fn.setreg, "+", rel_path)
	pcall(vim.fn.setreg, "*", rel_path)

	vim.notify(string.format("📋 Copied to clipboard: %s", rel_path), vim.log.levels.INFO, {
		title = "Copy Relative Path",
	})
	return rel_path
end

--- Registers user commands.
function M.setup()
	local function cmd_fn()
		M.copy_relative_path()
	end

	pcall(vim.api.nvim_create_user_command, "CopyRelativePath", cmd_fn, {
		desc = "Copy active file path relative to cwd to clipboard",
	})
	pcall(vim.api.nvim_create_user_command, "FoxCopyRelativePath", cmd_fn, {
		desc = "Copy active file path relative to cwd to clipboard",
	})
end

local lazyspec = require("fox.core.lazyspec")

return setmetatable({
	name = "fox_relative_path",
	dir = lazyspec.for_module(),
	cmd = { "CopyRelativePath", "FoxCopyRelativePath" },
	config = function()
		M.setup()
	end,
}, {
	__index = M,
})
