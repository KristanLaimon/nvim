local t = require("fox.lib.foxnvim.test")

t.describe("Fox Reader command registration", function()
	t.it("opens the reader from the palette before the preview plugin has loaded", function()
		local browser = require("fox.markdown.browser")
		local original_open = browser.open
		local opened
		browser.open = function(url)
			opened = url
		end
		local palette = require("plugins.fox.tools.command_palette")
		local original_record = palette.record_command_use
		palette.record_command_use = function() end
		local item
		for _, command in ipairs(palette.commands) do
			if command.cmd == "FoxReader" then
				item = command
				break
			end
		end
		local ok, err = pcall(palette.execute_item, item)
		palette.record_command_use = original_record
		browser.open = original_open
		require("fox.reader.server").stop()
		t.expect(item ~= nil).toBe(true)
		t.expect(ok).toBe(true)
		t.expect(err).toBe(nil)
		t.expect(type(opened)).toBe("string")
	end)
end)
