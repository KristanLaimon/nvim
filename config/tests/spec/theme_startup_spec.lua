local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("local theme startup", function()
	it("keeps VS Code Dark 2026 and Dark Modern palettes distinct", function()
		local original = vim.g.colors_name or "default"
		local ok, err = pcall(function()
			for _, palette in ipairs({
				{ name = "vscode-dark", background = 0x121314, keyword = 0xFF7B72, func = 0xD2A8FF },
				{ name = "vscode-dark-modern", background = 0x1F1F1F, keyword = 0x569CD6, func = 0xDCDCAA },
			}) do
				vim.cmd.colorscheme(palette.name)
				expect(vim.g.colors_name).toBe(palette.name)
				expect(vim.api.nvim_get_hl(0, { name = "Normal" }).bg).toBe(palette.background)
				expect(vim.api.nvim_get_hl(0, { name = "Keyword" }).fg).toBe(palette.keyword)
				expect(vim.api.nvim_get_hl(0, { name = "Function" }).fg).toBe(palette.func)
			end
		end)
		vim.cmd.colorscheme(original)
		assert(ok, err)
	end)

	it("loads One Dark Pro Night Flat with flat panels and One Dark syntax", function()
		local original = vim.g.colors_name or "default"
		local ok, err = pcall(function()
			vim.cmd.colorscheme("one-dark-pro-night-flat")
			expect(vim.g.colors_name).toBe("one-dark-pro-night-flat")
			for _, group in ipairs({ "Normal", "StatusLine", "TabLineFill", "NeoTreeNormal" }) do
				expect(vim.api.nvim_get_hl(0, { name = group }).bg).toBe(0x16191D)
			end
			expect(vim.api.nvim_get_hl(0, { name = "Keyword" }).fg).toBe(0xC678DD)
			expect(vim.api.nvim_get_hl(0, { name = "Function" }).fg).toBe(0x61AFEF)
			expect(vim.api.nvim_get_hl(0, { name = "String" }).fg).toBe(0x98C379)
		end)
		vim.cmd.colorscheme(original)
		assert(ok, err)
	end)

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
