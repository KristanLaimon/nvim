-- ============================================================================
-- FOX PLUGIN: Statusline Theme Picker & NvChad Statusline Engine.
-- ============================================================================
-- WHAT IT DOES
--   Provides NvChad-style statusline layouts (pills, blocks, classic, minimal,
--   vscode) and an interactive theme picker command `:FoxStatuslineTheme`.
-- ============================================================================

local store = require("fox.core.store")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.foxnvim/statusline.json",
	default_theme = "nvchad_pills",
}

M.available_themes = {
	nvchad_pills = "NvChad Pills (Rounded Statusline)",
	nvchad_blocks = "NvChad Blocks (Slanted Powerline)",
	nvchad_round = "NvChad Round (Curved Slants)",
	nagatoro_classic = "Nagatoro Classic (Minimal & Clean)",
	vscode = "VSCode Modern (Flat Bar)",
	minimal = "Minimalist (Compact)",
}

--- Formats active LSP clients into NvChad statusline string.
--- @return string lsp_info
function M.lsp_status()
	if not vim.lsp then
		return " No LSP"
	end
	local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
	if not get_clients then
		return " No LSP"
	end
	local clients = get_clients({ bufnr = 0 })
	if not clients or #clients == 0 then
		return " No LSP"
	end
	local names = {}
	for _, client in ipairs(clients) do
		if client.name and client.name ~= "null-ls" and client.name ~= "copilot" then
			table.insert(names, client.name)
		end
	end
	if #names == 0 then
		return " Active"
	end
	return " " .. table.concat(names, ", ")
end

--- Formats active environment indicator for statusline when > 1 environments are active.
--- @return string env_info
function M.environment_status()
	if _G.Environments and _G.Environments.indicator_status then
		return _G.Environments.indicator_status()
	end
	local ok, envs = pcall(require, "plugins.fox.tools.environments")
	if ok and envs.indicator_status then
		return envs.indicator_status()
	end
	return ""
end

function M.workflow_status()
	local query, active = package.loaded["fox.query"], false
	if query then
		for _, state in pairs(query.states) do
			if state.mode == "query" and state.tab == vim.api.nvim_get_current_tabpage() then
				active = true
				break
			end
		end
	end
	local normal, dim = "%#StatusLine#", "%#FoxWorkflowInactive#"
	return normal
		.. "["
		.. (active and dim or normal)
		.. "Editor"
		.. normal
		.. " | "
		.. (active and normal or dim)
		.. "Query"
		.. normal
		.. "]"
end

--- Formats editor mode into NvChad style pill string.
--- @param mode_str string
--- @return string formatted
function M.format_mode(mode_str)
	local modes = {
		["NORMAL"] = " NORMAL",
		["INSERT"] = "󰏫 INSERT",
		["VISUAL"] = "󰈈 VISUAL",
		["V-LINE"] = "󰈈 V-LINE",
		["V-BLOCK"] = "󰈈 V-BLOCK",
		["SELECT"] = "󰈈 SELECT",
		["S-LINE"] = "󰈈 S-LINE",
		["S-BLOCK"] = "󰈈 S-BLOCK",
		["REPLACE"] = "󰛔 REPLACE",
		["V-REPLACE"] = "󰛔 V-REPLACE",
		["COMMAND"] = "󰘳 COMMAND",
		["EX"] = "󰘳 EX",
		["MORE"] = "󰘳 MORE",
		["CONFIRM"] = "󰘳 CONFIRM",
		["SHELL"] = "󰞷 SHELL",
		["TERMINAL"] = "󰞷 TERMINAL",
	}
	return modes[mode_str] or (" " .. mode_str)
end

--- Extracts a clean, concise process title from vim.b.term_title or raw terminal URL.
--- @param str string Raw buffer name or term:// string
--- @return string|nil title
function M.get_term_title(str)
	local title = vim.b and vim.b.term_title
	if type(title) == "string" and title ~= "" and not title:find("^term://") then
		title = title:gsub("^Administrator:%s*", "")
		title = title:gsub("^Windows PowerShell", "powershell")
		if title:find("[/\\]") then
			title = vim.fn.fnamemodify(title, ":t")
		end
		title = title:gsub("%.[eE][xX][eE]$", "")
		title = vim.trim(title)
		if #title > 30 then
			title = title:sub(1, 27) .. "..."
		end
		if title ~= "" then
			return title
		end
	end

	if str then
		local shell_path = str:match("//%d+:(.*)$") or str:match(".*:(.*)$")
		if shell_path and shell_path ~= "" then
			shell_path = shell_path:gsub("\\", "/")
			local shell_name = vim.fn.fnamemodify(shell_path, ":t"):gsub("%.[eE][xX][eE]$", "")
			if shell_name ~= "" then
				return shell_name
			end
		end
	end

	return nil
