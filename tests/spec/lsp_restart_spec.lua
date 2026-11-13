local t = require("fox.lib.foxnvim.test")
local restart = require("fox.lsp.restart").restart

t.describe("Restart LSP for current file", function()
	local saved, clients, commands, notifications, native

	t.beforeEach(function()
		saved = { get_clients = vim.lsp.get_clients, exists = vim.fn.exists, cmd = vim.cmd, notify = vim.notify }
		clients = { { name = "lua_ls" } }
		commands, notifications = {}, {}
		native = true
		vim.lsp.get_clients = function(filter)
			assert(filter.bufnr == vim.api.nvim_get_current_buf())
			return clients
		end
		vim.fn.exists = function(name)
			assert(name == ":lsp")
			return native and 2 or 0
		end
		vim.cmd = setmetatable({
			LspRestart = function(name)
				table.insert(commands, "LspRestart " .. name)
			end,
		}, {
			__call = function(_, command)
				table.insert(commands, command)
			end,
		})
		vim.notify = function(message)
			table.insert(notifications, message)
		end
	end)

	t.afterEach(function()
		vim.lsp.get_clients, vim.fn.exists = saved.get_clients, saved.exists
		vim.cmd, vim.notify = saved.cmd, saved.notify
	end)

	t.it("uses native buffer-scoped restart when available", function()
		restart()
		t.expect(commands).toEqual({ "lsp restart" })
	end)

	t.it("restarts only attached server names once on older Neovim", function()
		native = false
		clients = { { name = "tsgo" }, { name = "eslint" }, { name = "tsgo" } }
		restart()
		t.expect(commands).toEqual({ "LspRestart tsgo", "LspRestart eslint" })
	end)

	t.it("reports files without an attached server without restarting anything", function()
		clients = {}
		restart()
		t.expect(commands).toEqual({})
		t.expect(notifications).toEqual({ "No LSP clients attached to the current file" })
	end)

	t.it("is discoverable in the command palette", function()
		local commands_list = require("plugins.fox.tools.command_palette").commands
		local found = false
		for _, command in ipairs(commands_list) do
			if command.cmd == "FoxLspRestart" then
				found = command.category == "LSP"
			end
		end
		t.expect(found).toBe(true)
	end)
end)
