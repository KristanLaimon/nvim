local M = {}

function M.render(graph, metadata, width, column_limit)
	local sql = require("fox.query.sql")
	column_limit = column_limit or 15
	local card_width = math.max(15, #graph.nodes == 1 and (width or 72) or math.floor(((width or 72) - 7) / 2))
	if graph.kind ~= "schema" then
		card_width = math.min(28, card_width)
	else
		card_width = 24
		for _, node in ipairs(graph.nodes) do
			card_width = math.max(card_width, vim.fn.strdisplaywidth(node.alias) + 6)
			for _, column in ipairs(node.table and node.table.columns or {}) do
				card_width = math.max(card_width, vim.fn.strdisplaywidth(column.name) + 11)
			end
		end
	end
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
	-- Merge up/right/down/left strokes so bends and intersecting links keep their junctions.
	local strokes = {}
	local glyphs =
		{ "│", "─", "└", "│", "│", "┌", "├", "─", "┘", "─", "┴", "┐", "┤", "┬", "┼" }
	local masks = {
		["│"] = 5,
		["─"] = 10,
		["┄"] = 10,
		["┌"] = 6,
		["┐"] = 12,
		["└"] = 3,
		["┘"] = 9,
		["├"] = 7,
		["┤"] = 13,
		["┬"] = 14,
		["┴"] = 11,
		["┼"] = 15,
	}
	local function segment(r1, c1, r2, c2, dotted)
		local dr, dc = r2 == r1 and 0 or (r2 > r1 and 1 or -1), c2 == c1 and 0 or (c2 > c1 and 1 or -1)
		local length = math.abs(r2 - r1) + math.abs(c2 - c1)
		local forward = dr == 1 and 4 or dr == -1 and 1 or dc == 1 and 2 or 8
		local backward = dr == 1 and 1 or dr == -1 and 4 or dc == 1 and 8 or 2
		for at = 0, length do
			local row, col = r1 + dr * at, c1 + dc * at
			local mask = bit.bor(at < length and forward or 0, at > 0 and backward or 0)
			strokes[row] = strokes[row] or {}
			mask = bit.bor(mask, strokes[row][col] or masks[cells[row] and cells[row][col]] or 0)
			strokes[row][col] = mask
			if mask > 0 then
				put(row, col, dotted and (mask == 2 or mask == 8 or mask == 10) and "┄" or glyphs[mask])
			end
		end
	end
	put(1, 1, graph.kind == "schema" and "SCHEMA RELATIONSHIP MAP" or "LIVE QUERY DIAGRAM")
	style(1, 1, 100, "Title")
	local state = graph.partial and "Partial SQL: resolved portions only" or "Diagram follows SQL at the cursor"
	if graph.kind == "schema" then
		state = graph.caption or "FK metadata; not query execution"
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
	local placements, focus = {}, nil
	local schema_wide = (width or 72) >= card_width * 3 + gap * 2 + 3
	if graph.kind == "schema" then
		local wide = schema_wide
		local heights, sides = {}, { 4, 4 }
		for index, node in ipairs(graph.nodes) do
			local count, keys = #(node.table and node.table.columns or {}), 0
			for _, role in pairs(node.roles) do
				if role.primary or role.foreign then
					keys = keys + 1
				end
			end
			heights[index] = math.max(1, math.min(count, math.max(column_limit, keys)))
				+ 3
				+ (count > math.max(column_limit, keys) and 1 or 0)
			if node.focus then
				focus = index
			end
		end
		local side = 1
		for index = 1, math.min(40, #graph.nodes) do
			if index ~= focus then
				placements[index] = {
					x = side == 1 and 1 or (wide and 2 or 1) * (card_width + gap) + 1,
					y = sides[side] + (not wide and focus and heights[focus] + 3 or 0),
				}
				sides[side] = sides[side] + heights[index] + 2
				side = 3 - side
			end
		end
		if focus then
			placements[focus] = {
				x = wide and card_width + gap + 1 or math.floor((card_width + gap) / 2) + 1,
				y = wide and math.max(4, math.floor((math.max(unpack(sides)) - heights[focus]) / 2)) or 4,
			}
		end
	end
	for index, node in ipairs(graph.nodes) do
		if index > 40 then
			break
		end
		local x = index % 2 == 1 and 1 or card_width + gap + 1
		if placements[index] then
			x, y = placements[index].x + 3, placements[index].y
		end
		local item, rows = node.table, {}
		local columns = {}
		for _, column in ipairs(item and item.columns or {}) do
			local roles = node.roles[column.name] or {}
			if roles.output or graph.kind == "schema" and (roles.primary or roles.foreign) then
				columns[#columns + 1] = column
			end
		end
		local selected = #columns
		for _, column in ipairs(item and item.columns or {}) do
			local roles = node.roles[column.name] or {}
			if not (roles.output or graph.kind == "schema" and (roles.primary or roles.foreign)) then
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
					text = graph.kind == "schema"
							and ((roles.primary and "PK" or "  ") .. " " .. (roles.foreign and "FK" or "  ") .. " " .. column.name)
						or flags .. " " .. column.name,
					group = roles.foreign and "DiagnosticInfo"
						or (roles.output or wildcard.output) and "String"
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
		local heading_rows = graph.kind == "schema" and 2 or 3
		local height = visible + heading_rows + 1 + (#rows > visible and 1 or 0)
		for row = y, y + height - 1 do
			put(row, x, "│" .. string.rep(" ", card_width - 2) .. "│")
			objects[row] = objects[row] or { regions = {} }
			objects[row].regions[#objects[row].regions + 1] = { first = x - 1, last = x + card_width - 1, item = item }
		end
		put(y, x, "┌" .. string.rep("─", card_width - 2) .. "┐")
		put(y + height - 1, x, "└" .. string.rep("─", card_width - 2) .. "┘")
		put(y + 1, x + 2, (node.focus and "> " or "") .. node.alias, card_width - 4)
		style(y + 1, x + 1, card_width - 2, node.focus and "Search" or item and "Title" or "DiagnosticWarn")
		if graph.kind ~= "schema" then
			put(y + 2, x + 2, node.name, card_width - 4)
			style(y + 2, x + 1, card_width - 2, "Comment")
		end
		for row = 1, visible do
			put(y + heading_rows - 1 + row, x + 2, rows[row].text, card_width - 4)
			style(y + heading_rows - 1 + row, x + 1, card_width - 2, rows[row].group)
		end
		if #rows > visible then
			put(y + height - 2, x + 2, "... " .. (#rows - visible) .. " more; Enter inspect", card_width - 4)
		end
		nodes[node.alias] = { x = x, row = y + 1, bottom = y + height - 1, item = item }
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
			local sr, tr = source.row, target.row
			local stem_target = false
			if graph.kind == "schema" then
				local center = focus and nodes[graph.nodes[focus].alias]
				if not schema_wide and center and (source == center or target == center) then
					gutter = center.x + math.floor(card_width / 2)
					local stem_source = source == center
					stem_target = target == center
					sx = stem_source and gutter or source.x < center.x and source.x + card_width - 1 or source.x
					tx = stem_target and gutter or target.x < center.x and target.x + card_width - 1 or target.x
					sr = stem_source and center.bottom or sr
					tr = stem_target and center.bottom or tr
				elseif source.x ~= target.x then
					local left = source.x < target.x and source or target
					local right = source.x < target.x and target or source
					gutter = math.floor((left.x + card_width + right.x) / 2)
					sx = source == left and source.x + card_width - 1 or source.x
					tx = target == left and target.x + card_width - 1 or target.x
				else
					gutter = source.x - 2
					sx, tx = source.x, target.x
					if source == target then
						sr, tr = source.row + 1, target.row + 2
					end
				end
			end
			local dotted = not edge.predicate or vim.trim(edge.predicate) == ""
			segment(sr, sx, sr, gutter, dotted)
			segment(sr, gutter, tr, gutter)
			segment(tr, gutter, tr, tx, dotted)
			put(tr, tx, stem_target and "^" or tx == target.x and ">" or "<")
			style(sr, math.min(sx, gutter), math.abs(sx - gutter) + 1, "DiagnosticInfo")
			style(tr, math.min(tx, gutter), math.abs(tx - gutter) + 1, "DiagnosticInfo")
			for row = math.min(sr, tr), math.max(sr, tr) do
				style(row, gutter, 1, "DiagnosticInfo")
			end
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
		if graph.kind == "schema" then
			highlights[#highlights + 1] = { #lines - 1, "DiagnosticInfo" }
		end
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
