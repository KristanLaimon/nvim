local M = {}

local postgres_value_keywords =
	" SELECT WHERE AND OR WHEN THEN ELSE LIMIT OFFSET BY AS DISTINCT BETWEEN LIKE ILIKE IS IN "

local function identifier(token)
	return token and (token.kind == "word" or token.kind == "identifier")
end
local sql = require("fox.query.sql")
local storage = require("fox.query.storage")

-- Match the worker's PostgreSQL JSON-operator rules before assigning binding positions.
function M.describe(query, engine)
	local tokens, incomplete = sql.tokens(query, engine)
	if incomplete then
		return nil
	end
	local identity, groups, order, seen, scopes, serial = {}, {}, {}, {}, { 0 }, 0
	for index, token in ipairs(tokens) do
		identity[#identity + 1] = { token.kind, token.value }
		if token.value == "(" and token.kind == "symbol" then
			serial = serial + 1
			scopes[#scopes + 1] = serial
		elseif token.value == ")" and token.kind == "symbol" then
			table.remove(scopes)
		elseif token.kind == "word" and token.upper == "UNION" then
			serial = serial + 1
			scopes[#scopes] = serial
		end
		local previous, following = tokens[index - 1], tokens[index + 1]
		local operator = engine == "postgres"
			and (
				following and (following.value == "|" or following.value == "&")
				or previous
					and (previous.kind == "identifier" or previous.kind == "string" or previous.value == ")" or previous.value == "]" or previous.kind == "word" and not postgres_value_keywords:find(
						" " .. previous.upper .. " ",
						1,
						true
					))
			)
		if token.kind == "symbol" and token.value == "?" and not operator then
			local label, key = "?" .. (#order + 1), "position:" .. (#order + 1)
			local column, dot, qualifier = tokens[index - 2], tokens[index - 3], tokens[index - 4]
			if
				previous
				and previous.value == "="
				and identifier(column)
				and dot
				and dot.kind == "symbol"
				and dot.value == "."
				and identifier(qualifier)
			then
				local parts, names, at = {}, {}, index - 2
				while identifier(tokens[at]) do
					table.insert(parts, 1, { tokens[at].kind, tokens[at].value })
					table.insert(names, 1, tokens[at].value)
					if not tokens[at - 1] or tokens[at - 1].kind ~= "symbol" or tokens[at - 1].value ~= "." then
						break
					end
					at = at - 2
				end
				label = table.concat(names, ".")
				key = table.concat(scopes, "/") .. ":" .. vim.json.encode(parts)
			end
			if not seen[key] then
				groups[#groups + 1] = { key = key, label = label }
				seen[key] = #groups
			end
			order[#order + 1] = seen[key]
		end
	end
	-- shortcut: content identifies statements; use stable statement IDs if values must survive SQL edits.
	return { id = vim.fn.sha256(vim.json.encode(identity)), groups = groups, order = order }
end

function M.load(root)
	local data, err = storage.load(root, "private/parameters.json", {})
	if not data then
		return nil, err
	end
	for document, statements in pairs(data) do
		if type(document) ~= "string" or type(statements) ~= "table" then
			return nil, "Invalid saved Query parameters; original file preserved"
		end
		for _, values in pairs(statements) do
			if type(values) ~= "table" then
				return nil, "Invalid saved Query parameters; original file preserved"
			end
			for _, value in pairs(values) do
				if type(value) ~= "string" then
					return nil, "Invalid saved Query value; original file preserved"
				end
			end
		end
	end
	return data
end

function M.values(root, document, description)
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	return data[document] and data[document][description.id] or {}
end

function M.set(root, document, description, key, value)
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	data[document] = data[document] or {}
	data[document][description.id] = data[document][description.id] or {}
	data[document][description.id][key] = value
	return storage.save(root, "private/parameters.json", data)
end

function M.bound(root, document, query, engine)
	local statements, err = sql.statements(query, engine)
	if not statements then
		return nil, err
	end
	local result = {}
	for _, statement in ipairs(statements) do
		local description = M.describe(statement.sql, engine)
		local values, load_err = {}, nil
		if #description.order > 0 then
			values, load_err = M.values(root, document, description)
		end
		if not values then
			return nil, load_err
		end
		for _, index in ipairs(description.order) do
			local value = values[description.groups[index].key]
			if value == nil then
				return nil, "Set " .. description.groups[index].label .. " in Parameters, then run again"
			end
			result[#result + 1] = value == "NULL" and vim.NIL or value:gsub("^text:", "")
		end
	end
	return result
end

function M.prune(root, document, text, engine)
	local statements = sql.statements(text, engine)
	if not statements then
		return true
	end
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	if not data[document] then
		return true
	end
	local retained = {}
	for _, statement in ipairs(statements) do
		local description = M.describe(statement.sql, engine)
		retained[description.id] = data[document][description.id]
	end
	data[document] = next(retained) and retained or nil
	return storage.save(root, "private/parameters.json", data)
end

function M.relocate(root, source, destination)
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	local updated = vim.deepcopy(data)
	for document, values in pairs(data) do
		if document == source or document:sub(1, #source + 1) == source .. "/" then
			updated[document] = nil
			if destination then
				updated[destination .. document:sub(#source + 1)] = values
			end
		end
	end
	if vim.deep_equal(data, updated) then
		return true
	end
	return storage.save(root, "private/parameters.json", updated)
end

return M
