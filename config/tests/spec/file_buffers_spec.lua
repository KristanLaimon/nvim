local t = require("fox.lib.foxnvim.test")
t.describe("Filesystem buffer reconciliation", function()
	local buffers, root
	t.beforeEach(function()
		buffers = {}
		root = vim.fn.tempname()
	end)
	t.afterEach(function()
		for _, b in ipairs(buffers) do
			pcall(vim.api.nvim_buf_delete, b, { force = true })
		end
	end)
	local function buffer(name, text)
		local b = vim.api.nvim_create_buf(true, false)
		buffers[#buffers + 1] = b
		vim.api.nvim_buf_set_name(b, name)
		if text then
			vim.api.nvim_buf_set_lines(b, 0, -1, false, { text })
		end
		return b
	end
	t.it("renames directory children while preserving unsaved text and undo", function()
		local b = buffer(root .. "/old/a.lua", "unsaved")
		require("fox.core.buffer_rename").update_buffers_path(root .. "/old", root .. "/new")
		t.expect(vim.api.nvim_buf_get_name(b)).toBe(root .. "/new/a.lua")
		t.expect(vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]).toBe("unsaved")
		t.expect(vim.bo[b].modified).toBe(true)
	end)
	t.it("preserves both buffers when the destination has changes", function()
		local source = buffer(root .. "/a", "source")
		local dest = buffer(root .. "/b", "destination")
		require("fox.core.buffer_rename").update_buffers_path(root .. "/a", root .. "/b")
		t.expect(vim.api.nvim_buf_get_lines(dest, 0, -1, false)[1]).toBe("destination")
		t.expect(vim.api.nvim_buf_get_lines(source, 0, -1, false)[1]).toBe("source")
	end)
	t.it("closes clean deleted children, retains dirty ones and unrelated siblings", function()
		local clean = buffer(root .. "/dir/clean")
		local dirty = buffer(root .. "/dir/dirty", "changes")
		local sibling = buffer(root .. "/directory/a")
		require("fox.core.file_buffers").deleted(root .. "/dir")
		t.expect(vim.api.nvim_buf_is_valid(clean)).toBe(false)
		t.expect(vim.api.nvim_buf_is_valid(dirty)).toBe(true)
		t.expect(vim.api.nvim_buf_is_valid(sibling)).toBe(true)
	end)
end)
