local t = require("fox.lib.foxnvim.test")

t.describe("local plugin directories", function()
	t.it("keeps equal filenames in separate modules distinct", function()
		local helper = dofile(vim.fn.stdpath("config") .. "/lua/fox/core/lazyspec.lua")
		helper.specs_root = vim.fn.tempname()
		local function directory(source)
			return assert(loadstring("local helper = ...; local dir = helper.for_module(); return dir", "@" .. source))(
				helper
			)
		end
		local ok, err = pcall(function()
			local tracker = directory("/config/lua/plugins/editor/wakatime.lua")
			local dashboard = directory("/config/lua/plugins/fox/tools/wakatime.lua")
			t.expect(tracker == dashboard).toBe(false)
			t.expect(vim.fn.isdirectory(tracker)).toBe(1)
			t.expect(vim.fn.isdirectory(dashboard)).toBe(1)
			t.expect(directory("/config/lua/plugins/editor/wakatime.lua")).toBe(tracker)
			t.expect(directory([[C:\config\lua\plugins\editor\wakatime.lua]])).toBe(tracker)
		end)
		vim.fn.delete(helper.specs_root, "rf")
		assert(ok, err)
	end)
end)
