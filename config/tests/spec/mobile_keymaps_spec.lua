-- ============================================================================
-- config/tests/spec/mobile_keymaps_spec.lua -- Mobile & Phone term keymap tests.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

-- Ensure keymaps are loaded
require("keymaps")

describe("Mobile & Phone Termux keymap aliases", function()
	it("registers launch shortcuts according to the detected environment", function()
		local environment = require("fox.core.environment")
		local detect, launch = environment.detect, _G.LaunchProfiles
		local ok, err = pcall(function()
			for _, mobile in ipairs({ false, true }) do
				environment.detect = function()
					return { is_mobile = mobile }
				end
				local spec = dofile(vim.fn.stdpath("config") .. "/lua/plugins/fox/dev/launch_profiles.lua")
				expect(vim.tbl_contains(spec.settings.keys.smart_launch, "<C-s>")).toBe(mobile)
				local keys = vim.tbl_map(function(binding)
					return binding[1]
				end, spec.keys)
				expect(vim.tbl_contains(keys, "<C-S>")).toBe(mobile)
			end
		end)
		environment.detect, _G.LaunchProfiles = detect, launch
		assert(ok, err)
	end)

	it("binds Command Palette shortcuts for Ctrl+Shift+P and leader aliases", function()
		local palette = require("plugins.fox.tools.command_palette")
		palette.setup()
		expect(palette.settings.keys.open).toContain("<C-S-p>")
		expect(palette.settings.keys.open).toContain("<leader>cp")
	end)

	it("binds Integrated Terminal toggle shortcuts for Ctrl+t, Ctrl+\\, leader+t, and leader+ft", function()
		local term = require("plugins.fox.dev.terminal")
		term.setup()
		expect(term.settings.keys.toggle).toContain("<C-t>")
		expect(term.settings.keys.toggle).toContain("<C-T>")
		expect(term.settings.keys.toggle).toContain("<C-\\>")
		expect(term.settings.keys.toggle).toContain("<leader>t")
		expect(term.settings.keys.toggle).toContain("<leader>ft")
	end)

	it("binds File Explorer toggle shortcuts for Ctrl+e, Ctrl+E, leader+e, and leader+fe", function()
		local editor = require("keymaps.editor")
		expect(editor.settings.keys.explorer).toContain("<C-e>")
		expect(editor.settings.keys.explorer).toContain("<C-E>")
		expect(editor.settings.keys.explorer).toContain("<leader>e")
		expect(editor.settings.keys.explorer).toContain("<leader>fe")
	end)

	it("has ZERO keymap collisions across all mobile shortcut aliases", function()
		local registry = require("fox.core.keymap_registry")
		expect(#registry.collisions).toBe(0)
	end)
end)
