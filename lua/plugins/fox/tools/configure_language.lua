local toolchain = require("fox.langs.toolchain")
local ui = require("fox.core.ui")
local list_highlights = vim.api.nvim_create_namespace("fox_language_configure")
local first_tool_row = 5

local categories = {
	{
		key = "formatters",
		title = "Formatters",
		lines = { "[ === ]", "Choose the default formatter", "or run tools in order." },
	},
	{ key = "linters", title = "Linters", lines = { "[  !  ]", "Choose which tools", "report diagnostics." } },
	{
		key = "servers",
		title = "LSPs",
		lines = { "[ < > ]", "Manage language servers", "for this project or globally." },
	},
}

local function maps(buf, bindings)
	for key, action in pairs(bindings) do
		vim.keymap.set("n", key, action, { buffer = buf, silent = true, nowait = true })
	end
end

local function open_file(path, seed, on_write)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	ui.float(buf, { title = " " .. vim.fs.basename(path) .. " ", width = 0.85, height = 0.75 })
	if not vim.uv.fs_stat(path) and not vim.bo[buf].modified and seed then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(seed, "\n", { plain = true }))
	end
	if on_write then
		local group = vim.api.nvim_create_augroup("FoxToolConfig" .. buf, { clear = true })
		vim.api.nvim_create_autocmd("BufWritePre", {
			buffer = buf,
			group = group,
			callback = function()
				local ok, value = pcall(vim.json.decode, table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
				if not ok or type(value) ~= "table" or vim.islist(value) and next(value) then
					error("LSP settings must be a JSON object")
				end
				vim.fn.mkdir(vim.fs.dirname(path), "p")
			end,
		})
		vim.api.nvim_create_autocmd("BufWritePost", { buffer = buf, group = group, callback = on_write })
	end
end

local function edit(ctx, scope, category, name, server)
	local spec = toolchain.metadata(name)
	local state = toolchain.read(ctx)
	local markers = toolchain.markers(state, category, name)
	local path = toolchain.find_config(ctx, markers and #markers > 0 and markers or spec.files)
	local cards, actions = {}, {}
	local function add(title, description, action)
		cards[#cards + 1] = { title = title, lines = { description } }
		actions[#actions + 1] = action
	end
	if path or spec.template then
		local custom = spec.config_args or spec.config_env or (spec.lint and spec.lint.config_args)
		local target = path or vim.fs.joinpath(ctx.root, custom and markers and markers[1] or spec.create or spec.files[1])
		add("Native config", path and vim.fs.basename(path) or "Edit a starter config. :w creates it.", function()
			open_file(target, path and nil or spec.template)
		end)
	end
	if server then
		add("LSP settings", "Edit " .. scope .. " JSON settings", function()
			local target = toolchain.settings_path(scope == "Project" and ctx.root or nil, name)
			open_file(target, "{}", function()
				toolchain.refresh(ctx, name, scope == "Global")
			end)
		end)
	end
	add("Effective defaults", "Inspect FoxVim and tool defaults", function()
		local config = server and vim.lsp.config[name]
			or (not spec.lint and require("conform").get_formatter_config(name, ctx.buf))
		local settings = server and toolchain.settings(name, config.settings, scope == "Project" and ctx.root or nil)
		local lines = vim.split(vim.inspect(settings or config or spec), "\n", { plain = true })
		local buf, win = ui.float({ title = " " .. name .. " defaults ", lines = lines, width = 0.75, height = 0.65 })
		maps(buf, {
			q = function()
				vim.api.nvim_win_close(win, true)
			end,
			["<Esc>"] = function()
				vim.api.nvim_win_close(win, true)
			end,
		})
	end)
	require("plugins.fox.git.git_center.diff_menu").open(name, cards, function(index)
		actions[index]()
	end)
end

local function open()
	local buf = vim.api.nvim_get_current_buf()
	local ctx = toolchain.context(buf)
	if ctx.ft == "" or vim.bo[buf].buftype ~= "" then
		vim.notify("Open a file with a detected language first", vim.log.levels.WARN)
		return
	end
	local defaults = toolchain.catalog(ctx)
	local menu = require("plugins.fox.git.git_center.diff_menu")
	local show_cards
	local function show_list(category)
		local key = category.key
		local candidates = defaults[key]
		local scope = "Project"
		local list, win = ui.float({
			width = 1,
			height = 1,
			title = " " .. category.title .. " / " .. ctx.ft .. " ",
			border = { "+", "-", "+", "|", "+", "-", "+", "|" },
		})
		vim.wo[win].cursorline = true
		vim.wo[win].wrap = false
		local rows, selected, state
		local function target()
			return scope == "Global" and toolchain.global_context(ctx) or ctx
		end
		local function draw(focused)
			state = toolchain.read(target(), scope == "Global")
			selected = toolchain.selection(state, key, candidates.enabled)
			rows = vim.tbl_filter(function(name)
				return vim.tbl_contains(candidates.available, name)
			end, selected)
			for _, name in ipairs(candidates.available) do
				if not vim.tbl_contains(rows, name) then
					rows[#rows + 1] = name
				end
			end
			local mode = state.formatter_mode or (candidates.fallback and "fallback" or "pipeline")
			local width = math.max(1, math.min(76, vim.o.columns - 4))
			local status = scope:upper()
			if key == "formatters" then
				status = status .. (mode == "fallback" and "  /  FIRST AVAILABLE" or "  /  RUN ALL IN ORDER")
			end
			local divider = "  +" .. string.rep("-", math.max(0, width - 6)) .. "+"
			local lines = {
				"  " .. status,
				divider,
				"  PRIO   TOOL",
				divider,
			}
			local enabled_rows = {}
			for row, name in ipairs(rows) do
				local index = vim.fn.index(selected, name)
				lines[#lines + 1] = ("  [%s]  %s"):format(index >= 0 and ("%02d"):format(index + 1) or "  ", name)
				if index >= 0 then
					enabled_rows[#enabled_rows + 1] = first_tool_row + row - 2
				end
			end
			if #rows == 0 then
				lines[#lines + 1] = "  No tools registered for " .. ctx.ft
			end
			lines[#lines + 1] = divider
			local hints_start = #lines
			local mode_key = key == "formatters" and "[m] Format mode" or "[g] Project / Global"
			local hints = width >= 64
					and {
						"  [Space] Toggle     [o] Only this    [K/J] Priority",
						"  [e] Edit          [c] Filenames    " .. mode_key,
						"  [r] Reset         [q] Back",
					}
				or {
					"  [Space] Toggle   [o] Only this",
					"  [K/J] Priority   [e] Edit",
					"  [c] Filenames    [r] Reset",
					"  " .. mode_key .. "   [q] Back",
				}
			vim.list_extend(lines, hints)
			local height = math.max(1, math.min(#lines, vim.o.lines - 4))
			local row, col = ui.center(width, height)
			vim.api.nvim_win_set_config(win, { relative = "editor", width = width, height = height, row = row, col = col })
			vim.bo[list].modifiable = true
			vim.api.nvim_buf_set_lines(list, 0, -1, false, lines)
			vim.bo[list].modifiable = false
			vim.api.nvim_buf_clear_namespace(list, list_highlights, 0, -1)
			vim.api.nvim_buf_set_extmark(list, list_highlights, 0, 0, { end_col = #lines[1], hl_group = "Title" })
			for _, enabled_row in ipairs(enabled_rows) do
				vim.api.nvim_buf_set_extmark(list, list_highlights, enabled_row, 2, { end_col = 6, hl_group = "DiagnosticOk" })
			end
			for line = hints_start, #lines - 1 do
				for start_col, end_col in lines[line + 1]:gmatch("()%[[^%]]+%]()") do
					vim.api.nvim_buf_set_extmark(list, list_highlights, line, start_col - 1, {
						end_col = end_col - 1,
						hl_group = "Special",
					})
				end
			end
			local focus_index = focused and vim.fn.index(rows, focused) or -1
			vim.api.nvim_win_set_cursor(win, { first_tool_row + math.max(0, focus_index), 0 })
		end
		local function current()
			return rows[vim.api.nvim_win_get_cursor(win)[1] - first_tool_row + 1]
		end
		local function save(field, value, focused, restart)
			local ok, err = toolchain.save(target(), field, value)
			if not ok then
				vim.notify(err, vim.log.levels.ERROR)
				return
			end
			if key ~= "formatters" then
				toolchain.refresh(ctx, restart, scope == "Global")
			end
			draw(focused)
		end
		local function choose(only)
			local name = current()
			if not name then
				return
			end
			local choices = only and { name } or vim.deepcopy(selected)
			if not only then
				local at = vim.fn.index(choices, name) + 1
				if at > 0 then
					table.remove(choices, at)
				else
					choices[#choices + 1] = name
				end
			end
			save(key, choices, name)
		end
		local function move(delta)
			local name = current()
			local at = name and vim.fn.index(selected, name) + 1 or 0
			local to = at + delta
			if at > 0 and to >= 1 and to <= #selected then
				selected[at], selected[to] = selected[to], selected[at]
				save(key, selected, name)
			end
		end
		local function back()
			vim.api.nvim_win_close(win, true)
			show_cards()
		end
		maps(list, {
			q = back,
			["<Esc>"] = back,
			["<Space>"] = function()
				choose(false)
			end,
			o = function()
				choose(true)
			end,
			J = function()
				move(1)
			end,
			K = function()
				move(-1)
			end,
			r = function()
				save(key, nil)
			end,
			g = function()
				if key ~= "formatters" then
					scope = scope == "Global" and "Project" or "Global"
					draw(current())
				end
			end,
			m = function()
				if key == "formatters" then
					local mode = state.formatter_mode or (candidates.fallback and "fallback" or "pipeline")
					save("formatter_mode", mode == "fallback" and "pipeline" or "fallback", current())
				end
			end,
			e = function()
				local name = current()
				if name then
					edit(ctx, scope, key, name, candidates.servers[name])
				end
			end,
			c = function()
				local name = current()
				if not name then
					return
				end
				local markers = toolchain.markers(state, key, name) or toolchain.metadata(name).files or {}
				vim.ui.input(
					{ prompt = "Config filenames (comma separated): ", default = table.concat(markers, ", ") },
					function(input)
						if input == nil or not vim.api.nvim_win_is_valid(win) then
							return
						end
						local names = vim.split(vim.trim(input), ",", { trimempty = true })
						names = vim.tbl_map(vim.trim, names)
						for _, filename in ipairs(names) do
							if not toolchain.valid_filename(filename) then
								vim.notify("Use filenames without directory components", vim.log.levels.ERROR)
								return
							end
						end
						local overrides = toolchain.read(target(), true).markers
						overrides = type(overrides) == "table" and overrides or {}
						overrides[key .. "/" .. name] = names
						save("markers", overrides, name, candidates.servers[name] and name or nil)
					end
				)
			end,
		})
		local resize = vim.api.nvim_create_autocmd("VimResized", {
			callback = function()
				if vim.api.nvim_win_is_valid(win) then
					draw(current())
				end
			end,
		})
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = list,
			once = true,
			callback = function()
				vim.api.nvim_del_autocmd(resize)
			end,
		})
		draw()
	end
	show_cards = function()
		menu.open("Language Configure / " .. ctx.ft, categories, function(index)
			show_list(categories[index])
		end, nil, 3)
	end
	show_cards()
end

return {
	name = "fox_configure_language",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = "ConfigureCurrentLanguage",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		vim.api.nvim_create_user_command("ConfigureCurrentLanguage", open, { desc = "Configure current language tools" })
		require("fox.langs.toolchain_lint").setup()
	end,
}
