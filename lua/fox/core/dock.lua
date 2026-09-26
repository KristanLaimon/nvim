-- ============================================================================
-- fox.core.dock -- The bottom dock shared by terminals and task outputs.
-- ============================================================================
-- WHAT THE DOCK IS
--   One horizontal strip at the bottom of the editor, split vertically between
--   the multi-terminal (LEFT) and task outputs (RIGHT). Both plugins used to
--   carry their own copy of this window-hunting logic, and the copies disagreed
--   about which side each pane belonged on.
--
-- THE RULE
--   Terminals sit left of task outputs. `enforce_order()` swaps them back when a
--   new split lands on the wrong side, and both plugins call it after opening.
--
-- USAGE
--   local dock = require("fox.core.dock")
--   local win = dock.open({ prefer = "terminal", height = 10 })
--   local task_win, term_win = dock.find()
-- ============================================================================

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

--- Filetype marking a task-output buffer, alongside the `fox_is_task` flag.
M.task_filetype = "TaskRunner"

--- Height, in lines, of a fresh bottom split when the dock does not exist yet.
M.default_height = 12

-- ---------------------------------------------------------------------------
-- Classification
-- ---------------------------------------------------------------------------

--- Classifies a window as task output, terminal, or neither.
--- A task output IS a terminal buffer, so the task test comes first.
---
--- @param win integer Window handle.
--- @return boolean is_task
--- @return boolean is_terminal
function M.classify(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false, false
	end

	local buf = vim.api.nvim_win_get_buf(win)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false, false
	end

	local is_task = (vim.b[buf].fox_is_task or vim.bo[buf].filetype == M.task_filetype) and true or false
	local is_term = ((vim.bo[buf].buftype == "terminal" and not is_task) or vim.b[buf].fox_is_multi_term) and true
		or false
	return is_task, is_term
end

--- Finds the first task-output window and the first terminal window.
--- @return integer|nil task_win
--- @return integer|nil term_win
function M.find()
	local task_win, term_win
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local is_task, is_term = M.classify(win)
		if is_task and not task_win then
			task_win = win
		elseif is_term and not term_win then
			term_win = win
		end
	end
	return task_win, term_win
end

--- Checks if a window is a normal code buffer window (not dock, floating, neo-tree, or special UI).
--- @param win integer
--- @return boolean
function M.is_code_win(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end

	local cfg = vim.api.nvim_win_get_config(win)
	if cfg and cfg.relative and cfg.relative ~= "" then
		return false
	end

	local is_task, is_term = M.classify(win)
	if is_task or is_term then
		return false
	end

	local buf = vim.api.nvim_win_get_buf(win)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	local ft = vim.bo[buf].filetype
	local bt = vim.bo[buf].buftype

	if ft == "neo-tree" or ft == "qf" or ft == "help" then
		return false
	end

	if ft == "alpha" or ft == "dashboard" or ft == "starter" or ft == "snacks_dashboard" then
		return true
	end

	if bt == "nofile" or bt == "quickfix" or bt == "prompt" then
		return false
	end

	return true
end

--- Finds a main code window in the active tabpage.
--- @return integer|nil win
function M.find_code_win()
	local cur = vim.api.nvim_get_current_win()
	if M.is_code_win(cur) then
		return cur
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if M.is_code_win(win) then
			return win
		end
	end
	return nil
end

--- Ensures Neo-tree stays on the far-left at full height so dock windows
--- (terminals and task outputs) remain strictly to the right of Neo-tree
--- under the code buffer.
function M.enforce_neotree_layout()
	local cur_win = vim.api.nvim_get_current_win()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "neo-tree" then
				vim.wo[win].winfixwidth = true

				-- Only run wincmd H if Neo-tree is not already at column 0 (far left)
				local pos = vim.api.nvim_win_get_position(win)
				if pos[2] > 0 then
					vim.api.nvim_set_current_win(win)
					vim.cmd("silent! wincmd H")
				end

				local ok, store = pcall(require, "fox.core.store")
				if ok then
					local width_file = vim.fn.stdpath("state") .. "/neotree_width"
					local saved_width = tonumber(store.read_file(width_file) or "") or 30
					if saved_width >= 18 and saved_width <= 60 then
						pcall(vim.api.nvim_win_set_width, win, saved_width)
					end
				end

				if vim.api.nvim_win_is_valid(cur_win) then
					pcall(vim.api.nvim_set_current_win, cur_win)
				end
				break
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

--- Puts the terminal back on the left of the task output when a split landed on
--- the wrong side. Focus is restored to whatever window the user was in.
function M.enforce_order()
	local task_win, term_win = M.find()
	if task_win and term_win then
		local term_col = vim.api.nvim_win_get_position(term_win)[2]
		local task_col = vim.api.nvim_win_get_position(task_win)[2]
		if term_col > task_col then
			local cur_win = vim.api.nvim_get_current_win()
			vim.api.nvim_set_current_win(task_win)
			vim.cmd("wincmd x")
			if vim.api.nvim_win_is_valid(cur_win) then
				pcall(vim.api.nvim_set_current_win, cur_win)
			end
		end
	end

	M.enforce_neotree_layout()
end

--- Opens a window inside the dock and returns it.
--- With the dock already on screen the new window is split beside the existing
--- pane, on the side the caller belongs to; otherwise the dock itself is created
--- as a bottom split under the code buffer.
---
--- @param opts table|nil Options:
---   prefer string  "terminal" or "task" (default). Decides which side to take.
---   height number  Height of a freshly created dock. Default `M.default_height`.
--- @return integer win New window handle.
function M.open(opts)
	opts = opts or {}
	local task_win, term_win = M.find()
	local height = opts.height or M.default_height

	if opts.prefer == "terminal" then
		if term_win then
			vim.api.nvim_set_current_win(term_win)
			vim.cmd("rightbelow vsplit")
		elseif task_win then
			-- Land on the left of the task output rather than beyond it.
			vim.api.nvim_set_current_win(task_win)
			vim.cmd("leftabove vsplit")
		else
			local target_win = M.find_code_win()
			if not target_win then
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					local buf = vim.api.nvim_win_get_buf(win)
					if vim.bo[buf].filetype ~= "neo-tree" then
						target_win = win
						break
					end
				end
			end
			if target_win then
				vim.api.nvim_set_current_win(target_win)
				vim.cmd("rightbelow " .. height .. "split")
			else
				vim.cmd("botright " .. height .. "split")
			end
		end
	else
		local anchor = task_win or term_win
		if anchor then
			vim.api.nvim_set_current_win(anchor)
			vim.cmd("rightbelow vsplit")
		else
			local target_win = M.find_code_win()
			if not target_win then
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
					local buf = vim.api.nvim_win_get_buf(win)
					if vim.bo[buf].filetype ~= "neo-tree" then
						target_win = win
						break
					end
				end
			end
			if target_win then
				vim.api.nvim_set_current_win(target_win)
				vim.cmd("rightbelow " .. height .. "split")
			else
				vim.cmd("botright " .. height .. "split")
			end
		end
	end

	local win = vim.api.nvim_get_current_win()
	M.style(win)
	M.enforce_order()
	return win
end

--- Strips line numbers and signs from a dock window and fixes its height.
--- @param win integer Window handle.
function M.style(win)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].winfixheight = false
end

return M
