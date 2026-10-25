local t = require("fox.lib.foxnvim.test")
t.describe("Local devicons compatibility", function()
	local saved, icons
	t.beforeEach(function()
		saved = package.loaded["mini.icons"]
		package.loaded["mini.icons"] = {
			get = function(category, name)
				if name == "widget.service.ts" or name == "service.ts" then
					return "S", "MiniIconsRed", false
				end
				if name == "lua" or name == "main.lua" then
					return "L", "MiniIconsBlue", false
				end
				if category == "default" then
					return "F", "MiniIconsGrey", true
				end
				return "F", "MiniIconsGrey", true
			end,
			list = function(category)
				return category == "extension" and { "lua", "service.ts" } or {}
			end,
		}
		package.loaded["fox.ui.devicons"] = nil
		package.loaded["nvim-web-devicons"] = nil
		icons = require("nvim-web-devicons")
		vim.api.nvim_set_hl(0, "MiniIconsBlue", { fg = "#4e79f0", ctermfg = 12 })
	end)
	t.afterEach(function()
		package.loaded["mini.icons"] = saved
		package.loaded["fox.ui.devicons"] = nil
		package.loaded["nvim-web-devicons"] = nil
	end)
	t.it("resolves file, extension, filetype and compound names", function()
		t.expect(icons.get_icon("/tmp/main.lua", "lua")).toBe("L")
		t.expect(icons.get_icon(nil, "lua")).toBe("L")
		t.expect(icons.get_icon_by_filetype("lua")).toBe("L")
		t.expect(icons.get_icon("widget.service.ts", "ts")).toBe("S")
	end)
	t.it("respects opt-in defaults and per-call overrides", function()
		t.expect(icons.get_icon("unknown")).toBe(nil)
		t.expect(icons.get_icon("unknown", nil, { default = true })).toBe("F")
		icons.setup({ default = true })
		t.expect(icons.get_icon("unknown")).toBe("F")
		t.expect(icons.get_icon("unknown", nil, { default = false })).toBe(nil)
	end)
	t.it("returns current hex and terminal colors", function()
		local icon, hex, term = icons.get_icon_colors("main.lua")
		t.expect(icon).toBe("L")
		t.expect(hex).toBe("#4e79f0")
		t.expect(term).toBe(12)
		vim.api.nvim_set_hl(0, "MiniIconsBlue", { fg = "#ffffff", ctermfg = 15 })
		local _, updated = icons.get_icon_color_by_filetype("lua")
		t.expect(updated).toBe("#ffffff")
	end)
	t.it("supports icon overrides, filetype aliases, defaults and color refresh", function()
		icons.set_icon({ custom = { icon = "C", color = "#123456", name = "Custom" } })
		icons.set_icon_by_filetype({ customft = "custom" })
		t.expect(icons.get_icon_by_filetype("customft")).toBe("C")
		icons.set_default_icon("D", "#654321", "7")
		t.expect(icons.get_icon("unknown", nil, { default = true })).toBe("D")
		vim.api.nvim_set_hl(0, "DevIconCustom", {})
		icons.refresh()
		local _, hex = icons.get_icon_color(nil, "custom")
		t.expect(hex).toBe("#123456")
	end)
	t.it("exposes a catalog and loaded status for Telescope and other consumers", function()
		t.expect(icons.has_loaded()).toBe(true)
		local entries = icons.get_icons_by_extension()
		t.expect(entries.lua.icon).toBe("L")
		t.expect(entries.lua.color).toBe("#4e79f0")
		t.expect(icons.get_icons()[1].name).toBe("Default")
	end)
end)
