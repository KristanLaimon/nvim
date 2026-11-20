local workspace = require("fox.reader.workspace")
local M = { path = vim.fn.stdpath("state") .. "/fox-reader.json" }

local function load()
	local file = io.open(M.path, "rb")
	if not file then
		return { preferences = {}, positions = {} }
	end
	local content = file:read("*a")
	file:close()
	local ok, data = pcall(vim.json.decode, content)
	if not ok or type(data) ~= "table" or type(data.preferences) ~= "table" or type(data.positions) ~= "table" then
		return { preferences = {}, positions = {} }, "Saved reader state is corrupt; defaults were loaded"
	end
	return data
end

local function document_key(root, path)
	local resolved = workspace.included(path) and workspace.resolve(root, path)
	if not resolved then
		return nil
	end
	local normalized = vim.fs.normalize(root)
	path = vim.fs.normalize(resolved)
	if vim.fn.has("win32") == 1 then
		normalized = normalized:lower()
		path = path:lower()
	end
	return vim.fn.sha256(normalized .. "\0" .. path)
end

function M.get(root, path)
	local data, warning = load()
	local key = path and document_key(root, path)
	return {
		preferences = data.preferences,
		position = key and data.positions[key] or vim.NIL,
		warning = warning or vim.NIL,
	}
end

local function valid_preferences(value)
	if type(value) ~= "table" then
		return false
	end
	local themes = { editor = true, paper = true, light = true, dark = true }
	local alignments = { justify = true, left = true, center = true, right = true }
	local fonts = {
		["Georgia"] = true,
		["Arial"] = true,
		["Verdana"] = true,
		["Tahoma"] = true,
		["Trebuchet MS"] = true,
		["Times New Roman"] = true,
		["Palatino Linotype"] = true,
		["Garamond"] = true,
		["Cambria"] = true,
		["Consolas"] = true,
		["Courier New"] = true,
		["system-ui"] = true,
		["serif"] = true,
		["sans-serif"] = true,
		["monospace"] = true,
	}
	return themes[value.theme]
		and fonts[value.font]
		and alignments[value.alignment]
		and type(value.size) == "number"
		and value.size >= 14
		and value.size <= 28
		and type(value.lineSpacing) == "number"
		and value.lineSpacing >= 1
		and value.lineSpacing <= 2.5
		and type(value.width) == "number"
		and value.width >= 400
		and value.width <= 1200
		and type(value.focus) == "boolean"
end

function M.save(root, request)
	if type(request) ~= "table" then
		return false, "Invalid reader state"
	end
	local data = load()
	if request.kind == "preferences" and valid_preferences(request.value) then
		data.preferences = request.value
	elseif request.kind == "position" and type(request.path) == "string" and type(request.value) == "table" then
		local key = document_key(root, request.path)
		local position = request.value
		if
			not key
			or type(position.heading) ~= "string"
			or #position.heading > 512
			or type(position.offset) ~= "number"
			or math.abs(position.offset) > 10000000
			or type(position.scroll) ~= "number"
			or position.scroll < 0
			or position.scroll > 10000000
		then
			return false, "Invalid document position"
		end
		data.positions[key] = { heading = position.heading, offset = position.offset, scroll = position.scroll }
	else
		return false, "Invalid reader state"
	end
	local ok, encoded = pcall(vim.json.encode, data)
	if not ok then
		return false, "Cannot encode reader state"
	end
	local made = pcall(vim.fn.mkdir, vim.fs.dirname(M.path), "p")
	if not made then
		return false, "Cannot create reader state directory"
	end
	local temporary = M.path .. "." .. vim.fn.sha256(assert(vim.uv.random(16))):sub(1, 16) .. ".tmp"
	local file = io.open(temporary, "wb")
	if not file then
		return false, "Cannot write reader state"
	end
	local wrote = file:write(encoded)
	local closed = file:close()
	if not wrote or not closed then
		vim.uv.fs_unlink(temporary)
		return false, "Cannot write reader state"
	end
	local renamed = vim.uv.fs_rename(temporary, M.path)
	if not renamed then
		vim.uv.fs_unlink(temporary)
		return false, "Cannot replace reader state"
	end
	return true
end

return M
