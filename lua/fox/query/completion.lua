local M = {}

function M.new()
	return setmetatable({}, { __index = M })
end

function M.get_trigger_characters()
	return { "." }
end

function M.compare(a, b)
	local left = type(a.data) == "table" and a.data.fox_query_priority or nil
	local right = type(b.data) == "table" and b.data.fox_query_priority or nil
	if left ~= right then
		return (left or math.huge) < (right or math.huge)
	end
end

function M.get_completions(_, context, callback)
	local query = package.loaded["fox.query"]
	local state = query and query.states[vim.b[context.bufnr].fox_query_root or ""]
	local items, seen = {}, {}
	local engine = require("fox.langs.sql.dialect").read(context.bufnr) or vim.b[context.bufnr].fox_sql_dialect
	if engine then
		for _, item in ipairs(require("fox.langs.sql.functions").items(engine)) do
			items[#items + 1], seen[item.label] = item, true
		end
	end
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
		"EXISTS",
		"IN",
		"HAVING",
		"DISTINCT",
		"UNION",
		"CURRENT_DATE",
		"CURRENT_TIME",
		"CURRENT_TIMESTAMP",
	}) do
		items[#items + 1] = { label = keyword, kind = 14, detail = engine or "SQL" }
		seen[keyword] = true
	end
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
		local metadata = vim.tbl_extend("force", state.metadata, { syntax = engine or state.metadata.syntax })
		local statement = sql.scope(text, offset, "statement", nil, metadata.syntax or metadata.engine)
		local statement_offset = offset
		for _, scope in ipairs(sql.statements(text, metadata.syntax or metadata.engine) or {}) do
			if offset >= scope.first and offset <= scope.last then
				statement_offset = offset - scope.first + 1
				break
			end
		end
		local graph = sql.completion_graph(statement or text, statement_offset, metadata)
		local line = (vim.api.nvim_buf_get_lines(context.bufnr, cursor[1] - 1, cursor[1], false)[1] or ""):sub(1, cursor[2])
		local alias = line:match("([%w_]+)%.[%w_]*$")
		local function add(label, kind, detail, priority)
			if not seen[label] then
				items[#items + 1] = {
					label = label,
					kind = kind,
					detail = detail,
					data = priority and { fox_query_priority = priority } or nil,
				}
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
				if not node.nested and node.alias:lower() == alias:lower() and node.table then
					for _, column in ipairs(node.table.columns) do
						add(column.name, 5, node.table.key .. " | " .. tostring(column.type))
					end
				end
			end
		else
			for _, table in ipairs(state.metadata.tables or {}) do
				add(metadata.engine == "mysql" and table.name or table.key, 7, "table/view")
			end
			local columns = {}
			for _, node in ipairs(graph.nodes) do
				if node.table and not node.nested then
					if node.table.cte then
						add(node.table.name, 7, "WITH table (query only)")
					end
					local depth = node.completion_depth or 0
					for _, column in ipairs(node.table.columns) do
						add(node.alias .. "." .. column.name, 5, tostring(column.type), depth * 2 + 1)
						local key = column.name:lower()
						local previous = columns[key]
						if not previous or depth < previous.depth then
							columns[key] = { column = column, count = 1, table = node.table, depth = depth }
						elseif depth == previous.depth then
							previous.count = previous.count + 1
						end
					end
				end
			end
			for _, entry in pairs(columns) do
				if entry.count == 1 then
					add(entry.column.name, 5, entry.table.key .. " | " .. tostring(entry.column.type), entry.depth * 2)
				end
			end
		end
	end
	callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
	return function() end
end

return M
