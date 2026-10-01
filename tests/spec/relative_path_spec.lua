-- ============================================================================
-- tests/spec/relative_path_spec.lua -- Relative path copier tests.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local rp = require("plugins.fox.editor.relative_path")

describe("plugins.fox.editor.relative_path", function()
	local test_buf

	beforeEach(function()
		rp.setup()
		test_buf = vim.api.nvim_create_buf(true, false)
	end)

	afterEach(function()
		if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
			pcall(vim.api.nvim_buf_delete, test_buf, { force = true })
		end
	end)

	it("returns relative path from current working directory", function()
		local cwd = vim.fn.getcwd()
		local fake_path = cwd .. "/lua/fake/test_module.lua"
		vim.api.nvim_buf_set_name(test_buf, fake_path)
		vim.api.nvim_set_current_buf(test_buf)

		local rel, full = rp.get_active_relative_path()
		expect(rel).toBe("lua/fake/test_module.lua")
		expect(full).toBe(fake_path)
	end)

	it("copies relative path to system registers + and *", function()
		local cwd = vim.fn.getcwd()
		local fake_path = cwd .. "/docs/sample/file.txt"
		vim.api.nvim_buf_set_name(test_buf, fake_path)
		vim.api.nvim_set_current_buf(test_buf)

		local copied = rp.copy_relative_path()
		expect(copied).toBe("docs/sample/file.txt")
		expect(vim.fn.getreg("+")).toBe("docs/sample/file.txt")
		expect(vim.fn.getreg("*")).toBe("docs/sample/file.txt")
	end)

	it("prioritizes currently focused window when multiple buffers exist", function()
		local cwd = vim.fn.getcwd()
		local buf1 = vim.api.nvim_create_buf(true, false)
		local buf2 = vim.api.nvim_create_buf(true, false)

		vim.api.nvim_buf_set_name(buf1, cwd .. "/first.lua")
		vim.api.nvim_buf_set_name(buf2, cwd .. "/second.lua")

		vim.api.nvim_set_current_buf(buf2)
		local rel = rp.get_active_relative_path()
		expect(rel).toBe("second.lua")

		vim.api.nvim_set_current_buf(buf1)
		rel = rp.get_active_relative_path()
		expect(rel).toBe("first.lua")

		pcall(vim.api.nvim_buf_delete, buf1, { force = true })
		pcall(vim.api.nvim_buf_delete, buf2, { force = true })
	end)

	it("handles non-file buffers gracefully", function()
		local nofile_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[nofile_buf].buftype = "nofile"
		vim.api.nvim_set_current_buf(nofile_buf)

		-- No other real file buffers
		local old_bufs = vim.api.nvim_list_bufs()
		for _, b in ipairs(old_bufs) do
			if b ~= nofile_buf and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= "" then
				pcall(vim.api.nvim_buf_delete, b, { force = true })
			end
		end

		local rel = rp.get_active_relative_path()
		expect(rel == nil or type(rel) == "string").toBe(true)

		pcall(vim.api.nvim_buf_delete, nofile_buf, { force = true })
	end)
end)
