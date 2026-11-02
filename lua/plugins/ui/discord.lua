-- ============================================================================
-- PLUGIN: cord.nvim -- Discord rich presence.
-- ============================================================================
-- Shows what you are editing on your Discord profile: file, repository and
-- elapsed time, idle after five minutes. Purely cosmetic; toggle it at runtime
-- with `:Cord toggle` (also in the command palette under "Discord").
-- Hot-reload configuration without restarting Neovim via `:CordReload`.
-- ============================================================================

local application_id = "1566816819879092294"

local function hot_reload()
	local presence = package.loaded["fox.discord"]
	if presence and presence.stop then
		presence.stop()
	end
	for _, module in ipairs({ "fox.discord", "fox.discord.ai_cli_names", "fox.discord.loading_msgs" }) do
		package.loaded[module] = nil
	end
	package.loaded["plugins.ui.discord"] = nil

	local ok_spec, spec = pcall(require, "plugins.ui.discord")
	if not ok_spec or type(spec) ~= "table" then
		vim.notify("❌ Failed to reload Discord spec", vim.log.levels.ERROR, { title = "Discord Plugin" })
		return
	end

	local opts = spec.opts or {}
	local ok_cord, cord = pcall(require, "cord")
	if ok_cord and cord.setup then
		if not require("cord.api.config").verify(opts) then
			return
		end
		require("fox.discord").setup()
		cord.setup(opts)
		pcall(function()
			require("cord.api.command").restart()
		end)
		vim.notify(
			"🎮 Discord plugin (cord.nvim) hot-reloaded successfully!",
			vim.log.levels.INFO,
			{ title = "Discord Plugin" }
		)
	else
		vim.notify(
			"⚠️ cord.nvim module not found, updated spec only",
			vim.log.levels.WARN,
			{ title = "Discord Plugin" }
		)
	end
end

for _, name in ipairs({ "DiscordReload", "CordReload" }) do
	pcall(vim.api.nvim_create_user_command, name, hot_reload, { desc = "Hot-reload Discord plugin (cord.nvim)" })
end

return {
	"vyfor/cord.nvim",
	build = ":Cord update",
	lazy = false,
	config = function(_, opts)
		require("fox.discord").setup()
		require("cord").setup(opts)
	end,
	opts = {
		usercmds = true,
		advanced = {
			plugin = { debounce = { delay = 50, interval = 250 } },
			server = { auto_update = false },
			discord = {
				-- Retry the latest activity when Discord drops a rate-limited update.
				sync = { enabled = true, mode = "periodic", interval = 12000, reset_on_update = false, pad = true },
			},
		},
		timestamp = {
			enabled = true,
		},
		editor = {
			client = application_id,
			tooltip = "Foxnvim",
			icon = "https://raw.githubusercontent.com/vyfor/icons/master/icons/minecraft/dark/neovim.png",
		},
		display = {
			theme = "minecraft",
			flavor = "dark",
			show_time = true,
			show_repository = true,
		},
		idle = {
			enabled = true,
			show_status = true,
			timeout = 300000,
		},
		text = {
			terminal = function()
				local cur_buf = vim.api.nvim_get_current_buf()
				if vim.bo[cur_buf].buftype == "terminal" then
					return require("fox.discord").terminal_text()
				end
				return false
			end,
		},
		hooks = {
			ready = function(manager)
				require("fox.discord").ready(manager)
			end,
			shutdown = function()
				require("fox.discord").shutdown()
			end,
			post_activity = function(opts, activity)
				require("fox.discord").post_activity(opts, activity)
			end,
		},
	},
}
