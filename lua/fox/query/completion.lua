local M = {}

function M.new()
	return setmetatable({}, { __index = M })
end

function M.get_trigger_characters()
	return { "." }
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
		local sql = require("fox.query.sql")
		local cursor = context.cursor or vim.api.nvim_win_get_cursor(0)
		local offset = cursor[2] + 1
		for _, line in ipairs(vim.api.nvim_buf_get_lines(context.bufnr, 0, cursor[1] - 1, false)) do
			offset = offset + #line + 1
		end
		local statement = sql.scope(text, offset, "statement", nil, state.metadata.syntax or state.metadata.engine)
		local graph = sql.analyze(statement or text, state.metadata)
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
				if node.alias:lower() == alias:lower() and node.table then
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
			local columns = {}
			for _, node in ipairs(graph.nodes) do
				if node.table then
					for _, column in ipairs(node.table.columns) do
						add(node.alias .. "." .. column.name, 5, tostring(column.type))
						local key = column.name:lower()
						local previous = columns[key]
						columns[key] = { column = column, count = (previous and previous.count or 0) + 1, table = node.table }
					end
				end
			end
			for _, entry in pairs(columns) do
				if entry.count == 1 then
					add(entry.column.name, 5, entry.table.key .. " | " .. tostring(entry.column.type))
				end
			end
		end
	end
	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
	return function() end
end

return M
