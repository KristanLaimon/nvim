local t = require("fox.lib.foxnvim.test")

t.describe("Markdown runtime parser guard", function()
	t.it("loads the builtin ftplugin when the parser is missing or incompatible", function()
		local original_start = vim.treesitter.start
		local get_parser = t.spyOn(vim.treesitter, "get_parser")
		local buf = vim.api.nvim_create_buf(false, true)
		local ok, err = pcall(function()
			local filetypes = dofile(vim.fn.stdpath("config") .. "/lua/fox/core/filetypes.lua")
			filetypes.setup()
			local guarded_start = vim.treesitter.start
			filetypes.setup()
			t.expect(vim.treesitter.start == guarded_start).toBe(true)
			vim.api.nvim_buf_call(buf, function()
				vim.bo[buf].filetype = "markdown"
				for _, throws in ipairs({ false, true }) do
					get_parser.mockImplementation(function()
						if throws then
							error("incompatible parser")
						end
						return nil, "missing parser"
					end)
					dofile(vim.env.VIMRUNTIME .. "/ftplugin/markdown.lua")
					t.expect(vim.bo[buf].filetype).toBe("markdown")
				end
			end)
		end)
		vim.treesitter.start = original_start
		get_parser.mockRestore()
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)

	t.it("delegates to Treesitter for available Markdown parsers and other languages", function()
		local original_start = vim.treesitter.start
		local start = t.spyOn(vim.treesitter, "start")
		local get_parser = t.spyOn(vim.treesitter, "get_parser")
		local calls = {}
		start.mockImplementation(function(buf, lang)
			calls[#calls + 1] = { buf, lang }
		end)
		get_parser.mockImplementation(function()
			return {}
		end)
		local ok, err = pcall(function()
			dofile(vim.fn.stdpath("config") .. "/lua/fox/core/filetypes.lua").setup()
			vim.treesitter.start(0, "markdown")
			get_parser.mockImplementation(function()
				error("must not check other languages")
			end)
			vim.treesitter.start(0, "lua")
			t.expect(calls).toEqual({ { 0, "markdown" }, { 0, "lua" } })
		end)
		start.mockRestore()
		vim.treesitter.start = original_start
		get_parser.mockRestore()
		assert(ok, err)
	end)
end)
