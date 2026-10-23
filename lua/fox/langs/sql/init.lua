local M = {}

M.bundle_name = "SQL / FoxQuerier"
M.requires = { { cmd = "python3", alt = "python", name = "Python 3 (database driver bridge)" } }
M.treesitter = { "sql" }
M.defaults = { expandtab = true, shiftwidth = 2, tabstop = 2, softtabstop = 2 }

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "sql",
		callback = function(args)
			if not require("fox.langs").has_editorconfig(args.buf) then
				for key, value in pairs(M.defaults) do
					vim.bo[args.buf][key] = value
				end
			end
		end,
	})
end

return M
