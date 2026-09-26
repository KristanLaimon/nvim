local M = {}

function M.run()
	local foxnvim = require("fox.lib.foxnvim")
	local import = foxnvim.import

	local json_mod = import("foxnvim.json")
	assert(type(json_mod.decode) == "function", "import('foxnvim.json') failed")

	local sh_mod = import("foxnvim.terminal")
	assert(type(sh_mod.exec) == "function", "import('foxnvim.terminal') failed")

	local cli_mod = import("foxnvim.cli")
	assert(type(cli_mod.parse_args) == "function", "import('foxnvim.cli') failed")

	print("  ✓ foxnvim.import spec passed")
end

return M
