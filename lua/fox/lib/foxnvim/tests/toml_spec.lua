local M = {}

function M.run()
	local toml = require("fox.lib.foxnvim.toml")
	local sample_toml = [[
title = "foxnvimscript"
version = 1

[author]
name = "fox"
]]

	local decoded = toml.decode(sample_toml)
	assert(decoded.title == "foxnvimscript", "TOML decode title failed: " .. tostring(decoded.title))
	assert(decoded.author and decoded.author.name == "fox", "TOML decode section failed")

	local encoded = toml.encode(decoded)
	assert(encoded:find("foxnvimscript"), "TOML encode failed")

	print("  ✓ foxnvim.toml spec passed")
end

return M
