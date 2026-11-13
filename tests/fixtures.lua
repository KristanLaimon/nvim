-- ============================================================================
-- tests/fixtures.lua -- Shared test fixture helpers
-- ============================================================================

local M = {}

--- Returns the absolute path to the fixtures directory
--- @return string
M.fixtures_dir = function()
	return vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
end

--- Returns the path to the dummy_project fixture
--- @return string
M.dummy_project = function()
	return vim.fn.joinpath(M.fixtures_dir(), "dummy_project")
end

--- Copies the dummy project fixture to a temporary directory and returns the path
--- The caller is responsible for cleaning up the returned directory.
--- @return string path to the copied fixture directory
M.copy_dummy_project = function()
	local path = require("fox.core.path")
	local src = M.dummy_project()
	local dest = vim.fn.tempname()
	vim.fn.mkdir(dest, "p")

	-- Copy all files from fixture to temp dir
	local function copy_dir(source, target)
		local dir = vim.loop.fs_scandir(source)
		if not dir then
			return
		end
		vim.fn.mkdir(target, "p")
		while true do
			local name, type = vim.loop.fs_scandir_next(dir)
			if not name then
				break
			end
			local src_path = path.join(source, name)
			local dst_path = path.join(target, name)
			if type == "directory" then
				copy_dir(src_path, dst_path)
			else
				vim.fn.mkdir(vim.fn.fnamemodify(dst_path, ":h"), "p")
				local content = vim.fn.readfile(src_path)
				if content then
					vim.fn.writefile(content, dst_path)
				end
			end
		end
	end

	copy_dir(src, dest)
	return dest
end

return M
