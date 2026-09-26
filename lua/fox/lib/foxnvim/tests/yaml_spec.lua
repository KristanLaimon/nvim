local M = {}

function M.run()
	local yaml = require("fox.lib.foxnvim.yaml")
	local sample_yaml = [[
name: foxnvimscript
version: 2
mode: test
]]

	local decoded = yaml.decode(sample_yaml)
	assert(decoded.name == "foxnvimscript", "YAML decode name failed: " .. tostring(decoded.name))
	assert(decoded.version == 2, "YAML decode version failed: " .. tostring(decoded.version))

	local encoded = yaml.encode(decoded)
	assert(encoded:find("foxnvimscript"), "YAML encode failed")

	print("  ✓ foxnvim.yaml spec passed")
end

return M
