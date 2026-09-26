-- ============================================================================
-- fox.projects.favorites -- The starred paths shared by the pickers.
-- ============================================================================
-- WHO USES IT
--   plugins/fox/file_explorer.lua  Star a folder or file while browsing.
--   plugins/editor/project.lua     Pin a project to the top of the recent list.
--   Both read and write the SAME file, so a folder starred in one shows up
--   starred in the other.
--
-- THE KEY FORMAT MATTERS
--   Entries are keyed by `key(path)`: forward slashes, no trailing slash, and on
--   Windows/WSL a lowercased DRIVE LETTER only. Existing favorites files use
--   exactly that, so changing the rule would silently orphan every entry.
--
-- USAGE
--   local favorites = require("fox.projects.favorites")
--   local starred = favorites.load()
--   favorites.toggle(path)   --> true when it is now a favorite
--   favorites.is(path)
-- ============================================================================

local store = require("fox.core.store")
local path_util = require("fox.core.path")

local M = {}

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------

--- File holding the `{ [key] = true }` map.
M.file = vim.fn.stdpath("data") .. "/project_favorites.json"

-- ---------------------------------------------------------------------------
-- API
-- ---------------------------------------------------------------------------

--- Storage key for a path. See the header before changing this.
--- @param p string|nil Path.
--- @return string key Empty string when `p` is nil or empty.
function M.key(p)
	local clean = path_util.normalize(p)
	if clean ~= "" and (vim.fn.has("win32") == 1 or vim.fn.has("wsl") == 1) then
		clean = clean:sub(1, 1):lower() .. clean:sub(2)
	end
	return clean
end

--- All favorites, keyed by `M.key`.
--- @return table<string, boolean>
function M.load()
	return store.load(M.file, {})
end

--- Writes the favorites map back.
--- @param favorites table<string, boolean>
function M.save(favorites)
	store.save(M.file, favorites)
end

--- True when the path is starred.
--- @param p string Path.
--- @return boolean
function M.is(p)
	return M.load()[M.key(p)] == true
end

--- Stars or unstars a path.
--- @param p string Path.
--- @return boolean is_favorite State AFTER the toggle.
function M.toggle(p)
	local favorites = M.load()
	local key = M.key(p)

	if favorites[key] then
		favorites[key] = nil
		M.save(favorites)
		return false
	end

	favorites[key] = true
	M.save(favorites)
	return true
end

--- Moves a favorite from one path to another, e.g. after a rename.
--- Does nothing when the old path was not starred.
---
--- @param old_path string
--- @param new_path string
function M.move(old_path, new_path)
	local favorites = M.load()
	local old_key = M.key(old_path)

	if not favorites[old_key] then
		return
	end
	favorites[old_key] = nil
	favorites[M.key(new_path)] = true
	M.save(favorites)
end

--- Removes a path from the favorites, if present.
--- @param p string Path.
function M.remove(p)
	local favorites = M.load()
	local key = M.key(p)

	if favorites[key] then
		favorites[key] = nil
		M.save(favorites)
	end
end

return M
