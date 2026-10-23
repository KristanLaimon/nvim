local M = {}

function M.new()
	return setmetatable({}, { __index = M })
end

function M.get_completions(_, context, callback)
	local query = package.loaded["fox.query"]
	local state = query and query.states[vim.b[context.bufnr].fox_query_root or ""]
	local items, seen = {}, {}
	if state then
		local text = table.concat(vim.api.nvim_buf_get_lines(context.bufnr, 0, -1, false), "\n")
		if #text > 128 * 1024 then
			callback({ items = {} })
			return function() end
		end
		local graph = require("fox.query.sql").analyze(text, state.metadata)
		local line = vim.api.nvim_get_current_line():sub(1, vim.api.nvim_win_get_cursor(0)[2])
		local alias = line:match("([%w_]+)%.[%w_]*$")
		local function add(label, kind, detail)
			if not seen[label] then
				items[#items + 1] = { label = label, kind = kind, detail = detail }
				seen[label] = true
			end
		end
		if alias then
			for _, item in ipairs(state.metadata.tables or {}) do
				if item.schema == alias then
					add(item.name, 7, item.key)
				end
			end
			for _, node in ipairs(graph.nodes) do
				if node.alias == alias and node.table then
					for _, column in ipairs(node.table.columns) do
						add(column.name, 5, node.table.key .. " | " .. tostring(column.type))
					end
				end
			end
		else
			for _, keyword in ipairs({
				"SELECT",
				"FROM",
				"WHERE",
				"JOIN",
				"LEFT JOIN",
				"INNER JOIN",
				"ON",
				"GROUP BY",
				"ORDER BY",
				"LIMIT",
				"AS",
				"IS NULL",
				"WITH",
			}) do
				add(keyword, 14, "SQL")
			end
			for _, table in ipairs(state.metadata.tables or {}) do
				add(table.key, 7, "table/view")
			end
			for _, node in ipairs(graph.nodes) do
				if node.table then
					for _, column in ipairs(node.table.columns) do
						add(node.alias .. "." .. column.name, 5, tostring(column.type))
					end
				end
			end
		end
	end
	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
	return function() end
end

return M
