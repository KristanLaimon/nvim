-- ============================================================================
-- tests/integration/run.lua -- Entry point for tests that need the REAL editor.
-- ============================================================================
-- WHY A SECOND RUNNER
--   tests/run.lua runs under `nvim -l` with no plugins, so it only covers pure
--   logic. Anything that needs nvim-dap, telescope or the actual startup sequence
--   has to boot the full config -- that is what this runner does.
--
-- HOW TO RUN
--   nvim --headless -S tests/integration/run.lua -- --only-failure
--   nvim --headless -S tests/integration/run.lua -- dap --only-failure    # name filter
--
-- WRITING AN INTEGRATION SPEC
--   Same shape as tests/spec (foxnvim.test describe/it/expect), but plugins may
--   be assumed loaded. Load what you need explicitly at the top of the spec:
--     require("lazy").load({ plugins = { "nvim-dap" } })
-- ============================================================================

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
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
local function run()
	local filter, options = require("fox.lib.foxnvim.test").parse_args(arguments)

	local files = {}
	for _, file in ipairs(vim.fn.glob(root .. "/tests/integration/*_spec.lua", false, true)) do
		local name = vim.fn.fnamemodify(file, ":t:r")
		if not filter or name:find(filter, 1, true) then
			files[#files + 1] = file
		end
	end

	local child_spec = vim.env.FOX_TEST_INTEGRATION_SPEC
	if not child_spec then
		-- Each spec owns editor-wide fixtures: cwd, buffers, mappings and lazy loading.
		local passed, failed, os_dependent = 0, 0, 0
		for _, file in ipairs(files) do
			local command = { vim.v.progpath, "--headless", "-i", "NONE", "-S", root .. "/tests/integration/run.lua", "--" }
			if options.only_failure then
				command[#command + 1] = "--only-failure"
			end
			local environment = vim.fn.environ()
			-- Supplying env opts otherwise reintroduces the outer editor's RPC socket.
			environment.NVIM, environment.NVIM_LISTEN_ADDRESS = nil, nil
			environment.FOX_TEST_INTEGRATION_SPEC = file
			local stdout_file, stderr_file
			if vim.fn.has("win32") == 1 then
				-- Use real files so descendants cannot keep the runner's capture pipes open.
				stdout_file, stderr_file = vim.fn.tempname(), vim.fn.tempname()
				local python = vim.fn.exepath("python")
				if python == "" then
					python = vim.fn.exepath("python3")
				end
				assert(python ~= "", "Windows integration tests require Python for isolated process IO")
				command = {
					python,
					"-c",
					[[
import subprocess, sys
command = [sys.argv[1], '--headless', '-i', 'NONE', '-S', sys.argv[2], '--']
if sys.argv[5] == '1':
    command.append('--only-failure')
with open(sys.argv[3], 'wb') as stdout, open(sys.argv[4], 'wb') as stderr:
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                close_fds=True, creationflags=subprocess.CREATE_NO_WINDOW, timeout=120)
    except subprocess.TimeoutExpired:
        sys.exit(124)
sys.exit(result.returncode)
]],
					vim.v.progpath,
					root .. "/tests/integration/run.lua",
					stdout_file,
					stderr_file,
					options.only_failure and "1" or "0",
				}
			end
			local result = vim
				.system(command, {
					cwd = root,
					env = environment,
					clear_env = true,
					text = true,
				})
				:wait(120000)
			local output = (result.stdout or "") .. (result.stderr or "")
			for _, path in ipairs({ stdout_file, stderr_file }) do
				if vim.fn.filereadable(path) == 1 then
					output = output .. table.concat(vim.fn.readfile(path), "\n") .. "\n"
				end
				vim.fn.delete(path)
			end
			if result.code == 124 then
				output = output .. "\nIntegration spec timed out: " .. file
			elseif result.code ~= 0 then
				output = output .. "\nIntegration process exited with code " .. tostring(result.code) .. ": " .. file
			end
			local spec_passed, spec_failed, spec_os =
				output:match("Test Results: (%d+) Passed, (%d+) Failed, (%d+) Not%-Tests OS%-Dependent")
			os_dependent = os_dependent + (tonumber(spec_os) or 0)
			passed = passed + (tonumber(spec_passed) or 0)
			failed = failed + (tonumber(spec_failed) or 0)
			if (result.code ~= 0 or not spec_passed) and (tonumber(spec_failed) or 0) == 0 then
				failed = failed + 1
			end
			if not spec_passed then
				output = output .. "\nMissing test summary (process exit " .. tostring(result.code) .. "): " .. file
			end
			if result.code ~= 0 or (tonumber(spec_failed) or 0) > 0 or not spec_passed or not options.only_failure then
				print(vim.fn.fnamemodify(file, ":t") .. "\n" .. output)
			else
				for line in output:gmatch("[^\r\n]+") do
					if line:match("^Skipping ") or line:match("^Not%-Tests OS%-Dependent:") then
						print(line)
					end
				end
			end
		end
		print(string.format("Test Results: %d Passed, %d Failed, %d Not-Tests OS-Dependent", passed, failed, os_dependent))
		vim.cmd(failed > 0 and "cq!" or "qa!")
		return
	end

	local failed = 0
	for _, file in ipairs(files) do
		if script_path(file) == script_path(child_spec) then
			local ok, err = pcall(dofile, file)
			if not ok then
				failed = failed + 1
				print("Failed to load spec -> " .. file .. ": " .. tostring(err))
			end
		end
	end

	local ok, result = pcall(require("fox.lib.foxnvim.test").run, options)
	if not ok then
		print(tostring(result))
	end

	vim.cmd((failed > 0 or not ok or result.failed > 0) and "cq!" or "qa!")
end

if vim.v.vim_did_enter == 1 then
	vim.schedule(run)
else
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function()
			vim.schedule(run)
		end,
	})
end
