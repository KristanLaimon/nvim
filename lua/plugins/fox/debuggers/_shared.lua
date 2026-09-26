-- ============================================================================
-- 🦊 FOX: shared pieces for the per-language debugger modules
-- ============================================================================
-- Files in this directory are NOT lazy.nvim specs. lazy's `import` only walks
-- subdirectories that contain an init.lua (lua/lazy/core/util.lua:328), so this
-- folder is invisible to `{ import = "plugins.fox" }`. lua/plugins/editor/dap.lua
-- requires each module by name and calls it with the `dap` module.
-- ============================================================================

local M = {}

-- Without this js-debug stops inside node internals and the tsx/ts-node loader.
-- nvim-dap force-lists every frame's buffer (session.lua: buflisted = true), so
-- each one becomes a bufferline tab with a long absolute path.
-- Shared with the launch profiles, so both debug paths skip the same files.
M.js_skip = require("fox.langs.typescript").js_skip_files

M.web_filetypes = {
	"typescript",
	"javascript",
	"typescriptreact",
	"javascriptreact",
	"svelte",
	"vue",
	"astro",
}

-- Append configurations to every given filetype. Modules append instead of
-- assigning so several of them (bun, node, browsers) can share a filetype.
--
-- The first module to claim a filetype clears it first: mason-nvim-dap's
-- default_setup already pushed its own generic entries ("Python: Launch file",
-- "Chrome: Debug", ...) into the same tables, and those would otherwise sit in
-- the picker next to the ones configured here.
local claimed = {}
function M.add(dap, filetypes, configs)
	for _, ft in ipairs(filetypes) do
		if not claimed[ft] then
			claimed[ft] = true
			dap.configurations[ft] = {}
		end
		vim.list_extend(dap.configurations[ft], configs)
	end
end

-- js-debug-adapter drives pwa-node, pwa-chrome and pwa-msedge. Registered here
-- because both node.lua and browsers.lua need it, whatever order they load in.
local js_debug_done = false
function M.js_debug(dap)
	if js_debug_done then
		return
	end
	js_debug_done = true

	local mason_path = (vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter"):gsub("\\", "/")
	local dap_server = mason_path .. "/js-debug/src/dapDebugServer.js"
	local cmd_bin = mason_path .. "/js-debug-adapter.cmd"

	if vim.fn.filereadable(dap_server) == 1 then
		dap.adapters["pwa-node"] = {
			type = "server",
			host = "localhost",
			port = "${port}",
			executable = { command = "node", args = { dap_server, "${port}" } },
		}
		dap.adapters["pwa-chrome"] = {
			type = "server",
			host = "localhost",
			port = "${port}",
			executable = { command = "node", args = { dap_server, "${port}" } },
		}
	elseif vim.fn.filereadable(cmd_bin) == 1 then
		dap.adapters["pwa-node"] = { type = "executable", command = cmd_bin }
		dap.adapters["pwa-chrome"] = { type = "executable", command = cmd_bin }
	end

	-- Edge is Chromium: same js-debug server, different browser binary.
	dap.adapters["pwa-msedge"] = dap.adapters["pwa-chrome"]
end

return M
