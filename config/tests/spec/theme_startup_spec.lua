local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("local theme startup", function()
	it("loads the saved theme eagerly without an upstream theme plugin", function()
		local names = { "plugins.fox.ui.ryoku_theme", "plugins.fox.ui.omarchy_theme", "plugins.fox.ui.theme_picker" }
		local saved, restored = {}, false
		for _, name in ipairs(names) do
			saved[name] = package.loaded[name]
		end
		package.loaded[names[1]] = {
			is_sync_enabled = function()
				return false
			end,
		}
		package.loaded[names[2]] = {
			is_sync_enabled = function()
				return false
			end,
		}
		package.loaded[names[3]] = {
			setup = function() end,
			restore_saved_theme = function()
				restored = true
			end,
		}
		local spec = dofile(vim.fn.stdpath("config") .. "/lua/plugins/ui/themes.lua")[1]
		local ok, err = pcall(spec.config)
		for _, name in ipairs(names) do
			package.loaded[name] = saved[name]
		end
		assert(ok, err)
		expect(spec.name).toBe("fox_theme_startup")
		expect(spec.lazy).toBe(false)
		expect(spec[1]).toBe(nil)
		expect(restored).toBe(true)
	end)

	it("loads every static palette offered by the picker from the local runtime", function()
		local original = vim.g.colors_name or "default"
		local ok, err = pcall(function()
			for _, name in ipairs(require("plugins.fox.ui.theme_picker").discover_themes()) do
				if name ~= "ryoku-fox" and name ~= "omarchy-fox" then
					vim.cmd.colorscheme(name)
					expect(vim.g.colors_name).toBe(name)
					expect(vim.api.nvim_get_hl(0, { name = "Normal" }).fg ~= nil).toBe(true)
				end
			end
		end)
		vim.cmd.colorscheme(original)
		assert(ok, err)
	end)
end)
