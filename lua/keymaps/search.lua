-- ============================================================================
-- KEYMAPS: Search -- finding files, opening them in splits, following URLs.
-- ============================================================================
-- KEYS
--   <C-k>            Focus the window above, or find files when there is none
--   <C-S-/> / <C-?>  Find files, including ignored and hidden ones
--   <C-S-h/j/k/l>    Choose a file or current buffer for a directional split
--   <C-LeftMouse>    Open the URL under the mouse in the browser
--
-- SPECIAL CASE
--   While a debug session is running, <C-S-j> toggles the DAP repl instead of
--   opening a split -- the repl is what you want at a breakpoint, and the key is
--   in the same place as the terminal you would otherwise reach for.
-- ============================================================================

local debug_keymaps = require("keymaps.debug")

local M = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	keys = {
		--- Fuzzy find, honouring .gitignore.
		find_files = { "<C-k>", "<C-K>" },
		--- Find files in the current code window, even when a window is above it.
		find_here = {
			"<C-A-k>",
			"<C-A-K>",
			"<C-M-k>",
			"<C-M-K>",
			"<A-C-k>",
			"<A-C-K>",
			"<M-C-k>",
			"<M-C-K>",
		},
		--- Fuzzy find everything, ignored and hidden files included.
		find_all_files = {
			"<C-S-/>",
			"<C-?>",
		},
		--- Find a file and open it in a split. Direction follows hjkl.
		split = {
			h = { "<C-S-h>", "<C-S-H>" },
			j = { "<C-S-j>", "<C-S-J>" },
			k = { "<C-S-k>", "<C-S-K>" },
			l = { "<C-S-l>", "<C-S-L>" },
		},
		--- Open a URL under the mouse.
		open_url = "<C-LeftMouse>",
	},

	--- Split command per direction, and how each direction is described.
	splits = {
		h = { command = "leftabove vsplit", label = "Left (←)" },
		j = { command = "rightbelow split", label = "Down (↓)" },
		k = { command = "leftabove split", label = "Up (↑)" },
		l = { command = "rightbelow vsplit", label = "Right (→)" },
	},

	--- Matches a URL inside the WORD under the cursor.
	url_pattern = "https?://[^%s\"'<>%)%]]+",
}

-- ============================================================================
-- ACTIONS
-- ============================================================================

--- Opens the file picker; picking a file opens it in a split.
--- @param direction "h"|"j"|"k"|"l"
local function open_find_files_split(direction)
	local split = M.settings.splits[direction]
	local dir_cmd = {
		h = "TelescopeFindFilesSplitLeft",
		j = "TelescopeFindFilesSplitBelow",
		k = "TelescopeFindFilesSplitAbove",
		l = "TelescopeFindFilesSplitRight",
	}
	if dir_cmd[direction] and vim.fn.exists(":" .. dir_cmd[direction]) > 0 then
		vim.cmd(dir_cmd[direction])
		return
	end

	local ok, builtin = pcall(require, "telescope.builtin")
	if not ok then
		vim.notify("Telescope is not ready", vim.log.levels.ERROR)
		return
	end

	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	local find_opts = {
		prompt_title = " 🔍 Open File to the " .. (split and split.label or direction) .. " ",
		file_ignore_patterns = { "node_modules[/\\]", "node_modules$", "%.git[/\\]", "%.git$" },
		attach_mappings = function(prompt_bufnr)
			actions.select_default:replace(function()
				local selection = action_state.get_selected_entry()
				actions.close(prompt_bufnr)

				local filepath = selection and (selection.value or selection[1])
				if filepath and split then
					vim.cmd(split.command .. " " .. vim.fn.fnameescape(filepath))
				end
			end)
			return true
		end,
	}
	if vim.fn.executable("rg") == 1 then
		find_opts.find_command =
			{ "rg", "--files", "--color=never", "--hidden", "--no-require-git", "--glob", "!**/.git/*" }
	elseif vim.fn.executable("fd") == 1 then
		find_opts.find_command = { "fd", "--type", "f", "--hidden", "--no-require-git", "--exclude", ".git" }
	end

	builtin.find_files(find_opts)
end

-- ============================================================================
-- MAPPINGS
-- ============================================================================

--- Standard mapping options, with a description.
local function opts(desc)
	return { noremap = true, silent = true, desc = desc }
end

local function ensure_code_window()
	local ok, dock = pcall(require, "fox.core.dock")
	if not ok then
		return
	end
	local cur_win = vim.api.nvim_get_current_win()
	if not dock.is_code_win(cur_win) then
		local target = dock.find_code_win()
		if target and vim.api.nvim_win_is_valid(target) then
			vim.api.nvim_set_current_win(target)
		else
			pcall(vim.cmd, "wincmd l")
			local new_win = vim.api.nvim_get_current_win()
			if not dock.is_code_win(new_win) then
				pcall(vim.cmd, "vsplit")
				pcall(vim.cmd, "enew")
			end
		end
	end
