-- ============================================================================
-- fox.core.store -- JSON file persistence for every FOX module.
-- ============================================================================
-- WHY THIS EXISTS
--   Ten plugins each carried their own `io.open` + `vim.json.decode` + pcall
--   dance to persist state (tasks, launch profiles, breakpoints, favorites,
--   workspaces, fonts, nuget cache...). Same six lines, ten chances to forget a
--   `pcall` and hard-error the editor on a truncated file.
--
-- CONTRACT
--   * Reads never throw. A missing or corrupt file yields the caller's fallback.
--   * Writes create parent directories and return ok/err instead of throwing.
--   * `nil` is never written: `save` refuses non-table values.
--
-- USAGE
--   local store = require("fox.core.store")
--   local data = store.load(path, {})           -- always a table here
--   local ok, err = store.save(path, data)      -- creates parent dirs
-- ============================================================================

local path_util = require("fox.core.path")

local M = {}

-- ---------------------------------------------------------------------------
-- Reading
-- ---------------------------------------------------------------------------

--- Reads a whole file as a string.
---
--- @param filepath string Path to read.
--- @return string|nil content File contents, or nil when unreadable.
function M.read_file(filepath)
	local f = io.open(filepath, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

--- Loads and decodes a JSON file.
--- Never throws: unreadable, empty and malformed files all return `fallback`.
---
--- @param filepath string Path to a JSON file.
--- @param fallback any Value returned when the file cannot be decoded. Default `{}`.
--- @return any data Decoded table, or `fallback`.
function M.load(filepath, fallback)
	if fallback == nil then
		fallback = {}
	end
	local content = M.read_file(filepath)
	if not content or content == "" then
		return fallback
	end
	local ok, data = pcall(vim.json.decode, content)
	if ok and type(data) == "table" then
		return data
	end
	return fallback
end

-- ---------------------------------------------------------------------------
-- Deterministic encoding
-- ---------------------------------------------------------------------------
-- `vim.json.encode` walks object tables with `pairs`, whose order depends on
-- Lua's hash implementation -- the same table can serialize with its keys in
-- a different order on every run, which shows up as spurious git diffs on
-- config files that never actually changed. Object keys are sorted here;
-- arrays keep their natural order since it is meaningful.

--- Encodes `value` as JSON with object keys sorted for stable output.
--- @param value any
--- @return string
local function encode_sorted(value)
	if type(value) ~= "table" then
		return vim.json.encode(value)
	end
	if next(value) == nil or vim.islist(value) then
		local parts = {}
		for i, item in ipairs(value) do
			parts[i] = encode_sorted(item)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	local keys = {}
	for key in pairs(value) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		table.insert(parts, vim.json.encode(tostring(key)) .. ":" .. encode_sorted(value[key]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

--- Writes a string to a file, creating parent directories as needed.
---
--- @param filepath string Destination path.
--- @param content string Content to write.
--- @return boolean ok
--- @return string|nil err Error message when `ok` is false.
function M.write_file(filepath, content)
	path_util.ensure_dir(vim.fs.dirname(filepath))
	local f, err = io.open(filepath, "w")
	if not f then
		return false, err or ("cannot open for writing: " .. filepath)
	end
	f:write(content)
	f:close()
	return true
end

--- Encodes a table as JSON and writes it, creating parent directories.
---
--- @param filepath string Destination path.
--- @param data table Table to serialize.
--- @return boolean ok
--- @return string|nil err Error message when `ok` is false.
function M.save(filepath, data)
	if type(data) ~= "table" then
		return false, "store.save expects a table, got " .. type(data)
	end
	local ok, encoded = pcall(encode_sorted, data)
	if not ok then
		return false, tostring(encoded)
	end
	return M.write_file(filepath, encoded)
end

return M
