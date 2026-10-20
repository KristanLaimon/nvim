local M = {}
local previews = {}
local browser_handler

local function notify(method, preview)
	local channel = vim.g.mkdp_node_channel_id
	if channel then
		-- The server may stop before its channel variable is cleared.
		pcall(vim.rpcnotify, channel, method, { bufnr = preview })
	end
end

-- Keep Mermaid source untouched; only the browser receives a fenced Markdown copy.
local function mermaid_preview(source)
	local preview = previews[source]
	if not preview then
		preview = vim.api.nvim_create_buf(false, true)
		previews[source] = preview
		vim.api.nvim_buf_set_name(
			preview,
			"fox-mermaid://" .. source .. "/" .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(source), ":t") .. ".md"
		)
		local group = vim.api.nvim_create_augroup("FoxMermaidPreview" .. source, { clear = true })
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost", "InsertLeave" }, {
			group = group,
			buffer = source,
			callback = function()
				mermaid_preview(source)
				notify("refresh_content", preview)
			end,
		})
		vim.api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
			group = group,
			buffer = source,
			callback = function(ev)
				if ev.event == "BufWipeout" or vim.g.mkdp_auto_close == 1 then
					notify("close_page", preview)
					vim.b[preview].MarkdownPreviewToggleBool = 0
				end
				if ev.event == "BufWipeout" then
					previews[source] = nil
					vim.api.nvim_buf_delete(preview, { force = true })
					vim.api.nvim_del_augroup_by_id(group)
				end
			end,
		})
	end
	local lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
	-- Tilde fences cannot be closed by backticks in Mermaid labels.
	local fence = "~~~"
	for _, line in ipairs(lines) do
		local tildes = line:match("^%s*(~+)")
		if tildes and #tildes >= #fence then
			fence = tildes .. "~"
		end
	end
	table.insert(lines, 1, fence .. "mermaid")
	lines[#lines + 1] = fence
	vim.api.nvim_buf_set_lines(preview, 0, -1, false, lines)
	return preview
end

--- Open the preview without the plugin's Node launcher, which only reports
--- spawn errors and silently ignores a browser handler's nonzero exit status.
function M.open(url)
	local original_url = url
	url = url:gsub("(/page/)(%d+)", function(path, source)
		return path .. (previews[tonumber(source)] or source)
	end)
	if url ~= original_url then
		-- The source URL contains raw Mermaid; report the rendered page URL too.
		vim.schedule(function()
			vim.notify("Mermaid preview: " .. url)
		end)
	end
	if browser_handler then
		vim.fn[browser_handler](url)
		return
	end
	local function failed(reason)
		vim.schedule(function()
			vim.notify("Markdown preview: " .. reason .. "\nOpen manually: " .. url, vim.log.levels.ERROR)
		end)
	end

	local cmd
	if vim.g.mkdp_browser and vim.g.mkdp_browser ~= "" then
		if vim.fn.has("win32") == 1 then
			cmd = { "cmd.exe", "/c", "start", '""', vim.g.mkdp_browser, (url:gsub("&", "^&")) }
		elseif vim.fn.has("mac") == 1 then
			cmd = { "open", "-a", vim.g.mkdp_browser, url }
		else
			cmd = { vim.g.mkdp_browser, url }
		end
	elseif vim.fn.has("win32") == 1 then
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
	-- GitHub preserves literal quotes, dashes and ellipses instead of smart typography.
	vim.g.mkdp_preview_options = vim.tbl_deep_extend("keep", vim.g.mkdp_preview_options or {}, {
		mkit = { typographer = false },
	})
	-- The server uses nvim_call_function, so it needs a real Vimscript function.
	vim.cmd([[
function! FoxMarkdownOpenBrowser(url) abort
  call luaeval('require("fox.markdown.browser").open(_A)', a:url)
endfunction
]])
	if vim.g.mkdp_browserfunc ~= "FoxMarkdownOpenBrowser" then
		browser_handler = vim.g.mkdp_browserfunc
		if browser_handler == "" then
			browser_handler = nil
		end
	end
	vim.g.mkdp_browserfunc = "FoxMarkdownOpenBrowser"
	vim.filetype.add({ extension = { mermaid = "mermaid", mmd = "mermaid" } })
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
				name ~= "MarkdownPreviewStop"
				and vim.bo.filetype ~= "mermaid"
				and not vim.tbl_contains(vim.g.mkdp_filetypes or { "markdown" }, vim.bo.filetype)
			then
				vim.notify("Open a Markdown or Mermaid buffer before starting its browser preview.", vim.log.levels.WARN)
				return
			end
			if name ~= "MarkdownPreviewStop" and vim.bo.filetype == "mermaid" then
				local preview = mermaid_preview(vim.api.nvim_get_current_buf())
				if vim.fn.exists("*mkdp#rpc#get_server_status") == 1 and vim.fn["mkdp#rpc#get_server_status"]() == -1 then
					vim.b[preview].MarkdownPreviewToggleBool = 0
				end
				-- Avoid BufHidden auto-close while borrowing the scratch buffer for the RPC.
				local eventignore = vim.o.eventignore
				vim.o.eventignore = "all"
				local ok, err = pcall(vim.api.nvim_buf_call, preview, function()
					vim.fn[action]()
				end)
				vim.o.eventignore = eventignore
				if not ok then
					error(err)
				end
			else
				vim.fn[action]()
			end
			if name == "MarkdownPreviewStop" then
				for _, preview in pairs(previews) do
					vim.b[preview].MarkdownPreviewToggleBool = 0
				end
			end
		end, { desc = name .. " in the browser", force = true })
	end
end

return M
