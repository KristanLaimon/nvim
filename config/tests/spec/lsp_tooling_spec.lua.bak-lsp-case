local t = require("fox.lib.foxnvim.test")
local m = require("fox.lsp.tooling")
t.describe("Local LSP tooling", function()
	t.it("maps every managed LSP from its owning metadata", function()
		local packages = m.packages()
		t.expect(packages.lua_ls).toBe("lua-language-server")
		t.expect(packages.yamlls).toBe("yaml-language-server")
		t.expect(packages.stylua).toBe(nil)
		for name, tool in pairs(require("fox.core.installer").tools) do
			t.expect(require("fox.core.installer").get_mason_package_name(name)).toBe(tool.mason)
		end
	end)
	t.it("installs only explicit choices and preserves versions", function()
		local cmd = vim.api.nvim_cmd
		local received
		vim.api.nvim_cmd = function(value)
			received = value
		end
		m.install({ "lua_ls@3.15" })
		vim.api.nvim_cmd = cmd
		t.expect(received.args).toEqual({ "lua-language-server@3.15" })
	end)
	t.it("cancels selection without installing anything", function()
		local select, cmd, ft = vim.ui.select, vim.api.nvim_cmd, vim.bo.filetype
		local called = false
		vim.bo.filetype = "lua"
		vim.ui.select = function(_, _, callback)
			callback(nil)
		end
		vim.api.nvim_cmd = function()
			called = true
		end
		m.install({}, { lua_ls = { filetypes = { "lua" } } })
		vim.ui.select, vim.api.nvim_cmd, vim.bo.filetype = select, cmd, ft
		t.expect(called).toBe(false)
	end)
end)
