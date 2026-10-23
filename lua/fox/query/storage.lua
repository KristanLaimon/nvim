local M = {}
local uv = vim.uv or vim.loop

function M.root(root)
	return (uv.fs_realpath(root or vim.fn.getcwd()) or vim.fs.normalize(root or vim.fn.getcwd()))
		:gsub("\\", "/")
		:gsub("/$", "")
end

function M.path(root, relative)
	assert(not relative:find("..", 1, true) and not relative:match("^[/\\]"), "Invalid query state path")
	return M.root(root) .. "/.foxnvim/query/" .. relative
end

function M.write(root, relative, text)
	if relative:match("^private/") or relative:match("^cache/") or relative:match("^exports/") then
		local prepared, prepare_err = M.prepare(root)
		if not prepared then
			return nil, prepare_err
		end
	end
	local destination = M.path(root, relative)
	vim.fn.mkdir(vim.fs.dirname(destination), "p")
	local temporary = destination .. "." .. uv.os_getpid() .. "." .. uv.hrtime() .. ".tmp"
	local file, err = uv.fs_open(temporary, "wx", 384)
	if not file then
		return nil, err
	end
	local offset, write_err = 0, nil
	while offset < #text do
		local written, chunk_err = uv.fs_write(file, text:sub(offset + 1), offset)
		if not written or written == 0 then
			write_err = chunk_err or "Short file write"
			break
		end
		offset = offset + written
	end
	local synced, sync_err = uv.fs_fsync(file)
	local closed, close_err = uv.fs_close(file)
	if write_err or not synced or not closed then
		uv.fs_unlink(temporary)
		return nil, write_err or sync_err or close_err
	end
	local ok, rename_err = uv.fs_rename(temporary, destination)
	if not ok then
		uv.fs_unlink(temporary)
	end
	return ok, rename_err
end

function M.read(root, relative)
	local file = io.open(M.path(root, relative), "rb")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

function M.load(root, relative, fallback)
	local content = M.read(root, relative)
	if not content then
		return fallback
	end
	local ok, data = pcall(vim.json.decode, content)
	if not ok or type(data) ~= "table" then
		return nil, "Invalid JSON in .foxnvim/query/" .. relative .. "; original file preserved"
	end
	return data
end

function M.save(root, relative, data)
	return M.write(root, relative, vim.json.encode(data))
end

function M.cache(root, fingerprint)
	local data, err = M.load(root, "cache/" .. fingerprint .. ".json", nil)
	if not data then
		return nil, err
	end
	if data.updated_at ~= nil and type(data.updated_at) ~= "number" then
		return nil, "Invalid cache timestamp; refresh metadata"
	end
	if
		data.syntax ~= nil
		and (
			type(data.syntax) ~= "string"
			or not vim.tbl_contains({ "sqlite", "mysql", "mysql-no-backslash", "postgres" }, data.syntax)
		)
	then
		return nil, "Invalid cached SQL dialect; refresh metadata"
	end
	if
		type(data.tables) ~= "table"
		or not vim.islist(data.tables)
		or type(data.relations) ~= "table"
		or not vim.islist(data.relations)
	then
		return nil, "Invalid schema cache; refresh metadata to rebuild it"
	end
	for _, item in ipairs(data.tables) do
		if
			type(item) ~= "table"
			or type(item.key) ~= "string"
			or type(item.name) ~= "string"
			or type(item.columns) ~= "table"
			or not vim.islist(item.columns)
		then
			return nil, "Invalid table metadata in cache; refresh to rebuild it"
		end
		if item.schema ~= nil and type(item.schema) ~= "string" then
			return nil, "Invalid cached schema; refresh metadata"
		end
		if item.indexes ~= nil then
			if type(item.indexes) ~= "table" or not vim.islist(item.indexes) then
				return nil, "Invalid cached indexes; refresh metadata"
			end
			for _, index in ipairs(item.indexes) do
				if type(index) ~= "table" or type(index.name) ~= "string" then
					return nil, "Invalid cached index; refresh metadata"
				end
			end
		end
		for _, column in ipairs(item.columns) do
			if type(column) ~= "table" or type(column.name) ~= "string" then
				return nil, "Invalid cached column; refresh to rebuild metadata"
			end
		end
	end
	for _, relation in ipairs(data.relations) do
		if
			type(relation) ~= "table"
			or type(relation.source) ~= "string"
			or type(relation.target) ~= "string"
			or type(relation.name) ~= "string"
			or type(relation.columns) ~= "table"
			or not vim.islist(relation.columns)
		then
			return nil, "Invalid cached relationship; refresh metadata"
		end
		for _, pair in ipairs(relation.columns) do
			if
				type(pair) ~= "table"
				or type(pair.source) ~= "string"
				or pair.target ~= nil and type(pair.target) ~= "string"
			then
				return nil, "Invalid cached key mapping; refresh metadata"
			end
		end
	end
	return data
