-- Color previews use the same parsers and Tailwind palette as FOX completion.
local M = { ns = vim.api.nvim_create_namespace("fox_color_highlights") }
local colorify = require("fox.lsp.colorify")
local options, enabled, generations = {}, true, {}
local function color(value)
	local hex = value:match("^#(%x+)$") or value:match("^0x(%x+)$")
	if hex then
		if #hex == 3 or #hex == 4 then
			return "#" .. hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
		end
		if #hex == 6 or #hex == 8 then
			return "#" .. hex:sub(1, 6):lower()
		end
		return
	end
	if value:match("^rgba?%(") then
		local parts = {}
		for v, percent in value:gmatch("([%d.]+)(%%?)") do
			parts[#parts + 1] = math.min(255, tonumber(v) * (percent == "%" and 2.55 or 1))
		end
		if #parts >= 3 then
			return string.format(
				"#%02x%02x%02x",
				math.floor(parts[1] + 0.5),
				math.floor(parts[2] + 0.5),
				math.floor(parts[3] + 0.5)
			)
		end
	end
	if value:match("^hsla?%(") then
		local h, s, l = value:match("%(([%d.+-]+)[, %s]+([%d.]+)%%[, %s]+([%d.]+)%%")
		if h then
			return colorify.hsl_to_hex(tonumber(h) % 360, math.min(100, tonumber(s)), math.min(100, tonumber(l)))
		end
	end
	return colorify.extract_hex_color(value)
end
M.color = color
function M.spans(line, variables)
	local spans, used = {}, {}
	local function add(first, last, hex)
		if not hex then
			return
		end
		for col = first, last do
			if used[col] then
				return
			end
		end
		for col = first, last do
			used[col] = true
		end
		spans[#spans + 1] = { first - 1, last, hex }
	end
	local function scan(pattern, resolve)
		local pos = 1
		while true do
			local a, b = line:find(pattern, pos)
			if not a then
				break
			end
			add(a, b, resolve(line:sub(a, b)))
			pos = b + 1
		end
	end
	if options.enable_var_usage ~= false then
		scan("var%(%s*%-%-[%w_-]+%s*%)", function(v)
			return (variables or {})[v:match("%-%-[%w_-]+")]
		end)
	end
	if options.enable_rgb ~= false then
		scan("rgba?%([^()]+%)", color)
	end
	if options.enable_hsl ~= false then
		scan("hsla?%([^()]+%)", color)
	end
	if options.enable_hex ~= false then
		scan("#%x+", color)
		scan("0x%x+", color)
	end
	if options.enable_tailwind then
		scan("[%w_-]+%-%d+", colorify.extract_color_by_name)
	end
	if options.enable_named_colors ~= false then
		scan("%f[%a][%a]+%f[^%a]", function(v)
			local hex = colorify.named_colors[v:lower()]
			if hex then
				return hex
			end
			if v:lower() == "rebeccapurple" then
				return "#663399"
			end
			-- Vim's bundled X11 names supply uncommon CSS names. CSS overrides above win.
			local n = vim.api.nvim_get_color_by_name(v)
			if n >= 0 and v:lower() ~= "transparent" then
				return string.format("#%06x", n)
			end
		end)
	end
	if options.enable_hsl_without_function ~= false then
		scan("%d+%.?%d*%s+%d+%.?%d*%%%s+%d+%.?%d*%%", function(v)
			return color("hsl(" .. v .. ")")
		end)
	end
	return spans
end
function M.refresh(buf)
	if not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
	if
		not enabled
		or vim.bo[buf].buftype ~= ""
		or vim.tbl_contains(options.exclude_filetypes or {}, vim.bo[buf].filetype)
	then
		return
	end
	local variables = {}
	-- Bound work for giant generated files; only visible text is decorated.
	local lines = vim.api.nvim_buf_get_lines(buf, 0, math.min(20000, vim.api.nvim_buf_line_count(buf)), false)
	for _, line in ipairs(lines) do
		for name, value in line:gmatch("(%-%-[%w_-]+)%s*:%s*([^;]+)") do
			variables[name] = color(vim.trim(value))
		end
	end
	local seen = {}
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local first, last = unpack(vim.api.nvim_win_call(win, function()
			return { vim.fn.line("w0"), vim.fn.line("w$") }
		end))
		for row = first, last do
			if not seen[row] then
				seen[row] = true
				local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
				if #line <= 10000 then
					for _, span in ipairs(M.spans(line, variables)) do
						local hex = span[3]
						local hl = "FoxColor" .. hex:sub(2)
						vim.api.nvim_set_hl(0, hl, { bg = hex, fg = colorify.get_contrast_fg(hex) })
						vim.api.nvim_buf_set_extmark(
							buf,
							M.ns,
							row - 1,
							span[1],
							{ end_col = span[2], hl_group = hl, priority = 110 }
						)
					end
				end
			end
		end
	end
end
function M.schedule(buf)
	generations[buf] = (generations[buf] or 0) + 1
	local generation = generations[buf]
	vim.defer_fn(function()
		if generations[buf] == generation then
			M.refresh(buf)
		end
	end, 80)
end
function M.toggle(value)
	enabled = value == nil and not enabled or value == true
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		M.refresh(buf)
	end
end
function M.setup(opts)
	options = opts or {}
	enabled = true
	local group = vim.api.nvim_create_augroup("fox_color_highlights", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "WinScrolled", "ColorScheme" }, {
		group = group,
		callback = function(a)
			M.schedule(a.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(a)
			generations[a.buf] = nil
		end,
	})
	vim.api.nvim_create_user_command("HighlightColors", function(a)
		local action = a.args:lower()
		if action == "isactive" then
			print(enabled)
		else
			if action == "toggle" then
				M.toggle()
			elseif action == "on" or action == "off" then
				M.toggle(action == "on")
			else
				error("Expected On, Off, Toggle or IsActive")
			end
		end
	end, {
		nargs = 1,
		complete = function()
			return { "On", "Off", "Toggle", "IsActive" }
		end,
		desc = "Control inline color previews",
	})
	M.schedule(vim.api.nvim_get_current_buf())
end
return M
