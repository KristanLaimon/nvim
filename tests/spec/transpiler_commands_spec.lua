-- ============================================================================
-- tests/spec/transpiler_commands_spec.lua -- Spec tests for FoxTranspile commands
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("fox.lib.foxnvim.fs")

-- Ensure keymaps and user commands are loaded
require("keymaps.fox")

describe("FoxTranspile commands and file resolution", function()
	it("registers user commands for transpilation", function()
		expect(vim.fn.exists(":FoxTranspile")).toBe(2)
		expect(vim.fn.exists(":FoxTranspileBoth")).toBe(2)
		expect(vim.fn.exists(":FoxTranspileSh")).toBe(2)
		expect(vim.fn.exists(":FoxTranspilePs1")).toBe(2)
		expect(vim.fn.exists(":FoxExport")).toBe(2)
	end)

	it("transpiles active .foxnvim buffer next to the file", function()
		local tmp = vim.fn.tempname() .. "_test.foxnvim"
		fs.write(tmp, 'local x = 10\nprint("Value:", x)')

		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp)
		vim.api.nvim_set_current_buf(buf)

		vim.cmd("FoxTranspileBoth")

		local sh_path = tmp:gsub("%.foxnvim$", ".sh")
		local ps1_path = tmp:gsub("%.foxnvim$", ".ps1")

		expect(fs.exists(sh_path)).toBe(true)
		expect(fs.exists(ps1_path)).toBe(true)

		-- Cleanup
		os.remove(tmp)
		if fs.exists(sh_path) then
			os.remove(sh_path)
		end
		if fs.exists(ps1_path) then
			os.remove(ps1_path)
		end
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	it("rejects non-foxnvim files without transpiling", function()
		local tmp = vim.fn.tempname() .. "_test.lua"
		fs.write(tmp, 'print("Lua file")')

		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp)
		vim.api.nvim_set_current_buf(buf)

		vim.cmd("FoxTranspileBoth")

		local sh_path = tmp:gsub("%.lua$", ".sh")
		expect(fs.exists(sh_path)).toBe(false)

		os.remove(tmp)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
