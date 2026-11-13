local M = {}
local pending = {}

-- Only an explicit discard or a successful write may authorize closing.
function M.confirm(target, on_close)
	if pending[target] then
		return
	end
	pending[target] = true
	vim.cmd.stopinsert()
	local filename = vim.api.nvim_buf_get_name(target)
	local label = filename == "" and "[Untitled]" or vim.fn.fnamemodify(filename, ":t")
	local lines = { "Save changes to " .. label .. "?", "", "[ Save ]", "[ Don't Save ]", "[ Cancel ]" }
	local buf, win = require("fox.core.ui").float({
		title = " Unsaved changes ",
		filetype = "fox_unsaved_changes",
		lines = lines,
		width = math.max(1, math.min(70, vim.o.columns - 4)),
		height = #lines,
	})
	vim.wo[win].cursorline = true
	vim.api.nvim_win_set_cursor(win, { 5, 0 })
	local resolved = false
	local function save(path)
		if not vim.api.nvim_buf_is_valid(target) then
			return
		end
		local ok, err = pcall(vim.api.nvim_buf_call, target, function()
			vim.cmd("write" .. (path and (" " .. vim.fn.fnameescape(path)) or ""))
		end)
		if ok and not vim.bo[target].modified then
			on_close()
		else
			vim.notify(tostring(err or "The buffer still has unsaved changes"), vim.log.levels.ERROR)
		end
	end
	local function finish(choice)
		if resolved then
			return
		end
		resolved = true
		pending[target] = nil
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if not vim.api.nvim_buf_is_valid(target) then
			return
		end
		if choice == 4 then
			on_close()
		elseif choice == 3 then
			if filename == "" then
				vim.ui.input({ prompt = "Save as: ", completion = "file" }, function(path)
					if path and path ~= "" then
						save(path)
					end
				end)
			else
				save()
			end
		end
	end
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			pending[target] = nil
			resolved = true
		end,
	})
	local opts = { buffer = buf, silent = true, nowait = true }
	for _, key in ipairs({ "<Esc>", "q", "<C-c>" }) do
		vim.keymap.set("n", key, function()
			finish(5)
		end, opts)
	end
	for key, delta in pairs({ ["<Down>"] = 1, ["<Tab>"] = 1, j = 1, ["<Up>"] = -1, ["<S-Tab>"] = -1, k = -1 }) do
		vim.keymap.set("n", key, function()
			local row = vim.api.nvim_win_get_cursor(win)[1]
			vim.api.nvim_win_set_cursor(win, { 3 + (row - 3 + delta) % 3, 0 })
		end, opts)
	end
	vim.keymap.set("n", "<CR>", function()
		finish(vim.api.nvim_win_get_cursor(win)[1])
	end, opts)
	local function click_choice()
		local mouse = vim.fn.getmousepos()
		if
			mouse.winid == win
			and mouse.line >= 3
			and mouse.line <= 5
			and mouse.column >= 1
			and mouse.column <= #lines[mouse.line]
		then
			finish(mouse.line)
		end
	end
	for _, key in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>" }) do
		vim.keymap.set("n", key, click_choice, opts)
	end
end

return M
