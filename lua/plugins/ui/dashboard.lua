-- ============================================================================
-- PLUGINS: Native FoxVim Dashboard with Environment Detection & Responsive Banners
-- ============================================================================

local env_lib = require("fox.core.environment")

local settings = {
	--- Colour of the ASCII banner. Re-applied on every colorscheme change.
	header_highlight = { name = "AlphaHeaderOrange", opts = { fg = "#FF8800", bold = true } },

	--- Menu entries, in order: { key, icon, label, command }.
	buttons = {
		{ "p", "💼", "Recent projects", ":RecentProjects<CR>" },
		{ "f", "📁", "File Explorer", ":TelescopeFileBrowserDesktop<CR>" },
		{ "n", "📝", "Notes", ":Notes<CR>" },
		{ "s", "📦", "Dependencies & Toolchains", ":FoxInstallDependencies<CR>" },
		{ "h", "🩺", "Health Check", ":FoxHealthCheck<CR>" },
		{ "w", "📚", "Wiki & Docs (Ctrl+Shift+D)", ":FoxWiki<CR>" },
		{ "e", "🧩", "Plugins & Extensions", ":Lazy<CR>" },
		{ "m", "⚙️", "Server Manager (Mason)", ":Mason<CR>" },
		{ "q", "🚪", "Quit", ":qa<CR>" },
	},

	--- WSL entry, inserted at this position when WSL is available.
	wsl_button = { "l", "🐧", "File Explorer (WSL)", ":TelescopeFileBrowserWSL<CR>" },
	wsl_button_position = 5,

	--- Filetypes that must never be replaced by the dashboard.
	protected_filetypes = { "alpha", "neo-tree" },
}

