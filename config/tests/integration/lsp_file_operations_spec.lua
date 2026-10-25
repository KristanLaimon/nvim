local t = require("fox.lib.foxnvim.test")
require("lazy").load({ plugins = { "neo-tree.nvim" } })
t.describe("LSP file operation transport", function()
	t.it("applies a willRename edit and sends didRename over stdio", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		local old, new, log = dir .. "/a.ts", dir .. "/b.ts", dir .. "/notifications.json"
		vim.fn.writefile({ "old value" }, old)
		local buf = vim.fn.bufadd(old)
		vim.fn.bufload(buf)
		local id = vim.lsp.start(
			{
				name = "fox_file_operation_fixture",
				root_dir = dir,
				cmd = { "python3", vim.fn.stdpath("config") .. "/config/tests/fixtures/file_operations_server.py", log },
			},
			{ bufnr = buf }
		)
		t.expect(vim.wait(3000, function()
			local c = vim.lsp.get_client_by_id(id)
			return c and c.initialized
		end, 10)).toBe(true)
		local events = require("neo-tree.events")
		local args = { source = old, destination = new }
		t.expect(events.fire_event(events.BEFORE_FILE_RENAME, args).handled).toBe(true)
		events.fire_event(events.FILE_RENAMED, args)
		t.expect(vim.wait(2000, function()
			return vim.fn.filereadable(log) == 1
		end, 10)).toBe(true)
		t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]).toBe("new value")
		t.expect(vim.api.nvim_buf_get_name(buf)).toBe(new)
		t.expect(vim.fn.readfile(new)[1]).toBe("old value")
		local params = vim.json.decode(table.concat(vim.fn.readfile(log)))
		t.expect(params.files[1].newUri).toBe(vim.uri_from_fname(new))
		vim.lsp.get_client_by_id(id):stop(true)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(dir, "rf")
	end)
end)
