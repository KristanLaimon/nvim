-- Native icon resolution with the original attributed icon metadata.
local M = {}
local data = require("fox.ui.icon_data")
local catalog, defaults, scratch, cache
local palette = {
	Azure = "#3a8bfd",
	Blue = "#4e79f0",
	Cyan = "#22d3ee",
	Green = "#6cc644",
	Grey = "#8c8c8c",
	Orange = "#f38019",
	Purple = "#a855f7",
	Red = "#f14c4c",
	Yellow = "#f1e05a",
}

local function highlights()
	for name, color in pairs(palette) do
		vim.api.nvim_set_hl(0, "MiniIcons" .. name, { fg = color })
	end
end
local function basename(name)
	return name:gsub("\\", "/"):match("([^/]+)/*$") or name
end
local function filetype(name)
	if not scratch or not vim.api.nvim_buf_is_valid(scratch) then
		scratch = vim.api.nvim_create_buf(false, true)
	end
	local ok, ft = pcall(vim.filetype.match, { filename = name, buf = scratch })
	if not ok then
		ok, ft = pcall(vim.filetype.match, { filename = "~/" .. name, buf = scratch })
	end
	return ok and ft or nil
end
function M.setup(opts)
	opts = opts or {}
	cache = nil
	catalog, defaults = vim.deepcopy(data), vim.deepcopy(data.default)
	M.config =
		{ style = opts.style or "glyph", use_file_extension = opts.use_file_extension or function()
			return true
		end }
	-- Resolve partial overrides against the unmodified catalog first.
	for category in pairs(data) do
		M.config[category] = opts[category] or {}
		for name, item in pairs(opts[category] or {}) do
			local glyph, hl = M.get(category, name)
			catalog[category][name] = vim.tbl_extend("force", { glyph = glyph, hl = hl }, item)
			if category == "default" then
				defaults[name] = catalog[category][name]
			end
		end
	end
	highlights()
	cache = {}
	_G.MiniIcons = M
end
function M.get(category, name)
	assert(type(name) == "string" and data[category], "Invalid icon category or name")
	if category == "directory" then
		name = basename(name)
	elseif category ~= "file" then
		name = name:lower()
	end
	local cached = cache and cache[category] and cache[category][name]
	if cached then
		return unpack(cached)
	end
	local item = catalog[category][name]
	if not item and category == "file" then
		local base = basename(name)
		item = catalog.file[base]
		if not item then
			local dot = base:find("%..", 2)
			local ext = dot and base:sub(dot + 1):lower()
			if ext and M.config.use_file_extension(ext, name) then
				local glyph, hl, fallback = M.get("extension", ext)
				if not fallback then
					item = { glyph = glyph, hl = hl }
				end
			end
		end
		if not item then
			local ft = filetype(name)
			if ft then
				local glyph, hl = M.get("filetype", ft)
				item = { glyph = glyph, hl = hl }
			end
		end
	elseif not item and category == "extension" then
		local suffix = name:match("%.(.+)")
		while suffix do
			if catalog.extension[suffix] then
				local glyph, hl = M.get("extension", suffix)
				item = { glyph = glyph, hl = hl }
				break
			end
			suffix = suffix:match("%.(.+)")
		end
		if not item then
			local ft = filetype("aaa." .. name)
			if ft then
				local glyph, hl = M.get("filetype", ft)
				item = { glyph = glyph, hl = hl }
			end
		end
	end
	if type(item) == "string" then
		local glyph, hl = M.get("filetype", item)
		item = { glyph = glyph, hl = hl }
	end
	local fallback = item == nil
	item = item or defaults[category] or defaults.file
	local glyph = item.glyph
	if M.config.style == "ascii" then
		glyph = vim.fn.toupper(vim.fn.strcharpart(basename(name), 0, 1))
	end
	if cache then
		cache[category] = cache[category] or {}
		cache[category][name] = { glyph, item.hl, fallback }
	end
	return glyph, item.hl, fallback
end
function M.list(category)
	return vim.tbl_keys(catalog[category] or {})
end
M.setup({})
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("fox_icons_palette", { clear = true }),
	callback = highlights,
})
return M
