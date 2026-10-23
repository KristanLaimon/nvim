-- ============================================================================
-- config/tests/spec/theme_picker_spec.lua -- Nagatoro theme discovery & picker.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local theme_picker = require("plugins.fox.ui.theme_picker")

describe("plugins.fox.ui.theme_picker", function()
	it("discovers all -fox and nagatoro-* formatted themes in colors/", function()
		local themes = theme_picker.discover_themes()
		expect(themes).toContain("nagatoro-fox")
		expect(themes).toContain("nagatoro-light")
		expect(themes).toContain("onedark-fox")
		expect(themes).toContain("catppuccin-fox")
		expect(themes).toContain("nord-fox")
	end)

	it("registers FoxThemePicker user command", function()
		theme_picker.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["FoxThemePicker"]).toBeDefined()
	end)

	it("retrieves current saved theme or fallback", function()
		local current = theme_picker.get_current_theme()
		expect(type(current)).toBe("string")
		expect(#current).toBeGreaterThan(0)
	end)
end)

describe("project UI themes", function()
	it("isolates project choices, restores global defaults, and cancels without saving", function()
		local project = require("fox.core.project")
		local store = require("fox.core.store")
		local root = vim.fn.tempname()
		local active = root .. "/one"
		local saved_root, saved_file = project.root, theme_picker.settings.store_file
		local saved_select, saved_theme = vim.ui.select, vim.g.colors_name or "default"
		local saved_project = theme_picker._project_file
		project.root = function()
			return active
		end
		theme_picker.settings.store_file = root .. "/global/theme.json"
		local ok, err = pcall(function()
			assert(
				store.save(theme_picker.settings.store_file, { theme = "nord-fox", ryoku_sync = false, omarchy_sync = false })
			)
			local global_before = store.read_file(theme_picker.settings.store_file)
			theme_picker.set_theme("onedark-fox", "project")
			expect(store.load(active .. "/.foxnvim/theme.json", {}).theme).toBe("onedark-fox")
			expect(store.read_file(theme_picker.settings.store_file)).toBe(global_before)
			expect(vim.g.colors_name).toBe("onedark-fox")
			active = root .. "/two"
			theme_picker.restore_saved_theme()
			expect(vim.g.colors_name).toBe("nord-fox")
			assert(store.save(active .. "/.vscode/theme.json", { theme = "onedark-fox" }))
			expect(theme_picker.get_current_theme()).toBe("nord-fox")
			vim.ui.select = function(options, _, callback)
				expect(#options).toBe(2)
				callback(nil)
			end
			vim.cmd.colorscheme("nagatoro-light")
			theme_picker.choose_scope("nagatoro-light", "nord-fox", theme_picker.project_theme_file())
			expect(vim.g.colors_name).toBe("nord-fox")
			expect(store.read_file(theme_picker.settings.store_file)).toBe(global_before)
			expect(store.read_file(theme_picker.project_theme_file())).toBe(nil)
			assert(store.save(theme_picker.project_theme_file(), { theme = false }))
			expect(theme_picker.get_current_theme()).toBe("nord-fox")
			active = root .. "/one"
			vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })
			vim.wait(1000, function()
				return vim.g.colors_name == "onedark-fox"
			end)
			expect(vim.g.colors_name).toBe("onedark-fox")
			theme_picker.set_theme("catppuccin-fox", "global")
			expect(store.load(theme_picker.settings.store_file, {}).theme).toBe("catppuccin-fox")
			expect(store.load(theme_picker.project_theme_file(), {}).theme).toBe("onedark-fox")
			expect(vim.g.colors_name).toBe("onedark-fox")
			active = root .. "/two"
			theme_picker.restore_saved_theme()
			expect(vim.g.colors_name).toBe("catppuccin-fox")
		end)
		project.root, theme_picker.settings.store_file = saved_root, saved_file
		theme_picker._project_file = saved_project
		vim.ui.select = saved_select
		pcall(vim.cmd.colorscheme, saved_theme)
		assert(ok, err)
	end)
end)
