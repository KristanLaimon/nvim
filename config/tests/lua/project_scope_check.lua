-- Run with nvim --clean --headless -l config/tests/lua/project_scope_check.lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
vim.opt.runtimepath:prepend(root)

local injector = require("plugins.fox.tools.type_injector_lua")
local config_root = vim.fn.stdpath("config")
local project = vim.fn.tempname()
local opted_in = project .. "/neovim-plugin"
local core = {
	load_project_types = function(dir)
		return { lua = dir == opted_in and { "vim_nvim" } or {} }
	end,
	resolve_schema_dir = function() end,
	scan_available_schemas = function()
		return {}
	end,
}
assert(not injector.is_neovim_project(project, core), "Plain Lua project treated as Neovim")
assert(not injector.is_neovim_project(config_root .. "-other", core), "Config sibling treated as Neovim")
assert(injector.is_neovim_project(config_root, core), "Neovim config not detected")
assert(injector.is_neovim_project(config_root .. "/lua", core), "Config subdirectory not detected")
assert(injector.is_neovim_project(opted_in, core), "Explicit Neovim types ignored")
local config_libs = injector.get_active_lua_libraries(config_root, core)
assert(vim.tbl_contains(config_libs, vim.env.VIMRUNTIME), "Neovim runtime missing from config")
assert(vim.tbl_contains(config_libs, config_root .. "/lua"), "Config libraries missing")
local plain_libs = injector.get_active_lua_libraries(project, core)
assert(not vim.tbl_contains(plain_libs, vim.env.VIMRUNTIME), "Neovim runtime leaked into plain Lua")
assert(not vim.tbl_contains(plain_libs, config_root .. "/lua"), "Config libraries leaked into plain Lua")
print("PASS: plain Lua, config, nested config, sibling and explicit Neovim projects")

local lsp = require("fox.langs.lua").lsp_config.lua_ls
for _, dir in ipairs({ project, config_root }) do
	local config = { root_dir = dir, settings = vim.deepcopy(lsp.settings) }
	lsp.before_init({}, config)
	local is_config = dir == config_root
	assert(vim.tbl_contains(config.settings.Lua.workspace.library, vim.env.VIMRUNTIME) == is_config)
	assert(vim.tbl_contains(config.settings.Lua.diagnostics.globals, "vim") == is_config)
end
print("PASS: LuaLS initialization scopes Neovim libraries and globals")

local clients = {}
for _, dir in ipairs({ project, config_root }) do
	clients[#clients + 1] = {
		config = { root_dir = dir, settings = { Lua = { workspace = { library = { "sentinel" } } } } },
		notify = function(self, method)
			assert(method == "workspace/didChangeConfiguration")
			self.notified = true
		end,
	}
end
local original = vim.lsp.get_clients
vim.lsp.get_clients = function()
	return clients
end
local ok, err = pcall(function()
	injector.apply_lsp_settings(project, core)
	assert(clients[1].notified, "Project client not refreshed")
	assert(not clients[2].notified, "Other project's client was refreshed")
	assert(clients[2].config.settings.Lua.workspace.library[1] == "sentinel", "Other project's libraries changed")
	injector.apply_lsp_settings(nil, core)
	assert(vim.tbl_contains(clients[2].config.settings.Lua.workspace.library, vim.env.VIMRUNTIME))
	assert(not vim.tbl_contains(clients[1].config.settings.Lua.workspace.library, vim.env.VIMRUNTIME))
end)
vim.lsp.get_clients = original
assert(ok, err)
print("PASS: type refresh stays scoped to each client root")
