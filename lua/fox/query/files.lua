local M = {}
local storage = require("fox.query.storage")
local uv = vim.uv or vim.loop

local function checked_path(root, relative)
	local path = storage.root(root)
	for part in (".foxnvim/query/queries/" .. relative):gmatch("[^/]+") do
		path = path .. "/" .. part
		local stat = uv.fs_lstat(path)
		if stat and stat.type == "link" then
			return nil, "SQL file actions do not follow symbolic links"
		end
	end
	return path
end

function M.path(root, relative)
	if
		type(relative) ~= "string"
		or relative == ""
		or relative:find("..", 1, true)
		or relative:match("^[ /]")
		or relative:match("[/ ]$")
		or relative:find('[:*?"<>|\\%c]')
	then
		return nil, "Use a relative path inside the SQL queries folder"
	end
	for part in relative:gmatch("[^/]+") do
		if part == "." or part:match("[. ]$") then
			return nil, "Invalid query path component"
		end
	end
	return checked_path(root, relative)
end

function M.list(state)
	local entries, seen = {}, {}
	local function add(relative, directory)
		if relative == "." or seen[relative] then
			return
		end
		local parent = vim.fs.dirname(relative)
		if parent ~= "." then
			add(parent, true)
		end
		seen[relative] = true
		entries[#entries + 1] = { relative = relative, directory = directory }
	end
	local function scan(relative)
		local path = checked_path(state.root, relative)
		if not path then
			return
		end
		local handle = uv.fs_scandir(path)
		if not handle then
			return
		end
		while true do
			local name, kind = uv.fs_scandir_next(handle)
			if not name then
				break
			end
			local child = relative == "" and name or relative .. "/" .. name
			if kind == "directory" then
				add(child, true)
				scan(child)
			elseif kind == "file" and name:match("%.sql$") then
				add(child, false)
			end
		end
	end
	scan("")
	for buf in pairs(state.consoles) do
		if vim.api.nvim_buf_is_valid(buf) then
			add(vim.b[buf].fox_query_document:sub(#"queries/" + 1), false)
		end
	end
	table.sort(entries, function(a, b)
		return a.relative:gsub("/", "\0") < b.relative:gsub("/", "\0")
	end)
	return entries
end

local function documents(state, relative, deleting)
	local result = {}
	local base = storage.path(state.root, "queries/")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf):gsub("\\", "/")
		if
			name:sub(1, #base):lower() == base:lower()
			and not state.consoles[buf]
			and (vim.bo[buf].buflisted or vim.bo[buf].modified)
		then
			local file = name:sub(#base + 1)
			if file == relative or file:sub(1, #relative + 1) == relative .. "/" then
				return nil, "Close other editor buffers for this SQL file before renaming or deleting"
			end
		end
	end
	for buf, item in pairs(state.consoles) do
		if vim.api.nvim_buf_is_valid(buf) then
			local file = vim.b[buf].fox_query_document:sub(#"queries/" + 1)
			if file == relative or file:sub(1, #relative + 1) == relative .. "/" then
				if item.client and item.client.busy or deleting and vim.bo[buf].modified then
					return nil, "Save modified SQL and finish or cancel running queries before deleting; wait before renaming"
				end
				result[#result + 1] = { buf = buf, relative = file }
			end
		end
	end
	return result
end

function M.create(state, relative, directory)
	local path, err = M.path(state.root, relative)
	if not path then
		return nil, err
	end
	if not directory and not relative:match("%.sql$") then
		return nil, "SQL files must end in .sql"
	end
	local prepared, prepare_err = pcall(vim.fn.mkdir, storage.path(state.root, "queries"), "p")
	if not prepared then
		return nil, prepare_err
	end
	if directory then
		return uv.fs_mkdir(path, 448)
	end
	local handle, open_err = uv.fs_open(path, "wx", 384)
	if not handle then
		return nil, open_err
	end
	return uv.fs_close(handle)
end

function M.rename(state, relative, destination)
	local path, err = M.path(state.root, relative)
	if not path then
		return nil, err
	end
	local target, target_err = M.path(state.root, destination)
	if not target then
		return nil, target_err
	end
	if uv.fs_lstat(target) then
		return nil, "Destination already exists"
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			local name = vim.api.nvim_buf_get_name(buf):gsub("\\", "/"):lower()
			local destination_path = target:lower()
			if name == destination_path or name:sub(1, #destination_path + 1) == destination_path .. "/" then
				if vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buflisted or vim.bo[buf].modified then
					return nil, "Destination already has an open SQL buffer"
				end
				-- Buffer renames leave an unloaded entry for the old filename.
				vim.api.nvim_buf_delete(buf, { force = false })
			end
		end
	end
	if destination:sub(1, #relative + 1) == relative .. "/" then
		return nil, "Cannot move a folder inside itself"
	end
	local stat = uv.fs_stat(path)
	if (not stat or stat.type == "file") and not destination:match("%.sql$") then
		return nil, "SQL files must end in .sql"
	end
	local buffers, buffers_err = documents(state, relative, false)
	if not buffers then
		return nil, buffers_err
	end
	local ok, rename_err = true, nil
	if stat then
		ok, rename_err = uv.fs_rename(path, target)
	end
	if not ok then
		return nil, rename_err
	end
	if not stat and #buffers == 0 then
		return nil, "SQL file no longer exists"
	end
	for _, item in ipairs(buffers) do
		local name = destination .. item.relative:sub(#relative + 1)
		vim.api.nvim_buf_set_name(item.buf, storage.path(state.root, "queries/" .. name))
		vim.b[item.buf].fox_query_document = "queries/" .. name
	end
	return true
end

function M.delete(state, relative)
	local path, err = M.path(state.root, relative)
	if not path then
		return nil, err
	end
	local buffers, buffers_err = documents(state, relative, true)
	if not buffers then
		return nil, buffers_err
	end
	local plan = {}
	local function collect(name)
		local checked, check_err = M.path(state.root, name)
		if not checked then
			return nil, check_err
		end
		local stat = uv.fs_lstat(checked)
		if not stat then
			return true
		end
		if stat.type == "directory" then
			local handle, scan_err = uv.fs_scandir(checked)
			if not handle then
				return nil, scan_err
			end
			while true do
				local child = uv.fs_scandir_next(handle)
				if not child then
					break
				end
				local ok, child_err = collect(name .. "/" .. child)
				if not ok then
					return nil, child_err
				end
			end
		end
		plan[#plan + 1] = { path = checked, directory = stat.type == "directory" }
		return true
	end
	local ok, collect_err = collect(relative)
	if not ok then
		return nil, collect_err
	end
	for _, entry in ipairs(plan) do
		local removed, remove_err
		if entry.directory then
			removed, remove_err = uv.fs_rmdir(entry.path)
		else
			removed, remove_err = uv.fs_unlink(entry.path)
		end
		if not removed then
			return nil, remove_err
		end
	end
	for _, item in ipairs(buffers) do
		require("fox.query").close_buffer(item.buf, true)
	end
	return true
end

return M
