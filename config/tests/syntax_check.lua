-- ============================================================================
-- config/tests/syntax_check.lua -- Parse every Lua file in the config.
-- ============================================================================
-- WHY
--   A syntax error in a plugin file is invisible until the moment lazy.nvim loads
--   it, which is usually the worst moment. This compiles (but never runs) every
--   file, so a broken edit is caught immediately.
--
-- HOW TO RUN
--   nvim -l config/tests/syntax_check.lua
--   Exits 1 and prints `file:line: message` for each file that fails to parse.
-- ============================================================================

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

--- Directories scanned, relative to the config root.
local scan_dirs = { "lua", "config/tests", "config/colors", "config/schemas-langs" }

local failures = 0
local checked = 0

for _, dir in ipairs(scan_dirs) do
	for _, file in ipairs(vim.fn.glob(root .. "/" .. dir .. "/**/*.lua", false, true)) do
		checked = checked + 1
		local _, err = loadfile(file)
		if err then
			failures = failures + 1
			print("  ✗ " .. err)
		end
	end
end

print(string.format("Parsed %d files, %d with syntax errors.", checked, failures))
os.exit(failures > 0 and 1 or 0)
