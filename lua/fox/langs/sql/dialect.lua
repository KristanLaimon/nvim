local M = {}
local storage = require("fox.query.storage")
M.names = { mysql = "MySQL", postgres = "PostgreSQL", sqlite = "SQLite" }

function M.read(buf)
	local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
	local name = line:match("^%s*%-%-%s*foxquery:%s*dialect=(%w+)%s*$")
	return M.names[name] and name or nil
end

function M.options(root)
	local settings, err = storage.load(root, "settings.json", {})
	if not settings then
		return nil, err
	end
	local profiles, profile_err = storage.profiles(root)
	if not profiles then
		return nil, profile_err
	end
	local engines = {}
	for _, profile in ipairs(profiles) do
		engines[profile.engine] = true
	end
	local preferred = vim.tbl_count(engines) == 1 and next(engines) or settings.sql_dialect
	if not M.names[preferred] then
		preferred = "sqlite"
	end
	local options = { preferred }
	for _, name in ipairs({ "mysql", "postgres", "sqlite" }) do
		if name ~= preferred then
			options[#options + 1] = name
		end
	end
	return options
end

function M.set(buf, name, root)
	if not M.names[name] then
		return nil, "Choose mysql, postgres, or sqlite"
	end
	local settings, err = storage.load(root, "settings.json", {})
	if not settings then
		return nil, err
	end
	settings.sql_dialect = name
	local saved, save_err = storage.save(root, "settings.json", settings)
	if not saved then
		return nil, save_err
	end
	local had_header = M.read(buf) ~= nil
	vim.api.nvim_buf_set_lines(buf, 0, had_header and 1 or 0, false, { "-- foxquery: dialect=" .. name })
	vim.b[buf].fox_sql_dialect = name
	return true
end

function M.ensure(buf, root)
	local name = M.read(buf)
	if not name then
		local options, err = M.options(root)
		if not options then
			return nil, err
		end
		name = options[1]
		local ok, set_err = M.set(buf, name, root)
		if not ok then
			return nil, set_err
		end
	end
	vim.b[buf].fox_sql_dialect = name
	return name
end

return M
