local M = {}

--- Open the preview without the plugin's Node launcher, which only reports
--- spawn errors and silently ignores a browser handler's nonzero exit status.
function M.open(url)
	local function failed(reason)
		vim.schedule(function()
			vim.notify("Markdown preview: " .. reason .. "\nOpen manually: " .. url, vim.log.levels.ERROR)
		end)
	end

	local cmd
	if vim.fn.has("win32") == 1 then
		cmd = { "explorer.exe", url }
	elseif vim.fn.has("mac") == 1 then
		cmd = { "open", url }
	elseif vim.fn.has("wsl") == 1 and vim.fn.executable("wslview") == 1 then
		cmd = { "wslview", url }
	else
		cmd = { "xdg-open", url }
	end

	local ok, err = pcall(vim.system, cmd, { text = true, detach = true }, function(result)
		-- Explorer may return 1 even when it successfully hands off the URL.
		if result.code ~= 0 and not (cmd[1] == "explorer.exe" and result.code == 1 and result.stderr == "") then
			failed(
				vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or ("browser exited with code " .. result.code)
			)
		end
	end)
	if not ok then
		failed(tostring(err))
	end
end

function M.setup()
	-- The server uses nvim_call_function, so it needs a real Vimscript function.
	vim.cmd([[
function! FoxMarkdownOpenBrowser(url) abort
  call luaeval('require("fox.markdown.browser").open(_A)', a:url)
endfunction
]])
	if not vim.g.mkdp_browserfunc or vim.g.mkdp_browserfunc == "" then
		if not vim.g.mkdp_browser or vim.g.mkdp_browser == "" then
			vim.g.mkdp_browserfunc = "FoxMarkdownOpenBrowser"
		end
	end
	vim.g.mkdp_echo_preview_url = 1
end

--- The upstream commands are buffer-local and only installed by future
--- BufEnter/FileType events. Keep global fallbacks for lazy command loading
--- and palette execution after a picker closes.
function M.setup_commands()
	local actions = {
		MarkdownPreview = "mkdp#util#open_preview_page",
		MarkdownPreviewToggle = "mkdp#util#toggle_preview",
		MarkdownPreviewStop = "mkdp#util#stop_preview",
	}
	for name, action in pairs(actions) do
		vim.api.nvim_create_user_command(name, function()
			if
				name ~= "MarkdownPreviewStop" and not vim.tbl_contains(vim.g.mkdp_filetypes or { "markdown" }, vim.bo.filetype)
			then
				vim.notify("Open a Markdown buffer before starting its browser preview.", vim.log.levels.WARN)
				return
			end
			vim.fn[action]()
		end, { desc = name .. " in the browser", force = true })
	end
end

return M
