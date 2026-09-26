local M = {}

function M.run()
	local json = require("fox.lib.foxnvim.json")
	local obj = { name = "foxnvimscript", version = 1, active = true }
	local encoded = json.encode(obj)
	assert(encoded:find("foxnvimscript"), "JSON encode failed")

	local decoded = json.decode(encoded)
	assert(decoded.name == "foxnvimscript", "JSON decode name failed")
	assert(decoded.version == 1, "JSON decode version failed")
	assert(decoded.active == true, "JSON decode boolean failed")

	print("  ✓ foxnvim.json spec passed")
end

return M
