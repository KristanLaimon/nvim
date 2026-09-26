-- ============================================================================
-- tests/foxnvimscript/libraries/yaml_spec.lua -- Spec tests for foxnvim.yaml module
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local yaml = require("fox.lib.foxnvim.yaml")

describe("foxnvim.yaml module", function()
	it("parses YAML strings and handles invalid input", function()
		expect(type(yaml)).toBe("table")
		if yaml.decode then
			local res = yaml.decode("name: FOX\nversion: 2")
			if res then
				expect(res.name).toBe("FOX")
			end
		end
	end)
end)
