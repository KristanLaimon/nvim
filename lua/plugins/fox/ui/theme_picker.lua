-- ============================================================================
-- FOX PLUGIN: Nagatoro Theme System & Interactive Theme Picker.
-- ============================================================================
-- WHAT IT DOES
--   Discovers all themes formatted for nagatoro-fox (nagatoro-fox, nagatoro-light,
--   onedark-fox, catppuccin-fox, nord-fox), previews them live in Telescope or
--   vim.ui.select, and persists choice in .foxnvim/theme.json.
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local store = lazy_req("fox.core.store")

local M = {}
local project = lazy_req("fox.core.project")

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.foxnvim/theme.json",
	default_theme = "nagatoro-fox",
	keymap = nil,
}

--- Scans config/colors/ directory for available nagatoro-fox formatted themes.
--- @return string[] theme_names
function M.discover_themes()
	local themes = {}
	local colors_dir = vim.fn.stdpath("config") .. "/config/colors"
	local files = vim.fn.globpath(colors_dir, "*.lua", false, true)

	for _, file in ipairs(files) do
		local name = vim.fn.fnamemodify(file, ":t:r")
		if name == "ryoku-fox" then
			if require("plugins.fox.ui.ryoku_theme").is_available() then
				table.insert(themes, name)
			end
		elseif name == "omarchy-fox" then
			local has_omarchy, omarchy_mod = pcall(require, "plugins.fox.ui.omarchy_theme")
			if has_omarchy and omarchy_mod.is_omarchy_available() then
				table.insert(themes, name)
			end
		elseif name:match("%-fox$") or name:match("^nagatoro%-") or name == "dark-fox-night" then
			table.insert(themes, name)
		end
	end

	table.sort(themes)
	if #themes == 0 then
		table.insert(themes, M.settings.default_theme)
	end

	return themes
end

--- Project themes are read exclusively from .foxnvim, never compatibility folders.
function M.project_theme_file(root)
	return (root or project.root()) .. "/.foxnvim/theme.json"
end

function M.get_project_theme()
	local file = M.project_theme_file()
	if vim.fs.normalize(file) == vim.fs.normalize(M.settings.store_file) then
		return nil
	end
	local data = store.load(file, {})
	if type(data.theme) == "string" and data.theme:match("^[%w_-]+$") then
		return data.theme
	end
end

--- Gets the project override or global default.
function M.get_current_theme()
	local data = store.load(M.settings.store_file, {})
	return M.get_project_theme() or data.theme or M.settings.default_theme
end

--- Applies colorscheme and saves to store.
--- @param name string
function M.set_theme(name, scope, project_file)
	if not name or name == "" then
		return
	end
	local ok, err = pcall(vim.cmd.colorscheme, name)
	if not ok or vim.g.colors_name ~= name then
		vim.notify("Failed to apply theme " .. name .. ": " .. tostring(err or "palette unavailable"), vim.log.levels.ERROR)
		return
	end
	local is_project = scope == "project"
	local file = is_project and (project_file or M.project_theme_file()) or M.settings.store_file
	local data = store.load(file, {})
	data.theme = name
	if not is_project then
		data.ryoku_sync = name == "ryoku-fox"
		data.omarchy_sync = name == "omarchy-fox"
	end
	ok, err = store.save(file, data)
	if not ok then
		vim.notify("Failed to save theme to " .. file .. ": " .. tostring(err), vim.log.levels.ERROR)
	end
	M.restore_saved_theme()
end

--- Restores persisted theme on startup.
function M.restore_saved_theme()
	M._project_file = M.project_theme_file()
	local override = M.get_project_theme()
	local ryoku = require("plugins.fox.ui.ryoku_theme")
	ryoku.stop_watcher()
	local omarchy = require("plugins.fox.ui.omarchy_theme")
	omarchy.stop_watcher()
	if override then
		local ok = pcall(vim.cmd.colorscheme, override)
		if ok and vim.g.colors_name == override then
			if override == "ryoku-fox" then
				ryoku.setup()
				ryoku.start_watcher()
			elseif override == "omarchy-fox" then
				omarchy.start_watcher()
			end
			return
		end
	end
	if ryoku.is_sync_enabled() and ryoku.apply({ quiet = true }) then
		ryoku.setup()
		ryoku.start_watcher()
		return
	end
	local has_omarchy, omarchy_mod = pcall(require, "plugins.fox.ui.omarchy_theme")
	if has_omarchy and omarchy_mod.is_sync_enabled() and omarchy_mod.is_omarchy_available() then
		omarchy_mod.apply_omarchy_theme({ quiet = true })
		omarchy_mod.start_watcher()
		return
	end

	local saved = store.load(M.settings.store_file, {}).theme or M.settings.default_theme
	if saved then
		pcall(vim.cmd.colorscheme, saved)
	end
