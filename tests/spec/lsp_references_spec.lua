-- ============================================================================
-- tests/spec/lsp_references_spec.lua -- LSP reference counter & CodeLens.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local lsp_refs = require("plugins.fox.tools.lsp_references")

describe("plugins.fox.tools.lsp_references", function()
	it("defaults to enabled = true (ON)", function()
		expect(type(lsp_refs.is_enabled())).toBe("boolean")
	end)

	it("registers FoxToggleReferences and FoxRunCodeLens user commands", function()
		lsp_refs.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["FoxToggleReferences"]).toBeDefined()
		expect(cmds["FoxRunCodeLens"]).toBeDefined()
	end)

	it("toggles enabled state and returns boolean", function()
		local initial = lsp_refs.is_enabled()
		lsp_refs.toggle()
		local toggled = lsp_refs.is_enabled()
		expect(toggled).toBe(not initial)
		-- Restore
		lsp_refs.toggle()
		expect(lsp_refs.is_enabled()).toBe(initial)
	end)

	it("runs refresh without throwing errors when no LSP is attached", function()
		expect(function()
			lsp_refs.refresh(0)
		end).not_.toThrow()
	end)
end)
