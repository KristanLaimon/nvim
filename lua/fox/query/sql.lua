local M = {}

-- Positions are byte offsets, matching Neovim edits and selections.
function M.tokens(text, engine)
	local tokens, i, incomplete = {}, 1, false
	local function add(value, kind, first, last)
		tokens[#tokens + 1] = { value = value, upper = value:upper(), kind = kind, first = first, last = last }
	end
	while i <= #text do
		local first, char = i, text:sub(i, i)
		if char:match("%s") then
			i = i + 1
		elseif text:sub(i, i + 1) == "--" or engine and engine:match("^mysql") and char == "#" then
			i = (text:find("\n", i, true) or #text) + 1
		elseif text:sub(i, i + 1) == "/*" then
			local depth = 1
			i = i + 2
			while i <= #text and depth > 0 do
				if text:sub(i, i + 1) == "/*" then
					depth, i = depth + 1, i + 2
				elseif text:sub(i, i + 1) == "*/" then
					depth, i = depth - 1, i + 2
				else
					i = i + 1
				end
			end
			incomplete = incomplete or depth > 0
		elseif char == "'" or char == '"' or char == "`" or char == "[" then
			local quote, value, closed = char == "[" and "]" or char, {}, false
			i = i + 1
			while i <= #text do
				local next_char = text:sub(i, i)
				if next_char == quote then
					if text:sub(i + 1, i + 1) == quote then
						value[#value + 1], i = quote, i + 2
					else
						i, closed = i + 1, true
						break
					end
				elseif
					next_char == "\\"
					and char == "'"
					and (engine == "mysql" or engine == "postgres" and text:sub(first - 1, first - 1):lower() == "e")
				then
					value[#value + 1], i = text:sub(i, i + 1), i + 2
				else
					value[#value + 1], i = next_char, i + 1
				end
			end
			incomplete = incomplete or not closed
			add(table.concat(value), char == "'" and "string" or "identifier", first, i - 1)
		elseif char == "$" and text:sub(i):match("^%$[%w_]*%$") then
			local tag = text:sub(i):match("^%$[%w_]*%$")
			local finish = text:find(tag, i + #tag, true)
			incomplete = incomplete or not finish
			i = finish and finish + #tag or #text + 1
			add(text:sub(first, i - 1), "string", first, i - 1)
		elseif char:match("[%a_$]") then
			local value = text:sub(i):match("^[%w_$]+")
			i = i + #value
			add(value, "word", first, i - 1)
		else
			add(char, "symbol", i, i)
			i = i + 1
		end
	end
	return tokens, incomplete
end

function M.statements(text, engine)
	local tokens, incomplete = M.tokens(text, engine)
	if incomplete then
		return nil, "SQL contains an unfinished quote or comment; select complete SQL explicitly"
	end
	local result, first, depth = {}, 1, 0
	for _, token in ipairs(tokens) do
		if token.kind == "symbol" and token.value == "(" then
			depth = depth + 1
		end
		if token.kind == "symbol" and token.value == ")" then
			depth = depth - 1
		end
		if token.kind == "symbol" and token.value == ";" and depth == 0 then
			local chunk = text:sub(first, token.first - 1)
			if #M.tokens(chunk, engine) > 0 then
				result[#result + 1] = { sql = chunk, first = first, last = token.last }
			end
			first = token.last + 1
		end
	end
	if depth ~= 0 then
		return nil, "Unbalanced SQL parentheses; select complete SQL explicitly"
	end
	local tail = text:sub(first)
	if #M.tokens(tail, engine) > 0 then
		result[#result + 1] = { sql = tail, first = first, last = #text + 1 }
	end
	return result
end

function M.scope(text, offset, kind, selection, engine)
	if kind == "selection" then
		if not selection or selection == "" then
			return nil, "Select SQL first (character or line selection)"
		end
		return selection
	end
	if kind == "file" then
		return text
	end
	if kind == "section" then
		local first, last, position = 1, #text, 1
		local tokens = M.tokens(text, engine)
		for line in (text .. "\n"):gmatch("(.-)\n") do
			if line:match("^%s*%-%-%s*@section%s+") then
				local inside = false
				for _, token in ipairs(tokens) do
					if token.first <= position and token.last >= position and token.kind == "string" then
						inside = true
					end
				end
				if not inside then
					if position <= offset then
						first = position
					elseif position > offset then
						last = position - 1
						break
					end
				end
			end
			position = position + #line + 1
		end
		return text:sub(first, last)
	end
	local statements, err = M.statements(text, engine)
	if not statements then
		return nil, err
	end
	for _, statement in ipairs(statements) do
		if offset >= statement.first and offset <= statement.last then
			return statement.sql
		end
	end
	return nil, "No statement at the SQL cursor"
end

local reserved = {}
for word in
	("SELECT FROM WHERE JOIN LEFT RIGHT INNER OUTER FULL CROSS ON USING GROUP ORDER HAVING LIMIT OFFSET UNION AS AND OR SET NATURAL WINDOW RETURNING FOR"):gmatch(
		"%S+"
	)
do
	reserved[word] = true
end

local function identifier(token)
	return token and (token.kind == "identifier" or token.kind == "word" and not reserved[token.upper])
end

function M.table(metadata, name)
	local found
	for _, item in ipairs(metadata.tables or {}) do
		if item.key:lower() == name:lower() then
			return item
		end
		if item.name:lower() == name:lower() then
			if found then
				return nil
			end
			found = item
		end
	end
	return found
end

-- A deliberately scoped analyzer; execution is validated independently by the driver.
local function analyze_flat(text, metadata)
	metadata = metadata or { tables = {}, relations = {} }
	if #text > 128 * 1024 then
		return {
			nodes = {},
			edges = {},
			unresolved = { "Statement exceeds 128 KiB live-analysis budget; use a smaller statement" },
			partial = true,
		}
	end
	local tokens, incomplete = M.tokens(text, metadata.syntax or metadata.engine)
	local graph = { nodes = {}, edges = {}, unresolved = {}, partial = incomplete, text = text }
	local depth, clause, sources = 0, "output", {}
	for i, token in ipairs(tokens) do
		if token.kind == "symbol" and token.value == "(" then
			depth = depth + 1
		end
		if token.kind == "symbol" and token.value == ")" then
			depth = depth - 1
		end
		if token.upper == "UNION" or token.upper == "WITH" then
			graph.partial = true
		end
		if token.upper == "SELECT" and depth > 0 then
			graph.partial = true
		end
		if depth == 0 and token.kind == "word" and (token.upper == "FROM" or token.upper == "JOIN") then
			local at, name = i + 1, {}
			while identifier(tokens[at]) do
				name[#name + 1] = tokens[at].value
				if not tokens[at + 1] or tokens[at + 1].value ~= "." then
					at = at + 1
					break
				end
				at = at + 2
			end
			if #name == 0 then
				graph.partial = true
			else
				if tokens[at] and tokens[at].upper == "AS" then
					at = at + 1
				end
				local alias = identifier(tokens[at]) and tokens[at].value or name[#name]
				local table_name = table.concat(name, ".")
				local item = M.table(metadata, table_name)
				local node = {
					alias = alias,
					name = table_name,
					table = item,
					roles = {},
					first = token.first,
					joined = token.upper == "JOIN",
				}
				if not item then
					graph.unresolved[#graph.unresolved + 1] = table_name
				end
				graph.nodes[#graph.nodes + 1], sources[alias:lower()] = node, node
			end
		end
	end
	depth = 0
	for i, token in ipairs(tokens) do
		if token.kind == "symbol" and token.value == "(" then
			depth = depth + 1
		end
		if token.kind == "symbol" and token.value == ")" then
			depth = depth - 1
		end
		if depth == 0 and token.kind == "word" then
			if token.upper == "SELECT" then
				clause = "output"
			elseif token.upper == "FROM" or token.upper == "JOIN" then
				clause = "source"
			elseif token.upper == "ON" or token.upper == "USING" then
				clause = "join"
			elseif token.upper == "WHERE" or token.upper == "HAVING" then
				clause = "filter"
			elseif token.upper == "GROUP" or token.upper == "ORDER" then
				clause = "other"
			end
		end
		if clause ~= "source" and token.kind ~= "string" then
			local previous, next_token = tokens[i - 1], tokens[i + 1]
			if next_token and next_token.value == "." and tokens[i + 2] then
				local node = sources[token.value:lower()]
				if node then
					local column = tokens[i + 2].value
					local resolved = column == "*"
					for _, known in ipairs(node.table and node.table.columns or {}) do
						if known.name:lower() == column:lower() then
							column, resolved = known.name, true
							break
						end
					end
					if not resolved and node.table then
						graph.partial = true
						graph.unresolved[#graph.unresolved + 1] = node.alias .. "." .. column
					end
					node.roles[column] = node.roles[column] or {}
					node.roles[column][clause] = true
				end
			elseif
				(identifier(token) or token.value == "*")
				and not (previous and previous.value == ".")
				and not (next_token and next_token.value == "(")
			then
				local candidates, names = {}, {}
				for _, node in ipairs(graph.nodes) do
					for _, column in ipairs(node.table and node.table.columns or {}) do
						if column.name:lower() == token.value:lower() or token.value == "*" then
							candidates[node.alias] = node
							names[node.alias] = token.value == "*" and "*" or column.name
						end
					end
				end
				local count = vim.tbl_count(candidates)
				if count == 1 or token.value == "*" then
					for _, node in pairs(candidates) do
						local name = names[node.alias]
						node.roles[name] = node.roles[name] or {}
						node.roles[name][clause] = true
					end
				elseif count > 1 then
					graph.partial = true
					graph.unresolved[#graph.unresolved + 1] = "ambiguous column " .. token.value
				end
			end
		end
	end
	for i, node in ipairs(graph.nodes) do
		if node.joined then
			local finish = graph.nodes[i + 1] and graph.nodes[i + 1].first - 1 or #text
			local fragment = text:sub(node.first, finish)
			local fragment_tokens = M.tokens(fragment)
			local edge = {
				target = node.alias,
				source = graph.nodes[i - 1] and graph.nodes[i - 1].alias,
				kind = "JOIN",
			}
			local before = text:sub(1, node.first - 1)
			edge.kind = before:upper():match("([%a]+)%s+OUTER%s+$") or before:match("([%a]+)%s+$") or "INNER"
			if
				not ({ LEFT = true, RIGHT = true, INNER = true, FULL = true, CROSS = true, OUTER = true })[edge.kind:upper()]
			then
				edge.kind = "INNER"
			end
			local predicate_start, predicate_end
			for _, token in ipairs(fragment_tokens) do
				if token.kind == "word" and (token.upper == "ON" or token.upper == "USING") then
					predicate_start = token.last + 1
				end
				if
					predicate_start
					and token.kind == "word"
					and vim.tbl_contains({ "WHERE", "GROUP", "ORDER", "HAVING", "LIMIT", "UNION" }, token.upper)
				then
					predicate_end = token.first - 1
					break
				end
			end
			if predicate_start then
				edge.predicate = vim.trim(fragment:sub(predicate_start, predicate_end or #fragment)):gsub("\n", " ")
				local predicate_tokens = M.tokens(edge.predicate)
				for at, token in ipairs(predicate_tokens) do
					if
						predicate_tokens[at + 1]
						and predicate_tokens[at + 1].value == "."
						and sources[token.value:lower()]
						and token.value:lower() ~= node.alias:lower()
					then
						edge.source = sources[token.value:lower()].alias
						break
					end
				end
			end
			if edge.kind:upper() == "CROSS" then
				edge.predicate = "Cartesian product (no join predicate)"
			end
			graph.edges[#graph.edges + 1] = edge
		end
	end
	return graph
end

-- Analyze each SELECT scope separately so reused aliases do not overwrite one another.
function M.analyze(text, metadata, level)
	metadata = metadata or { tables = {}, relations = {} }
	level = level or 0
	if #text > 128 * 1024 or level >= 24 then
		local graph = analyze_flat("", metadata)
		graph.partial = true
		graph.unresolved = { "Statement exceeds live-analysis budget; use a smaller statement" }
		return graph
	end
	local tokens = M.tokens(text, metadata.syntax or metadata.engine)
	local children, parts, first, i = {}, {}, 1, 1
	local scoped = vim.tbl_extend("force", metadata, { tables = vim.list_extend({}, metadata.tables or {}) })
	local ctes = {}
	if tokens[1] and tokens[1].upper == "WITH" then
		local at = tokens[2] and tokens[2].upper == "RECURSIVE" and 3 or 2
		while identifier(tokens[at]) do
			local name, columns = tokens[at].value, {}
			at = at + 1
			if tokens[at] and tokens[at].value == "(" then
				at = at + 1
				while tokens[at] and tokens[at].value ~= ")" do
					if identifier(tokens[at]) then
						columns[#columns + 1] = tokens[at].value
					end
					at = at + 1
				end
				at = at + 1
			end
			if not tokens[at] or tokens[at].upper ~= "AS" then
				break
			end
			at = at + 1
			if tokens[at] and tokens[at].upper == "NOT" then
				at = at + 1
			end
			if tokens[at] and tokens[at].upper == "MATERIALIZED" then
				at = at + 1
			end
			if not tokens[at] or tokens[at].value ~= "(" then
				break
			end
			ctes[at] = { name = name, columns = columns }
			local depth = 1
			at = at + 1
			while tokens[at] and depth > 0 do
				if tokens[at].kind == "symbol" then
					if tokens[at].value == "(" then
						depth = depth + 1
					end
					if tokens[at].value == ")" then
						depth = depth - 1
					end
				end
				at = at + 1
			end
			if not tokens[at] or tokens[at].value ~= "," then
				break
			end
			at = at + 1
		end
	end
	while i <= #tokens do
		local token, next_token = tokens[i], tokens[i + 1]
		if
			token.value == "("
			and next_token
			and next_token.kind == "word"
			and (next_token.upper == "SELECT" or next_token.upper == "WITH")
		then
			local finish, depth = i + 1, 1
			while finish <= #tokens and depth > 0 do
				if tokens[finish].value == "(" and tokens[finish].kind == "symbol" then
					depth = depth + 1
				end
				if tokens[finish].value == ")" and tokens[finish].kind == "symbol" then
					depth = depth - 1
				end
				finish = finish + 1
			end
			if depth ~= 0 then
				break
			end
			local closing = tokens[finish - 1]
			local body = text:sub(token.last + 1, closing.first - 1)
			local cte = ctes[i]
			local child = M.analyze(body, scoped, level + 1)
			local preceding = tokens[i - 1]
			local derived = preceding
				and preceding.kind == "word"
				and (preceding.upper == "FROM" or preceding.upper == "JOIN")
			local key = cte and cte.name or "__fox_subquery_" .. (#children + 1)
			local at = finish
			if tokens[at] and tokens[at].upper == "AS" then
				at = at + 1
			end
			local source_names = {}
			for _, node in ipairs(child.nodes) do
				if not node.nested then
					source_names[#source_names + 1] = node.alias
				end
			end
			local alias = cte and cte.name
				or derived and identifier(tokens[at]) and tokens[at].value
				or (
					(
						preceding and preceding.upper == "IN" and "IN"
						or preceding and preceding.upper == "EXISTS" and "EXISTS"
						or "SELECT"
					)
					.. " from "
					.. table.concat(source_names, ", ")
					.. " #"
					.. (#children + 1)
				)
			local item = { key = key, name = cte and cte.name or alias, columns = {}, subquery = true, cte = cte ~= nil }
			local names = {}
			local function column(name, type_name)
				if not names[name] then
					item.columns[#item.columns + 1] = { name = name, type = type_name }
					names[name] = true
				end
			end
			local body_tokens, body_depth, projection = M.tokens(body, metadata.syntax or metadata.engine), 0, {}
			local function output()
				local last, previous = projection[#projection], projection[#projection - 1]
				if not last then
					return
				end
				if previous and previous.upper == "AS" then
					column(last.value)
				elseif last.value == "*" then
					for _, node in ipairs(child.nodes) do
						if not node.nested and (not previous or projection[1].value:lower() == node.alias:lower()) then
							for _, col in ipairs(node.table and node.table.columns or {}) do
								column(col.name, col.type)
							end
						end
					end
				elseif
					identifier(last)
					and (
						not previous
						or previous.value == "."
						or previous.value == ")"
						or previous.kind == "word"
						or previous.kind == "identifier"
						or previous.kind == "string"
					)
				then
					column(last.value)
				else
					column(body:sub(projection[1].first, last.last))
					child.partial = true
				end
				projection = {}
			end
			local selecting = false
			for _, entry in ipairs(body_tokens) do
				if entry.kind == "symbol" and entry.value == "(" then
					body_depth = body_depth + 1
				end
				if entry.kind == "symbol" and entry.value == ")" then
					body_depth = body_depth - 1
				end
				if body_depth == 0 and entry.kind == "word" and entry.upper == "FROM" then
					output()
					break
				end
				if body_depth == 0 and entry.upper == "SELECT" then
					selecting = true
				elseif body_depth == 0 and entry.value == "," then
					output()
				elseif selecting and not (body_depth == 0 and entry.upper == "DISTINCT") then
					projection[#projection + 1] = entry
				end
			end
			output()
			if cte then
				for index, name in ipairs(cte.columns) do
					if item.columns[index] then
						item.columns[index].name = name
					end
				end
			end
			scoped.tables[#scoped.tables + 1] = item
			children[#children + 1] =
				{ graph = child, item = item, alias = alias, derived = derived, body = body, first = token.first, cte = cte }
			if not cte then
				parts[#parts + 1] = text:sub(first, token.first - 1)
				parts[#parts + 1] = derived and key or "NULL"
			end
			first, i = closing.last + 1, finish
			if cte and tokens[i] and tokens[i].value == "," then
				first = tokens[i].last + 1
			end
		else
			i = i + 1
		end
	end
	if #children == 0 then
		return analyze_flat(text, metadata)
	end
	parts[#parts + 1] = text:sub(first)
	local graph = analyze_flat(table.concat(parts), scoped)
	graph.text = text
	for _, child in ipairs(children) do
		local wrapper
		for _, node in ipairs(graph.nodes) do
			if node.table == child.item then
				wrapper = node
			end
		end
		if not wrapper then
			wrapper = {
				alias = child.alias,
				name = child.cte and "WITH table (query only)" or "Query result",
				table = child.item,
				roles = {},
				first = child.first,
			}
			graph.nodes[#graph.nodes + 1] = wrapper
		else
			wrapper.name = child.cte and "WITH table (query only)" or "Derived table"
		end
		local prefix = wrapper.alias .. " / "
		local child_aliases = {}
		for _, node in ipairs(child.graph.nodes) do
			child_aliases[node.alias:lower()] = true
		end
		local child_tokens = M.tokens(child.body, metadata.syntax or metadata.engine)
		for index, token in ipairs(child_tokens) do
			if
				token.kind ~= "string"
				and child_tokens[index + 1]
				and child_tokens[index + 1].value == "."
				and not child_aliases[token.value:lower()]
			then
				for _, outer in ipairs(graph.nodes) do
					if not outer.nested and outer ~= wrapper and outer.alias:lower() == token.value:lower() then
						graph.edges[#graph.edges + 1] = {
							source = outer.alias,
							target = wrapper.alias,
							kind = "CORRELATED",
							predicate = "outer reference: " .. token.value .. "." .. (child_tokens[index + 2] or {}).value,
						}
					end
				end
			end
		end
		for _, node in ipairs(child.graph.nodes) do
			local old_alias = node.alias
			if not node.nested then
				graph.edges[#graph.edges + 1] = {
					source = prefix .. old_alias,
					target = wrapper.alias,
					kind = "SUBQUERY",
					predicate = "feeds " .. wrapper.alias,
				}
			end
			node.alias, node.nested = prefix .. old_alias, true
			graph.nodes[#graph.nodes + 1] = node
		end
		for _, edge in ipairs(child.graph.edges) do
			edge.source = edge.source and prefix .. edge.source
			edge.target = prefix .. edge.target
			graph.edges[#graph.edges + 1] = edge
		end
		graph.partial = graph.partial or child.graph.partial
		vim.list_extend(graph.unresolved, child.graph.unresolved)
	end
	return graph
end

function M.completion_graph(text, offset, metadata, level)
	level = level or 0
	local graph = M.analyze(text, metadata)
	if level >= 24 or #text > 128 * 1024 then
		return graph
	end
	local tokens = M.tokens(text, metadata.syntax or metadata.engine)
	for index, token in ipairs(tokens) do
		local next_token = tokens[index + 1]
		if
			token.kind == "symbol"
			and token.value == "("
			and next_token
			and (next_token.upper == "SELECT" or next_token.upper == "WITH")
			and token.last < offset
		then
			local depth, closing = 1, nil
			for at = index + 1, #tokens do
				if tokens[at].kind == "symbol" and tokens[at].value == "(" then
					depth = depth + 1
				end
				if tokens[at].kind == "symbol" and tokens[at].value == ")" then
					depth = depth - 1
				end
				if depth == 0 then
					closing = tokens[at]
					break
				end
			end
			if not closing or offset <= closing.first then
				local child = M.completion_graph(
					text:sub(token.last + 1, closing and closing.first - 1 or #text),
					offset - token.last,
					metadata,
					level + 1
				)
				local aliases = {}
				for _, node in ipairs(child.nodes) do
					if not node.nested then
						aliases[node.alias:lower()] = true
					end
				end
				for _, node in ipairs(graph.nodes) do
					if not node.nested and node.table and not node.table.subquery and not aliases[node.alias:lower()] then
						child.nodes[#child.nodes + 1] = node
					end
				end
				return child
			end
		end
	end
	return graph
end

function M.object_at(text, offset, metadata)
	for _, statement in ipairs(M.statements(text, metadata.syntax or metadata.engine) or {}) do
		if offset >= statement.first and offset <= statement.last then
			offset, text = offset - statement.first + 1, statement.sql
			break
		end
	end
	local tokens = M.tokens(text, metadata.syntax or metadata.engine)
	local graph = M.analyze(text, metadata)
	for index, token in ipairs(tokens) do
		if identifier(token) and offset >= token.first and offset <= token.last then
			local qualifier = tokens[index - 1] and tokens[index - 1].value == "." and tokens[index - 2]
			local found, found_column
			for _, node in ipairs(graph.nodes) do
				if node.table and not node.nested then
					if
						not qualifier
						and (node.alias:lower() == token.value:lower() or node.table.name:lower() == token.value:lower())
					then
						return node.table
					end
					if not qualifier or node.alias:lower() == qualifier.value:lower() then
						for _, column in ipairs(node.table.columns) do
							if column.name:lower() == token.value:lower() then
								if found then
									return nil
								end
								found, found_column = node.table, column
							end
						end
					end
				end
			end
			return found, found_column
		end
	end
end

function M.join_candidates(metadata, graph)
	local result = {}
	for _, node in ipairs(graph.nodes) do
		if node.table and not node.nested and not node.table.subquery then
			for _, relation in ipairs(metadata.relations or {}) do
				if relation.source == node.table.key or relation.target == node.table.key then
					local target = relation.source == node.table.key and relation.target or relation.source
					result[#result + 1] =
						{ node = node, relation = relation, target = target, target_table = M.table(metadata, target) }
				end
			end
		end
	end
	return result
end

function M.quote(name, engine)
	local quote = engine == "mysql" and "`" or '"'
	return quote .. name:gsub(quote, quote .. quote) .. quote
end

function M.suggest_alias(item, graph)
	local base = ""
	for word in item.name:gsub("(%l)(%u)", "%1_%2"):gmatch("[%a%d]+") do
		base = base .. word:sub(1, 1):lower()
	end
	if not base:match("^[%a]") then
		base = "t"
	end
	local used = {}
	for _, node in ipairs(graph.nodes) do
		used[node.alias:lower()] = true
	end
	local alias, suffix = base, 2
	while used[alias] or reserved[alias:upper()] do
		alias, suffix = base .. suffix, suffix + 1
	end
	return alias
end

function M.join_label(candidate)
	local pairs = {}
	for _, pair in ipairs(candidate.relation.columns) do
		local own, other = pair.source, pair.target
		if candidate.relation.source ~= candidate.node.table.key then
			own, other = other, own
		end
		pairs[#pairs + 1] = candidate.node.alias
			.. "."
			.. tostring(own)
			.. " = "
			.. candidate.target
			.. "."
			.. tostring(other)
	end
	return table.concat(pairs, " AND ")
end

-- SQLite's identifier keywords: https://www.sqlite.org/lang_keywords.html
local sqlite_keywords = {}
for word in
	([[ABORT ACTION ADD AFTER ALL ALTER ALWAYS ANALYZE AND AS ASC ATTACH AUTOINCREMENT
BEFORE BEGIN BETWEEN BY CASCADE CASE CAST CHECK COLLATE COLUMN COMMIT CONFLICT CONSTRAINT
CREATE CROSS CURRENT CURRENT_DATE CURRENT_TIME CURRENT_TIMESTAMP DATABASE DEFAULT DEFERRABLE
DEFERRED DELETE DESC DETACH DISTINCT DO DROP EACH ELSE END ESCAPE EXCEPT EXCLUDE EXCLUSIVE
EXISTS EXPLAIN FAIL FILTER FIRST FOLLOWING FOR FOREIGN FROM FULL GENERATED GLOB GROUP GROUPS
HAVING IF IGNORE IMMEDIATE IN INDEX INDEXED INITIALLY INNER INSERT INSTEAD INTERSECT INTO IS
ISNULL JOIN KEY LAST LEFT LIKE LIMIT MATCH MATERIALIZED NATURAL NO NOT NOTHING NOTNULL NULL
NULLS OF OFFSET ON OR ORDER OTHERS OUTER OVER PARTITION PLAN PRAGMA PRECEDING PRIMARY QUERY
RAISE RANGE RECURSIVE REFERENCES REGEXP REINDEX RELEASE RENAME REPLACE RESTRICT RETURNING RIGHT
ROLLBACK ROW ROWS SAVEPOINT SELECT SET TABLE TEMP TEMPORARY THEN TIES TO TRANSACTION TRIGGER
UNBOUNDED UNION UNIQUE UPDATE USING VACUUM VALUES VIEW VIRTUAL WHEN WHERE WINDOW WITH WITHOUT]]):gmatch("%S+")
do
	sqlite_keywords[word] = true
end

-- PostgreSQL folds unquoted names to lowercase; retain quotes for mixed case and keywords.
local postgres_keywords = {}
for word in
	([[ALL ANALYSE ANALYZE AND ANY ARRAY AS ASC ASYMMETRIC AUTHORIZATION BETWEEN BIGINT BINARY
BIT BOOLEAN BOTH CASE CAST CHAR CHARACTER CHECK COALESCE COLLATE COLLATION COLUMN CONCURRENTLY
CONSTRAINT CREATE CROSS CURRENT_CATALOG CURRENT_DATE CURRENT_ROLE CURRENT_SCHEMA CURRENT_TIME
CURRENT_TIMESTAMP CURRENT_USER DEC DECIMAL DEFAULT DEFERRABLE DESC DISTINCT DO ELSE END EXCEPT
EXISTS EXTRACT FALSE FETCH FLOAT FOR FOREIGN FREEZE FROM FULL GRANT GREATEST GROUP GROUPING
HAVING ILIKE IN INITIALLY INNER INOUT INT INTEGER INTERSECT INTERVAL INTO IS ISNULL JOIN JSON_ARRAY
JSON_ARRAYAGG JSON_OBJECT JSON_OBJECTAGG LATERAL LEADING LEAST LEFT LIKE LIMIT LOCALTIME
LOCALTIMESTAMP NATIONAL NATURAL NCHAR NONE NORMALIZE NOT NOTNULL NULL NULLIF NUMERIC OFFSET ON
ONLY OR ORDER OUT OUTER OVERLAPS OVERLAY PLACING POSITION PRECISION PRIMARY REAL REFERENCES
RETURNING RIGHT ROW SELECT SESSION_USER SETOF SIMILAR SMALLINT SOME SUBSTRING SYMMETRIC SYSTEM_USER
TABLE TABLESAMPLE THEN TIME TIMESTAMP TO TRAILING TREAT TRIM TRUE UNION UNIQUE USER USING VALUES
VARCHAR VARIADIC VERBOSE WHEN WHERE WINDOW WITH XMLATTRIBUTES XMLCONCAT XMLELEMENT XMLEXISTS
XMLFOREST XMLNAMESPACES XMLPARSE XMLPI XMLROOT XMLSERIALIZE XMLTABLE]]):gmatch("%S+")
do
	postgres_keywords[word] = true
end

local function join_identifier(name, engine)
	if engine == "postgres" and name:match("^[a-z_][a-z0-9_]*$") and not postgres_keywords[name:upper()] then
		return name
	end
	if
		(engine == "sqlite" or engine == "mysql")
		and name:match("^[%a_][%w_]*$")
		and not sqlite_keywords[name:upper()]
	then
		return name
	end
	return M.quote(name, engine)
end

function M.join_sql(candidate, target_alias, kind, engine)
	if not target_alias:match("^[%a_][%w_]*$") then
		return nil, "Use a simple SQL alias"
	end
	if kind ~= "INNER" and kind ~= "LEFT" then
		return nil, "Choose INNER or LEFT"
	end
	local relation, predicates, qualified = candidate.relation, {}, {}
	if not candidate.target_table then
		return nil, "Target table is not in the selected metadata; refresh its schema first"
	end
	if candidate.target_table.schema then
		qualified[#qualified + 1] = join_identifier(candidate.target_table.schema, engine)
	end
	qualified[#qualified + 1] = join_identifier(candidate.target_table.name, engine)
	for _, pair in ipairs(relation.columns) do
		if type(pair.source) ~= "string" or type(pair.target) ~= "string" then
			return nil, "Foreign-key mapping is incomplete; refresh or inspect the target table"
		end
		local own, other = pair.source, pair.target
		if relation.source ~= candidate.node.table.key then
			own, other = other, own
		end
		predicates[#predicates + 1] = join_identifier(candidate.node.alias, engine)
			.. "."
			.. join_identifier(own, engine)
			.. " = "
			.. join_identifier(target_alias, engine)
			.. "."
			.. join_identifier(other, engine)
	end
	if #predicates == 0 then
		return nil, "Relationship has no key mapping"
	end
	return kind
		.. " JOIN "
		.. table.concat(qualified, ".")
		.. " AS "
		.. join_identifier(target_alias, engine)
		.. " ON "
		.. table.concat(predicates, " AND ")
end

return M
