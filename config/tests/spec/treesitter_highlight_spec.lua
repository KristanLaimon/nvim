local t = require("fox.lib.foxnvim.test")

t.describe("Treesitter highlighting size guard", function()
	t.it("highlights ordinary files beyond 3500 lines and skips files over 1 MiB", function()
		local callback
		local env = package.loaded["fox.core.environment"]
		local ts = package.loaded["nvim-treesitter"]
		package.loaded["fox.core.environment"] = {
			detect = function()
				return { is_termux = true }
			end,
		}
		package.loaded["nvim-treesitter"] = { setup = function() end }
		local autocmd = t.spyOn(vim.api, "nvim_create_autocmd")
		autocmd.mockImplementation(function(_, opts)
			callback = opts.callback
			return 0
		end)
		local calls = 0
		local start = t.spyOn(vim.treesitter, "start")
		start.mockImplementation(function()
			calls = calls + 1
		end)
		local buf = vim.api.nvim_create_buf(false, true)
		local ok, err = pcall(function()
			dofile(vim.fn.stdpath("config") .. "/lua/plugins/lsp/treesitter.lua").config()
			local lines = {}
			for i = 1, 3694 do
				lines[i] = "-- ordinary source line"
			end
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			callback({ buf = buf })
			t.expect(calls).toBe(1)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { string.rep("x", 1024 * 1024) })
			callback({ buf = buf })
			t.expect(calls).toBe(1)
		end)
		vim.api.nvim_buf_delete(buf, { force = true })
		autocmd.mockRestore()
		start.mockRestore()
		package.loaded["fox.core.environment"] = env
		package.loaded["nvim-treesitter"] = ts
		assert(ok, err)
	end)
end)