end

--- Formats filename for statusline, simplifying raw terminal URLs (term://...) into clean labels.
--- @param str string
--- @return string formatted
function M.format_filename(str)
	if not str or str == "" then
		return "[No Name]"
	end

	local is_term = false
	if vim.bo and vim.bo.buftype == "terminal" then
		is_term = true
	elseif str:find("^term://") then
		is_term = true
	end

	if is_term then
		local title = M.get_term_title(str)

		if vim.b and vim.b.fox_task_name then
			if title and title ~= "" and title ~= vim.b.fox_task_name then
				return "🖥️ Task: " .. tostring(vim.b.fox_task_name) .. " - " .. title
			end
			return "🖥️ Task: " .. tostring(vim.b.fox_task_name)
		end

		if vim.b and vim.b.fox_term_num then
			local num = tostring(vim.b.fox_term_num)
			if title and title ~= "" then
				return "󰞷 Terminal #" .. num .. " - " .. title
			end
			return "󰞷 Terminal #" .. num
		end

		if title and title ~= "" then
			return "󰞷 Terminal (" .. title .. ")"
		end

		return "󰞷 Terminal"
	end

	return str
end

--- Formats current buffer line ending into a statusline label (LF / CRLF / CR).
--- @return string formatted
function M.fileformat_status()
	local fmt = vim.bo[vim.api.nvim_get_current_buf()].fileformat
	local map = { unix = "LF", dos = "CRLF", mac = "CR" }
	return "⏎ " .. (map[fmt] or fmt:upper())
end

--- Formats active Python interpreter version & env for statusline when editing Python files or when Python LSP is active.
--- @return string python_info
function M.python_status()
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return ""
	end
	local ft = vim.bo[buf].filetype
	local show = (ft == "python")
	if not show then
		local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
		local clients = get_clients and get_clients({ bufnr = buf }) or {}
		for _, c in ipairs(clients) do
			if c.name == "basedpyright" or c.name == "pyright" or c.name == "ruff" then
				show = true
				break
			end
		end
	end
	if not show then
		return ""
	end

	local ok, py = pcall(require, "fox.langs.python")
	if ok and py.python_status then
		return py.python_status()
	end
	return ""
end

--- Returns cached branch immediately; resolution completes asynchronously.
function M.resolve_git_branch(dir)
	return require("fox.ui.statusline_git").branch(dir or vim.fn.getcwd())
end

--- Formats active git branch for statusline.
--- Accurately resolves active branch for file, terminal, or working directory.
--- @return string branch_name
function M.git_branch()
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) then
		return M.resolve_git_branch(vim.fn.getcwd())
	end

	local gitsigns_head = vim.b[buf] and vim.b[buf].gitsigns_head
	if gitsigns_head and gitsigns_head ~= "" then
		return gitsigns_head
	end

	local name = vim.api.nvim_buf_get_name(buf)
	if name and name:find("^term://") then
		local extracted = name:gsub("term://(.-)//.*", "%1")
		if extracted and extracted ~= "" then
			return M.resolve_git_branch(extracted)
		end
	end

	if name and name ~= "" and vim.bo[buf].buftype == "" then
		local fdir = vim.fs.dirname(name)
		if fdir and fdir ~= "" then
			return M.resolve_git_branch(fdir)
		end
	end

	return M.resolve_git_branch(vim.fn.getcwd())
end

--- Retrieves current statusline theme selection.
--- @return string theme_name
function M.get_current_theme()
	local data = store.load(M.settings.store_file, {})
	return data.theme or M.settings.default_theme
end

