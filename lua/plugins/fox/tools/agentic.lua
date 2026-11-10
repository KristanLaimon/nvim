return {
	name = "fox_agentic",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = {
		"FoxAgenticOpen",
		"FoxAgenticToggle",
		"FoxAgenticSessions",
		"FoxAgenticBind",
		"FoxAgenticDetach",
		"FoxAgenticReturn",
		"FoxAgenticRefresh",
		"FoxAgenticHelp",
		"FoxAgenticCodex",
	},
	keys = {
		{ "<F2>", "<Cmd>FoxAgenticToggle<CR>", mode = { "n", "i", "v", "t" }, desc = "Toggle Agentic Mode" },
	},
	config = function()
		local agentic = require("fox.agentic")
		agentic.setup()
		for name, callback in pairs({
			FoxAgenticOpen = function()
				agentic.show()
			end,
			FoxAgenticToggle = agentic.toggle,
			FoxAgenticSessions = function()
				if not agentic.active() then
					agentic.show()
				end
				local state = agentic.state()
				if state and state.connection and state.connection.ready then
					agentic.sessions()
				end
			end,
			FoxAgenticDetach = agentic.detach,
			FoxAgenticReturn = function()
				agentic.show(agentic.state())
			end,
			FoxAgenticRefresh = agentic.refresh,
			FoxAgenticHelp = agentic.help,
			FoxAgenticCodex = agentic.start_codex,
		}) do
			vim.api.nvim_create_user_command(name, function()
				callback()
			end, {})
		end
		vim.api.nvim_create_user_command("FoxAgenticBind", function(args)
			local state = agentic.state()
			if not state or not state.connection or not state.connection.ready or state.connection.closed then
				vim.notify("Open Agentic and connect to Codex first", vim.log.levels.WARN)
				return
			end
			agentic.bind({ id = args.args, cwd = state.root })
		end, { nargs = 1 })
	end,
}
