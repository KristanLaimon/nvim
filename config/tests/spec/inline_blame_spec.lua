local t = require("fox.lib.foxnvim.test")
local m = require("fox.git.inline_blame")
t.describe("Native inline blame", function()
	t.it("parses metadata, original lines, unicode authors and relative dates", function()
		local info = m.parse(
			string.rep("a", 40)
				.. " 7 10 1\nauthor José\nauthor-time 100\nsummary Initial work\nfilename folder/a.lua\n\ttext"
		)
		t.expect(info.author).toBe("José")
		t.expect(info.original_line).toBe(7)
		t.expect(info.time).toBe(100)
		t.expect(m.relative_date(100, 220)).toBe("2 minutes ago")
		t.expect(m.parse("fatal: not a repository")).toBe(nil)
	end)
	t.it("builds escaped forge URLs and strips transport credentials", function()
		local info = { sha = string.rep("a", 40), relative = "folder/space ü.lua" }
		local url = m.url("git@github.com:user/repo.git", info, "file", 7, 9)
		t.expect(url).toBe("https://github.com/user/repo/blob/" .. info.sha .. "/folder/space%20%C3%BC.lua#L7-L9")
		t.expect(m.url("https://token@gitlab.com/team/repo.git", info, "commit", 1))
			.toBe("https://gitlab.com/team/repo/-/commit/" .. info.sha)
		t.expect(m.url("ssh://git@bitbucket.org/team/repo.git", info, "file", 1)).toContain("#lines-1")
		t.expect(m.repo_url("git@ssh.dev.azure.com:v3/org/project/repo"))
			.toBe("https://dev.azure.com/org/project/_git/repo")
		t.expect(m.repo_url("/local/repo")).toBe(nil)
	end)
	t.it("rejects uncommitted commit URLs", function()
		local info = { sha = string.rep("0", 40), relative = "file" }
		t.expect(m.url("https://github.com/u/r", info, "commit", 1)).toBe(nil)
		t.expect(m.url("https://github.com/u/r", info, "file", 1, 1, "main")).toContain("/blob/main/file#L1")
	end)
	t.it("discards responses after edits or explicit cancellation", function()
		local b = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(b, vim.fn.tempname() .. ".lua")
		local system, done = vim.system, nil
		vim.system = function(_, _, callback)
			done = callback
			return { kill = function() end }
		end
		local called = false
		m.fetch(b, 1, function()
			called = true
		end)
		vim.api.nvim_buf_set_lines(b, 0, -1, false, { "changed" })
		done({ code = 0, stdout = "" })
		vim.wait(10, function()
			return false
		end)
		t.expect(called).toBe(false)
		local state = m.fetch(b, 1, function()
			called = true
		end)
		state.cancelled = true
		done({ code = 0, stdout = "" })
		vim.wait(10, function()
			return false
		end)
		vim.system = system
		vim.api.nvim_buf_delete(b, { force = true })
		t.expect(called).toBe(false)
	end)
end)