end

function M.prepare(root)
	if not M.read(root, ".gitignore") then
		return M.write(root, ".gitignore", "private/\ncache/\nexports/\nrecovery/\n*.tmp\n")
	end
	return true
end

function M.fingerprint(profile)
	local identity = {}
	for _, key in ipairs({ "id", "engine", "host", "port", "database", "schema", "user", "path" }) do
		identity[#identity + 1] = tostring(profile[key] or "")
	end
	return vim.fn.sha256(table.concat(identity, "\n")):sub(1, 24)
end

function M.validate(profile)
	if type(profile) ~= "table" or type(profile.id) ~= "string" or not profile.id:match("^[%w_-]+$") then
		return nil, "Profile id must contain letters, digits, _ or -"
	end
	if not vim.tbl_contains({ "sqlite", "mysql", "postgres" }, profile.engine) then
		return nil, "Choose sqlite, mysql, or postgres"
	end
	if profile.password ~= nil then
		return nil, "Remove password from the profile; use a RAM prompt or password_env reference"
	end
	if profile.engine == "sqlite" then
		if type(profile.path) ~= "string" or profile.path == "" then
			return nil, "SQLite needs a database path"
		end
	else
		for _, key in ipairs({ "host", "database", "user" }) do
			if type(profile[key]) ~= "string" or profile[key] == "" then
				return nil, "Connection needs " .. key
			end
		end
		if type(profile.port) ~= "number" or profile.port < 1 or profile.port > 65535 or profile.port % 1 ~= 0 then
			return nil, "Port must be 1..65535"
		end
	end
	return true
end

function M.profiles(root)
	local data, err = M.load(root, "connections.json", { profiles = {} })
	if not data then
		return nil, err
	end
	if type(data.profiles) ~= "table" or not vim.islist(data.profiles) then
		return nil, "connections.json needs a profiles array"
	end
	local ids = {}
	for _, profile in ipairs(data.profiles) do
		local ok, validation = M.validate(profile)
		if not ok then
			return nil, validation
		end
		if ids[profile.id] then
			return nil, "Duplicate profile id"
		end
		ids[profile.id] = true
	end
	return data.profiles
end

function M.document_buffer(root, relative, filetype)
	local name = M.path(root, relative)
	local buf = vim.fn.bufnr(name)
	if buf == -1 then
		buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].swapfile, vim.bo[buf].undofile, vim.bo[buf].modeline = false, false, false
		vim.bo[buf].buftype = "acwrite"
		vim.api.nvim_buf_set_name(buf, name)
	end
	if not vim.api.nvim_buf_is_loaded(buf) then
		vim.fn.bufload(buf)
		vim.b[buf].fox_query_loaded = nil
	end
	vim.bo[buf].buflisted = true
	vim.b[buf].fox_query_root, vim.b[buf].fox_query_document = M.root(root), relative
	vim.bo[buf].buftype, vim.bo[buf].bufhidden = "acwrite", "hide"
	vim.bo[buf].swapfile, vim.bo[buf].undofile, vim.bo[buf].modeline = false, false, false
	vim.bo[buf].filetype = filetype
	if not vim.b[buf].fox_query_loaded then
		local content = M.read(root, relative) or ""
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n", { plain = true }))
		vim.bo[buf].modified, vim.b[buf].fox_query_loaded = false, true
		vim.b[buf].fox_query_disk = content
		vim.api.nvim_create_autocmd("BufWriteCmd", {
			buffer = buf,
			callback = function()
				local document = vim.b[buf].fox_query_document
				local current = M.read(root, document) or ""
				if current ~= vim.b[buf].fox_query_disk then
					error("File changed externally; reload or resolve the conflict before saving")
				end
				local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
				local ok, err = M.write(root, document, text)
				if not ok then
					error(err)
				end
				vim.b[buf].fox_query_disk, vim.bo[buf].modified = text, false
			end,
		})
	end
	return buf
end

return M
