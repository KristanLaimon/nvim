local M = {}

function M.render(graph, metadata, width, column_limit)
	local sql = require("fox.query.sql")
	column_limit = column_limit or 15
	local card_width = math.max(15, math.min(28, math.floor(((width or 72) - 7) / 2)))
	local gap, cells, styles, objects, nodes = 7, {}, {}, {}, {}
	local function put(row, column, text, limit)
		cells[row] = cells[row] or {}
		local used = 0
		text = tostring(text):gsub("[%c]", " ")
		for i = 0, vim.fn.strchars(text) - 1 do
			local char = vim.fn.strcharpart(text, i, 1)
			local size = vim.fn.strdisplaywidth(char)
			if used + size > (limit or math.huge) then
				break
			end
			if size == 0 then
				local at = math.max(column, column + used - 1)
				cells[row][at] = (cells[row][at] or "") .. char
			else
				cells[row][column + used] = char
				for extra = 1, size - 1 do
					cells[row][column + used + extra] = ""
				end
				used = used + size
			end
		end
	end
	local function style(row, column, length, group)
		styles[#styles + 1] = { row = row, column = column, length = length, group = group }
	end
	put(1, 1, graph.kind == "schema" and "SCHEMA RELATIONSHIP MAP" or "LIVE QUERY DIAGRAM")
	style(1, 1, 100, "Title")
	local state = graph.partial and "Partial SQL: resolved portions only" or "Diagram follows SQL at the cursor"
	if graph.kind == "schema" then
		state = "FK metadata; not query execution"
	end
	put(2, 1, state .. (metadata.updated_at and (" | cache " .. os.date("%H:%M", metadata.updated_at)) or ""))
	style(2, 1, 150, "Comment")
	local candidates = {}
	for _, edge in ipairs(graph.edges) do
		if not edge.predicate or vim.trim(edge.predicate) == "" then
			local target
			for _, node in ipairs(graph.nodes) do
				if node.alias == edge.target then
					target = node
				end
			end
			if target and target.table then
				for _, node in ipairs(graph.nodes) do
					if node ~= target and node.table and (node.first or 0) < (target.first or math.huge) then
						for _, relation in ipairs(metadata.relations or {}) do
							if
								relation.source == node.table.key and relation.target == target.table.key
								or relation.target == node.table.key and relation.source == target.table.key
							then
								for _, pair in ipairs(relation.columns) do
									local source_name = relation.source == node.table.key and pair.source or pair.target
									local target_name = relation.source == target.table.key and pair.source or pair.target
									candidates[node.alias] = candidates[node.alias] or {}
									candidates[target.alias] = candidates[target.alias] or {}
									candidates[node.alias][source_name or ""] = true
									candidates[target.alias][target_name or ""] = true
								end
							end
						end
					end
				end
			end
		end
	end
	local y, pair_height, shown = 4, 0, {}
	for index, node in ipairs(graph.nodes) do
		if index > 40 then
			break
		end
		local x = index % 2 == 1 and 1 or card_width + gap + 1
		local item, rows = node.table, {}
		local columns = {}
		for _, column in ipairs(item and item.columns or {}) do
			if (node.roles[column.name] or {}).output then
				columns[#columns + 1] = column
			end
		end
		local selected = #columns
		for _, column in ipairs(item and item.columns or {}) do
			if not (node.roles[column.name] or {}).output then
				columns[#columns + 1] = column
			end
		end
		for _, column in ipairs(columns) do
			local roles = node.roles[column.name] or {}
			local wildcard = node.roles["*"] or {}
			local candidate = candidates[node.alias] and candidates[node.alias][column.name]
			do
				local flags = ((roles.output or wildcard.output) and "*" or " ")
					.. (roles.join and "k" or candidate and "?" or " ")
					.. (roles.filter and "f" or " ")
				rows[#rows + 1] = {
					text = flags .. " " .. column.name,
					group = (roles.output or wildcard.output) and "String"
						or roles.join and "Identifier"
						or candidate and "DiagnosticHint"
						or roles.filter and "Special"
						or "Comment",
				}
			end
		end
		if #rows == 0 then
			rows[1] = {
				text = item and "(no columns in metadata)" or "? unresolved source",
				group = item and "Comment" or "DiagnosticWarn",
			}
		end
		local visible = math.min(#rows, math.max(column_limit, selected))
		local height = visible + 4 + (#rows > visible and 1 or 0)
		for row = y, y + height - 1 do
			put(row, x, "|" .. string.rep(" ", card_width - 2) .. "|")
			objects[row] = objects[row] or { regions = {} }
			objects[row].regions[#objects[row].regions + 1] = { first = x - 1, last = x + card_width - 1, item = item }
		end
		put(y, x, "+" .. string.rep("-", card_width - 2) .. "+")
		put(y + height - 1, x, "+" .. string.rep("-", card_width - 2) .. "+")
		put(y + 1, x + 2, node.alias, card_width - 4)
		style(y + 1, x + 1, card_width - 2, item and "Title" or "DiagnosticWarn")
		put(y + 2, x + 2, node.name, card_width - 4)
		style(y + 2, x + 1, card_width - 2, "Comment")
		for row = 1, visible do
			put(y + 2 + row, x + 2, rows[row].text, card_width - 4)
			style(y + 2 + row, x + 1, card_width - 2, rows[row].group)
		end
		if #rows > visible then
			put(y + height - 2, x + 2, "... " .. (#rows - visible) .. " more; Enter inspect", card_width - 4)
		end
		nodes[node.alias] = { x = x, row = y + 1, item = item }
		if item then
			shown[item.key] = true
		end
		pair_height = math.max(pair_height, height)
		if index % 2 == 0 then
			y, pair_height = y + pair_height + 2, 0
		end
	end
	for _, edge in ipairs(graph.edges) do
		local source, target = nodes[edge.source], nodes[edge.target]
		if source and target then
			local gutter = card_width + 1 + math.floor(gap / 2)
			local sx = source.x == 1 and card_width or source.x
			local tx = target.x == 1 and card_width or target.x
			local stroke = edge.predicate and vim.trim(edge.predicate) ~= "" and "-" or "."
			for x = math.min(sx, gutter), math.max(sx, gutter) do
				put(source.row, x, stroke)
			end
			for row = math.min(source.row, target.row), math.max(source.row, target.row) do
				put(row, gutter, "|")
			end
			for x = math.min(tx, gutter), math.max(tx, gutter) do
				put(target.row, x, stroke)
			end
			put(target.row, tx, target.x == 1 and "<" or ">")
		end
	end
	local last = 2
	for row in pairs(cells) do
		last = math.max(last, row)
	end
	local lines, highlights = {}, {}
	for row = 1, last do
		local data, length = cells[row] or {}, 0
		for column in pairs(data) do
			length = math.max(length, column)
		end
		for column = 1, length do
			if data[column] == nil then
				data[column] = " "
			end
		end
		lines[row] = table.concat(data)
	end
	for _, span in ipairs(styles) do
		local data = cells[span.row] or {}
		local first = 0
		for column = 1, span.column - 1 do
			first = first + #(data[column] or " ")
		end
		local finish = first
		for column = span.column, span.column + span.length - 1 do
			finish = finish + #(data[column] or " ")
		end
		highlights[#highlights + 1] =
			{ span.row - 1, span.group, math.min(first, #lines[span.row]), math.min(finish, #lines[span.row]) }
	end
	lines[#lines + 1] = ""
	for _, edge in ipairs(graph.edges) do
		lines[#lines + 1] = "["
			.. tostring(edge.source or "?")
			.. "] -- "
			.. edge.kind:upper()
			.. " --> ["
			.. edge.target
			.. "]: "
			.. (edge.predicate and vim.trim(edge.predicate) ~= "" and edge.predicate or "pending predicate")
	end
	if #graph.nodes == 0 then
		lines[#lines + 1] = "Type FROM <table> to resolve a source"
	end
	if #graph.nodes > 40 then
		lines[#lines + 1] = (#graph.nodes - 40) .. " nodes outside viewport; search/recenter to inspect"
	end
	if graph.kind ~= "schema" then
		local seen, count = {}, 0
		for _, node in ipairs(graph.nodes) do
			if node.table then
				for _, relation in ipairs(metadata.relations or {}) do
					local other = relation.source == node.table.key and relation.target
						or relation.target == node.table.key and relation.source
					if other and not shown[other] and not seen[other] then
						seen[other], count = true, count + 1
						if count <= 20 then
							lines[#lines + 1] = "[" .. node.alias .. "] .... [" .. other .. "] related, not joined"
							highlights[#highlights + 1] = { #lines - 1, "Comment" }
							objects[#lines] = sql.table(metadata, other)
						end
					end
				end
			end
		end
		if count > 20 then
			lines[#lines + 1] = (count - 20) .. " context tables hidden"
		end
	end
	for _, unresolved in ipairs(graph.unresolved or {}) do
		lines[#lines + 1] = "? " .. unresolved
	end
	return lines, highlights, objects
end

return M
