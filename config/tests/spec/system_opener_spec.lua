local t = require("fox.lib.foxnvim.test")
local viewer = require("plugins.fox.ui.image_viewer")

t.describe("OS default application opener", function()
	local original_has, original_system, original_notify
	local filepath, calls, notifications, platform
	t.beforeEach(function()
		original_has, original_system, original_notify = vim.fn.has, vim.system, vim.notify
		filepath = vim.fn.tempname() .. " space & quote' %.txt"
		vim.fn.writefile({ "test" }, filepath)
		calls, notifications, platform = {}, {}, "linux"
		vim.fn.has = function(feature)
			if feature == "win32" or feature == "wsl" or feature == "mac" or feature == "macunix" then
				return feature == platform and 1 or 0
			end
			return original_has(feature)
		end
		vim.system = function(cmd, opts, callback)
			calls[#calls + 1] = { cmd = cmd, opts = opts, callback = callback }
		end
		vim.notify = function(message, level)
			notifications[#notifications + 1] = { message = message, level = level }
		end
	end)
	t.afterEach(function()
		vim.fn.has, vim.system, vim.notify = original_has, original_system, original_notify
		vim.fn.delete(filepath)
	end)

	t.it("passes a Windows path as one literal argument without a command shell", function()
		platform = "win32"
		viewer.open_with_system_app(filepath)
		t.expect(calls[1].cmd).toEqual({ "explorer.exe", (filepath:gsub("/", "\\")) })
		t.expect(calls[1].opts.detach).toBe(true)
		calls[1].callback({ code = 1, stderr = "" })
		vim.wait(10)
		t.expect(#notifications).toBe(1)
	end)

	t.it("passes Linux paths literally and reports asynchronous opener failures", function()
		viewer.open_with_system_app(filepath)
		t.expect(calls[1].cmd).toEqual({ "xdg-open", filepath })
		calls[1].callback({ code = 3, stderr = "No application registered" })
		vim.wait(50, function()
			return #notifications == 2
		end)
		t.expect(notifications[2].level).toBe(vim.log.levels.ERROR)
		t.expect(notifications[2].message).toContain("No application registered")
	end)
end)
