local t = require("fox.lib.foxnvim.test")
t.describe("Local dependency replacement specs", function()
	t.it("keeps each replacement distinct in Lazy and configures its user commands", function()
		local names = { "fox_icons", "fox_color_highlights", "fox_blade", "fox_laravel", "fox_inline_blame" }
		local plugins = require("lazy.core.config").plugins
		local dirs = {}
		for _, name in ipairs(names) do
			t.expect(plugins[name] ~= nil).toBe(true)
			t.expect(dirs[plugins[name].dir]).toBe(nil)
			dirs[plugins[name].dir] = true
		end
		require("lazy").load({ plugins = names })
		t.expect(vim.fn.exists(":GitBlameToggle")).toBe(2)
		t.expect(vim.fn.exists(":HighlightColors")).toBe(2)
		t.expect(vim.fn.exists(":BladeNavGoToFile")).toBe(2)
		t.expect(_G.MiniIcons == require("fox.ui.icons")).toBe(true)
	end)
end)
