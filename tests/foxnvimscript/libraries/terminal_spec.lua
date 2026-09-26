-- ============================================================================
-- tests/foxnvimscript/libraries/terminal_spec.lua -- Spec tests for foxnvim.terminal module
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local terminal = require("fox.lib.foxnvim.terminal")

describe("foxnvim.terminal module", function()
	it("executes basic echo command", function()
		local res = terminal.exec("echo hello_fox")
		expect(res.ok).toBe(true)
		expect(res.code).toBe(0)
		expect(res.output).toContain("hello_fox")
	end)

	it("supports callable $ syntax", function()
		local res = terminal("echo fox_dollar")
		expect(res.ok).toBe(true)
		expect(res.output).toContain("fox_dollar")
	end)

	it("returns current working directory", function()
		local cwd = terminal.cwd()
		expect(type(cwd)).toBe("string")
		expect(#cwd > 0).toBe(true)
	end)
end)
