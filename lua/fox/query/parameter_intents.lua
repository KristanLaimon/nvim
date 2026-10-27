local M = {}

local clauses = {}
for word in
	("SELECT FROM WHERE JOIN ON USING HAVING GROUP ORDER LIMIT OFFSET FETCH RETURNING SET VALUES WHEN THEN ELSE INTO WITH"):gmatch(
		"%S+"
	)
do
	clauses[word] = true
end
local source_stops =
	{ LEFT = true, RIGHT = true, INNER = true, OUTER = true, FULL = true, CROSS = true, NATURAL = true }

local function normalized(token)
	return { token.kind, token.kind == "word" and token.upper or token.value }
end

-- Split at SQL expression boundaries, retaining parent expressions for function/list arguments.
function M.describe(tokens, bindings)
	local root, stack = { items = {} }, {}
	local current = root
	for index, token in ipairs(tokens) do
		if token.kind == "symbol" and token.value == "(" then
			local child = { items = {} }
			current.items[#current.items + 1] = child
			stack[#stack + 1], current = current, child
		elseif token.kind == "symbol" and token.value == ")" then
			current = table.remove(stack) or root
		else
			current.items[#current.items + 1] = { token = token, index = index }
		end
	end
	local result, sources, pending = {}, {}, { { node = root, parents = {}, source = "" } }
	local function walk(node, parents, source, argument_names, inherited_clause)
		local branches, branch = {}, {}
		for _, item in ipairs(node.items) do
			if item.token and item.token.kind == "word" and item.token.upper == "UNION" then
				branches[#branches + 1], branch = branch, {}
			else
				branch[#branch + 1] = item
			end
		end
		branches[#branches + 1] = branch
		for _, items in ipairs(branches) do
			local own_source, columns = {}, nil
			for index, item in ipairs(items) do
				if
					item.token
					and item.token.kind == "word"
					and (item.token.upper == "FROM" or item.token.upper == "INTO" or item.token.upper == "UPDATE")
				then
					local at = index + 1
					while items[at] and items[at].token do
						local token = items[at].token
						if token.kind == "word" and (clauses[token.upper] or source_stops[token.upper]) or token.value == "," then
							break
						end
						if not bindings[items[at].index] then
							own_source[#own_source + 1] = normalized(token)
						end
						at = at + 1
					end
					if item.token.upper == "INTO" and items[at] and not items[at].token then
						columns = { {} }
						for _, column in ipairs(items[at].items) do
							if column.token and column.token.value == "," then
								columns[#columns + 1] = {}
							elseif column.token then
								local name = columns[#columns]
								name[#name + 1] = normalized(column.token)
							end
						end
					end
					break
				end
			end
			local scope = #own_source > 0 and vim.json.encode(own_source) or source
			if node == root then
				sources[#sources + 1] = scope
			end
			local clause, segment, between, argument, cases = inherited_clause or "EXPRESSION", {}, false, 1, {}
			local function flush()
				if #segment == 0 then
					return
				end
				local case = cases[#cases]
				local shape = {
					clause,
					argument_names and argument_names[argument] or false,
					case and case.head or false,
					clause == "THEN" and case and case.guard or false,
				}
				for _, item in ipairs(segment) do
					if not item.token then
						shape[#shape + 1] = "()"
					elseif not bindings[item.index] then
						shape[#shape + 1] = normalized(item.token)
					end
				end
				local context = { parents, scope, shape }
				if clause == "WHEN" and case then
					case.guard = shape
				end
				for _, item in ipairs(segment) do
					if not item.token then
						local first = item.items[1] and item.items[1].token
						local grouping = #segment == 1
							and not (first and first.kind == "word" and (first.upper == "SELECT" or first.upper == "WITH"))
						pending[#pending + 1] = {
							node = item,
							parents = grouping and parents or context,
							source = scope,
							names = clause == "VALUES" and columns or nil,
							clause = grouping and clause or nil,
						}
					elseif bindings[item.index] then
						result[item.index] = { context = vim.json.encode(context) }
					end
				end
				segment = {}
			end
			for index, item in ipairs(items) do
				local token = item.token
				local following = items[index + 1] and items[index + 1].token
				if token and token.kind == "word" and token.upper == "CASE" then
					cases[#cases + 1] = { head = {}, capturing = true, clause = clause }
				end
				local case = cases[#cases]
				if token and token.kind == "word" and token.upper == "WHEN" and case then
					case.capturing = false
				elseif token and case and case.capturing then
					case.head[#case.head + 1] = normalized(token)
				end
				if token and token.kind == "word" and token.upper == "END" and case then
					flush()
					clause = table.remove(cases).clause
				elseif
					token
					and token.kind == "word"
					and source_stops[token.upper]
					and following
					and (following.upper == "JOIN" or source_stops[following.upper])
				then
					flush()
				elseif token and token.kind == "word" and clauses[token.upper] then
					flush()
					clause, between = token.upper, false
				elseif
					token and token.kind == "word" and (token.upper == "OR" or token.upper == "AND" and not between)
					or token and token.kind == "symbol" and token.value == ","
				then
					flush()
					if token.value == "," then
						argument = argument + 1
					end
				else
					segment[#segment + 1] = item
					if token and token.kind == "word" and token.upper == "BETWEEN" then
						between = true
					elseif token and token.kind == "word" and token.upper == "AND" then
						between = false
					end
				end
			end
			flush()
		end
	end
	while #pending > 0 do
		local task = table.remove(pending)
		walk(task.node, task.parents, task.source, task.names, task.clause)
	end
	table.sort(sources)
	return result, vim.json.encode(sources)
end

return M
