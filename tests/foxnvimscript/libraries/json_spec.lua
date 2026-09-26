-- ============================================================================
-- tests/foxnvimscript/libraries/json_spec.lua -- Spec tests for foxnvim.json module
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local json = require("fox.lib.foxnvim.json")

describe("foxnvim.json module", function()
	it("encodes and decodes JSON objects", function()
		local tbl = { name = "FOX", version = 2 }
		local encoded = json.encode(tbl)
		expect(type(encoded)).toBe("string")
		expect(encoded).toContain("FOX")

		local decoded = json.decode(encoded)
		expect(decoded.name).toBe("FOX")
		expect(decoded.version).toBe(2)
	end)

	it("handles nil and empty inputs gracefully", function()
		expect(json.encode(nil)).toBe("null")
		expect(json.decode(nil)).toBe(nil)
	end)
end)
