-- ============================================================================
-- tests/spec/theme_picker_spec.lua -- Nagatoro theme discovery & picker.
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
