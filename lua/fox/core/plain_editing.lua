-- Opt-in, non-modal editing for ordinary file windows.
local M = { enabled = false, settings_file = vim.fn.stdpath("data") .. "/fox_plain_editing.json" }
local store = require("fox.core.store")
local saved_maps = {}
local saved_options
local saved_mousemoveevent

local mappings = {
	{
		"n",
		"<MouseMove>",
		function()
			require("fox.lsp.mouse_hover").move()
		end,
	},
	{
		"i",
		"<MouseMove>",
		function()
			require("fox.lsp.mouse_hover").move()
		end,
	},
	{
		"n",
		"<C-LeftMouse>",
		function()
			require("keymaps.lsp").goto_definition_at_mouse()
		end,
	},
	{
		"i",
		"<C-LeftMouse>",
		function()
			require("keymaps.lsp").goto_definition_at_mouse()
		end,
	},
	{
		"i",
		"<Esc>",
		function()
			local blink = package.loaded["blink.cmp"]
			if blink and blink.is_menu_visible() then
				blink.hide()
			end
			return vim.fn.pumvisible() == 1 and "<C-e>" or "<Ignore>"
		end,
		expr = true,
	},
	{ "i", "<C-a>", "<Esc>gg0vG$<C-g>" },
	{ "s", "<C-a>", "<Esc>gg0vG$<C-g>" },
	{ "s", "<C-c>", '<Esc>gv"+ygi' },
	{ "s", "<C-x>", '<Esc>gv"+c' },
	{ "s", "<C-v>", '<C-o>"+p' },
	{ "s", "<Esc>", "<Esc>i" },
}

local function editable()
	return vim.bo.buftype == ""
		and vim.bo.modifiable
		and not vim.bo.readonly
		and vim.fn.isdirectory(vim.api.nvim_buf_get_name(0)) == 0
		and vim.api.nvim_win_get_config(0).relative == ""
end

local function restore_options()
	if saved_options then
		vim.o.keymodel = saved_options.keymodel
		vim.o.selectmode = saved_options.selectmode
		saved_options = nil
	end
end

local function attach(buf)
	if saved_maps[buf] then
		return
	end
	saved_maps[buf] = {}
	for index, mapping in ipairs(mappings) do
		local previous = vim.fn.maparg(mapping[2], mapping[1], false, true)
		saved_maps[buf][index] = previous.buffer == 1 and previous or false
		vim.keymap.set(mapping[1], mapping[2], mapping[3], {
			buffer = buf,
			silent = true,
			expr = mapping.expr,
			desc = "Plain editing",
		})
	end
end

local function refresh()
	if not M.enabled or not editable() then
		restore_options()
		return
	end
	attach(vim.api.nvim_get_current_buf())
	if not saved_options then
		saved_options = { keymodel = vim.o.keymodel, selectmode = vim.o.selectmode }
		vim.o.keymodel = "startsel,stopsel"
		vim.o.selectmode = "mouse,key"
	end
	-- Ignore temporary normal commands (Ctrl+O), command-line and selection modes.
	if vim.api.nvim_get_mode().mode == "n" and vim.fn.getcmdwintype() == "" then
		vim.cmd.startinsert()
	end
end

local function apply(enabled)
	local was_enabled = M.enabled
	M.enabled = enabled
	if enabled and not was_enabled then
		saved_mousemoveevent = vim.o.mousemoveevent
		vim.o.mousemoveevent = true
	elseif not enabled and was_enabled then
		vim.o.mousemoveevent = saved_mousemoveevent
		require("fox.lsp.mouse_hover").close()
	end
	if not enabled then
		restore_options()
		for buf, previous in pairs(saved_maps) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_call(buf, function()
					for index, mapping in ipairs(mappings) do
						pcall(vim.keymap.del, mapping[1], mapping[2], { buffer = buf })
						if previous[index] then
							vim.fn.mapset(mapping[1], false, previous[index])
						end
					end
				end)
			end
		end
		saved_maps = {}
		if was_enabled then
			vim.cmd.stopinsert()
		end
	end
	vim.schedule(function()
		refresh()
		local dashboard = package.loaded["fox.ui.dashboard"]
		if dashboard then
			dashboard.redraw()
		end
	end)
end

function M.toggle()
	local enabled = not M.enabled
	local ok, err = store.save(M.settings_file, { enabled = enabled })
	if not ok then
		vim.notify("Cannot save plain editing preference: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	apply(enabled)
	vim.notify(enabled and "Plain editing enabled (Vim motions off)" or "Vim motions enabled")
	return true
end

function M.setup()
	local group = vim.api.nvim_create_augroup("FoxPlainEditing", { clear = true })
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = group,
		callback = function()
			if M.enabled and editable() then
				-- Insert mode is global; leave it before a sidebar handles the click.
				restore_options()
				vim.cmd.stopinsert()
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter", "WinEnter", "ModeChanged" }, {
		group = group,
		callback = function()
			if M.enabled then
				vim.schedule(refresh)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			saved_maps[event.buf] = nil
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave", "InsertCharPre", "CursorMoved", "CursorMovedI" }, {
		group = group,
		callback = function()
			if M.enabled then
				require("fox.lsp.mouse_hover").close()
			end
		end,
	})
	vim.api.nvim_create_user_command("FoxToggleVimMotions", M.toggle, {
		desc = "Toggle Vim motions / plain editing (persistent)",
		force = true,
	})
	local settings = store.load(M.settings_file, {})
	apply(type(settings) == "table" and settings.enabled == true)
end

return M
