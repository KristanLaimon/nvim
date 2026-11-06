local M = {}

function M.restart()
	local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
	if #clients == 0 then
		vim.notify("No LSP clients attached to the current file", vim.log.levels.INFO)
		return
	end

	if vim.fn.exists(":lsp") == 2 then
		vim.cmd("lsp restart")
	else
		local restarted = {}
		for _, client in ipairs(clients) do
			if not restarted[client.name] then
				vim.cmd.LspRestart(client.name)
				restarted[client.name] = true
			end
		end
	end
end

return M
