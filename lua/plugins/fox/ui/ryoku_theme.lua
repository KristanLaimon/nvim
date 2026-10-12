-- Live Ryoku palette adapter. Ryoku owns the source; FoxVim only reads it.
local store = require("fox.core.store")
local M = {}
M.settings = {
	palette_file = vim.fn.expand("~/.cache/ryoku/colors.json"),
	store_file = vim.fn.stdpath("config") .. "/.foxnvim/theme.json",
}

function M.is_available()
	local env = require("fox.core.environment").detect()
	return env.is_ryoku and not env.is_wsl
end

function M.is_sync_enabled()
	return store.load(M.settings.store_file, {}).ryoku_sync == true
end

function M.translate(raw)
	local c = {}
	for key, value in pairs(raw) do
		if type(value) == "string" and value:match("^#%x%x%x%x%x%x$") then
			c[key] = value
		end
	end
	if not c.background or not c.foreground then
		return nil
	end
	local r, g, b = c.background:match("#(%x%x)(%x%x)(%x%x)")
	return {
		mode = (tonumber(r, 16) * 0.299 + tonumber(g, 16) * 0.587 + tonumber(b, 16) * 0.114) > 128 and "light" or "dark",
		background = c.background,
		foreground = c.foreground,
		dark_background = c.surfaceContainerLowest or c.color0,
		lighter_background = c.surfaceContainerHigh or c.color8,
		selection = c.surfaceContainerHighest or c.color8,
		muted = c.outline or c.color8,
		accent = c.primary or c.color4,
		red = c.error or c.color1,
		green = c.color2,
		yellow = c.color3,
		blue = c.color4,
		magenta = c.color5,
		cyan = c.color6,
		orange = c.secondary or c.color11,
		bright_magenta = c.color13,
	}
end

function M.apply(opts)
	opts = opts or {}
	if not M.is_available() then
		return false
	end
	local raw = store.load(M.settings.palette_file, {})
	local colors = M.translate(raw)
	if not colors then
		if not opts.quiet then
			vim.notify("Ryoku palette is unavailable or incomplete", vim.log.levels.WARN)
		end
		return false
	end
	local adapter = require("plugins.fox.ui.omarchy_theme")
	vim.o.background = colors.mode
	vim.g.colors_name = "ryoku-fox"
	for name, spec in pairs(adapter.build_highlights(adapter.build_palette(colors), colors)) do
		vim.api.nvim_set_hl(0, name, spec)
	end
	for i = 0, 15 do
		vim.g["terminal_color_" .. i] = raw["color" .. i]
	end
	M._last = vim.json.encode(raw)
	vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "ryoku-fox", modeline = false })
	return true
end

function M.stop_watcher()
	if M._timer then
		M._timer:stop()
		M._timer:close()
		M._timer = nil
	end
end

function M.start_watcher()
	if M._timer then
		return
	end
	-- Polling survives atomic replacement of the palette and missing cache dirs.
	M._timer = (vim.uv or vim.loop).new_timer()
	M._timer:start(
		1000,
		1000,
		vim.schedule_wrap(function()
			if M.is_sync_enabled() then
				local raw = store.load(M.settings.palette_file, {})
				if vim.json.encode(raw) ~= M._last then
					M.apply({ quiet = true })
				end
			end
		end)
	)
end

function M.set_sync_enabled(enabled, opts)
	opts = opts or {}
	if enabled and not M.apply() then
		return false
	end
	local cfg = store.load(M.settings.store_file, {})
	if enabled then
		if cfg.theme ~= "ryoku-fox" then
			cfg.ryoku_previous_theme = cfg.theme or "nagatoro-fox"
		end
		cfg.theme = "ryoku-fox"
	end
	cfg.ryoku_sync = enabled
	if not enabled and opts.restore_theme ~= false then
		cfg.theme = cfg.ryoku_previous_theme or "nagatoro-fox"
	end
	local ok, err = store.save(M.settings.store_file, cfg)
	if not ok then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return false
	end
	if enabled then
		M.start_watcher()
	else
		M.stop_watcher()
		if opts.restore_theme ~= false then
			pcall(vim.cmd.colorscheme, cfg.theme)
		end
	end
	return true
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true
	vim.api.nvim_create_user_command("FoxRyokuSyncToggle", function()
		local enabled = not M.is_sync_enabled()
		if M.set_sync_enabled(enabled) then
			vim.notify("Ryoku theme sync: " .. (enabled and "ON" or "OFF"))
		end
	end, { desc = "Toggle automatic Ryoku theme synchronization" })
	vim.api.nvim_create_user_command("FoxRyokuSyncNow", function()
		M.apply()
	end, { desc = "Apply current Ryoku palette" })
	vim.api.nvim_create_user_command("FoxRyokuSyncStatus", function()
		vim.notify("Ryoku theme sync: " .. (M.is_sync_enabled() and "ON" or "OFF"))
	end, { desc = "Show Ryoku theme synchronization status" })
	vim.api.nvim_create_autocmd("VimLeavePre", { callback = M.stop_watcher })
end

return setmetatable({
	name = "fox_ryoku_theme",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = { "FoxRyokuSyncToggle", "FoxRyokuSyncNow", "FoxRyokuSyncStatus" },
	config = M.setup,
}, { __index = M })
