local t = require("fox.lib.foxnvim.test")
require("lazy").load({ plugins = { "fox_buffer_cleaner" } })
local cleaner = _G.BufferCleaner

t.describe("buffer cleaner event batching", function()
	t.it("coalesces enter events and allows another cleanup after completion", function()
		cleaner.setup()

		-- Drain startup cleanup before observing a new batch of enter events.
		vim.wait(20)
		local calls = 0
		local clean = t.spyOn(cleaner, "clean_buffers")
		clean.mockImplementation(function()
			calls = calls + 1
		end)
		local ok, err = xpcall(function()
			for _ = 1, 3 do
				vim.api.nvim_exec_autocmds({ "BufEnter", "BufWinEnter" }, { group = "FOXCleanNoNameBuffers" })
			end
			t.expect(calls).toBe(0)
			t.expect(vim.wait(1000, function()
				return calls == 1
			end)).toBe(true)
			vim.api.nvim_exec_autocmds("BufEnter", { group = "FOXCleanNoNameBuffers" })
			t.expect(vim.wait(1000, function()
				return calls == 2
			end)).toBe(true)
		end, debug.traceback)
		clean.mockRestore()
		assert(ok, err)
	end)
end)
