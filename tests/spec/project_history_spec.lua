local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local history = require("fox.projects.history")
local uv = vim.uv or vim.loop

describe("local project history", function()
	local root, original, open, rename
	t.beforeEach(function()
		root, original, open, rename = vim.fn.tempname(), history.file, io.open, uv.fs_rename
		vim.fn.mkdir(root, "p")
		history.file = root .. "/project_history"
	end)
	t.afterEach(function()
		rawset(io, "open", open)
		uv.fs_rename = rename
		history.file = original
		vim.fn.delete(root, "rf")
	end)

	it("reads the existing format without checking local or WSL project directories", function()
		vim.fn.writefile({ "C:/work/old", "//wsl.localhost/Ubuntu/home/me/app", "/missing/project" }, history.file)
		expect(history.list()).toEqual({ "C:/work/old", "//wsl.localhost/Ubuntu/home/me/app", "/missing/project" })
	end)

	it("creates a missing history and moves the selected project to the newest position", function()
		expect(history.list()).toEqual({})
		expect(history.remember("/work/one")).toBe(true)
		expect(history.remember("/work/two")).toBe(true)
		expect(history.remember("/work/one/")).toBe(true)
		expect(history.list()).toEqual({ "/work/two", "/work/one" })
	end)

	it("persists rename and removal without touching unrelated or unavailable paths", function()
		vim.fn.writefile({ "/old", "//wsl.localhost/Ubuntu/home/me/project", "/other" }, history.file)
		expect(history.rename("/old", "/new")).toBe(true)
		expect(history.remove("/other")).toBe(true)
		expect(history.list()).toEqual({ "/new", "//wsl.localhost/Ubuntu/home/me/project" })
	end)

	it("reloads external changes instead of keeping stale process-local lists", function()
		assert(history.remember("/one"))
		vim.fn.writefile({ "/two" }, history.file)
		expect(history.list()).toEqual({ "/two" })
	end)

	it("rejects paths that cannot be represented in the history format", function()
		vim.fn.writefile({ "/kept" }, history.file)
		expect(history.remember("/bad\npath")).toBe(false)
		expect(history.rename("/kept", "")).toBe(false)
		expect(history.remove(nil)).toBe(false)
		expect(history.list()).toEqual({ "/kept" })
	end)

	it("never overwrites unreadable history with an empty list", function()
		vim.fn.writefile({ "/kept" }, history.file)
		rawset(io, "open", function(file, mode)
			if file == history.file and mode == "rb" then
				return nil, "read denied"
			end
			return open(file, mode)
		end)
		local ok, err = history.remember("/new")
		expect(ok).toBe(false)
		expect(err).toBe("read denied")
		rawset(io, "open", open)
		expect(history.list()).toEqual({ "/kept" })
	end)

	it("keeps the original file intact when replacing it fails", function()
		vim.fn.writefile({ "/kept" }, history.file)
		uv.fs_rename = function()
			return nil, "rename denied"
		end
		local ok, err = history.remember("/new")
		expect(ok).toBe(false)
		expect(err).toBe("rename denied")
		expect(history.list()).toEqual({ "/kept" })
		expect(vim.fn.glob(history.file .. ".*.tmp")).toBe("")
	end)
end)
