local M = {}

function M.open()
	local workspace = require("fox.reader.workspace")
	local root, err = workspace.root(vim.fn.getcwd())
	if not root then
		vim.notify("Fox Reader: " .. err, vim.log.levels.ERROR)
		return
	end
	local url = require("fox.reader.server").start(root)
	local name = vim.api.nvim_buf_get_name(0)
	local path = name ~= "" and vim.uv.fs_realpath(name)
	if path and vim.bo.filetype == "markdown" then
		local relative = vim.fs.relpath(root, vim.fs.normalize(path))
		if relative and workspace.resolve(root, relative) and workspace.included(relative) then
			url = url .. "?path=" .. vim.uri_encode(relative, "rfc3986")
		else
			vim.notify("Fox Reader: document is outside the workspace or excluded; opening library", vim.log.levels.WARN)
		end
	end
	require("fox.markdown.browser").open(url)
end

function M.setup()
	vim.api.nvim_create_user_command("FoxReader", M.open, { desc = "Open Fox Reader", force = true })
	local group = vim.api.nvim_create_augroup("FoxReader", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			require("fox.reader.server").stop()
		end,
	})
end

return M
