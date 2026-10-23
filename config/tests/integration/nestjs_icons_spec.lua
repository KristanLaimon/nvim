local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

require("lazy").load({ plugins = { "mini.icons" } })

describe("NestJS file icons", function()
	it("gives controllers, modules, services, and specs distinct role icons", function()
		local icons = require("mini.icons")
		local seen = {}
		for _, filename in ipairs({
			"app.controller.ts",
			"app.module.ts",
			"app.service.ts",
			"app.controller.spec.ts",
		}) do
			local glyph, hl = icons.get("file", filename)
			expect(seen[glyph] == nil).toBe(true)
			expect(seen[hl] == nil).toBe(true)
			seen[glyph], seen[hl] = true, true
		end
		local spec_glyph, spec_hl = icons.get("file", "app.controller.spec.ts")
		for _, filename in ipairs({ "app.module.spec.ts", "app.service.spec.js", "example.spec.ts" }) do
			local glyph, hl = icons.get("file", filename)
			expect(glyph).toBe(spec_glyph)
			expect(hl).toBe(spec_hl)
		end
	end)

	it("resolves compound suffixes through mini.icons and the devicons mock", function()
		local icons = require("mini.icons")
		local devicons = require("nvim-web-devicons")
		local ts_icon, ts_hl = icons.get("file", "main.ts")
		for category, entries in pairs(require("fox.langs.typescript").icons) do
			for name, expected in pairs(entries) do
				local filename = category == "extension" and ("users." .. name) or name
				local path = "C:/project/src/" .. filename
				local glyph, hl = icons.get("file", path)
				expect(glyph).toBe(expected.glyph)
				expect(hl).toBe(expected.hl)
				local mock_glyph, mock_hl = devicons.get_icon(filename, filename:match("[^.]+$"))
				expect(mock_glyph).toBe(expected.glyph)
				expect(mock_hl).toBe(expected.hl)
			end
		end
		expect(icons.get("file", "main.ts")).toBe(ts_icon)
		local _, hl = icons.get("file", "main.ts")
		expect(hl).toBe(ts_hl)
		expect(ts_icon == "").toBe(false)
	end)
end)