--- Generates native statusline layout for a given statusline theme.
--- @param theme_name string
--- @return table statusline_options
function M.get_config(theme_name)
	M.setup()
	theme_name = theme_name or M.get_current_theme()

	local common_diagnostics = {
		"diagnostics",
		symbols = { error = " ", warn = " ", info = "󰋼 ", hint = "󰌵 " },
	}

	local common_diff = {
		"diff",
		symbols = { added = " ", modified = "󰝤 ", removed = " " },
	}

	local common_filename = {
		"filename",
		file_status = true,
		path = 1,
		fmt = M.format_filename,
		symbols = { modified = " 󰏫", readonly = " 󰌾", unnamed = "[No Name]", newfile = "[New]" },
	}

	if theme_name == "nvchad_blocks" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				a = { { "mode", fmt = M.format_mode } },
				b = {
					M.fileformat_status,
					M.environment_status,
					{ M.git_branch, icon = "" },
					common_diff,
					common_diagnostics,
				},
				c = { M.workflow_status, common_filename },
				x = { M.python_status, M.lsp_status, "filetype" },
				y = { "encoding", "fileformat" },
				z = { { "location", icon = "" }, "progress" },
			},
		}
	elseif theme_name == "nvchad_round" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				a = { { "mode", fmt = M.format_mode } },
				b = {
					M.fileformat_status,
					M.environment_status,
					{ M.git_branch, icon = "" },
					common_diff,
					common_diagnostics,
				},
				c = { M.workflow_status, common_filename },
				x = { M.python_status, M.lsp_status, "filetype" },
				y = { "encoding" },
				z = { { "location", icon = "" }, "progress" },
			},
		}
	elseif theme_name == "vscode" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
			},
			sections = {
				a = { "mode" },
				b = { M.fileformat_status, M.environment_status, { M.git_branch, icon = "" }, common_diagnostics },
				c = { M.workflow_status, common_filename },
				x = { M.python_status, M.lsp_status, "filetype" },
				y = { "progress" },
				z = { "location" },
			},
		}
	elseif theme_name == "minimal" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
				component_separators = "",
				section_separators = "",
			},
			sections = {
				a = { "mode" },
				b = { M.fileformat_status, M.environment_status, common_filename },
				c = { M.workflow_status },
				x = { M.python_status, { M.git_branch, icon = "" }, M.lsp_status },
				y = { "filetype" },
				z = { "location" },
			},
		}
	elseif theme_name == "nagatoro_classic" then
		return {
			options = {
				theme = "auto",
				globalstatus = true,
			},
			sections = {
				a = {
					M.fileformat_status,
					M.environment_status,
					{ M.git_branch, icon = "🌿" },
					common_diff,
					common_diagnostics,
				},
				b = { common_filename },
				c = { M.workflow_status },
				x = {
					{
						"mode",
						fmt = function(str)
							return "-- " .. str .. " --"
						end,
					},
					M.python_status,
					"encoding",
					"fileformat",
					"filetype",
				},
				y = { "progress" },
				z = { "location" },
			},
		}
	end

	-- Default: nvchad_pills
	return {
		options = {
			theme = "auto",
			globalstatus = true,
			component_separators = { left = "", right = "" },
			section_separators = { left = "", right = "" },
		},
		sections = {
			a = { { "mode", fmt = M.format_mode } },
			b = {
				M.fileformat_status,
				M.environment_status,
				{ M.git_branch, icon = "" },
				common_diff,
				common_diagnostics,
			},
			c = { M.workflow_status, common_filename },
			x = { M.python_status, M.lsp_status, "filetype" },
			y = { "encoding" },
			z = { { "location", icon = "" }, "progress" },
		},
	}
end

--- Sets active statusline theme and applies configuration.
--- @param theme_name string
function M.set_theme(theme_name)
	if not M.available_themes[theme_name] then
		vim.notify("Unknown statusline theme: " .. tostring(theme_name), vim.log.levels.WARN)
		return
	end

	local ok, err = store.save(M.settings.store_file, { theme = theme_name })
	if not ok then
		vim.notify("Cannot save statusline theme: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	require("fox.ui.statusline").setup(M.get_config(theme_name))
	vim.notify("Statusline theme set to: " .. M.available_themes[theme_name], vim.log.levels.INFO)
end

--- Opens interactive statusline theme picker.
function M.open_picker()
	local items = {}
	local keys = {}
	for k, label in pairs(M.available_themes) do
		table.insert(keys, k)
		table.insert(items, label .. " (" .. k .. ")")
	end

	vim.ui.select(items, { prompt = "Select Statusline Theme:" }, function(choice, index)
		if choice and index then
			M.set_theme(keys[index])
		end
	end)
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true
	local function workflow_highlight()
		local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
		local status = vim.api.nvim_get_hl(0, { name = "StatusLine", link = false })
		vim.api.nvim_set_hl(0, "FoxWorkflowInactive", { fg = comment.fg, bg = status.bg, bold = false })
	end
	workflow_highlight()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("FoxStatuslineWorkflow", { clear = true }),
		callback = workflow_highlight,
	})

	local group = vim.api.nvim_create_augroup("FoxStatuslineTermTitle", { clear = true })
	vim.api.nvim_create_autocmd({ "TermOpen", "TermClose", "TermRequest", "TermEnter", "TermLeave" }, {
		group = group,
		callback = function()
			vim.cmd("redrawstatus")
		end,
	})

	vim.api.nvim_create_user_command("FoxStatuslineTheme", function(opts)
		if opts.args and opts.args ~= "" then
			M.set_theme(opts.args)
		else
			M.open_picker()
		end
	end, {
		nargs = "?",
		complete = function()
			local names = {}
			for k in pairs(M.available_themes) do
				table.insert(names, k)
			end
			return names
		end,
		desc = "Pick or set statusline theme",
	})
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "fox_statusline_picker",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = "FoxStatuslineTheme",
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
