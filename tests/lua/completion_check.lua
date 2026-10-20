-- Run with nvim -l tests/lua/completion_check.lua (requires Mason's LuaLS).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
vim.opt.runtimepath:prepend(root)

local project = vim.fn.tempname()
vim.fn.mkdir(project .. "/lua/sample", "p")
vim.fn.writefile({ "return { answer = function() return 42 end }" }, project .. "/lua/sample/init.lua")
vim.fn.writefile({ "return { greet = function() return 'hello' end }" }, project .. "/library.lua")
local lines = {
	'local sample = require("sample")',
	'local fs = require("fox.lib.foxnvim.fs")',
	'local fox = require("fox.lib.foxnvim")',
	'local library = require("library")',
}
vim.fn.writefile(lines, project .. "/main.lua")
vim.cmd.edit(vim.fn.fnameescape(project .. "/main.lua"))
vim.bo.filetype = "lua"
local buf = vim.api.nvim_get_current_buf()
local config = vim.deepcopy(require("fox.langs.lua").lsp_config.lua_ls)
local binary = vim.fn.stdpath("data") .. "/mason/packages/lua-language-server/bin/lua-language-server"
if vim.fn.has("win32") == 1 then
	binary = binary .. ".exe"
end
config.name = "lua_completion_check"
config.cmd = { binary }
config.root_dir(buf, function(dir)
	assert(vim.fs.normalize(dir) == vim.fs.normalize(project), "Markerless Lua project root was not detected")
	config.root_dir = dir
end)
config.capabilities = vim.lsp.protocol.make_client_capabilities()
local id = vim.lsp.start(config)
local client = id and vim.lsp.get_client_by_id(id)

local ok, err = pcall(function()
	assert(client, "Could not start LuaLS: " .. binary)
	assert(
		vim.wait(15000, function()
			return client.initialized
		end, 50),
		"LuaLS did not initialize"
	)
	for _, check in ipairs({
		{ "library.", "greet" },
		{ 'require("lib', "library" },
		{ "sample.", "answer" },
		{ "fs.", "exists" },
		{ "fox.console.", "log" },
		{ 'require("sam', "sample" },
		{ 'require("fox.lib.foxnvim.f', "fox.lib.foxnvim.fs" },
	}) do
		local expression, label = unpack(check)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(vim.deepcopy(lines), { expression }))
		local found = false
		local deadline = vim.uv.hrtime() + 30e9
		repeat
			local response = client:request_sync("textDocument/completion", {
				textDocument = { uri = vim.uri_from_bufnr(buf) },
				position = { line = #lines, character = #expression },
				context = { triggerKind = 1 },
			}, 3000, buf)
			local result = response and response.result or {}
			for _, item in ipairs(result.items or result) do
				if item.label == label or item.label:sub(1, #label + 1) == label .. "(" then
					found = true
					break
				end
			end
			if not found then
				vim.wait(100)
			end
		until found or vim.uv.hrtime() > deadline
		assert(found, "No completion for " .. label .. " in " .. expression)
		print("PASS: " .. label)
	end
end)
if client then
	client:stop(true)
end
vim.fn.delete(project, "rf")
assert(ok, err)
