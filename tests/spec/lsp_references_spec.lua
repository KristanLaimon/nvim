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

	-- Regression: a full clear+re-attach on every BufEnter/BufWritePost/InsertLeave
	-- resurrected in-flight extmarks and stacked "# usages" many times per symbol.
	it("does not clear+re-attach symbol-usage while it already has workers", function()
		local prev_state = package.loaded["symbol-usage.state"]
		local prev_buf = package.loaded["symbol-usage.buf"]
		local prev_store = require("fox.core.store").load(lsp_refs.settings.store_file, {})
		local calls = { attach = 0, clear = 0 }

		require("fox.core.store").save(lsp_refs.settings.store_file, { enabled = true })
		package.loaded["symbol-usage.state"] = {
			get_buf_workers = function()
				return { fake = true }
			end,
		}
		package.loaded["symbol-usage.buf"] = {
			attach_buffer = function()
				calls.attach = calls.attach + 1
			end,
			clear_buffer = function()
				calls.clear = calls.clear + 1
			end,
		}

		local buf = vim.api.nvim_create_buf(true, false)
		lsp_refs.refresh(buf)
		expect(calls.attach).toBe(0)

		lsp_refs.clear(buf)
		expect(calls.clear).toBe(1)

		package.loaded["symbol-usage.state"] = prev_state
		package.loaded["symbol-usage.buf"] = prev_buf
		require("fox.core.store").save(lsp_refs.settings.store_file, prev_store)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)

	it("attaches symbol-usage when the buffer has no workers yet", function()
		local prev_state = package.loaded["symbol-usage.state"]
		local prev_buf = package.loaded["symbol-usage.buf"]
		local prev_store = require("fox.core.store").load(lsp_refs.settings.store_file, {})
		local attached = 0

		require("fox.core.store").save(lsp_refs.settings.store_file, { enabled = true })
		package.loaded["symbol-usage.state"] = {
			get_buf_workers = function()
				return {}
			end,
		}
		package.loaded["symbol-usage.buf"] = {
			attach_buffer = function()
				attached = attached + 1
			end,
		}

		local buf = vim.api.nvim_create_buf(true, false)
		lsp_refs.refresh(buf)
		expect(attached).toBe(1)

		package.loaded["symbol-usage.state"] = prev_state
		package.loaded["symbol-usage.buf"] = prev_buf
		require("fox.core.store").save(lsp_refs.settings.store_file, prev_store)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)
end)
