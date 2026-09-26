-- ============================================================================
-- tests/foxnvimscript/libraries/fetch_spec.lua -- Spec tests for foxnvim.fetch module
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local fetch = require("fox.lib.foxnvim.fetch")

describe("foxnvim.fetch module", function()
	it("exposes HTTP request methods", function()
		expect(type(fetch)).toBe("table")
		expect(type(fetch.get)).toBe("function")
		expect(type(fetch.post)).toBe("function")
		expect(type(fetch.put)).toBe("function")
		expect(type(fetch.delete)).toBe("function")
	end)
end)
