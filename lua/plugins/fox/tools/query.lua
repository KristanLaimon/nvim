local commands = {
	"FoxMode",
	"FoxQueryView",
	"FoxQueryConnections",
	"FoxQueryNew",
	"FoxQueryOpen",
	"FoxQueryRun",
	"FoxQueryCancel",
	"FoxQueryExplorer",
	"FoxQueryInspect",
	"FoxQueryGraph",
	"FoxQueryNotes",
	"FoxQueryRefresh",
	"FoxQueryResults",
	"FoxQueryClearParameters",
	"FoxQueryClearCache",
	"FoxQueryInsertJoin",
	"FoxQueryInstallDrivers",
	"FoxQueryExport",
	"FoxQueryPin",
	"FoxQueryActivity",
	"FoxQueryHelp",
	"FoxQueryErrorDetails",
}

return {
	name = "fox_query",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = commands,
	keys = { { "<C-A-o>", "<Cmd>FoxMode<CR>", mode = { "n", "i", "v", "t" }, desc = "Switch FoxEditor / FoxQuerier" } },
	config = function()
		local query = require("fox.query")
		query.setup()
		local function command(name, callback, opts)
			vim.api.nvim_create_user_command(name, callback, opts or {})
		end
		command("FoxMode", function(args)
			local function choose(mode)
				if mode == "editor" then
					query.hide()
				elseif mode == "query" then
					query.show()
				end
			end
			if args.args ~= "" then
				choose(args.args)
			else
				vim.ui.select({ "editor", "query" }, { prompt = "Project view (FoxAI is not implemented)" }, choose)
			end
		end, {
			nargs = "?",
			complete = function()
				return { "editor", "query" }
			end,
		})
		command("FoxQueryView", function(args)
			query.show(args.args ~= "" and args.args or (query.state().view == "visual" and "standard" or "visual"))
		end, {
			nargs = "?",
			complete = function()
				return { "standard", "visual" }
			end,
		})
		command("FoxQueryConnections", function()
			query.profile()
		end)
		command("FoxQueryNew", function(args)
			query.show()
			query.new(args.args ~= "" and args.args or nil)
		end, { nargs = "?" })
		command("FoxQueryOpen", function()
			query.show()
			query.open()
		end)
		command("FoxQueryRun", function(args)
			query.run(args.args ~= "" and args.args or "statement")
		end, {
			nargs = "?",
			range = true,
			complete = function()
				return { "statement", "selection", "section", "file" }
			end,
		})
		command("FoxQueryCancel", query.cancel)
		command("FoxQueryExplorer", function()
			query.show("standard")
			query.focus_panel("side")
		end)
		command("FoxQueryInspect", function()
			query.inspect()
		end)
		command("FoxQueryGraph", function(args)
			query.graph(args.args == "all")
		end, {
			nargs = "?",
			complete = function()
				return { "all", "neighborhood" }
			end,
		})
		command("FoxQueryNotes", function()
			query.notes()
		end)
		command("FoxQueryRefresh", function()
			query.refresh_metadata()
		end)
		command("FoxQueryResults", query.results)
		command("FoxQueryActivity", function()
			query.focus_panel("activity")
		end)
		command("FoxQueryHelp", query.help)
		command("FoxQueryErrorDetails", query.error_details)
		command("FoxQueryInsertJoin", function()
			query.insert_join()
		end)
		command("FoxQueryInstallDrivers", query.install_drivers)
		command("FoxQueryExport", query.export)
		command("FoxQueryPin", query.pin)
		command("FoxQueryClearParameters", function()
			for _, item in pairs(query.state().consoles) do
				item.params = {}
			end
		end)
		command("FoxQueryClearCache", function()
			local storage = require("fox.query.storage")
			local root = storage.root()
			for _, filename in ipairs(vim.fn.glob(storage.path(root, "cache/*.json"), false, true)) do
				vim.fn.delete(filename)
			end
		end)
	end,
}
