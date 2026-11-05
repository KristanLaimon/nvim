local M = {}

local function set_padding(value)
	if vim.g.neovide or vim.env.TMUX or vim.env.STY or vim.env.NVIM or not vim.api.nvim_ui_send then
		return
	end
	if not vim.env.KITTY_WINDOW_ID then
		return
	end
	local tui = false
	for _, ui in ipairs(vim.api.nvim_list_uis()) do
		tui = tui or ui.stdout_tty
	end
	if not tui then
		return
	end
	local settings = {}
	for _, edge in ipairs({ "top", "right", "bottom", "left" }) do
		settings["padding-" .. edge] = value
	end
	-- No reply: terminal responses must not become editor input.
	vim.api.nvim_ui_send("\27P@kitty-cmd" .. vim.json.encode({
		cmd = "set-spacing",
		version = { 0, 26, 0 },
		no_response = true,
		payload = { match_window = "id:" .. vim.env.KITTY_WINDOW_ID, settings = settings },
	}) .. "\27\\")
end

function M.setup()
	local group = vim.api.nvim_create_augroup("fox_kitty_padding", { clear = true })
	vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter", "VimResume" }, {
		group = group,
		callback = function()
			set_padding(0)
		end,
	})
	vim.api.nvim_create_autocmd({ "VimLeavePre", "VimSuspend" }, {
		group = group,
		callback = function()
			set_padding(vim.NIL)
		end,
	})
	if vim.v.vim_did_enter == 1 then
		set_padding(0)
	end
end

return M
