-- Devicons compatibility owned by FoxVim, backed by the local icon catalog.
local M = {}
local overrides, by_ft = {}, {}
local default_enabled = false
local default_icon
local function backend()
	return require("mini.icons")
end
local function colors(hl)
	if not hl then
		return
	end
	local value = vim.api.nvim_get_hl(0, { name = hl, link = false })
	return string.format("#%06x", value.fg or 0x6d8086), value.ctermfg or 66
end
local function custom(entry, key)
	local hl = "DevIcon" .. (entry.name or key):gsub("[^%w]", "")
	vim.api.nvim_set_hl(0, hl, { fg = entry.color or "#6d8086", ctermfg = tonumber(entry.cterm_color) or 66 })
	return {
		icon = entry.icon or "",
		hl = hl,
		name = entry.name or key,
		color = entry.color,
		cterm_color = entry.cterm_color,
	}
end
local function lookup(category, name, opts)
	if type(name) ~= "string" then
		name = ""
	end
	local item = overrides[name] or overrides[name:lower()]
	local icon, hl, is_default
	if item then
		icon, hl = item.icon, item.hl
	else
		icon, hl, is_default = backend().get(category, name)
	end
	if is_default then
		local use_default = opts and opts.default
		if use_default == nil then
			use_default = default_enabled
		end
		if not use_default then
			return
		end
		if default_icon then
			return default_icon.icon, default_icon.hl
		end
	end
	return icon, hl
end
function M.get_icon(name, ext, opts)
	local basename = type(name) == "string" and vim.fs.basename(name) or nil
	if basename then
		local icon, hl = lookup("file", basename, { default = false })
		if icon ~= nil then
			return icon, hl
		end
	end
	if ext and ext ~= "" then
		return lookup("extension", ext, opts)
	end
	return lookup("file", basename or "", opts)
end
function M.get_icon_by_filetype(ft, opts)
	if by_ft[ft] then
		return M.get_icon(nil, by_ft[ft], opts)
	end
	return lookup("filetype", ft, opts)
end
function M.get_icon_name_by_filetype(ft)
	return by_ft[ft] or ft
end
local function record(icon, hl, name)
	local hex, term = colors(hl)
	return { icon = icon, color = hex, cterm_color = tostring(term or 66), name = name }
end
local function catalog(category)
	local entries = {}
	for _, name in ipairs(backend().list(category)) do
		local icon, hl = lookup(category, name, { default = true })
		entries[name] = record(icon, hl, name)
	end
	return entries
end
function M.get_icons_by_extension()
	return catalog("extension")
end
function M.get_icons_by_filename()
	return catalog("file")
end
function M.get_icons_by_operating_system()
	return catalog("os")
end
function M.get_icons_by_desktop_environment()
	return {}
end
function M.get_icons_by_window_manager()
	return {}
end
function M.get_default_icon()
	if default_icon then
		return record(default_icon.icon, default_icon.hl, "Default")
	end
	local icon, hl = backend().get("default", "file")
	return record(icon, hl, "Default")
end
function M.get_icons()
	return vim.tbl_extend("force", { [1] = M.get_default_icon() }, catalog("os"), catalog("file"), catalog("extension"))
end
function M.set_icon(entries)
	for key, entry in pairs(entries or {}) do
		overrides[key] = custom(entry, key)
	end
end
function M.set_icon_by_filetype(entries)
	by_ft = vim.tbl_extend("force", by_ft, entries or {})
end
function M.set_default_icon(icon, color, cterm_color)
	default_icon = custom({ icon = icon, color = color, cterm_color = cterm_color, name = "Default" }, "Default")
end
function M.setup(opts)
	opts = opts or {}
	if opts.default ~= nil then
		default_enabled = opts.default
	end
	M.set_icon(opts.override)
	M.set_icon(opts.override_by_filename)
	M.set_icon(opts.override_by_extension)
end
function M.has_loaded()
	return true
end
function M.refresh()
	for key, entry in pairs(overrides) do
		overrides[key] = custom(entry, key)
	end
	if default_icon then
		default_icon = custom(default_icon, "Default")
	end
end
M.set_up_highlights = M.refresh
for _, suffix in ipairs({ "", "_by_filetype" }) do
	local getter = suffix == "" and M.get_icon or M.get_icon_by_filetype
	M["get_icon_color" .. suffix] = function(...)
		local icon, hl = getter(...)
		local hex = colors(hl)
		return icon, hex
	end
	M["get_icon_cterm_color" .. suffix] = function(...)
		local icon, hl = getter(...)
		local _, term = colors(hl)
		return icon, term
	end
	M["get_icon_colors" .. suffix] = function(...)
		local icon, hl = getter(...)
		local hex, term = colors(hl)
		return icon, hex, term
	end
end
vim.api.nvim_create_autocmd(
	"ColorScheme",
	{ group = vim.api.nvim_create_augroup("fox_devicons", { clear = true }), callback = M.refresh }
)
return M
