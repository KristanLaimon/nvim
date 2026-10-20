--- @module "foxnvim"
--- Master entry point for the FoxVim Lua libraries.
--- Exposes `json`, `yaml`, `toml`, `terminal`, `cli`, `fs`, `fetch`, `wiki`, and `tests`.
---
--- @example
--- local fox = require("fox.lib.foxnvim")
--- local fetch = fox.fetch
--- local json = fox.json
local M = {}

M.json = require("fox.lib.foxnvim.json")
M.yaml = require("fox.lib.foxnvim.yaml")
M.toml = require("fox.lib.foxnvim.toml")
M.terminal = require("fox.lib.foxnvim.terminal")
M.cli = require("fox.lib.foxnvim.cli")
M.fs = require("fox.lib.foxnvim.fs")
M.fetch = require("fox.lib.foxnvim.fetch")
M.wiki = require("fox.lib.foxnvim.wiki")
M.tests = require("fox.lib.foxnvim.tests")
M.console = require("fox.lib.foxnvim.console")
M.test = require("fox.lib.foxnvim.test")
M.describe = M.test.describe
M.expect = M.test.expect
M.it = M.test.it
M.async = require("fox.lib.foxnvim.async")
M.concurrent = M.async
M.parallel = M.async

M.setTimeout = M.async.setTimeout
M.clearTimeout = M.async.clearTimeout
M.setInterval = M.async.setInterval
M.clearInterval = M.async.clearInterval

--- Setup global functions (setTimeout, clearTimeout, setInterval, clearInterval, console, fetch, describe, test, expect, import, foxnvim, cli, terminal, fs).
function M.setup_globals()
	_G.foxnvim = M
	_G.cli = M.cli
	_G.terminal = M.terminal
	_G.fs = M.fs
	_G.setTimeout = M.setTimeout
	_G.clearTimeout = M.clearTimeout
	_G.setInterval = M.setInterval
	_G.clearInterval = M.clearInterval
	_G.console = M.console
	_G.fetch = M.fetch
	_G.test = M.test.test
	_G.describe = M.test.describe
	_G.expect = M.test.expect
	_G.it = M.test.it
	_G.import = M.import
end

--- Global smart import function for Lua in Neovim.
--- Automatically detects file extensions (`.json`, `.yaml`, `.yml`, `.toml`) or module aliases (`"fetch"`, `"json"`, `"fs"`, etc.).
---
--- @param target string Module name alias or file path to import.
--- @return any module_or_data Module table or parsed data structure.
function M.import(target)
	if not target or type(target) ~= "string" then
		error("import(): Target must be a non-empty string")
	end

	if target == "foxnvim.terminal" or target == "terminal" or target == "foxnvim.cmd" or target == "cmd" then
		return M.terminal
	elseif target == "foxnvim.json" or target == "json" then
		return M.json
	elseif target == "foxnvim.yaml" or target == "yaml" then
		return M.yaml
	elseif target == "foxnvim.toml" or target == "toml" then
		return M.toml
	elseif target == "foxnvim.cli" or target == "cli" then
		return M.cli
	elseif target == "foxnvim.fs" or target == "fs" then
		return M.fs
	elseif target == "foxnvim.fetch" or target == "fetch" then
		return M.fetch
	elseif target == "foxnvim.console" or target == "console" then
		return M.console
	elseif target == "foxnvim.async" or target == "async" or target == "concurrent" or target == "parallel" then
		return M.async
	elseif target == "foxnvim.test" or target == "test" or target == "tests" then
		return M.test
	end

	if target:match("%.json$") then
		return M.json.load(target)
	elseif target:match("%.yaml$") or target:match("%.yml$") then
		return M.yaml.load(target)
	elseif target:match("%.toml$") then
		return M.toml.load(target)
	end

	local ok, res = pcall(require, target)
	if ok then
		return res
	end

	if M.fs and M.fs.exists and M.fs.exists(target) then
		if target:match("%.json$") then
			return M.json.load(target)
		end
		if target:match("%.yaml$") or target:match("%.yml$") then
			return M.yaml.load(target)
		end
		if target:match("%.toml$") then
			return M.toml.load(target)
		end
	end

	error("import(): Cannot import target: " .. tostring(target))
end

M.setup_globals()

return M
