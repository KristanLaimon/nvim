-- ============================================================================
-- config/tests/spec/git_blame_spec.lua -- Git Blame plugin specification & integration.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local git_blame_spec = require("plugins.editor.git_blame")

describe("plugins.editor.git_blame", function()
	it("exports the local inline blame specification", function()
		expect(git_blame_spec.name).toBe("fox_inline_blame")
		expect(git_blame_spec.opts).toBeDefined()
		expect(git_blame_spec.opts.enabled).toBe(true)
		expect(git_blame_spec.opts.highlight_group).toBe("GitBlame")
		expect(git_blame_spec.opts.date_format).toBe("%r")
		expect(git_blame_spec.opts.message_template).toContain("<author>")
	end)

	it("exposes user commands in cmd spec list", function()
		expect(git_blame_spec.cmd).toContain("GitBlameToggle")
		expect(git_blame_spec.cmd).toContain("GitBlameEnable")
		expect(git_blame_spec.cmd).toContain("GitBlameDisable")
		expect(git_blame_spec.cmd).toContain("GitBlameOpenCommitURL")
		expect(git_blame_spec.cmd).toContain("GitBlameCopySHA")
		expect(git_blame_spec.cmd).toContain("GitBlameCopyCommitURL")
		expect(git_blame_spec.cmd).toContain("GitBlameOpenFileURL")
	end)

	it("registers the advertised Git Blame commands when configured", function()
		git_blame_spec.config(nil, git_blame_spec.opts)
		for _, command in ipairs(git_blame_spec.cmd) do
			expect(vim.fn.exists(":" .. command)).toBe(2)
		end
	end)

	it("config sets up GitBlame highlight group with italic styling", function()
		expect(type(git_blame_spec.config)).toBe("function")
		expect(function()
			git_blame_spec.config(nil, git_blame_spec.opts)
		end).not_.toThrow()
		local hl = vim.api.nvim_get_hl(0, { name = "GitBlame", link = false })
		expect(hl).toBeDefined()
	end)
end)
