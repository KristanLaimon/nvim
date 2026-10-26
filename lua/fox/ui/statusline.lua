-- Native global statusline for the six FOX layouts; no plugin runtime needed.
local M = {}
local config, scheduled
local modes = {
	n = "NORMAL",
	i = "INSERT",
	v = "VISUAL",
	V = "V-LINE",
	["\22"] = "V-BLOCK",
	s = "SELECT",
	S = "S-LINE",
	["\19"] = "S-BLOCK",
	R = "REPLACE",
	Rv = "V-REPLACE",
	c = "COMMAND",
	r = "MORE",
	rm = "MORE",
	["r?"] = "CONFIRM",
	["!"] = "SHELL",
	t = "TERMINAL",
}
local function escape(value)
	return tostring(value):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end
local function hl(name)
	return "%#" .. name .. "#"
end
local function color(name, fallback)
	local c = vim.api.nvim_get_hl(0, { name = name, link = false })
	return c.fg or fallback
end
local backgrounds = {}
function M.highlights()
	local base = vim.api.nvim_get_hl(0, { name = "StatusLine", link = false })
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local fg, bg = base.fg or normal.fg or 0xcdd6f4, base.bg or normal.bg or 0x202330
	local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
	local accent = color(mode == "i" and "String" or "Function", 0x89b4fa)
	if mode == "v" or mode == "V" or mode == "\22" then
		accent = color("Statement", 0xcba6f7)
	end
	local band = vim.api.nvim_get_hl(0, { name = "Pmenu", link = false }).bg or bg
	backgrounds = { a = accent, b = band, c = bg, x = bg, y = band, z = accent }
	for _, section in ipairs({ "a", "b", "c", "x", "y", "z" }) do
		local edge = section == "a" or section == "z"
		vim.api.nvim_set_hl(0, "FoxStatus" .. section, { fg = edge and bg or fg, bg = backgrounds[section], bold = edge })
		for _, kind in ipairs({ "Error", "Warn", "Info", "Hint" }) do
			vim.api.nvim_set_hl(
				0,
				"FoxStatus" .. section .. kind,
				{ fg = color("Diagnostic" .. kind, fg), bg = backgrounds[section] }
			)
		end
	end
	for _, section in ipairs({ "a", "b", "y", "z" }) do
		local neighbor = ({ a = "b", b = "c", y = "x", z = "y" })[section]
		local next_bg = backgrounds[neighbor]
		vim.api.nvim_set_hl(0, "FoxStatusSep" .. section, { fg = backgrounds[section], bg = next_bg })
	end
