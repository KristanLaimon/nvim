local M = {}

-- Extensions included in the reader's library.
M.extensions = { ".md", ".txt", ".json", ".js", ".py" }

local function normalize(path)
	path = vim.fs.normalize(path)
	return vim.fn.has("win32") == 1 and path:lower() or path
end

function M.root(path)
	local resolved = vim.uv.fs_realpath(path)
	local stat = resolved and vim.uv.fs_stat(resolved)
	if not stat or stat.type ~= "directory" then
		return nil, "Workspace directory is unavailable"
	end
	return vim.fs.normalize(resolved)
end

function M.resolve(root, relative)
	if type(relative) ~= "string" or relative == "" or relative:find("[%z\\:]") or relative:sub(1, 1) == "/" then
		return nil
	end
	local path = vim.uv.fs_realpath(root .. "/" .. relative)
	if not path then
		return nil
	end
	local boundary = normalize(root):gsub("/$", "") .. "/"
	if normalize(path):sub(1, #boundary) ~= boundary then
		return nil
	end
	return vim.fs.normalize(path)
end

function M.included(path)
	local extension = path:match("(%.[^./\\]+)$")
	if not extension then
		return false
	end
	return vim.tbl_contains(M.extensions, extension:lower())
end

function M.list(root, callback)
	local pending = { "" }
	local documents = {}
	local function step()
		local directory = table.remove(pending)
		if not directory then
			table.sort(documents)
			callback(documents)
			return
		end
		local path = directory == "" and root or M.resolve(root, directory)
		local handle = path and vim.uv.fs_scandir(path)
		if handle then
			while true do
				local name, kind = vim.uv.fs_scandir_next(handle)
				if not name then
					break
				end
				local relative = directory == "" and name or (directory .. "/" .. name)
				if kind == "directory" then
					pending[#pending + 1] = relative
				elseif kind == "file" and M.included(relative) then
					documents[#documents + 1] = relative
				end
			end
		end
		vim.schedule(step)
	end
	vim.schedule(step)
end

function M.read(root, relative)
	local path = M.resolve(root, relative)
	local stat = path and vim.uv.fs_stat(path)
	if not stat or stat.type ~= "file" or not M.included(relative) then
		return nil, "Document is unavailable"
	end
	for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buffer) then
			local name = vim.api.nvim_buf_get_name(buffer)
			local resolved = name ~= "" and vim.uv.fs_realpath(name)
			if resolved and normalize(resolved) == normalize(path) then
				return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
			end
		end
	end
	local file = io.open(path, "rb")
	if not file then
		return nil, "Document cannot be read"
	end
	local contents = file:read("*a")
	file:close()
	return contents
end

return M
