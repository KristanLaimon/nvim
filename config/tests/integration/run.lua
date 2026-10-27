-- ============================================================================
-- config/tests/integration/run.lua -- Entry point for tests that need the REAL editor.
-- ============================================================================
-- WHY A SECOND RUNNER
--   config/tests/run.lua runs under `nvim -l` with no plugins, so it only covers pure
--   logic. Anything that needs nvim-dap, telescope or the actual startup sequence
--   has to boot the full config -- that is what this runner does.
--
-- HOW TO RUN
--   nvim --headless -S config/tests/integration/run.lua -- --only-failure
--   nvim --headless -S config/tests/integration/run.lua -- dap --only-failure    # name filter
--
-- WRITING AN INTEGRATION SPEC
--   Same shape as config/tests/spec (foxnvim.test describe/it/expect), but plugins may
--   be assumed loaded. Load what you need explicitly at the top of the spec:
--     require("lazy").load({ plugins = { "nvim-dap" } })
-- ============================================================================

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
local arguments = {}
local found_script = false
local function script_path(value)
	local path = vim.fs.normalize(vim.fn.fnamemodify(value, ":p"))
	return vim.fn.has("win32") == 1 and path:lower() or path
end
for _, argument in ipairs(vim.v.argv or {}) do
	if found_script then
		arguments[#arguments + 1] = argument
	elseif script_path(argument) == script_path(debug.getinfo(1, "S").source:sub(2)) then
		found_script = true
	end
end
local filter, options = require("fox.lib.foxnvim.test").parse_args(arguments)

local failed = 0

for _, file in ipairs(vim.fn.glob(root .. "/config/tests/integration/*_spec.lua", false, true)) do
	local name = vim.fn.fnamemodify(file, ":t:r")
	if not filter or name:find(filter, 1, true) then
		local ok, err = pcall(dofile, file)
		if not ok then
			failed = failed + 1
			print("  Failed to load spec -> " .. name .. ": " .. tostring(err))
		end
	end
end

local ok, result = pcall(require("fox.lib.foxnvim.test").run, options)
if not ok then
	print(tostring(result))
end

vim.cmd((failed > 0 or not ok or result.failed > 0) and "cq!" or "qa!")
