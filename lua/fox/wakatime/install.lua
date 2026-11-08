local M = {}
local installing = false

function M.run()
	if installing then
		vim.notify("WakaTime CLI installation is already running.")
		return
	end
	local existing = require("fox.wakatime").cli()
	if existing then
		vim.notify("WakaTime CLI is already installed: " .. existing)
		return
	end
	local windows = vim.fn.has("win32") == 1
	local python
	for _, name in ipairs(windows and { "python", "python3" } or { "python3", "python" }) do
		if vim.fn.executable(name) == 1 then
			python = vim.fn.exepath(name)
			break
		end
	end
	if not python then
		vim.notify("Install Python 3, then run :WakaTimeInstall again.", vim.log.levels.ERROR)
		return
	end
	local destination = (vim.env.WAKATIME_HOME or vim.fn.expand("~"))
		.. "/.wakatime/wakatime-cli"
		.. (windows and ".exe" or "")
	installing = true
	vim.notify("Downloading and verifying the official WakaTime CLI...")
	local ok, err = pcall(
		vim.system,
		{
			python,
			vim.fn.stdpath("config") .. "/config/scripts/dependencies/install_wakatime.py",
			destination,
		},
		{ text = true, timeout = 180000 },
		vim.schedule_wrap(function(result)
			installing = false
			if result.code == 0 and require("fox.wakatime").cli() then
				vim.notify("WakaTime CLI installed. Set your tracking key with :WakaTimeApiKey.")
			else
				vim.notify("WakaTime CLI installation failed: " .. vim.trim(result.stderr or ""), vim.log.levels.ERROR)
			end
		end)
	)
	if not ok then
		installing = false
		vim.notify("Could not start WakaTime CLI installation: " .. tostring(err), vim.log.levels.ERROR)
	end
end

return M
