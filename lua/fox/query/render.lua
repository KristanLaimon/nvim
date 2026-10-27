local M = {}

function M.classification(item, metadata)
	local outgoing, incoming, keys, pk = 0, 0, {}, {}
	for _, relation in ipairs(metadata.relations or {}) do
		if relation.source == item.key then
			outgoing = outgoing + 1
			for _, pair in ipairs(relation.columns) do
				keys[pair.source] = true
			end
		end
		if relation.target == item.key then
			incoming = incoming + 1
		end
	end
	for _, column in ipairs(item.columns or {}) do
		if column.pk then
			pk[#pk + 1] = column.name
		end
	end
	local bridge = outgoing >= 2 and #pk >= 2
	for _, name in ipairs(pk) do
		if not keys[name] then
			bridge = false
		end
	end
	if bridge then
		return "Possible M:N bridge (composite PK consists of FK columns)"
	end
	if outgoing + incoming == 0 then
		return "Entity; no known relationships (metadata may be incomplete)"
	end
	return "Entity | " .. outgoing .. " outgoing / " .. incoming .. " incoming FK(s)"
end

function M.graph(graph, metadata, width, column_limit)
	return require("fox.query.diagram").render(graph, metadata, width, column_limit)
end

function M.explorer(metadata, selected, notes, height)
	local lines, objects = {}, {}
	for _, item in ipairs(metadata.tables or {}) do
		local key = item.key
		objects[#lines + 1] = item
		local label = metadata.engine == "mysql" and item.name or key
		lines[#lines + 1] = (selected == key and "> " or "  ") .. label .. (notes and notes[key] and " [note]" or "")
	end
	if #lines == 0 then
		lines[#lines + 1] = "No cached tables; connect/refresh"
	end
	while #lines < (height or 3) - 3 do
		lines[#lines + 1] = ""
	end
	vim.list_extend(lines, {
		"──────",
		"DATABASE EXPLORER",
		"/ ? n N: search  Enter: inspect  b: browse  gn: notes",
	})
	return lines, objects
end

function M.object_at(objects, row, column)
	local object = objects and objects[row]
	if object and object.regions then
		for _, region in ipairs(object.regions) do
			if column >= region.first and column < region.last then
				return region.item
			end
		end
		return nil
	end
	return object
end

function M.inspect(item, metadata, width)
	local legend = "PK primary / FK foreign / NN not null"
	local rows, foreign, spans = { item.key, false, legend }, {}, {}
	local flag_groups = { PK = "Identifier", FK = "DiagnosticInfo", NN = "Special" }
	for _, relation in ipairs(metadata.relations or {}) do
		if relation.source == item.key then
			for _, pair in ipairs(relation.columns) do
				foreign[pair.source] = true
			end
		end
	end
	local name_width, type_width = 4, 4
	for _, column in ipairs(item.columns or {}) do
		local name, kind = column.name:gsub("[%c]", " "), tostring(column.type):gsub("[%c]", " ")
		name_width = math.max(name_width, vim.fn.strdisplaywidth(name))
		type_width = math.max(type_width, vim.fn.strdisplaywidth(kind))
	end
	local function padded(value, cell_width)
		local text = tostring(value):gsub("[%c]", " ")
		return text .. string.rep(" ", cell_width - vim.fn.strdisplaywidth(text))
	end
	local function column_row(name, kind, primary, foreign_key, required)
		local padded_name, padded_type = padded(name, name_width), padded(kind, type_width)
		rows[#rows + 1] = padded_name
			.. "  "
			.. padded_type
			.. (primary and "  PK" or "    ")
			.. (foreign_key and "  FK" or "    ")
			.. (required and "  NN" or "    ")
		local first = #"│ " + #padded_name + 2
		spans[#spans + 1] = { #rows, "Type", first, first + #tostring(kind) }
		first = first + #padded_type + 2
		local flags = { primary, foreign_key, required }
		for index, flag in ipairs({ "PK", "FK", "NN" }) do
			if flags[index] then
				spans[#spans + 1] = { #rows, flag_groups[flag], first, first + 2 }
			end
			first = first + 4
		end
	end
	column_row("NAME", "TYPE", true, true, true)
	for _, column in ipairs(item.columns or {}) do
		column_row(column.name, column.type, column.pk, foreign[column.name], not column.nullable)
	end
	rows[#rows + 1] = false
	rows[#rows + 1] = "INDEXES / UNIQUE KEYS"
	for _, index in ipairs(item.indexes or {}) do
		rows[#rows + 1] = index.name
			.. (index.unique and " UNIQUE" or "")
			.. (index.column and " (" .. index.column .. ")" or "")
			.. (index.definition and " " .. index.definition or "")
		if index.unique then
			local first = #"│ " + #index.name + 1
			spans[#spans + 1] = { #rows, "Keyword", first, first + #"UNIQUE" }
		end
	end
	rows[#rows + 1] = false
	rows[#rows + 1] = "RELATIONSHIPS (visible metadata only)"
	rows[#rows + 1] = M.classification(item, metadata)
	local diagram, diagram_objects, diagram_highlights = M.map(metadata, item.key, 1, width or vim.o.columns - 8, 200)
	table.remove(diagram)
	local diagram_start = #rows
	vim.list_extend(rows, diagram)
	local inner = math.max(8, (width or 0) - 4)
	for _, row in ipairs(rows) do
		if row then
			inner = math.max(inner, vim.fn.strdisplaywidth(row))
		end
	end
	local border = string.rep("─", inner + 2)
	local lines = { "┌" .. border .. "┐" }
	for index, row in ipairs(rows) do
		if row == false then
			lines[#lines + 1] = "├" .. border .. "┤"
		else
			local text = row:gsub("[%c]", " ")
			if index == 3 then
				local visible = math.min(inner, math.max(8, vim.o.columns - 8))
				text = string.rep(" ", math.max(0, visible - vim.fn.strdisplaywidth(text))) .. text
			end
			lines[#lines + 1] = "│ " .. text .. string.rep(" ", inner - vim.fn.strdisplaywidth(text)) .. " │"
		end
	end
	lines[#lines + 1] = "└" .. border .. "┘"
	local highlights = {}
	for index, line in ipairs(lines) do
		local header = line:find("INDEXES /", 1, true) or line:find("RELATIONSHIPS", 1, true) or index == 2 or index == 5
		highlights[#highlights + 1] = { index - 1, header and "Title" or "Comment" }
	end
	for flag, group in pairs(flag_groups) do
		local first = assert(lines[4]:find(flag, 1, true)) - 1
		spans[#spans + 1] = { 3, group, first, first + 2 }
	end
	vim.list_extend(highlights, spans)
	for _, span in ipairs(diagram_highlights) do
		highlights[#highlights + 1] = {
			diagram_start + span[1] + 1,
			span[2],
			span[3] and span[3] + #"│ " or nil,
			span[4] and span[4] + #"│ " or nil,
		}
	end
	local objects = {}
	for row = 1, #lines do
		objects[row] = item
	end
	for row = 1, #diagram do
		local object = { regions = {} }
		for _, region in ipairs(diagram_objects[row] and diagram_objects[row].regions or {}) do
			object.regions[#object.regions + 1] = { first = region.first + 2, last = region.last + 2, item = region.item }
		end
		objects[diagram_start + row + 1] = object
	end
	return lines, highlights, objects
end

function M.neighborhood(metadata, key, depth)
	local visible, distance = {}, { [key] = 0 }
	local pending, cursor = { key }, 1
	while cursor <= #pending do
		local current = pending[cursor]
		cursor = cursor + 1
		if distance[current] < depth then
			for _, relation in ipairs(metadata.relations or {}) do
				local other
				if relation.source == current then
					other = relation.target
				elseif relation.target == current then
					other = relation.source
				end
				if other and distance[other] == nil then
					distance[other] = distance[current] + 1
					pending[#pending + 1] = other
				end
			end
		end
	end
	for _, item in ipairs(metadata.tables or {}) do
		if distance[item.key] then
			visible[#visible + 1] = item
		end
	end
	table.sort(visible, function(a, b)
		if distance[a.key] ~= distance[b.key] then
			return distance[a.key] < distance[b.key]
		end
		return a.key < b.key
	end)
	return visible
end

function M.map(metadata, key, depth, width, column_limit)
	local tables = key and M.neighborhood(metadata, key, depth or 3) or metadata.tables or {}
	local graph, visible = { kind = "schema", nodes = {}, edges = {} }, {}
	for _, item in ipairs(tables) do
		local roles = {}
		for _, column in ipairs(item.columns or {}) do
			if column.pk then
				roles[column.name] = { join = true, primary = true }
			end
		end
		for _, relation in ipairs(metadata.relations or {}) do
			if relation.source == item.key then
				for _, pair in ipairs(relation.columns) do
					roles[pair.source] = roles[pair.source] or {}
					roles[pair.source].join, roles[pair.source].foreign = true, true
				end
			end
		end
		graph.nodes[#graph.nodes + 1] =
			{ name = item.key, alias = item.key, table = item, roles = roles, focus = item.key == key }
		visible[item.key] = true
	end
	for _, relation in ipairs(metadata.relations or {}) do
		if visible[relation.source] and visible[relation.target] then
			local predicates = {}
			for _, pair in ipairs(relation.columns) do
				predicates[#predicates + 1] = tostring(pair.source) .. " = " .. tostring(pair.target)
			end
			graph.edges[#graph.edges + 1] = {
				source = relation.source,
				target = relation.target,
				kind = "FK",
				predicate = table.concat(predicates, " AND "),
			}
		end
	end
	graph.caption = (key and ("Focus " .. key .. " | depth " .. (depth or 3)) or "All visible tables")
		.. " | "
		.. #tables
		.. " nodes"
	local lines, highlights, objects = M.graph(graph, metadata, width, column_limit)
	lines[#lines + 1] = "Enter recenter | i inspect | / search | +/- depth | zh/zl pan | q back"
	return lines, objects, highlights
end

function M.value(value, is_string)
	local text = value == vim.NIL and "NULL"
		or (is_string or type(value) == "table") and vim.json.encode(value)
		or tostring(value)
	return text:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
end

function M.results(result)
	local lines, rows, headers = {}, {}, {}
	for index, set in ipairs(result.sets or {}) do
		local widths = {}
		for at, column in ipairs(set.columns) do
			widths[at] = math.max(1, math.min(32, vim.fn.strdisplaywidth(column)))
		end
		for row_index, row in ipairs(set.rows) do
			for at, value in ipairs(row) do
				widths[at] = math.min(
					32,
					math.max(widths[at] or 0, vim.fn.strdisplaywidth(M.value(value, set.strings and set.strings[row_index][at])))
				)
			end
		end
		local function format_row(row, strings)
			local values = {}
			for at, value in ipairs(row) do
				local text = M.value(value, strings and strings[at])
				if vim.fn.strdisplaywidth(text) > widths[at] then
					local suffix = strings and strings[at] and '…"' or "…"
					local limit = widths[at] - vim.fn.strdisplaywidth(suffix)
					text = vim.fn.strcharpart(text, 0, math.max(0, limit))
					while vim.fn.strdisplaywidth(text) > limit do
						text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
					end
					text = text .. suffix
				end
				values[#values + 1] = text .. string.rep(" ", widths[at] - vim.fn.strdisplaywidth(text))
			end
			return "│ " .. table.concat(values, " │ ") .. " │"
		end
		local segments = {}
		for _, width in ipairs(widths) do
			segments[#segments + 1] = string.rep("─", width + 2)
		end
		lines[#lines + 1] = "┌" .. table.concat(segments, "┬") .. "┐"
		headers[#headers + 1] = { first = #lines + 1, text = format_row(set.columns) }
		lines[#lines + 1] = format_row(set.columns)
		lines[#lines + 1] = "├" .. table.concat(segments, "┼") .. "┤"
		for row_index, row in ipairs(set.rows) do
			local strings = set.strings and set.strings[row_index]
			lines[#lines + 1] = format_row(row, strings)
			rows[#lines] = { set = set, row = row, widths = widths, strings = strings }
		end
		lines[#lines + 1] = "└" .. table.concat(segments, "┴") .. "┘"
		lines[#lines + 1] = "Result "
			.. index
			.. " | "
			.. #set.rows
			.. " loaded rows"
			.. (set.truncated and " | TRUNCATED" or "")
		lines[#lines + 1] = ""
	end
	return lines, rows, headers
end

return M
