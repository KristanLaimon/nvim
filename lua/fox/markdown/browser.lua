local M = {}

function M.open(url)
	local function failed(reason)
		vim.schedule(function()
			vim.notify("Markdown preview: " .. reason .. "\nOpen manually: " .. url, vim.log.levels.ERROR)
		end)
	end
	if vim.g.mkdp_browserfunc and vim.g.mkdp_browserfunc ~= "" then
		local ok, err = pcall(vim.fn[vim.g.mkdp_browserfunc], url)
		if not ok then
			failed(tostring(err))
		end
		return
	end
	local cmd
	if vim.g.mkdp_browser and vim.g.mkdp_browser ~= "" then
		cmd = { vim.g.mkdp_browser, url }
	elseif vim.fn.has("win32") == 1 then
		cmd = { "explorer.exe", url }
	elseif vim.fn.has("mac") == 1 then
		cmd = { "open", url }
	elseif vim.fn.has("wsl") == 1 and vim.fn.executable("wslview") == 1 then
		cmd = { "wslview", url }
	else
		cmd = { "xdg-open", url }
	end
	local function on_exit(result)
		if result.code ~= 0 and not (cmd[1] == "explorer.exe" and result.code == 1 and result.stderr == "") then
			failed(
				vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or ("browser exited with code " .. result.code)
			)
		end
	end
	local ok, err = pcall(function()
		if vim.fn.has("win32") == 1 then
			-- vim.system hides Windows GUI processes; launch visibly without detached flags.
			local handle, spawn_error
			handle, spawn_error = vim.uv.spawn(cmd[1], { args = { cmd[2] }, hide = false }, function(code)
				if handle and not handle:is_closing() then
					handle:close()
				end
				on_exit({ code = code, stderr = "" })
			end)
			if not handle then
				error(spawn_error)
			end
		else
			vim.system(cmd, { text = true, detach = true }, on_exit)
		end
	end)
	if not ok then
		failed(tostring(err))
	end
end

function M.setup_commands()
	local server = require("fox.markdown.server")
	for _, name in ipairs({ "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" }) do
		vim.api.nvim_create_user_command(name, function()
			local buf = vim.api.nvim_get_current_buf()
			if name == "MarkdownPreviewStop" or (name == "MarkdownPreviewToggle" and server.active(buf)) then
				server.stop()
				return
			end
			if not vim.tbl_contains({ "markdown", "mermaid" }, vim.bo[buf].filetype) then
				vim.notify("Open a Markdown or Mermaid buffer before starting its browser preview.", vim.log.levels.WARN)
				return
			end
			local ok, url = pcall(server.start, buf)
			if not ok then
				vim.notify("Markdown preview: " .. tostring(url), vim.log.levels.ERROR)
				return
			end
			vim.notify("Preview page: " .. url)
			M.open(url)
		end, { desc = name .. " in the browser", force = true })
	end
end

function M.setup()
	vim.filetype.add({ extension = { mermaid = "mermaid", mmd = "mermaid" } })
	local group = vim.api.nvim_create_augroup("FoxMarkdownPreview", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			require("fox.markdown.server").stop()
		end,
	})
end

return M
