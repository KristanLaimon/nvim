-- ============================================================================
-- 🚀 Node.js / TypeScript — js-debug-adapter (pwa-node)
-- ============================================================================

local shared = require("plugins.fox.debuggers._shared")

-- Node cannot execute .ts directly. Same resolver the launch profiles use, so
-- "debug this file" and "debug this profile" start TypeScript the same way.
local function ts_launch()
	return require("fox.langs.typescript").ts_runtime(vim.fn.getcwd(), vim.fn.expand("%:p"))
end

return function(dap)
	shared.js_debug(dap)

	shared.add(dap, shared.web_filetypes, {
		{
			type = "pwa-node",
			request = "launch",
			name = "🚀 Launch Current File (Node/TS)",
			program = "${file}",
			cwd = "${workspaceFolder}",
			-- integratedTerminal keeps the process inside a nvim terminal buffer;
			-- without it Windows pops external cmd.exe windows for npx/.cmd shims.
			console = "integratedTerminal",
			sourceMaps = true,
			skipFiles = shared.js_skip,
			runtimeExecutable = function()
				return ts_launch().exe
			end,
			runtimeArgs = function()
				return ts_launch().args
			end,
		},
		{
			type = "pwa-node",
			request = "attach",
			name = "🔗 Attach to Node Process",
			processId = require("dap.utils").pick_process,
			cwd = "${workspaceFolder}",
			skipFiles = shared.js_skip,
		},
	})
end
