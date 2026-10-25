local t = require("fox.lib.foxnvim.test")
local m = require("fox.git.inline_blame")
t.describe("Real Git inline blame", function()
	local root, buf
	local function git(args, cwd)
		local argv = { "git", "-C", cwd or root }
		vim.list_extend(argv, args)
		local result = vim.system(argv, { text = true }):wait()
		assert(result.code == 0, result.stderr)
		return vim.trim(result.stdout or "")
	end
	t.beforeEach(function()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		git({ "init", "-q" })
		git({ "config", "user.email", "test@example.invalid" })
		git({ "config", "user.name", "FOX Test" })
		vim.fn.writefile({ "first", "second" }, root .. "/space name.lua")
		git({ "add", "." })
		git({ "commit", "-qm", "Initial test" })
		vim.cmd.edit(root .. "/space name.lua")
		buf = vim.api.nvim_get_current_buf()
		require("lazy").load({ plugins = { "fox_inline_blame" } })
		m.setup({ enabled = true, delay = 1, date_format = "%r", message_template = "  <author>, <date> • <summary>" })
	end)
	t.afterEach(function()
		m.set_enabled(false)
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		vim.wait(200, function()
			return false
		end)
		vim.fn.delete(root, "rf")
	end)
	local function fetch(b, row)
		local done, info = false, nil
		m.fetch(b, row, function(value)
			info = value
			done = true
		end)
		t.expect(vim.wait(3000, function()
			return done
		end, 10)).toBe(true)
		return info
	end
	t.it("blames committed and unsaved text and renders/clears real extmarks", function()
		local info = fetch(buf, 1)
		t.expect(info.author).toBe("FOX Test")
		t.expect(info.sha).toBe(git({ "rev-parse", "HEAD" }))
		m.refresh(buf)
		t.expect(vim.wait(3000, function()
			return #vim.api.nvim_buf_get_extmarks(buf, m.ns, 0, -1, {}) > 0
		end, 10)).toBe(true)
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "unsaved" })
		info = fetch(buf, 1)
		t.expect(info.sha:match("^0+$") ~= nil).toBe(true)
		m.refresh(buf)
		t.expect(vim.wait(3000, function()
			local marks = vim.api.nvim_buf_get_extmarks(buf, m.ns, 0, -1, { details = true })
			return #marks > 0 and marks[1][4].virt_text[1][1]:find("Not Committed", 1, true) ~= nil
		end, 10)).toBe(true)
		vim.cmd("GitBlameDisable")
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, m.ns, 0, -1, {})).toBe(0)
	end)
	t.it("uses the nearest nested repository and handles files without a commit", function()
		vim.fn.mkdir(root .. "/nested", "p")
		git({ "init", "-q" }, root .. "/nested")
		local file = root .. "/nested/new.lua"
		vim.fn.writefile({ "new" }, file)
		local b = vim.fn.bufadd(file)
		vim.fn.bufload(b)
		local info = fetch(b, 1)
		t.expect(info.relative).toBe("new.lua")
		t.expect(info.sha:match("^0+$") ~= nil).toBe(true)
		vim.wait(200, function()
			return false
		end)
		vim.api.nvim_buf_delete(b, { force = true })
	end)
	t.it("hides ignored files and distinguishes process failures from new lines", function()
		git({ "config", "core.excludesfile", root .. "/ignore" })
		vim.fn.writefile({ "ignored.lua" }, root .. "/ignore")
		vim.fn.writefile({ "secret" }, root .. "/ignored.lua")
		local b = vim.fn.bufadd(root .. "/ignored.lua")
		vim.fn.bufload(b)
		t.expect(fetch(b, 1)).toBe(nil)
		vim.api.nvim_buf_delete(b, { force = true })
	end)
	t.it("copies SHA/URL using the clicked repository without opening a browser", function()
		git({ "remote", "add", "origin", "git@github.com:fox/example.git" })
		local setreg = vim.fn.setreg
		local copied
		vim.fn.setreg = function(_, value)
			copied = value
		end
		m.action("sha", true, { range = 0 })
		t.expect(vim.wait(3000, function()
			return copied ~= nil
		end, 10)).toBe(true)
		t.expect(copied).toBe(git({ "rev-parse", "HEAD" }))
		copied = nil
		m.action("file", true, { range = 2, line1 = 1, line2 = 2 })
		t.expect(vim.wait(3000, function()
			return copied ~= nil
		end, 10)).toBe(true)
		vim.fn.setreg = setreg
		t.expect(copied).toContain("/space%20name.lua#L1-L2")
	end)
end)
