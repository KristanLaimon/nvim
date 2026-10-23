local M = {}
local sql = require("fox.query.sql")

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

function M.explorer(metadata, filter, selected, notes)
	local lines, objects =
		{ "DATABASE EXPLORER", "Enter: inspect  b: browse  :FoxQueryNotes", "Filter: " .. (filter or ""), "" }, {}
	local candidates = {}
	for _, item in ipairs(metadata.tables or {}) do
		candidates[#candidates + 1] = item.key
	end
	if filter and filter ~= "" then
		candidates = vim.fn.matchfuzzy(candidates, filter)
	end
	for _, key in ipairs(candidates) do
		objects[#lines + 1] = sql.table(metadata, key)
		lines[#lines + 1] = (selected == key and "> " or "  ") .. key .. (notes and notes[key] and " [note]" or "")
	end
	if #candidates == 0 then
		lines[#lines + 1] = "No matching cached tables; connect/refresh"
	end
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
	local rows, foreign = { item.key, false, "COLUMNS  |  PK primary / FK foreign / NN not null" }, {}
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
	rows[#rows + 1] = padded("NAME", name_width) .. "  " .. padded("TYPE", type_width) .. "  PK  FK  NN"
	for _, column in ipairs(item.columns or {}) do
		rows[#rows + 1] = padded(column.name, name_width)
			.. "  "
			.. padded(column.type, type_width)
			.. (column.pk and "  PK" or "    ")
			.. (foreign[column.name] and "  FK" or "    ")
			.. (not column.nullable and "  NN" or "    ")
	end
	rows[#rows + 1] = false
	rows[#rows + 1] = "INDEXES / UNIQUE KEYS"
	for _, index in ipairs(item.indexes or {}) do
		rows[#rows + 1] = index.name
			.. (index.unique and " UNIQUE" or "")
			.. (index.column and " (" .. index.column .. ")" or "")
			.. (index.definition and " " .. index.definition or "")
	end
	rows[#rows + 1] = false
	rows[#rows + 1] = "RELATIONSHIPS (visible metadata only)"
	rows[#rows + 1] = M.classification(item, metadata)
	for _, relation in ipairs(metadata.relations or {}) do
		if relation.source == item.key or relation.target == item.key then
			rows[#rows + 1] = relation.source .. " -> " .. relation.target
			for _, pair in ipairs(relation.columns) do
				rows[#rows + 1] = "  " .. tostring(pair.source) .. " = " .. tostring(pair.target)
			end
		end
	end
	local inner = math.max(8, (width or 78) - 4)
	local border = string.rep("─", inner + 2)
	local lines = { "┌" .. border .. "┐" }
	for _, row in ipairs(rows) do
		if row == false then
			lines[#lines + 1] = "├" .. border .. "┤"
		else
			local text, cells = "", 0
			for at = 0, vim.fn.strchars(row) - 1 do
				local char = vim.fn.strcharpart(row, at, 1):gsub("[%c]", " ")
				local size = vim.fn.strdisplaywidth(char)
				if cells + size > inner then
					lines[#lines + 1] = "│ " .. text .. string.rep(" ", inner - cells) .. " │"
					text, cells = "", 0
				end
				text, cells = text .. char, cells + size
			end
			lines[#lines + 1] = "│ " .. text .. string.rep(" ", inner - cells) .. " │"
		end
	end
	lines[#lines + 1] = "└" .. border .. "┘"
	return lines
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
	return visible
end

function M.map(metadata, key, depth, width)
	local tables = key and M.neighborhood(metadata, key, depth or 3) or metadata.tables or {}
	local graph, visible = { kind = "schema", nodes = {}, edges = {} }, {}
	for _, item in ipairs(tables) do
		local roles = {}
		for _, column in ipairs(item.columns or {}) do
			if column.pk then
				roles[column.name] = { join = true }
			end
		end
		for _, relation in ipairs(metadata.relations or {}) do
			if relation.source == item.key then
				for _, pair in ipairs(relation.columns) do
					roles[pair.source] = { join = true }
				end
			end
		end
		graph.nodes[#graph.nodes + 1] = { name = item.key, alias = item.key, table = item, roles = roles }
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
				predicate = relation.name .. ": " .. table.concat(predicates, " AND "),
			}
		end
	end
	local lines, _, objects = M.graph(graph, metadata, width)
	lines[2] = (key and ("Focus " .. key .. " | depth " .. (depth or 3)) or "All visible tables")
		.. " | "
		.. #tables
		.. " nodes"
	lines[#lines + 1] = "Enter recenter | i inspect | / search | +/- depth | zh/zl pan | q back"
	return lines, objects
end

function M.results(result)
	local lines, rows = {}, {}
	local function display(value)
		local text = value == vim.NIL and "NULL" or type(value) == "table" and vim.json.encode(value) or tostring(value)
		return text:gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	end
	for index, set in ipairs(result.sets or {}) do
		local widths = {}
		for at, column in ipairs(set.columns) do
			widths[at] = math.max(1, math.min(32, vim.fn.strdisplaywidth(column)))
		end
		for _, row in ipairs(set.rows) do
			for at, value in ipairs(row) do
				widths[at] = math.min(32, math.max(widths[at] or 0, vim.fn.strdisplaywidth(display(value))))
			end
		end
		local function format_row(row)
			local values = {}
			for at, value in ipairs(row) do
				local text = display(value)
				if vim.fn.strdisplaywidth(text) > widths[at] then
					text = vim.fn.strcharpart(text, 0, widths[at])
				end
				while vim.fn.strdisplaywidth(text) > widths[at] do
					text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
				end
				values[#values + 1] = text .. string.rep(" ", widths[at] - vim.fn.strdisplaywidth(text))
			end
			return "| " .. table.concat(values, " | ") .. " |"
		end
		local segments = {}
		for _, width in ipairs(widths) do
			segments[#segments + 1] = string.rep("-", width + 2)
		end
		local border = "+" .. table.concat(segments, "+") .. "+"
		lines[#lines + 1] = border
		lines[#lines + 1] = format_row(set.columns)
		lines[#lines + 1] = border
		for _, row in ipairs(set.rows) do
			lines[#lines + 1] = format_row(row)
			rows[#lines] = { set = set, row = row, widths = widths }
		end
		lines[#lines + 1] = border
		lines[#lines + 1] = "Result "
			.. index
			.. " | "
			.. #set.rows
			.. " loaded rows"
			.. (set.truncated and " | TRUNCATED" or "")
		lines[#lines + 1] = ""
	end
	return lines, rows
end

return M
