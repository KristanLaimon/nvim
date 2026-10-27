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
function M.analyze(text, metadata)
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

function M.join_candidates(metadata, graph)
	local result = {}
	for _, node in ipairs(graph.nodes) do
		if node.table then
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
