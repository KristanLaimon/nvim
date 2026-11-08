local t = require("fox.lib.foxnvim.test")

t.describe("WakaTime CLI installation", function()
	t.it("installs asynchronously, prevents duplicate installs, and allows retry after failure", function()
		local tracker = require("fox.wakatime")
		local installer = dofile(vim.fn.stdpath("config") .. "/lua/fox/wakatime/install.lua")
		local saved_cli, saved_system, saved_notify = tracker.cli, vim.system, vim.notify
		local saved_executable, saved_exepath = vim.fn.executable, vim.fn.exepath
		vim.fn.executable = function()
			return 1
		end
		vim.fn.exepath = function()
			return "fake-python"
		end
		local installed, callback, notifications = false, nil, {}
		local calls = 0
		tracker.cli = function()
			return installed and "installed-cli" or nil
		end
		vim.notify = function(message)
			table.insert(notifications, message)
		end
		vim.system = function(args, opts, done)
			calls = calls + 1
			t.expect(args[2]:find("install_wakatime.py", 1, true) ~= nil).toBe(true)
			t.expect(args[3]:find(".wakatime/wakatime-cli", 1, true) ~= nil).toBe(true)
			t.expect(opts.detach).toBe(nil)
			callback = done
		end
		local ok, err = pcall(function()
			installer.run()
			installer.run()
			t.expect(calls).toBe(1)
			callback({ code = 1, stderr = "download failed" })
			t.expect(vim.wait(1000, function()
				return (notifications[#notifications] or ""):find("download failed", 1, true) ~= nil
			end, 10)).toBe(true)
			installer.run()
			t.expect(calls).toBe(2)
			installed = true
			callback({ code = 0 })
			t.expect(vim.wait(1000, function()
				return (notifications[#notifications] or ""):find("Set your tracking key", 1, true) ~= nil
			end, 10)).toBe(true)
			installer.run()
			t.expect(calls).toBe(2)
			installed = false
			vim.fn.executable = function()
				return 0
			end
			installer.run()
			t.expect(calls).toBe(2)
			t.expect(notifications[#notifications]:find("Install Python 3", 1, true) ~= nil).toBe(true)
		end)
		tracker.cli, vim.system, vim.notify = saved_cli, saved_system, saved_notify
		vim.fn.executable, vim.fn.exepath = saved_executable, saved_exepath
		assert(ok, err)
	end)
end)
