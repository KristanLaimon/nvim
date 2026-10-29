local t = require("fox.lib.foxnvim.test")
require("lazy").load({ plugins = { "fox_buffer_cleaner" } })
local cleaner = _G.BufferCleaner

t.describe("buffer cleaner event batching", function()
	t.it("coalesces enter events and allows another cleanup after completion", function()
		cleaner.setup()
		local pending, calls = {}, 0
		local schedule = t.spyOn(vim, "schedule")
		local clean = t.spyOn(cleaner, "clean_buffers")
		schedule.mockImplementation(function(callback)
			pending[#pending + 1] = callback
		end)
		clean.mockImplementation(function()
			calls = calls + 1
		end)
		for _ = 1, 3 do
			vim.api.nvim_exec_autocmds({ "BufEnter", "BufWinEnter" }, { group = "FOXCleanNoNameBuffers" })
		end
		local queued = #pending
		pending[1]()
		vim.api.nvim_exec_autocmds("BufEnter", { group = "FOXCleanNoNameBuffers" })
		pending[2]()
		schedule.mockRestore()
		clean.mockRestore()
		t.expect(queued).toBe(1)
		t.expect(calls).toBe(2)
	end)
end)
