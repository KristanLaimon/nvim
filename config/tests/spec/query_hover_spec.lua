local t = require("fox.lib.foxnvim.test")
local query = require("fox.query")

t.describe("SQL metadata hover", function()
	t.it("shows WITH output columns through the SQL K mapping", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		root = require("fox.query.storage").root(root)
		local original, preview = vim.api.nvim_get_current_buf(), vim.lsp.util.open_floating_preview
		local buf = vim.api.nvim_create_buf(false, true)
		local received
		local ok, err = pcall(function()
			query.state(root)
			vim.b[buf].fox_query_root = root
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				"-- foxquery: dialect=postgres",
				"WITH PlayerIds AS (SELECT 1 AS id) SELECT * FROM PlayerIds",
			})
			vim.api.nvim_set_current_buf(buf)
			require("fox.langs.sql").attach(buf, root)
			vim.api.nvim_win_set_cursor(0, { 2, 49 })
			vim.lsp.util.open_floating_preview = function(lines)
				received = table.concat(lines, "\n")
			end
			vim.fn.maparg("K", "n", false, true).callback()
			t.expect(received).toContain("WITH table (query only)")
			t.expect(received).toContain("- id")
		end)
		vim.lsp.util.open_floating_preview = preview
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(buf, { force = true })
		query.states[root] = nil
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)
end)
