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
	local buf = context.bufnr
	if not vim.api.nvim_buf_is_loaded(buf) then
		callback({ items = {} })
		return function() end
	end
	local query = package.loaded["fox.query"]
	local state = query and query.states[vim.b[buf].fox_query_root or ""]
	local items, seen = {}, {}
	local engine = require("fox.langs.sql.dialect").read(buf) or vim.b[buf].fox_sql_dialect
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
	local console = state and state.consoles and state.consoles[buf]
	local schema = console and console.metadata or not console and state and state.metadata
	if state then
		schema = schema or { tables = {}, relations = {} }
		local metadata = vim.tbl_extend("force", schema, { syntax = engine or schema.syntax })
		local cursor = context.cursor or vim.api.nvim_win_get_cursor(0)
		local count = vim.api.nvim_buf_line_count(buf)
		local row = math.max(0, math.min(count - 1, cursor[1] - 1))
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		local prefix = line:sub(1, cursor[2])
		local alias = prefix:match("([%w_]+)%.[%w_]*$")
		local nodes = {}
		-- Keep schema and keyword completions available when statement analysis is too expensive.
		if vim.api.nvim_buf_get_offset(buf, count) <= 128 * 1024 then
			local sql = require("fox.query.sql")
			local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			local offset = vim.api.nvim_buf_get_offset(buf, row) + #prefix + 1
			local statement, statement_offset = text, offset
			for _, scope in ipairs(sql.statements(text, metadata.syntax or metadata.engine) or {}) do
				if offset >= scope.first and offset <= scope.last then
					statement, statement_offset = scope.sql, offset - scope.first + 1
					break
				end
			end
			nodes = sql.completion_graph(statement, statement_offset, metadata).nodes
		end
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
			for _, item in ipairs(metadata.tables or {}) do
				if item.schema == alias then
					add(item.name, 7, item.key)
				end
			end
			for _, node in ipairs(nodes) do
				if not node.nested and node.alias:lower() == alias:lower() and node.table then
					for _, column in ipairs(node.table.columns) do
						add(column.name, 5, node.table.key .. " | " .. tostring(column.type))
					end
				end
			end
		else
			for _, table in ipairs(metadata.tables or {}) do
				add(metadata.engine == "mysql" and table.name or table.key, 7, "table/view")
			end
			local columns = {}
			for _, node in ipairs(nodes) do
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
	local awaiting_schema = console ~= nil and console.metadata == nil
	callback({ items = items, is_incomplete_forward = awaiting_schema, is_incomplete_backward = awaiting_schema })
	return function() end
end

return M
