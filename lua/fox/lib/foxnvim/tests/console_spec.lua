local M = {}

function M.run()
	local foxnvim = require("fox.lib.foxnvim")
	local import = foxnvim.import
	local console = import("console")

	assert(console ~= nil, "import('console') failed")
	assert(_G.console ~= nil, "global _G.console failed")

	-- Test stringify
	local obj = { name = "foxnvim", count = 5, active = true }
	local json_str = console.json(obj)
	assert(json_str:find('"name": "foxnvim"'), "console.json name failed")
	assert(json_str:find('"count": 5'), "console.json count failed")
	assert(json_str:find('"active": true'), "console.json boolean failed")

	-- Test format_args with table and primitives
	local formatted = console.format_args("Message:", obj, 100, true)
	assert(formatted:find("Message:"), "format_args message failed")
	assert(formatted:find('"name": "foxnvim"'), "format_args json table failed")
	assert(formatted:find("100 true"), "format_args primitives failed")

	-- Test callable console(...) and method logging
	local log_out = console.log("Test log", { a = 1 })
	assert(log_out:find("Test log"), "console.log string failed")
	assert(log_out:find('"a": 1'), "console.log table failed")

	local call_out = console("Direct call", { b = 2 })
	assert(call_out:find("Direct call"), "callable console(...) failed")

	local info_out = console.info("Info msg")
	assert(info_out:find("INFO"), "console.info failed")

	local warn_out = console.warn("Warn msg")
	assert(warn_out:find("WARN"), "console.warn failed")

	local error_out = console.error("Err msg")
	assert(error_out:find("ERROR"), "console.error failed")

	print("  ✓ foxnvim.console spec passed")
end

return M
