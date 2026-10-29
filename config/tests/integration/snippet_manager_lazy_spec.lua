local t = require("fox.lib.foxnvim.test")

t.describe("snippet manager on demand", function()
	t.it("reloads completion snippets on the first JSON save", function()
		local previous = package.loaded["blink.cmp"]
		local calls = 0
		package.loaded["blink.cmp"] = {
			reload = function(source)
				assert(source == "snippets")
				calls = calls + 1
			end,
		}
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, vim.fn.stdpath("config") .. "/config/snippets/startup-test.json")
		vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })
		package.loaded["blink.cmp"] = previous
		vim.api.nvim_buf_delete(buf, { force = true })
		t.expect(calls).toBe(1)
	end)
end)
