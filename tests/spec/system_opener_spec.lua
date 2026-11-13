local t = require("fox.lib.foxnvim.test")
local viewer = require("plugins.fox.ui.image_viewer")

t.describe("OS default application opener", function()
	local original_has, original_system, original_notify, original_spawn
	local filepath, calls, notifications, platform
	t.beforeEach(function()
		original_has, original_system, original_notify = vim.fn.has, vim.system, vim.notify
		original_spawn = vim.uv.spawn
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
		vim.uv.spawn = function(executable, opts, callback)
			local call = { cmd = { executable, unpack(opts.args) }, opts = opts }
			calls[#calls + 1] = call
			call.callback = function(result)
				callback(result.code)
			end
			return {
				is_closing = function()
					return call.closed == true
				end,
				close = function()
					call.closed = true
				end,
			}
		end
		vim.notify = function(message, level)
			notifications[#notifications + 1] = { message = message, level = level }
		end
	end)
	t.afterEach(function()
		vim.fn.has, vim.system, vim.notify = original_has, original_system, original_notify
		vim.uv.spawn = original_spawn
		vim.fn.delete(filepath)
	end)

	t.it("passes a Windows path as one literal argument without a command shell", function()
		platform = "win32"
		viewer.open_with_system_app(filepath)
		t.expect(calls[1].cmd).toEqual({ "explorer.exe", (filepath:gsub("/", "\\")) })
		t.expect(calls[1].opts.hide).toBe(false)
		calls[1].callback({ code = 1, stderr = "" })
		t.expect(calls[1].closed).toBe(true)
		vim.wait(10)
		t.expect(#notifications).toBe(1)
	end)
	t.it("uses the same literal folder dispatch for explicit directories and project root", function()
		platform = "win32"
		local dir = vim.fn.tempname() .. " folder & quote' %"
		vim.fn.mkdir(dir, "p")
		local project = require("fox.core.project")
		local original_root = project.root
		local ok, err = pcall(function()
			viewer.open_with_system_app(dir)
			t.expect(calls[1].cmd).toEqual({ "explorer.exe", (dir:gsub("/", "\\")) })
			t.expect(calls[1].opts.hide).toBe(false)
			project.root = function()
				return dir
			end
			viewer.open_project_root_in_explorer()
			t.expect(calls[2].cmd).toEqual(calls[1].cmd)
			calls[2].callback({ code = 2, stderr = "Association failed" })
			vim.wait(50, function()
				return #notifications == 3
			end)
			t.expect(notifications[3].message).toContain("exit 2")
		end)
		project.root = original_root
		vim.fn.delete(dir, "d")
		assert(ok, err)
	end)
	t.it("reports a Windows launch failure without announcing a successful open", function()
		platform = "win32"
		vim.uv.spawn = function()
			return nil, "ENOENT: explorer.exe"
		end
		viewer.open_with_system_app(filepath)
		t.expect(#notifications).toBe(1)
		t.expect(notifications[1].level).toBe(vim.log.levels.ERROR)
		t.expect(notifications[1].message).toContain("ENOENT")
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
