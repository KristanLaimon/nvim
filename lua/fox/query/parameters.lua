local M = {}

local postgres_value_keywords =
	" SELECT WHERE AND OR WHEN THEN ELSE LIMIT OFFSET BY AS DISTINCT BETWEEN LIKE ILIKE IS IN "

local function identifier(token)
	return token and (token.kind == "word" or token.kind == "identifier")
end
local sql = require("fox.query.sql")
local storage = require("fox.query.storage")

-- Match the worker's PostgreSQL JSON-operator rules before assigning binding positions.
local function describe_tokens(tokens, engine, identity_tokens)
	local identity, bindings, scopes, serial = {}, {}, { 0 }, 0
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
			local label, key = nil, "position:"
			local column, dot, qualifier = tokens[index - 2], tokens[index - 3], tokens[index - 4]
			if previous and previous.kind == "symbol" and previous.value == "=" and identifier(column) then
				label = column.value
			end
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
			bindings[index] = { label = label, legacy_key = key }
		end
	end
	local contexts, source = require("fox.query.parameter_intents").describe(tokens, bindings)
	local groups, order, seen, counts, from_count = {}, {}, {}, {}, 0
	for index, token in ipairs(tokens) do
		local binding = bindings[index]
		if binding then
			local intent = contexts[index].context
			local clause = contexts[index].clause
			if clause == "FROM" then
				from_count = from_count + 1
			end
			counts[intent] = (counts[intent] or 0) + 1
			local shared = binding.legacy_key ~= "position:"
			local key = "intent:" .. vim.fn.sha256(intent) .. ":" .. (shared and binding.legacy_key or counts[intent])
			if not seen[key] then
				groups[#groups + 1] = {
					key = key,
					intent = intent,
					legacy_key = shared and binding.legacy_key or "position:" .. (#order + 1),
					label = binding.label or (clause == "FROM" and "From #" .. from_count or "Parameter " .. (#order + 1)),
					clause = clause,
					positions = {},
				}
				seen[key] = #groups
			end
			local group = groups[seen[key]]
			group.positions[#group.positions + 1] = token.first
			order[#order + 1] = seen[key]
		end
	end
	if identity_tokens then
		identity = {}
		for _, token in ipairs(identity_tokens) do
			identity[#identity + 1] = { token.kind, token.value }
		end
	end
	return { id = vim.fn.sha256(vim.json.encode(identity)), source = source, groups = groups, order = order }
end

function M.describe(query, engine)
	local tokens, incomplete, legacy = sql.tokens(query, engine)
	if incomplete then
		return nil
	end
	local description = describe_tokens(tokens, engine, legacy)
	if legacy then
		local previous = describe_tokens(legacy, engine)
		local positions = {}
		for _, group in ipairs(previous.groups) do
			for _, position in ipairs(group.positions) do
				positions[position] = group
			end
		end
		for _, group in ipairs(description.groups) do
			local old = positions[group.positions[1]]
			if old then
				group.previous_key, group.previous_legacy_key = old.key, old.legacy_key
			end
		end
	end
	return description
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

local tracked = {}

function M.attach(buf)
	if tracked[buf] then
		return
	end
	local tracker = { edits = {} }
	tracked[buf] = tracker
	vim.api.nvim_buf_attach(buf, false, {
		on_bytes = function(_, _, _, _, _, first, _, _, old_size, _, _, new_size)
			tracker.edits[#tracker.edits + 1] = { first = first + 1, old_size = old_size, new_size = new_size }
			if not tracker.scheduled then
				tracker.scheduled = true
				vim.schedule(function()
					tracker.scheduled = false
					if tracked[buf] == tracker and vim.api.nvim_buf_is_loaded(buf) then
						local ok, err = M.sync(vim.b[buf].fox_query_root, vim.b[buf].fox_query_document)
						if not ok then
							vim.notify(err, vim.log.levels.ERROR)
						end
					end
				end)
			end
		end,
		on_detach = function()
			tracked[buf] = nil
		end,
	})
end

local function descriptions(text, engine)
	local statements = sql.statements(text, engine)
	if not statements then
		return nil
	end
	local result = {}
	for _, statement in ipairs(statements) do
		local description = M.describe(statement.sql, engine)
		local tokens = sql.tokens(statement.sql, engine)
		description.first = statement.first + tokens[1].first - 1
		description.last = statement.first + tokens[#tokens].last - 1
		for _, group in ipairs(description.groups) do
			for index, position in ipairs(group.positions) do
				group.positions[index] = statement.first + position - 1
			end
		end
		result[description.id] = description
	end
	return result
end

local function saved_value(values, group)
	if not group.dropped then
		return values[group.key]
			or values[group.previous_key]
			or values[group.legacy_key]
			or values[group.previous_legacy_key]
	end
end

local function score(before, after)
	local intents, positions, common, surviving = {}, {}, 0, 0
	for _, group in ipairs(before.groups) do
		intents[group.intent] = true
		for _, position in ipairs(group.surviving or group.positions) do
			positions[position] = true
		end
	end
	for _, group in ipairs(after.groups) do
		if intents[group.intent] then
			common = common + 1
		end
		for _, position in ipairs(group.surviving or group.positions) do
			if positions[position] then
				surviving = surviving + 1
			end
		end
	end
	return surviving * 100 + common * 10 + (before.source == after.source and 1 or 0)
end

local function best(description, candidates)
	local chosen, highest = nil, 0
	for id, candidate in pairs(candidates) do
		local rank = score(description, candidate)
		if rank > highest then
			chosen, highest = id, rank
		elseif rank == highest then
			chosen = nil
		end
	end
	return chosen
end

local function carry(before, after, saved)
	local values, positions, counts, used = {}, {}, {}, {}
	for _, group in ipairs(before.groups) do
		counts[group.intent] = (counts[group.intent] or 0) + 1
		for _, position in ipairs(group.surviving) do
			positions[position] = group
		end
	end
	local new_counts = {}
	for _, group in ipairs(after.groups) do
		new_counts[group.intent] = (new_counts[group.intent] or 0) + 1
	end
	for _, group in ipairs(after.groups) do
		for _, position in ipairs(group.positions) do
			local original = positions[position]
			-- A surviving token keeps its value while the surrounding SQL is still being typed.
			if original and not original.dropped then
				values[group.key], used[original.key] = saved_value(saved, original), true
			end
		end
	end
	for _, group in ipairs(after.groups) do
		-- A rewritten list with a different slot count has no safe positional fallback.
		if values[group.key] == nil and counts[group.intent] == new_counts[group.intent] then
			for _, original in ipairs(before.groups) do
				if
					original.intent == group.intent
					and (original.key == group.key or counts[group.intent] == 1)
					and not used[original.key]
				then
					values[group.key], used[original.key] = saved_value(saved, original), true
				end
			end
		end
	end
	return values
end

function M.sync(root, document)
	local buf = vim.fn.bufnr(storage.path(root, document))
	if buf == -1 or not vim.api.nvim_buf_is_loaded(buf) then
		return true
	end
	local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
	local previous = vim.b[buf].fox_query_parameter_text
	M.attach(buf)
	local tracker = tracked[buf]
	if previous == text and #tracker.edits == 0 then
		return true
	end
	local engine = require("fox.langs.sql.dialect").read(buf)
	local before, after = descriptions(previous or text, engine), descriptions(text, engine)
	if not before then
		vim.b[buf].fox_query_parameter_text, tracker.edits = text, {}
		return true
	end
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	local saved = data[document] or {}
	local original = vim.deepcopy(saved)
	for id, description in pairs(before) do
		for _, group in ipairs(description.groups) do
			group.surviving = {}
			local dropped = 0
			for _, initial in ipairs(group.positions) do
				local position, first, last, hard = initial, description.first, description.last, false
				for _, edit in ipairs(tracker.edits) do
					local finish, delta = edit.first + edit.old_size, edit.new_size - edit.old_size
					if position and position >= edit.first and position < finish then
						local whole = edit.first <= first and finish > last
						-- Whole-statement cuts can be moves; a deleted individual slot must stay forgotten.
						hard = not whole and (edit.old_size == 1 or edit.new_size == 0)
						position = nil
					elseif position and position >= finish then
						position = position + delta
					end
					first = first >= finish and first + delta or math.min(first, edit.first)
					last = last >= finish and last + delta or math.min(last, edit.first)
				end
				if position then
					group.surviving[#group.surviving + 1] = position
				end
				dropped = dropped + (hard and 1 or 0)
			end
			group.dropped = dropped == #group.positions
			if group.dropped and saved[id] then
				for _, key in ipairs({ group.key, group.legacy_key, group.previous_key, group.previous_legacy_key }) do
					saved[id][key] = nil
				end
			end
		end
	end
	if after then
		local old, new, matches = vim.tbl_extend("force", {}, before), vim.tbl_extend("force", {}, after), {}
		for id in pairs(after) do
			if old[id] then
				matches[id], old[id], new[id] = id, nil, nil
			end
		end
		local changed = true
		while changed do
			changed = false
			for id, description in pairs(old) do
				local candidate = best(description, new)
				if candidate and best(new[candidate], old) == id then
					matches[candidate], old[id], new[candidate], changed = id, nil, nil, true
				end
			end
		end
		local old_id, new_id = next(old), next(new)
		if old_id and new_id and not next(old, old_id) and not next(new, new_id) then
			matches[new_id] = old_id
		end
		local updates = {}
		for id, previous_id in pairs(matches) do
			updates[id] = carry(before[previous_id], after[id], saved[previous_id] or {})
		end
		for _, previous_id in pairs(matches) do
			saved[previous_id] = nil
		end
		for id, values in pairs(updates) do
			saved[id] = next(values) and values or nil
		end
	end
	if not vim.deep_equal(saved, original) then
		data[document] = next(saved) and saved or nil
		local ok, save_err = storage.save(root, "private/parameters.json", data)
		if not ok then
			return nil, save_err
		end
	end
	if after then
		vim.b[buf].fox_query_parameter_text, tracker.edits = text, {}
	end
	return true
end

function M.values(root, document, description)
	local ok, sync_err = M.sync(root, document)
	if not ok then
		return nil, sync_err
	end
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	local saved, values = data[document] and data[document][description.id] or {}, {}
	for _, group in ipairs(description.groups) do
		values[group.key] = saved_value(saved, group)
	end
	return values
end

function M.set(root, document, description, key, value)
	local ok, sync_err = M.sync(root, document)
	if not ok then
		return nil, sync_err
	end
	local data, err = M.load(root)
	if not data then
		return nil, err
	end
	data[document] = data[document] or {}
	local saved, values = data[document][description.id] or {}, {}
	for _, group in ipairs(description.groups) do
		values[group.key] = saved_value(saved, group)
	end
	values[key] = value
	data[document][description.id] = values
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
	local ok, sync_err = M.sync(root, document)
	if not ok then
		return nil, sync_err
	end
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