end

function M.find_files_here()
	ensure_code_window()
	if _G.FindFilesGitignore then
		_G.FindFilesGitignore()
	else
		vim.cmd("TelescopeFindFilesGitignore")
	end
end

function M.find_files_or_window_up()
	local current = vim.fn.winnr()
	local above = vim.fn.winnr("k")
	if above ~= current then
		vim.cmd("wincmd k")
		return
	end
	M.find_files_here()
end

-- The telescope plugin installs `_G.FindFiles*` with the project's own defaults;
-- the fallbacks keep these keys working before it has loaded.
for _, key in ipairs(M.settings.keys.find_files) do
	vim.keymap.set({ "n", "i" }, key, function()
		M.find_files_or_window_up()
	end, opts("Find files (respecting .gitignore)"))
end

for _, key in ipairs(M.settings.keys.find_here) do
	vim.keymap.set({ "n", "i" }, key, M.find_files_here, opts("Find files in current window"))
end

for _, key in ipairs(M.settings.keys.find_all_files) do
	vim.keymap.set({ "n", "i" }, key, function()
		ensure_code_window()
		if _G.FindFilesNoIgnore then
			_G.FindFilesNoIgnore()
		else
			vim.cmd("TelescopeFindFilesNoIgnore")
		end
	end, opts("Find all files (ignoring .gitignore)"))
end

local function choose_split(direction)
	local origin = vim.api.nvim_get_current_win()
	local split = M.settings.splits[direction]
	local ui = require("fox.core.ui")
	local width = math.max(1, math.min(76, vim.o.columns - 4))
	local divider = "  +" .. string.rep("-", math.max(0, width - 6)) .. "+"
	local lines = {
		"  EDITOR  /  OPEN SPLIT " .. split.label:upper(),
		divider,
		"  KEY   ACTION",
		divider,
		"  [1]   Open current buffer",
		"  [2]   Select a file",
		divider,
	}
	vim.list_extend(
		lines,
		width >= 38 and { "  [Enter] Open   [j/k] Move   [q] Back" } or { "  [Enter] Open   [j/k] Move", "  [q] Back" }
	)
	local buf, win = ui.float({
		title = " Open Split ",
		lines = lines,
		width = width,
		height = math.max(1, math.min(#lines, vim.o.lines - 4)),
		border = { "+", "-", "+", "|", "+", "-", "+", "|" },
		close_keys = ui.close_keys,
	})
	vim.wo[win].cursorline = true
	vim.wo[win].wrap = false
	local first_choice, last_choice = 5, 6
	local function move(offset)
		local row = vim.api.nvim_win_get_cursor(win)[1]
		vim.api.nvim_win_set_cursor(win, { math.max(first_choice, math.min(last_choice, row + offset)), 0 })
	end
	local function open(row)
		if row ~= first_choice and row ~= last_choice then
			return
		end
		ui.close(win)
		if vim.api.nvim_win_is_valid(origin) then
			vim.api.nvim_set_current_win(origin)
			if row == first_choice then
				vim.cmd(split.command)
			else
				open_find_files_split(direction)
			end
		end
	end
	local bindings = {
		["1"] = function()
			open(first_choice)
		end,
		["2"] = function()
			open(last_choice)
		end,
		["<CR>"] = function()
			open(vim.api.nvim_win_get_cursor(win)[1])
		end,
	}
	for _, key in ipairs({ "j", "<Down>" }) do
		bindings[key] = function()
			move(1)
		end
	end
	for _, key in ipairs({ "k", "<Up>" }) do
		bindings[key] = function()
			move(-1)
		end
	end
	for key, action in pairs(bindings) do
		vim.keymap.set("n", key, action, { buffer = buf, silent = true, nowait = true })
	end
	vim.api.nvim_win_set_cursor(win, { first_choice, 0 })
end

for direction, keys in pairs(M.settings.keys.split) do
	for _, key in ipairs(keys) do
		vim.keymap.set({ "n", "i", "v" }, key, function()
			-- Downward split doubles as the repl toggle during a debug session.
			if direction == "j" and debug_keymaps.toggle_repl() then
				return
			end
			choose_split(direction)
		end, opts("Find file and open in split (" .. direction .. ")"))
	end
end

vim.keymap.set({ "n", "i", "v", "t" }, M.settings.keys.open_url, function()
	local mouse = vim.fn.getmousepos()
	if mouse.winid == 0 then
		return
	end

	vim.api.nvim_set_current_win(mouse.winid)
	pcall(vim.api.nvim_win_set_cursor, mouse.winid, { mouse.line, math.max(mouse.column - 1, 0) })

	local url = vim.fn.expand("<cWORD>"):match(M.settings.url_pattern)
	if url then
		vim.ui.open(url)
	end
end, opts("Ctrl+Click: open URL under cursor in browser"))

return M