end
local function counts(values, keys, symbols, section)
	local parts = {}
	for _, key in ipairs(keys) do
		if (values[key] or 0) > 0 then
			local kind = ({
				error = "Error",
				warn = "Warn",
				info = "Info",
				hint = "Hint",
				added = "Hint",
				modified = "Warn",
				removed = "Error",
			})[key]
			parts[#parts + 1] = hl("FoxStatus" .. section .. kind)
				.. escape((symbols[key] or key) .. values[key])
				.. hl("FoxStatus" .. section)
		end
	end
	return table.concat(parts, " ")
end
function M.component(spec, section)
	local opts = type(spec) == "table" and spec or { spec }
	local item, value, raw = opts[1], "", false
	if type(item) == "function" then
		value = item()
		raw = item == require("plugins.fox.ui.statusline_picker").workflow_status
	elseif item == "mode" then
		local mode = vim.api.nvim_get_mode().mode
		value = modes[mode] or modes[mode:sub(1, 1)] or "NORMAL"
	elseif item == "filename" then
		value = vim.fn.expand("%:~:.")
		if value == "" then
			value = opts.symbols.unnamed
		end
		if opts.fmt then
			value = opts.fmt(value)
		end
		if vim.bo.modified then
			value = value .. opts.symbols.modified
		end
		if vim.bo.readonly or not vim.bo.modifiable then
			value = value .. opts.symbols.readonly
		end
	elseif item == "filetype" then
		value = vim.bo.filetype
		if value ~= "" then
			local icon = require("fox.ui.icons").get("filetype", value)
			value = icon .. " " .. value
		end
	elseif item == "encoding" then
		value = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or vim.o.encoding
	elseif item == "fileformat" then
		value = ({ unix = "", dos = "", mac = "" })[vim.bo.fileformat] or vim.bo.fileformat
	elseif item == "location" then
		value = string.format("%d:%d", vim.fn.line("."), vim.fn.virtcol("."))
	elseif item == "progress" then
		local row, total = vim.fn.line("."), vim.fn.line("$")
		value = row == 1 and "Top" or row == total and "Bot" or string.format("%2d", math.floor(row / total * 100)) .. "%"
	elseif item == "diagnostics" then
		local d = vim.diagnostic.count(0)
		value = counts(
			{ error = d[1], warn = d[2], info = d[3], hint = d[4] },
			{ "error", "warn", "info", "hint" },
			opts.symbols,
			section
		)
		raw = true
	elseif item == "diff" then
		local d = vim.b.gitsigns_status_dict or require("fox.ui.statusline_git").diff()
		value = counts(
			{ added = d.added, modified = d.changed, removed = d.removed },
			{ "added", "modified", "removed" },
			opts.symbols,
			section
		)
		raw = true
	end
	if opts.fmt and item ~= "filename" then
		value = opts.fmt(value)
	end
	if not value or value == "" then
		return ""
	end
	value = raw and value or escape(value)
	return opts.icon and escape(opts.icon) .. " " .. value or value
end
local function separator(kind, side)
	local seps = config.options[kind]
	return type(seps) == "table" and seps[side] or type(seps) == "string" and seps or (side == "left" and "" or "")
end
function M.render()
	if not config then
		return ""
	end
	local rendered = {}
	for _, section in ipairs({ "a", "b", "c", "x", "y", "z" }) do
		local parts = {}
		for _, spec in ipairs(config.sections[section] or {}) do
			local ok, value = pcall(M.component, spec, section)
			if ok and value ~= "" then
				parts[#parts + 1] = value .. hl("FoxStatus" .. section)
			end
		end
		local side = section < "x" and "left" or "right"
		rendered[section] = #parts > 0
				and hl("FoxStatus" .. section) .. " " .. table.concat(
					parts,
					" " .. escape(separator("component_separators", side)) .. " "
				) .. " "
			or ""
	end
	local left, right = {}, {}
	for _, section in ipairs({ "a", "b", "c" }) do
		left[#left + 1] = rendered[section]
		if section ~= "c" and rendered[section] ~= "" then
			left[#left + 1] = hl("FoxStatusSep" .. section) .. escape(separator("section_separators", "left"))
		end
	end
	for _, section in ipairs({ "x", "y", "z" }) do
		if section ~= "x" and rendered[section] ~= "" then
			right[#right + 1] = hl("FoxStatusSep" .. section) .. escape(separator("section_separators", "right"))
		end
		right[#right + 1] = rendered[section]
	end
	return table.concat(left) .. hl("FoxStatusc") .. "%<%=" .. table.concat(right)
end
function M.refresh()
	if scheduled then
		return
	end
	scheduled = true
	vim.schedule(function()
		scheduled = false
		vim.cmd.redrawstatus()
	end)
end
function M.setup(opts)
	config = opts
	M.highlights()
	vim.o.laststatus = 3
	vim.o.statusline = "%!v:lua.require'fox.ui.statusline'.render()"
	local group = vim.api.nvim_create_augroup("FoxNativeStatusline", { clear = true })
	vim.api.nvim_create_autocmd({ "ColorScheme", "ModeChanged" }, {
		group = group,
		callback = function()
			M.highlights()
			M.refresh()
		end,
	})
	vim.api.nvim_create_autocmd({
		"LspAttach",
		"LspDetach",
		"DiagnosticChanged",
		"BufEnter",
		"BufWritePost",
		"TermRequest",
		"CursorMoved",
		"CursorMovedI",
		"TextChanged",
		"TextChangedI",
		"WinEnter",
		"VimResized",
	}, { group = group, callback = M.refresh })
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "BufWritePost" }, {
		group = group,
		callback = function()
			require("fox.ui.statusline_git").invalidate()
			M.refresh()
		end,
	})
	vim.api.nvim_create_autocmd(
		"User",
		{ group = group, pattern = { "GitSignsUpdate", "FoxWorkflowChanged" }, callback = M.refresh }
	)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			require("fox.ui.statusline_git").cancel()
		end,
	})
	M.refresh()
end
return M
