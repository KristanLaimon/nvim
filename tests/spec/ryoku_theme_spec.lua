local t = require("fox.lib.foxnvim.test")
local ryoku = getmetatable(require("plugins.fox.ui.ryoku_theme")).__index

t.describe("Ryoku palette", function()
	t.it("maps material surfaces and terminal colors", function()
		local c = ryoku.translate({
			background = "#19120d",
			foreground = "#f0dfd6",
			primary = "#ffb782",
			surfaceContainerHigh = "#312822",
			color1 = "#ffb4ab",
		})
		t.expect(c.mode).toBe("dark")
		t.expect(c.accent).toBe("#ffb782")
		t.expect(c.lighter_background).toBe("#312822")
		t.expect(c.red).toBe("#ffb4ab")
	end)
	t.it("rejects incomplete or invalid palettes", function()
		t.expect(ryoku.translate({ background = "invalid", foreground = "#ffffff" })).toBe(nil)
		t.expect(ryoku.translate({})).toBe(nil)
	end)
	t.it("recognizes light palettes", function()
		t.expect(ryoku.translate({ background = "#fafafa", foreground = "#202020" }).mode).toBe("light")
	end)
	t.it("accepts terminal-only palettes and prefers explicit material colors", function()
		local raw = { color0 = "#101010", color7 = "#eeeeee", color4 = "#123456" }
		local c = ryoku.translate(raw)
		t.expect(c.background).toBe(raw.color0)
		t.expect(c.foreground).toBe(raw.color7)
		t.expect(c.accent).toBe(raw.color4)
		raw.background, raw.foreground = "#fafafa", "#202020"
		t.expect(ryoku.translate(raw).mode).toBe("light")
		t.expect(ryoku.translate({ color0 = "#101010", color7 = "invalid" })).toBe(nil)
	end)
end)

t.describe("Ryoku palette refresh", function()
	local file, saved, calls, enabled, succeeds
	t.beforeEach(function()
		file = vim.fn.tempname()
		saved =
			{ file = ryoku.settings.palette_file, stamp = ryoku._stamp, apply = ryoku.apply, sync = ryoku.is_sync_enabled }
		ryoku.settings.palette_file, ryoku._stamp = file, nil
		calls, enabled, succeeds = 0, true, true
		ryoku.is_sync_enabled = function()
			return enabled
		end
		ryoku.apply = function()
			calls = calls + 1
			return succeeds
		end
	end)
	t.afterEach(function()
		ryoku.settings.palette_file, ryoku._stamp = saved.file, saved.stamp
		ryoku.apply, ryoku.is_sync_enabled = saved.apply, saved.sync
		vim.fn.delete(file)
		vim.fn.delete(file .. ".new")
	end)
	t.it("skips unchanged files and detects atomic replacements with the same mtime", function()
		vim.fn.writefile({ "first" }, file)
		ryoku.refresh()
		ryoku.refresh()
		t.expect(calls).toBe(1)
		local uv = vim.uv or vim.loop
		local stat = uv.fs_stat(file)
		vim.fn.writefile({ "other" }, file .. ".new")
		uv.fs_utime(file .. ".new", stat.atime.sec, stat.mtime.sec + stat.mtime.nsec / 1e9)
		assert(uv.fs_rename(file .. ".new", file))
		ryoku.refresh()
		t.expect(calls).toBe(2)
	end)
	t.it("waits for a missing palette and retries failed applications", function()
		ryoku.refresh()
		t.expect(calls).toBe(0)
		vim.fn.writefile({ "palette" }, file)
		succeeds = false
		ryoku.refresh()
		succeeds = true
		ryoku.refresh()
		ryoku.refresh()
		t.expect(calls).toBe(2)
	end)
	t.it("does not apply desktop colors when sync is disabled", function()
		vim.fn.writefile({ "palette" }, file)
		enabled = false
		ryoku.refresh()
		t.expect(calls).toBe(0)
	end)
end)
