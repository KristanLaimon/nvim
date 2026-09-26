local M = {}

function M.run()
	local fs = require("fox.lib.foxnvim.fs")
	local test_file = vim.fn.stdpath("cache") .. "/fox_test_fs.txt"

	fs.write(test_file, "hello foxnvim fs")
	assert(fs.exists(test_file), "fs.exists failed")

	local content = fs.read(test_file)
	assert(content == "hello foxnvim fs", "fs.read content mismatch: " .. tostring(content))

	vim.fn.delete(test_file)
	print("  ✓ foxnvim.fs spec passed")
end

return M
