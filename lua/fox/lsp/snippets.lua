-- Local snippet catalog and custom overrides, using Blink's native snippet engine.
local M = {}
local function strings(value)
	if type(value) ~= "table" or not vim.islist(value) then
		return false
	end
	for _, item in ipairs(value) do
		if type(item) ~= "string" then
			return false
		end
	end
	return true
end
-- Metadata and malformed individual entries must never crash the completion menu.
function M.normalize(entries)
	local result = {}
	if type(entries) ~= "table" then
		return result
	end
	for _, name in ipairs(vim.tbl_keys(entries)) do
		local entry = entries[name]
		if type(name) == "string" and type(entry) == "table" and (type(entry.body) == "string" or strings(entry.body)) then
			local prefixes = entry.prefix == nil and { name }
				or type(entry.prefix) == "string" and { entry.prefix }
				or entry.prefix
			local description = entry.description or name
			if strings(description) then
				description = table.concat(description)
			end
			if type(description) ~= "string" then
				description = name
			end
			if strings(prefixes) then
				for _, prefix in ipairs(prefixes) do
					if prefix ~= "" then
						result[#result + 1] = { prefix = prefix, body = entry.body, description = description }
					end
				end
			end
		end
	end
	-- Stable ordering, including duplicate prefixes supplied by different snippets.
	table.sort(result, function(a, b)
		if a.prefix ~= b.prefix then
			return a.prefix < b.prefix
		end
		return a.description < b.description
	end)
	return result
end
local function engine(options)
	local native = require("blink.cmp.sources.snippets.default").new(options)
	local warned = {}
	native.registry.get_snippets_for_ft = function(registry, ft)
		local result = {}
		for _, path in ipairs(registry.registry[ft] or {}) do
			local file = io.open(path, "r")
			if file then
				local contents = file:read("*a")
				file:close()
				local ok, data = pcall(vim.json.decode, contents)
				if ok and type(data) == "table" then
					vim.list_extend(result, M.normalize(data))
				elseif not warned[path] then
					warned[path] = true
					vim.notify(
						"Cannot read snippets in " .. path .. ": " .. tostring(data),
						vim.log.levels.ERROR,
						{ title = "FOX Snippets" }
					)
				end
			end
		end
		return result
	end
	return native
end
function M.new(opts)
	local self = setmetatable({ options = vim.deepcopy(opts or {}) }, { __index = M })
	self:reload()
	return self
end
function M:reload()
	local custom = vim.deepcopy(self.options)
	custom.friendly_snippets = false
	custom.search_paths = custom.search_paths or { vim.fn.stdpath("config") .. "/config/snippets" }
	-- Schema files are metadata, not snippet definitions.
	local filter = custom.filter_snippets
	custom.filter_snippets = function(ft, path)
		return not path:match("schema%.json$") and (not filter or filter(ft, path))
	end
	local defaults = vim.deepcopy(custom)
	defaults.search_paths = { self.options.catalog_path or vim.fn.stdpath("config") .. "/config/snippet_catalog" }
	self.custom, self.defaults = engine(custom), engine(defaults)
end
function M:get_completions(context, callback)
	self.custom:get_completions(context, function(custom)
		local overridden = {}
		for _, item in ipairs(custom.items) do
			overridden[item.label] = true
		end
		self.defaults:get_completions(context, function(defaults)
			for _, item in ipairs(defaults.items) do
				if not overridden[item.label] then
					custom.items[#custom.items + 1] = item
				end
			end
			callback(custom)
		end)
	end)
end
function M:resolve(item, callback)
	return self.custom:resolve(item, callback)
end
return M
