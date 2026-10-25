local t = require("fox.lib.foxnvim.test")
t.describe("FOX icon catalog", function()
	local icons = require("fox.ui.icons")
	t.it("preserves the original config-file glyphs through the devicons consumer API", function()
		local saved = vim.deepcopy(icons.config)
		require("plugins.ui.devicons")[1].config()
		local devicons = require("fox.ui.devicons")
		for filename, expected in pairs({
			["settings.toml"] = { "", "MiniIconsOrange" },
			["data.json"] = { "󰘦", "MiniIconsYellow" },
			[".luacheckrc"] = { "󰢱", "MiniIconsBlue" },
			[".gitignore"] = { "󰊢", "MiniIconsPurple" },
		}) do
			local glyph, hl = devicons.get_icon(filename, filename:match("[^.]+$"))
			t.expect(glyph).toBe(expected[1])
			t.expect(hl).toBe(expected[2])
		end
		t.expect(#icons.list("filetype") > 900).toBe(true)
		icons.setup(saved)
	end)
	t.it("covers supported languages with native filetype detection and Windows paths", function()
		for _, ft in ipairs({
			"lua",
			"php",
			"blade",
			"typescript",
			"go",
			"python",
			"rust",
			"cpp",
			"cs",
			"zig",
			"ruby",
			"haskell",
			"teal",
			"html",
			"astro",
			"proto",
		}) do
			local _, _, fallback = icons.get("filetype", ft)
			t.expect(fallback).toBe(false)
		end
		t.expect(icons.get("file", [[C:\src\main.lua]])).toBe(icons.get("filetype", "lua"))
	end)
	t.it("keeps specific filenames and longest compound suffixes ahead of generic extensions", function()
		icons.setup(require("fox.langs.typescript").icons)
		t.expect(icons.get("file", "app.controller.spec.ts")).toBe(icons.get("extension", "spec.ts"))
		t.expect(icons.get("file", "nest-cli.json")).toBe("")
		t.expect(icons.get("file", "settings.blade.php")).toBe(icons.get("filetype", "blade"))
	end)
	t.it("distinguishes defaults and reapplies palette after theme changes", function()
		local _, _, fallback = icons.get("file", "random.unknownextension")
		t.expect(fallback).toBe(true)
		vim.api.nvim_set_hl(0, "MiniIconsBlue", {})
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		t.expect(vim.api.nvim_get_hl(0, { name = "MiniIconsBlue" }).fg).toBe(0x4e79f0)
		t.expect(#icons.list("extension") > 40).toBe(true)
	end)
end)
