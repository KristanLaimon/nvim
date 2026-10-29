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

t.describe("LSP executable case fallback", function()
	local root, original_path
	local function executable(directory, name, permissions)
		local filename = directory .. "/" .. name
		vim.fn.writefile({ "#!/bin/sh", "exit 0" }, filename)
		vim.fn.setfperm(filename, permissions or "rwxr-xr-x")
		return filename
	end
	t.beforeEach(function()
		root, original_path = vim.fn.tempname(), vim.env.PATH
		vim.fn.mkdir(root .. "/first", "p")
		vim.fn.mkdir(root .. "/second", "p")
		vim.env.PATH = root .. "/first:" .. root .. "/second"
	end)
	t.afterEach(function()
		vim.env.PATH = original_path
		vim.fn.delete(root, "rf")
	end)
	t.it("finds mixed case, preserves arguments and leaves the input unchanged", function()
		local expected = executable(root .. "/first", "FoxServer")
		local cmd = { "foxserver", "--stdio", "CaseSensitiveArgument" }
		t.expect(m.resolve_command(cmd)).toEqual({ expected, "--stdio", "CaseSensitiveArgument" })
		t.expect(cmd[1]).toBe("foxserver")
	end)
	t.it("prefers exact names even later in PATH", function()
		executable(root .. "/first", "FoxServer")
		executable(root .. "/second", "foxserver")
		local cmd = { "foxserver" }
		t.expect(m.resolve_command(cmd)).toBe(cmd)
	end)
	t.it("uses PATH order for case fallback and skips nonexistent directories", function()
		vim.env.PATH = root .. "/missing:" .. vim.env.PATH
		local expected = executable(root .. "/first", "FoxServer")
		executable(root .. "/second", "FOXSERVER")
		t.expect(m.resolve_command({ "foxserver" })[1]).toBe(expected)
	end)
	t.it("resolves explicit paths only inside their directory", function()
		local expected = executable(root .. "/first", "FoxServer")
		t.expect(m.resolve_command({ root .. "/first/foxserver" })[1]).toBe(expected)
		local cmd = { root .. "/second/foxserver" }
		t.expect(m.resolve_command(cmd)).toBe(cmd)
	end)
	t.it("rejects ambiguous case variants", function()
		executable(root .. "/first", "FoxServer")
		executable(root .. "/first", "FOXSERVER")
		local cmd = { "foxserver" }
		t.expect(m.resolve_command(cmd)).toBe(cmd)
	end)
	t.it("does not launch non-executable matches or rewrite missing commands", function()
		executable(root .. "/first", "FoxServer", "rw-r--r--")
		local cmd = { "foxserver" }
		t.expect(m.resolve_command(cmd)).toBe(cmd)
	end)
	t.it("keeps custom launchers and absent commands unchanged", function()
		local launcher = function() end
		t.expect(m.resolve_command(launcher)).toBe(launcher)
		t.expect(m.resolve_command(nil)).toBe(nil)
	end)
end)
