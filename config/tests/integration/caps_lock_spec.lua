local t = require("fox.lib.foxnvim.test")
t.describe("Caps Lock sysfs through polling and native notifications", function()
	t.it("warns after the default delay, once per activation, and resets on off/focus loss", function()
		local linux, shared = require("fox.core.os.linux"), require("fox.core.os.shared")
		assert(shared.is_linux, "This integration checks the Linux keyboard backend")
		local root, old_root = vim.fn.tempname(), linux.led_root
		vim.fn.mkdir(root .. "/input1::capslock", "p")
		local path = root .. "/input1::capslock/brightness"
		vim.fn.writefile({ "1" }, path)
		linux.led_root = root
		local caps = require("plugins.fox.editor.caps_lock")
		require("lazy").load({ plugins = { "fox_notify", "fox_caps_lock" } })
		local notify = require("fox.core.notify")
		local function count()
			local n = 0
			for _, record in ipairs(notify.history()) do
				if record.title[1] == caps.settings.notification_title then
					n = n + 1
				end
			end
			return n
		end
		local ok, err = xpcall(function()
			caps.reset_state()
			vim.api.nvim_exec_autocmds("FocusGained", {})
			t.expect(caps.get_state().polling).toBe(true)
			local initial, start = count(), (vim.uv or vim.loop).now()
			assert(
				vim.wait(4500, function()
					return count() > initial
				end, 20),
				"Caps Lock toast never appeared"
			)
			t.expect((vim.uv or vim.loop).now() - start >= caps.settings.delay_ms).toBe(true)
			t.expect(count()).toBe(initial + 1)
			vim.wait(600, function()
				return false
			end, 20)
			t.expect(count()).toBe(initial + 1)
			vim.fn.writefile({ "0" }, path)
			assert(vim.wait(1000, function()
				return caps.get_state().caps_on_since == nil
			end, 10))
			t.expect(caps.get_state().notified).toBe(false)
			vim.fn.writefile({ "1" }, path)
			assert(
				vim.wait(1000, function()
					return caps.get_state().caps_on_since ~= nil
				end, 10),
				vim.inspect(caps.get_state())
			)
			t.expect(caps.get_state().notified).toBe(false)
			vim.api.nvim_exec_autocmds("FocusLost", {})
			t.expect(caps.get_state().caps_on_since).toBe(nil)
		end, debug.traceback)
		linux.led_root = old_root
		caps.reset_state()
		vim.api.nvim_exec_autocmds("FocusGained", {})
		notify.dismiss_all()
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
