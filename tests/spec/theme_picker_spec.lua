-- ============================================================================
-- tests/spec/theme_picker_spec.lua -- Local theme discovery & picker.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local theme_picker = require("plugins.fox.ui.theme_picker")

describe("plugins.fox.ui.theme_picker", function()
	it("discovers renamed palettes and Doki Rei in colors/", function()
		local themes = theme_picker.discover_themes()
		expect(themes).toContain("foxnvim")
		expect(themes).toContain("foxnvim-light")
		expect(themes).toContain("onedar")
		expect(themes).toContain("one-dark-pro-night-flat")
		expect(themes).toContain("catppuccin")
		expect(themes).toContain("nord")
		expect(themes).toContain("kanagawa")
		expect(themes).toContain("foxnvim-full-back")
		expect(themes).toContain("doki-rey-ayanami-dark")
	end)

	it("resolves legacy saved theme names", function()
		local renamed = {
			["onedark-fox"] = "onedar",
			["nord-fox"] = "nord",
			["nagatoro-light"] = "foxnvim-light",
			["nagatoro-fox"] = "foxnvim",
			["kanagawa-fox"] = "kanagawa",
			["dark-fox-night"] = "foxnvim-full-back",
			["catppuccin-fox"] = "catppuccin",
		}
		for old, name in pairs(renamed) do
			expect(theme_picker.resolve_theme(old)).toBe(name)
		end
		expect(theme_picker.resolve_theme("doki-rey-ayanami-dark")).toBe("doki-rey-ayanami-dark")
		expect(theme_picker.resolve_theme(nil)).toBe(nil)
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
		local ryoku = require("plugins.fox.ui.ryoku_theme")
		local omarchy = require("plugins.fox.ui.omarchy_theme")
		local ryoku_file, omarchy_file = ryoku.settings.store_file, omarchy.settings.store_file
		project.root = function()
			return active
		end
		theme_picker.settings.store_file = root .. "/global/theme.json"
		ryoku.settings.store_file, omarchy.settings.store_file =
			theme_picker.settings.store_file, theme_picker.settings.store_file
		local ok, err = pcall(function()
			assert(
				store.save(theme_picker.settings.store_file, { theme = "nord-fox", ryoku_sync = false, omarchy_sync = false })
			)
			local global_before = store.read_file(theme_picker.settings.store_file)
			theme_picker.set_theme("onedar", "project")
			expect(store.load(active .. "/.foxnvim/theme.json", {}).theme).toBe("onedar")
			expect(store.read_file(theme_picker.settings.store_file)).toBe(global_before)
			expect(vim.g.colors_name).toBe("onedar")
			active = root .. "/two"
			theme_picker.restore_saved_theme()
			expect(vim.g.colors_name).toBe("nord")
			assert(store.save(active .. "/.vscode/theme.json", { theme = "onedar" }))
			expect(theme_picker.get_current_theme()).toBe("nord")
			vim.ui.select = function(options, _, callback)
				expect(#options).toBe(2)
				callback(nil)
			end
			vim.cmd.colorscheme("foxnvim-light")
			theme_picker.choose_scope("foxnvim-light", "nord", theme_picker.project_theme_file())
			expect(vim.g.colors_name).toBe("nord")
			expect(store.read_file(theme_picker.settings.store_file)).toBe(global_before)
			expect(store.read_file(theme_picker.project_theme_file())).toBe(nil)
			assert(store.save(theme_picker.project_theme_file(), { theme = false }))
			expect(theme_picker.get_current_theme()).toBe("nord")
			active = root .. "/one"
			vim.api.nvim_exec_autocmds("BufEnter", { modeline = false })
			vim.wait(1000, function()
				return vim.g.colors_name == "onedar"
			end)
			expect(vim.g.colors_name).toBe("onedar")
			theme_picker.set_theme("catppuccin", "global")
			expect(store.load(theme_picker.settings.store_file, {}).theme).toBe("catppuccin")
			expect(store.load(theme_picker.project_theme_file(), {}).theme).toBe("onedar")
			expect(vim.g.colors_name).toBe("onedar")
			active = root .. "/two"
			theme_picker.restore_saved_theme()
			expect(vim.g.colors_name).toBe("catppuccin")
		end)
		project.root, theme_picker.settings.store_file = saved_root, saved_file
		theme_picker._project_file = saved_project
		ryoku.settings.store_file, omarchy.settings.store_file = ryoku_file, omarchy_file
		vim.ui.select = saved_select
		pcall(vim.cmd.colorscheme, saved_theme)
		assert(ok, err)
	end)
end)
