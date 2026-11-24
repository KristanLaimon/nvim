local toolchain = require("fox.langs.toolchain")
local ui = require("fox.core.ui")

local categories = {
	{ key = "formatters", title = "Formatters", lines = { "Choose a default or a pipeline" } },
	{ key = "linters", title = "Linters", lines = { "Choose diagnostic tools" } },
	{ key = "servers", title = "LSPs", lines = { "Choose language servers" } },
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
		local list, win = ui.float({ width = 0.85, height = 0.65, title = " " .. category.title .. " / " .. ctx.ft .. " " })
		vim.wo[win].cursorline = true
		local rows, selected, state
		local function target()
			return scope == "Global" and toolchain.global_context(ctx) or ctx
		end
		local function draw(cursor)
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
			local mode = (state.formatter_mode or (candidates.fallback and "fallback" or "pipeline"))
			local lines = {
				scope .. (key == "formatters" and "  /  " .. mode or ""),
				"Space toggle   o only   K/J priority   e edit   c filenames",
				"r reset   q back" .. (key == "formatters" and "   m mode" or "   g project/global"),
				"",
			}
			for _, name in ipairs(rows) do
				local index = vim.fn.index(selected, name)
				lines[#lines + 1] = index >= 0 and (" [%d] %s"):format(index + 1, name) or (" [ ] " .. name)
			end
			if #rows == 0 then
				lines[#lines + 1] = " No tools registered for " .. ctx.ft
			end
			vim.bo[list].modifiable = true
			vim.api.nvim_buf_set_lines(list, 0, -1, false, lines)
			vim.bo[list].modifiable = false
			vim.api.nvim_win_set_cursor(win, { math.min(#lines, cursor or 5), 0 })
		end
		local function current()
			local line = vim.api.nvim_win_get_cursor(win)[1]
			return rows[line - 4], line
		end
		local function save(field, value, line, restart)
			local ok, err = toolchain.save(target(), field, value)
			if not ok then
				vim.notify(err, vim.log.levels.ERROR)
				return
			end
			if key ~= "formatters" then
				toolchain.refresh(ctx, restart, scope == "Global")
			end
			draw(line)
		end
		local function choose(only)
			local name, line = current()
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
			save(key, choices, only and 5 or line)
		end
		local function move(delta)
			local name, line = current()
			local at = name and vim.fn.index(selected, name) + 1 or 0
			local to = at + delta
			if at > 0 and to >= 1 and to <= #selected then
				selected[at], selected[to] = selected[to], selected[at]
				save(key, selected, line + delta)
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
					draw()
				end
			end,
			m = function()
				if key == "formatters" then
					local mode = state.formatter_mode or (candidates.fallback and "fallback" or "pipeline")
					save("formatter_mode", mode == "fallback" and "pipeline" or "fallback")
				end
			end,
			e = function()
				local name = current()
				if name then
					edit(ctx, scope, key, name, candidates.servers[name])
				end
			end,
			c = function()
				local name, line = current()
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
						save("markers", overrides, line, candidates.servers[name] and name or nil)
					end
				)
			end,
		})
		draw()
	end
	show_cards = function()
		menu.open("Configure current " .. ctx.ft, categories, function(index)
			show_list(categories[index])
		end)
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
