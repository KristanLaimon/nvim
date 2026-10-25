-- Run with nvim --clean --headless -l config/tests/lua/completion_check.lua (requires Mason's LuaLS).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
vim.opt.runtimepath:prepend(root)

local project = vim.fn.tempname()
vim.fn.mkdir(project .. "/lua/sample", "p")
vim.fn.writefile({ "{}" }, project .. "/.luarc.json")
vim.fn.writefile({ "local M = {}", "function M:SayHello() end", "return M" }, project .. "/json.lua")
vim.fn.writefile({ "return { answer = function() return 42 end }" }, project .. "/lua/sample/init.lua")
vim.fn.writefile({ "return { greet = function() return 'hello' end }" }, project .. "/library.lua")
local lines = {
	'local sample = require("sample")',
	'local json = require("json")',
	"json:SayHello()",
	'local library = require("library")',
}
vim.fn.writefile(lines, project .. "/main.lua")
vim.cmd.edit(vim.fn.fnameescape(project .. "/main.lua"))
vim.bo.filetype = "lua"
local buf = vim.api.nvim_get_current_buf()
local config = vim.deepcopy(require("fox.langs.lua").lsp_config.lua_ls)
local binary = vim.fn.stdpath("data") .. "/mason/bin/lua-language-server"
if vim.fn.executable(binary) ~= 1 then
	binary = vim.fn.stdpath("data") .. "/mason/packages/lua-language-server/lua-language-server"
end
if vim.fn.has("win32") == 1 then
	binary = vim.fn.stdpath("data") .. "/mason/packages/lua-language-server/bin/lua-language-server.exe"
end
config.name = "lua_completion_check"
config.cmd = { binary, "--logpath=" .. project .. "/logs", "--metapath=" .. project .. "/meta" }
config.root_dir(buf, function(dir)
	assert(vim.fs.normalize(dir) == vim.fs.normalize(project), "Lua project root was not detected")
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
		{ "json:", "SayHello" },
		{ 'require("sam', "sample" },
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
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modified = false
	vim.cmd.edit(vim.fn.fnameescape(project .. "/json.lua"))
	local module_buf = vim.api.nvim_get_current_buf()
	vim.lsp.buf_attach_client(module_buf, id)
	local response = client:request_sync("textDocument/references", {
		textDocument = { uri = vim.uri_from_bufnr(module_buf) },
		position = { line = 1, character = 13 },
		context = { includeDeclaration = false },
	}, 10000, module_buf)
	local found = false
	for _, location in ipairs(response and response.result or {}) do
		if location.uri == vim.uri_from_bufnr(buf) and location.range.start.line == 2 then
			found = true
		end
	end
	assert(found, "SayHello reference in main.lua was not found")
	print("PASS: SayHello reference in main.lua")
end)
if client then
	client:stop(true)
end
vim.fn.delete(project, "rf")
assert(ok, err)
