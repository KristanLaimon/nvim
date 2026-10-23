local t = require("fox.lib.foxnvim.test")
local ryoku = require("plugins.fox.ui.ryoku_theme")

t.describe("Ryoku palette", function()
	t.it("maps material surfaces and terminal colors", function()
		local c = ryoku.translate({
			background = "#19120d",
			foreground = "#f0dfd6",
			primary = "#ffb782",
			surfaceContainerHigh = "#312822",
			color1 = "#ffb4ab",
		})
		t.expect(c.mode).toBe("dark")
		t.expect(c.accent).toBe("#ffb782")
		t.expect(c.lighter_background).toBe("#312822")
		t.expect(c.red).toBe("#ffb4ab")
	end)
	t.it("rejects incomplete or invalid palettes", function()
		t.expect(ryoku.translate({ background = "invalid", foreground = "#ffffff" })).toBe(nil)
		t.expect(ryoku.translate({})).toBe(nil)
	end)
	t.it("recognizes light palettes", function()
		t.expect(ryoku.translate({ background = "#fafafa", foreground = "#202020" }).mode).toBe("light")
	end)
end)
