local M = {}

M.bundle_name = "SQL / FoxQuerier"
M.treesitter = { "sql" }
M.defaults = { expandtab = true, shiftwidth = 2, tabstop = 2, softtabstop = 2 }
M.mason = { sqlfluff = { mason = "sqlfluff", cmd = "sqlfluff", name = "SQLFluff", type = "formatter" } }
M.mason_order = { "sqlfluff" }

function M.attach(buf, root)
	vim.b[buf].fox_sql_root = require("fox.query.storage").root(root)
	local name, err = require("fox.langs.sql.dialect").ensure(buf, root)
	if not name then
		vim.notify(err, vim.log.levels.ERROR, { title = "SQL dialect" })
		return
	end
	vim.keymap.set("n", "K", function()
		require("fox.langs.sql.functions").hover(buf)
	end, { buffer = buf, desc = "SQL column, table or function information" })
	require("fox.langs.sql.diagnostics").attach(buf)
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "sql",
		callback = function(args)
			if not require("fox.langs").has_editorconfig(args.buf) then
				for key, value in pairs(M.defaults) do
					vim.bo[args.buf][key] = value
				end
			end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(args.buf) or vim.b[args.buf].fox_query_root then
					return
				end
				local dialect = require("fox.langs.sql.dialect")
				local root = require("fox.query.storage").root()
				if not dialect.read(args.buf) and vim.fn.filereadable(vim.api.nvim_buf_get_name(args.buf)) == 0 then
					local options, err = dialect.options(root)
					if not options then
						vim.notify(err, vim.log.levels.ERROR)
						return
					end
					vim.ui.select(options, {
						prompt = "SQL dialect",
						format_item = function(name)
							return dialect.names[name]
						end,
					}, function(name)
						if name and vim.api.nvim_buf_is_valid(args.buf) then
							local ok, set_err = dialect.set(args.buf, name, root)
							if ok then
								M.attach(args.buf, root)
							else
								vim.notify(set_err, vim.log.levels.ERROR)
							end
						end
					end)
				else
					M.attach(args.buf, root)
				end
			end)
		end,
	})
end

return M
