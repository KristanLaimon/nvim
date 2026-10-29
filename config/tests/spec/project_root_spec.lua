local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local history = require("fox.projects.history")

describe("local ProjectRoot command", function()
	local root, buf, original_buf, cwd, file, create_command, keymap, picker, commands, clients, find
	t.beforeEach(function()
		root, original_buf, cwd, file = vim.fn.tempname(), vim.api.nvim_get_current_buf(), vim.fn.getcwd(), history.file
		vim.fn.mkdir(root .. "/app/src", "p")
		vim.fn.writefile({}, root .. "/app/package.json")
		history.file = root .. "/history"
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, root .. "/app/src/file.lua")
		vim.api.nvim_set_current_buf(buf)
		create_command, keymap, picker, clients =
			vim.api.nvim_create_user_command, vim.keymap.set, _G.OpenRecentProjects, vim.lsp.get_clients
		find = vim.fs.find
		commands = {}
		vim.api.nvim_create_user_command = function(name, callback)
			commands[name] = callback
		end
		vim.keymap.set = function() end
		dofile(vim.fn.stdpath("config") .. "/lua/plugins/editor/project.lua").config()
	end)
	t.afterEach(function()
		vim.api.nvim_create_user_command, vim.keymap.set, _G.OpenRecentProjects, vim.lsp.get_clients =
			create_command, keymap, picker, clients
		vim.fs.find = find
		history.file = file
		vim.api.nvim_set_current_dir(cwd)
		vim.api.nvim_set_current_buf(original_buf)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(root, "rf")
	end)

	it("keeps cwd unchanged until requested, then finds and remembers the nearest root", function()
		expect(vim.fn.getcwd()).toBe(cwd)
		commands.ProjectRoot()
		assert(
			require("fox.core.path").equals(vim.fn.getcwd(), root .. "/app"),
			vim.fn.getcwd() .. " != " .. root .. "/app"
		)
		expect(history.list()).toEqual({ require("fox.core.path").normalize(root .. "/app") })
		expect(type(commands.RecentProjects)).toBe("function")
		expect(type(_G.OpenRecentProjects)).toBe("function")
	end)

	it("falls back to the attached LSP root when no marker exists", function()
		vim.fn.delete(root .. "/app/package.json")
		-- Parent directories may themselves contain project markers.
		vim.fs.find = function()
			return {}
		end
		vim.lsp.get_clients = function()
			return { { config = { root_dir = root .. "/app" } } }
		end
		commands.ProjectRoot()
		assert(
			require("fox.core.path").equals(vim.fn.getcwd(), root .. "/app"),
			vim.fn.getcwd() .. " != " .. root .. "/app"
		)
	end)
end)