return {
	name = "fox_dashboard",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = { "Alpha", "AlphaRedraw" },
	lazy = false,
	config = function()
		local alpha = require("fox.ui.dashboard")
		local dashboard = alpha.layout()
		local env = env_lib.detect()

		local artwork = require("fox.ui.dashboard_art")
		dashboard.opts.artwork = artwork
		dashboard.opts.layout[1].val = 0
		dashboard.opts.large_header = {
			[[      ___           ___           ___           ___           ___                       ___     ]],
			[[     /\  \         /\  \         |\__\         /\__\         /\__\          ___        /\__\    ]],
			[[    /::\  \       /::\  \        |:|  |       /::|  |       /:/  /         /\  \      /::|  |   ]],
			[[   /:/\:\  \     /:/\:\  \       |:|  |      /:|:|  |      /:/  /          \:\  \    /:|:|  |   ]],
			[[  /::\~\:\  \   /:/  \:\  \      |:|__|__   /:/|:|  |__   /:/__/  ___      /::\__\  /:/|:|__|__ ]],
			[[ /:/\:\ \:\__\ /:/__/ \:\__\ ____/::::\__\ /:/ |:| /\__\  |:|  | /\__\  __/:/\/__/ /:/ |::::\__\ ]],
			[[ \/__\:\ \/__/ \:\  \ /:/  / \::::/~~/~    \/__|:|/:/  /  |:|  |/:/  / /\/:/  /    \/__/~~/:/  / ]],
			[[      \:\__\    \:\  /:/  /   ~~|:|~~|         |:/:/  /   |:|__/:/  /  \::/__/           /:/  /  ]],
			[[       \/__/     \:\/:/  /      |:|  |         |::/  /     \::::/__/    \:\__\          /:/  /   ]],
			[[                  \::/  /       |:|  |         /:/  /       ~~~~         \/__/         /:/  /    ]],
			[[                   \/__/         \|__|         \/__/                                   \/__/     ]],
		}
		dashboard.section.header.val = {
			[[  _____ ___ __  __ _   _ __     _____ __  __  ]],
			[[ |  ___/ _ \ \/ /| \ | |\ \   / /_ _|  \/  | ]],
			[[ | |_ | | | |\  / |  \| | \ \ / / | || |\/| | ]],
			[[ |  _|| |_| |/  \ | |\  |  \ V /  | || |  | | ]],
			[[ |_|   \___//_/\_\_| \_|   \_/  |___|_|  |_| ]],
		}

		local function refresh_dashboard()
			pcall(alpha.redraw)
		end

		_G.Alpha_Refresh_Header = refresh_dashboard

		-- Dynamic header update on window resize (e.g. rotating phone screen or resizing split / neo-tree width)
		vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
			group = vim.api.nvim_create_augroup("AlphaResponsiveHeader", { clear = true }),
			callback = function()
				vim.schedule(refresh_dashboard)
			end,
		})

		vim.api.nvim_create_autocmd("BufWinEnter", {
			group = "AlphaResponsiveHeader",
			callback = function(ctx)
				local buf = ctx.buf
				if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "alpha" then
					vim.schedule(refresh_dashboard)
				end
			end,
		})

		-- `:colorscheme` clears user-defined groups, so the banner colour is
		-- re-applied whenever the theme changes, adapting to the active theme accent.
		local function set_header_highlight()
			local hl = vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false })
			local fg = hl and hl.fg
			if not fg then
				local cur_hl = vim.api.nvim_get_hl(0, { name = "CursorLineNr", link = false })
				fg = cur_hl and cur_hl.fg
			end
			local opts = { fg = fg or "#d2824e", bold = true }
			vim.api.nvim_set_hl(0, "AlphaHeaderTheme", opts)
			vim.api.nvim_set_hl(0, settings.header_highlight.name, opts)
		end
		set_header_highlight()
		vim.api.nvim_create_autocmd("ColorScheme", { callback = set_header_highlight })
		dashboard.section.header.opts.hl = "AlphaHeaderTheme"

		--- Turns a settings entry into an alpha button.
		--- @param entry table `{ key, icon, label, command }`
		local function make_button(entry)
			local icon = entry[2] ~= "" and (entry[2] .. "  ") or ""
			return dashboard.button(entry[1], icon .. entry[3], entry[4])
		end

		dashboard.section.buttons.val = vim.tbl_map(make_button, settings.buttons)

		-- The WSL entry would be a dead end on a machine without WSL.
		local ok_wsl, wsl = pcall(require, "plugins.fox.tools.wsl")
		if ok_wsl and wsl.available() then
			table.insert(dashboard.section.buttons.val, settings.wsl_button_position, make_button(settings.wsl_button))
		end
		table.insert(
			dashboard.section.buttons.val,
			dashboard.button("v", function()
				return require("fox.core.plain_editing").enabled and "Vim motions: OFF (click to enable)"
					or "Vim motions: ON (click to disable)"
			end, ":FoxToggleVimMotions<CR>")
		)

		dashboard.section.footer.val = "⚡ FOX Neovim (" .. env.label .. ")"

		-- alpha redraws on WinResized, which fires while a window is already gone
		-- (closing a split or the explorer) and then throws "invalid window id".
		-- Wrapping both entry points keeps that out of the message history.
		for _, name in ipairs({ "redraw", "draw" }) do
			local original = alpha[name]
			alpha[name] = function(...)
				return pcall(original, ...)
			end
		end

		alpha.setup(dashboard.opts)

		local function show_dashboard()
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].filetype ~= "neo-tree" and vim.bo[buf].buftype ~= "terminal" then
					if vim.bo[buf].filetype == "alpha" then
						return
					end
					vim.api.nvim_win_call(win, function()
						vim.cmd("Alpha")
					end)
					return
				end
			end

			-- If we reach here, there are no normal code windows, only neo-tree or terminals.
			-- Find neo-tree and split it to the right, so we don't accidentally split the terminal dock.
			for _, win in ipairs(vim.api.nvim_list_wins()) do
				local buf = vim.api.nvim_win_get_buf(win)
				if vim.bo[buf].filetype == "neo-tree" then
					vim.api.nvim_win_call(win, function()
						vim.cmd("rightbelow vsplit | Alpha")
					end)
					return
				end
			end

			-- Fallback if not even neo-tree exists
			vim.cmd("vsplit | Alpha")
		end

		local function has_pins()
			local ok, pinned_tabs = pcall(require, "plugins.fox.ui.pinned_tabs")
			return ok and #pinned_tabs.load_pins() > 0
		end

		-- Closing the last real buffer shows the dashboard instead of quitting.
		vim.api.nvim_create_autocmd("BufDelete", {
			callback = function()
				vim.schedule(function()
					local listed = vim.tbl_filter(function(b)
						return vim.fn.buflisted(b) == 1 and vim.api.nvim_buf_get_name(b) ~= ""
					end, vim.api.nvim_list_bufs())

					if #listed == 0 and not has_pins() then
						show_dashboard()
					end
				end)
			end,
		})
	end,
}