end

--- Ask after theme selection so cancelling never persists a preview.
function M.choose_scope(name, original_theme, project_file)
	vim.ui.select({ "Global theme", "This project only" }, { prompt = "Save UI-Theme for:" }, function(choice)
		pcall(vim.cmd.colorscheme, original_theme)
		if choice then
			M.set_theme(name, choice == "This project only" and "project" or "global", project_file)
		end
	end)
end

--- Opens interactive theme picker with live preview.
function M.open_picker()
	local themes = M.discover_themes()
	local project_file = M.project_theme_file()
	local original_theme = vim.g.colors_name or M.settings.default_theme

	local has_telescope = pcall(require, "telescope.builtin")
	local has_actions, actions = pcall(require, "telescope.actions")
	local has_action_state, action_state = pcall(require, "telescope.actions.state")

	if has_telescope and has_actions and has_action_state then
		local pickers = require("telescope.pickers")
		local finders = require("telescope.finders")
		local conf = require("telescope.config").values

		pickers
			.new({}, {
				prompt_title = "Select UI-Theme",
				finder = finders.new_table({ results = themes }),
				sorter = conf.generic_sorter({}),
				attach_mappings = function(prompt_bufnr, map)
					local function preview_selection()
						local selection = action_state.get_selected_entry()
						if selection and selection[1] then
							pcall(vim.cmd.colorscheme, selection[1])
						end
					end

					local function cancel_selection()
						actions.close(prompt_bufnr)
						pcall(vim.cmd.colorscheme, original_theme)
					end

					map("i", "<Tab>", function()
						actions.move_selection_next(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<S-Tab>", function()
						actions.move_selection_previous(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<Down>", function()
						actions.move_selection_next(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<Up>", function()
						actions.move_selection_previous(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<C-n>", function()
						actions.move_selection_next(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<C-p>", function()
						actions.move_selection_previous(prompt_bufnr)
						preview_selection()
					end)

					map("n", "j", function()
						actions.move_selection_next(prompt_bufnr)
						preview_selection()
					end)

					map("n", "k", function()
						actions.move_selection_previous(prompt_bufnr)
						preview_selection()
					end)

					map("i", "<Esc>", cancel_selection)
					map("n", "<Esc>", cancel_selection)
					map("n", "q", cancel_selection)

					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)
						if selection and selection[1] then
							M.choose_scope(selection[1], original_theme, project_file)
						end
					end)

					return true
				end,
			})
			:find()
	else
		vim.ui.select(themes, { prompt = "Select UI-Theme:" }, function(choice)
			if choice then
				M.choose_scope(choice, original_theme, project_file)
			else
				pcall(vim.cmd.colorscheme, original_theme)
			end
		end)
	end
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	vim.api.nvim_create_user_command("FoxThemePicker", function(opts)
		if opts.args and opts.args ~= "" then
			M.choose_scope(opts.args, vim.g.colors_name or M.settings.default_theme, M.project_theme_file())
		else
			M.open_picker()
		end
	end, {
		nargs = "?",
		complete = function()
			return M.discover_themes()
		end,
		desc = "Select UI-Theme",
	})

	local pending = false
	vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter", "DirChanged" }, {
		group = vim.api.nvim_create_augroup("fox_project_theme", { clear = true }),
		callback = function(args)
			if args.event == "BufEnter" and vim.bo[args.buf].buftype ~= "" then
				return
			end
			if pending then
				return
			end
			pending = true
			vim.schedule(function()
				pending = false
				local file = M.project_theme_file()
				if M._project_file ~= file then
					M._project_file = file
					M.restore_saved_theme()
				end
			end)
		end,
	})

	if M.settings.keymap then
		vim.keymap.set("n", M.settings.keymap, M.open_picker, { desc = "Select UI-Theme" })
	end
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "fox_theme_picker",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = "FoxThemePicker",
	keys = {},
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
