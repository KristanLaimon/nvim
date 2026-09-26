-- ============================================================================
-- FOX PHP: Composer & Local Vendor Bin Manager
-- ============================================================================
-- WHAT IT DOES
--   1. Prepends project `<cwd>/vendor/bin` to `vim.env.PATH`.
--   2. Keeps PATH updated when Neovim boots (`VimEnter`) or directory changes (`DirChanged`).
-- ============================================================================

local M = {}

local is_win = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
local path_sep = is_win and ";" or ":"

--- Prepends local `<cwd>/vendor/bin` to PATH if not already present.
function M.update_vendor_path()
	local cwd = vim.fn.getcwd()
	local vendor_bin = is_win and (cwd:gsub("/", "\\") .. "\\vendor\\bin") or (cwd .. "/vendor/bin")
	if not string.find(vim.env.PATH or "", vendor_bin, 1, true) then
		vim.env.PATH = vendor_bin .. path_sep .. (vim.env.PATH or "")
	end
end

--- Setup autocmds and initial PATH setup for Composer vendor bin.
function M.setup()
	-- Override Scoop's default PHP_INI_SCAN_DIR inside Neovim's process environment
	-- so PHP child processes won't scan Scoop's duplicate `cli/php.ini` file.
	if is_win then
		vim.env.PHP_INI_SCAN_DIR = ""
	end

	M.update_vendor_path()

	vim.api.nvim_create_autocmd({ "DirChanged", "VimEnter" }, {
		group = vim.api.nvim_create_augroup("FoxPHPComposerPath", { clear = true }),
		callback = function()
			M.update_vendor_path()
		end,
	})
end

return M
