local M = {}

-- Hide floats instead of closing them: buffers, cursor positions and callbacks survive.
function M.new(left, right, opts)
	local view = { mode = opts.mode or "split", maximized = false }
	function view.apply()
		if not vim.api.nvim_win_is_valid(left) or not vim.api.nvim_win_is_valid(right) then
			return
		end
		local settings = require("plugins.fox.git.git_center.config").settings
		local width = math.max(
			6,
			math.min(vim.o.columns - 4, math.floor(vim.o.columns * (view.maximized and 1 or settings.width_ratio)))
		)
		local height =
			math.max(1, math.min(vim.o.lines - 5, math.floor(vim.o.lines * (view.maximized and 1 or settings.height_ratio))))
		local row = math.max(1, math.floor((vim.o.lines - height) / 2))
		local col = math.max(0, math.floor((vim.o.columns - width) / 2))
		local ratio = opts.ratio()
		local left_width = view.mode == "split" and math.max(1, math.floor(width * ratio)) or width
		local right_width = view.mode == "split" and math.max(1, width - left_width - 2) or width
		local current = vim.api.nvim_get_current_win()
		local target = view.mode == "details" and right or left
		if view.mode ~= "browse" and opts.before_show then
			opts.before_show()
		end
		-- Unhide the destination before moving focus out of the pane being hidden.
		vim.api.nvim_win_set_config(target, { hide = false })
		if (view.mode == "details" and current == left) or (view.mode == "browse" and current == right) then
			vim.api.nvim_set_current_win(target)
		end
		vim.api.nvim_win_set_config(
			left,
			{ relative = "editor", width = left_width, height = height, row = row, col = col, hide = false }
		)
		vim.api.nvim_win_set_config(right, {
			relative = "editor",
			width = right_width,
			height = height,
			row = row,
			col = view.mode == "split" and col + left_width + 2 or col,
			hide = view.mode == "browse",
			zindex = vim.api.nvim_win_get_config(left).zindex + (view.mode == "details" and 1 or 0),
		})
		if opts.tab and vim.api.nvim_win_is_valid(opts.tab) then
			vim.api.nvim_win_set_config(opts.tab, { relative = "editor", width = width + 2, row = row - 1, col = col })
		end
		if opts.changed then
			opts.changed()
		end
	end

	function view.toggle_preview()
		if opts.manual then
			opts.manual()
		end
		view.mode = view.mode == "split" and "browse" or "split"
		view.apply()
	end

	function view.show_preview()
		if opts.manual then
			opts.manual()
		end
		if view.mode ~= "details" then
			view.previous_mode = view.mode
			view.mode = "details"
			view.apply()
		end
		vim.api.nvim_set_current_win(right)
	end

	function view.hide_preview()
		if opts.manual then
			opts.manual()
		end
		view.mode = "browse"
		view.apply()
		vim.api.nvim_set_current_win(left)
	end

	function view.expand()
		if opts.manual then
			opts.manual()
		end
		local returning = view.mode == "details"
		if returning then
			view.mode = view.previous_mode or "browse"
		else
			view.previous_mode = view.mode
			view.mode = "details"
		end
		view.apply()
		if returning then
			vim.api.nvim_set_current_win(left)
		end
	end

	function view.maximize()
		view.maximized = not view.maximized
		view.apply()
	end

	for _, win in ipairs({ left, right }) do
		local buf = vim.api.nvim_win_get_buf(win)
		vim.keymap.set({ "n", "v", "i", "t" }, "<Tab>", view.show_preview, { buffer = buf, silent = true, nowait = true })
		vim.keymap.set({ "n", "v", "i", "t" }, "<S-Tab>", view.hide_preview, { buffer = buf, silent = true, nowait = true })
		for key, action in pairs({ ["<F6>"] = view.toggle_preview, ["<F7>"] = view.expand, ["<F8>"] = view.maximize }) do
			vim.keymap.set("n", key, action, { buffer = buf, silent = true, nowait = true })
		end
	end
	local resize = vim.api.nvim_create_autocmd("VimResized", { callback = view.apply })
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = vim.api.nvim_win_get_buf(left),
		once = true,
		callback = function()
			vim.api.nvim_del_autocmd(resize)
		end,
	})
	return view
end

return M
