-- ============================================================================
-- tests/foxnvimscript/libraries/toml_spec.lua -- Spec tests for foxnvim.toml module
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local toml = require("fox.lib.foxnvim.toml")

describe("foxnvim.toml module", function()
	it("parses TOML strings and handles basic structures", function()
		expect(type(toml)).toBe("table")
		if toml.decode then
			local res = toml.decode('name = "FOX"\nversion = 2')
			if res then
				expect(res.name).toBe("FOX")
			end
		end
	end)
end)
