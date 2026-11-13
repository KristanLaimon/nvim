local t = require("fox.lib.foxnvim.test")
require("lazy").load({ plugins = { "nvim-dap" } })
local ansi = require("fox.dap.ansi")

t.describe("native DAP ANSI integration", function()
	t.it("colorizes real REPL chunked output and resets on clear", function()
		local repl = require("dap.repl")
		repl.open()
		repl.clear()
		repl.append("\27[38;2;", nil, { newline = false })
		vim.wait(30)
		repl.append("255;0;0márbol", nil, { newline = false })
		vim.wait(30)
		repl.append(" rojo\27[0m normal", nil, { newline = false })
		vim.wait(30)
		local buf
		for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
			if vim.bo[candidate].filetype == "dap-repl" then
				buf = candidate
			end
		end
		t.expect(buf).toBeDefined()
		t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("árbol rojo normal")
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, {})).toBe(1)
		repl.clear()
		repl.append("plain", nil, { newline = false })
		vim.wait(30)
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, {})).toBe(0)
		repl.close()
	end)
	t.it("attaches to UI consoles and buffers that already exist at setup", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].filetype = "dapui_console"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\27[32mconsole\27[0m" })
		ansi.setup()
		vim.bo[buf].modifiable = false
		vim.wait(30)
		t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "console" })
		t.expect(vim.bo[buf].modifiable).toBe(false)
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, {})).toBe(1)
		t.expect(require("lazy.core.config").plugins["baleia.nvim"]).toBeNil()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
