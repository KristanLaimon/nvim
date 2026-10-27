local commands = {
	"FoxMode",
	"FoxModeToggle",
	"FoxQueryView",
	"FoxQueryConnections",
	"FoxQueryNew",
	"FoxQueryOpen",
	"FoxQueryFiles",
	"FoxQueryRun",
	"FoxQueryRunPopup",
	"FoxQueryBrowsePopup",
	"FoxQueryAutoRun",
	"FoxQueryComplete",
	"FoxQueryDialect",
	"FoxQuerySyntaxCheck",
	"FoxQueryCancel",
	"FoxQueryExplorer",
	"FoxQueryInspect",
	"FoxQueryGraph",
	"FoxQueryNotes",
	"FoxQueryDeleteNote",
	"FoxQueryRefresh",
	"FoxQueryResults",
	"FoxQueryClearParameters",
	"FoxQueryClearCache",
	"FoxQueryInsertJoin",
	"FoxQueryExport",
	"FoxQueryPin",
	"FoxQueryColumns",
	"FoxQueryActivity",
	"FoxQueryHelp",
	"FoxQueryErrorDetails",
}

return {
	name = "fox_query",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = commands,
	keys = {
		{ "<F3>", "<Cmd>FoxModeToggle<CR>", mode = { "n", "i", "v", "t" }, desc = "Cycle Editor / Query" },
		{ "<C-A-o>", "<Cmd>FoxModeToggle<CR>", mode = { "n", "i", "v", "t" }, desc = "Cycle Editor / Query" },
	},
	config = function()
		local query = require("fox.query")
		query.setup()
		local function command(name, callback, opts)
			vim.api.nvim_create_user_command(name, callback, opts or {})
		end
		command("FoxModeToggle", function()
			local state = query.state()
			if state.mode == "query" and state.tab == vim.api.nvim_get_current_tabpage() then
				query.hide()
			else
				query.show()
			end
		end)
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
				query.select({ "editor", "query" }, { prompt = "Project view (FoxAI is not implemented)" }, choose)
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
			query.create(args.args ~= "" and args.args or nil)
		end, { nargs = "?" })
		command("FoxQueryOpen", function()
			query.show()
			query.open()
		end)
		command("FoxQueryFiles", function(args)
			query.show("standard")
			query.focus_panel("queries")
			if args.args ~= "" then
				query.file_action(args.args)
			end
		end, {
			nargs = "?",
			complete = function()
				return { "create", "folder", "rename", "delete" }
			end,
		})
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
		command("FoxQueryRunPopup", function(args)
			query.run_popup(args.args ~= "" and args.args or "statement")
		end, {
			nargs = "?",
			range = true,
			complete = function()
				return { "statement", "selection", "section", "file" }
			end,
		})
		command("FoxQueryBrowsePopup", function()
			query.browse(nil, true)
		end)
		command("FoxQueryComplete", query.complete)
		command("FoxQueryDialect", function(args)
			query.dialect(args.args)
		end, {
			nargs = "?",
			complete = function()
				return { "mysql", "postgres", "sqlite" }
			end,
		})
		command("FoxQuerySyntaxCheck", query.syntax_check)
		command("FoxQueryAutoRun", function()
			local state = query.state()
			state.autorun = not state.autorun
			query.refresh_view(state)
		end)
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
		command("FoxQueryDeleteNote", function()
			query.notes(nil, "delete")
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
		command("FoxQueryExport", query.export)
		command("FoxQueryPin", query.pin)
		command("FoxQueryColumns", query.column_limit)
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
