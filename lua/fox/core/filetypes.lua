local M = {}

function M.setup()
	vim.filetype.add({
		pattern = {
			[".*%.blade%.php"] = "blade",
		},
	})
end

return M
