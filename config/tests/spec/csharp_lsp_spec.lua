local t = require("fox.lib.foxnvim.test")
local cs = require("fox.langs.csharp")

t.describe("C# LSP launcher", function()
	t.it("starts OmniSharp in the detected project rather than the editor directory", function()
		local saved_start = vim.lsp.rpc.start
		local saved_resolve = require("fox.lsp.tooling").resolve_command
		local captured
		vim.lsp.rpc.start = function(cmd, dispatchers, options)
			captured = { cmd = cmd, dispatchers = dispatchers, options = options }
			return "rpc"
		end
		require("fox.lsp.tooling").resolve_command = function(cmd)
			return cmd
		end
		local dispatchers = {}
		local config = { root_dir = "/workspace/backend", cmd_env = { TEST = "1" }, detached = false }
		local ok, result = pcall(cs.lsp_config.omnisharp.cmd, dispatchers, config)
		vim.lsp.rpc.start = saved_start
		require("fox.lsp.tooling").resolve_command = saved_resolve
		assert(ok, result)
		t.expect(result).toBe("rpc")
		t.expect(captured.cmd[#captured.cmd - 1]).toBe("--source")
		t.expect(captured.cmd[#captured.cmd]).toBe(config.root_dir)
		t.expect(captured.options.cwd).toBe(config.root_dir)
		t.expect(captured.options.env).toBe(config.cmd_env)
		t.expect(captured.options.detached).toBe(false)
		t.expect(captured.dispatchers).toBe(dispatchers)
	end)
end)
