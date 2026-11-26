local t = require("fox.lib.foxnvim.test")
local sessions = require("fox.terminal.agent_sessions")

t.describe("agent session persistence", function()
	t.it("keeps exact IDs isolated by project and compacts slots", function()
		local original, dir = sessions.file, vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		sessions.file = function(root)
			return dir .. "/" .. vim.fn.sha256(root) .. ".json"
		end
		local data = { { slot = 5, agent = "claude", id = "claude-id" }, { slot = 1, agent = "codex", id = "codex-id" } }
		local ok, err = pcall(function()
			assert(sessions.save("/project/a", data))
			t.expect(sessions.load("/project/b")).toEqual({})
			local compacted = sessions.compact(sessions.load("/project/a"))
			t.expect(compacted)
				.toEqual({ { slot = 1, agent = "codex", id = "codex-id" }, { slot = 2, agent = "claude", id = "claude-id" } })
			t.expect(data[1].slot).toBe(5)
			t.expect(sessions.command(compacted[1])).toEqual({ "codex", "resume", "codex-id" })
			t.expect(sessions.command({ slot = 1, agent = "agy", id = "x;rm" })).toBeNil()
			t.expect(sessions.command({ slot = 1, agent = "codex", id = "--help" })).toBeNil()
			t.expect(sessions.save("/project/a", { data[1], data[1] })).toBe(false)
			t.expect(#sessions.load("/project/a")).toBe(2)
		end)
		sessions.file = original
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
end)
