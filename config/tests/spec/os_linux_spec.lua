local t = require("fox.lib.foxnvim.test")
local linux = require("fox.core.os.linux")
if vim.fn.has("linux") ~= 1 then
	return
end

t.describe("Linux Caps Lock detection", function()
	local root, saved
	t.beforeEach(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		saved = linux.led_root
		linux.led_root = root
	end)
	t.afterEach(function()
		linux.led_root = saved
		vim.fn.delete(root, "rf")
	end)
	local function led(name, value)
		vim.fn.mkdir(root .. "/" .. name, "p")
		vim.fn.writefile({ value }, root .. "/" .. name .. "/brightness")
	end
	t.it("reads live Caps Lock changes and ignores Num/Scroll Lock", function()
		led("input1::capslock", "0")
		led("input1::numlock", "1")
		led("input1::scrolllock", "1")
		t.expect(linux.is_caps_lock_on()).toBe(false)
		led("input1::capslock", "1")
		t.expect(linux.is_caps_lock_on()).toBe(true)
		led("input1::capslock", "0")
		t.expect(linux.is_caps_lock_on()).toBe(false)
	end)
	t.it("handles multiple keyboards, hotplug and vanished brightness files", function()
		led("input1::capslock", "0")
		led("input3::capslock", "1")
		t.expect(linux.is_caps_lock_on()).toBe(true)
		vim.fn.delete(root .. "/input3::capslock/brightness")
		t.expect(linux.is_caps_lock_on()).toBe(false)
		led("input7::capslock", "1")
		t.expect(linux.is_caps_lock_on()).toBe(true)
	end)
	t.it("tolerates absent sysfs and invalid data and dispatches through the OS interface", function()
		led("input1::capslock", "invalid")
		t.expect(linux.is_caps_lock_on()).toBe(false)
		led("input1::capslock", "1")
		local shared = require("fox.core.os.shared")
		local windows, is_linux = shared.is_windows, shared.is_linux
		shared.is_windows, shared.is_linux = false, true
		local ok, value = pcall(shared.is_caps_lock_on)
		shared.is_windows, shared.is_linux = windows, is_linux
		assert(ok, value)
		t.expect(value).toBe(true)
		linux.led_root = root .. "/missing"
		t.expect(linux.is_caps_lock_on()).toBe(false)
	end)
end)
