local M = { file = vim.fn.stdpath("data") .. "/project_nvim/project_history" }
local path = require("fox.core.path")
local uv = vim.uv or vim.loop

--- Oldest first; retain the existing file format and never stat project paths.
function M.list()
	local file, err = io.open(M.file, "rb")
	if not file then
		local _, _, code = uv.fs_stat(M.file)
		return {}, code ~= "ENOENT" and err or nil
	end
	local content, read_err = file:read("*a")
	file:close()
	if not content then
		return {}, read_err
	end
	local projects = {}
	for line in content:gmatch("[^\r\n]+") do
		if vim.trim(line) ~= "" then
			table.insert(projects, path.normalize(line))
		end
	end
	return projects
end

local function update(transform)
	local projects, err = M.list()
	if err then
		return false, err
	end
	projects = transform(projects)
	local ok, mkdir_err = pcall(vim.fn.mkdir, vim.fs.dirname(M.file), "p")
	if not ok then
		return false, mkdir_err
	end
	local temporary = M.file .. "." .. vim.fn.getpid() .. ".tmp"
	local file, open_err = io.open(temporary, "wb")
	if not file then
		return false, open_err
	end
	local written, write_err = file:write(#projects > 0 and table.concat(projects, "\n") .. "\n" or "")
	local closed, close_err = file:close()
	local renamed, rename_err
	if written and closed then
		renamed, rename_err = uv.fs_rename(temporary, M.file)
	end
	if not renamed then
		uv.fs_unlink(temporary)
		return false, write_err or close_err or rename_err
	end
	return true
end

local function valid(dir)
	return type(dir) == "string" and dir ~= "" and not dir:find("[\r\n%z]")
end

function M.remember(dir)
	if not valid(dir) then
		return false, "Invalid project path"
	end
	dir = path.normalize(dir)
	return update(function(projects)
		local kept = {}
		for _, project in ipairs(projects) do
			if not path.equals(project, dir) then
				table.insert(kept, project)
			end
		end
		table.insert(kept, dir)
		return kept
	end)
end

function M.remove(dir)
	if not valid(dir) then
		return false, "Invalid project path"
	end
	return update(function(projects)
		return vim.tbl_filter(function(project)
			return not path.equals(project, dir)
		end, projects)
	end)
end

function M.rename(old, new)
	if not valid(old) or not valid(new) then
		return false, "Invalid project path"
	end
	return update(function(projects)
		for index, project in ipairs(projects) do
			if path.equals(project, old) then
				projects[index] = path.normalize(new)
			end
		end
		return projects
	end)
end

return M
