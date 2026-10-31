-- ============================================================================
-- config/tests/spec/terminal_auto_insert_spec.lua -- Spec for Terminal auto-insert & click behavior
-- ============================================================================
local t = require("fox.lib.foxnvim.test")
local describe, it, expect, afterEach = t.describe, t.it, t.expect, t.afterEach

local terminal = require("plugins.fox.dev.terminal")

describe("terminal auto insert & click behavior", function()
	local created_bufs = {}

	afterEach(function()
		for _, buf in ipairs(created_bufs) do
			if vim.api.nvim_buf_is_valid(buf) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
		created_bufs = {}
	end)

	it("registers setup and LeftMouse mapping for terminal buffers", function()
		terminal.setup()

		local buf = vim.api.nvim_create_buf(false, true)
		table.insert(created_bufs, buf)
		vim.b[buf].fox_is_multi_term = true

		vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })

		local keymaps = vim.api.nvim_buf_get_keymap(buf, "n")
		local has_left_mouse = false
		for _, map in ipairs(keymaps) do
			if map.lhs == "<LeftMouse>" then
				has_left_mouse = true
				break
			end
		end

		expect(has_left_mouse).toBeTruthy()
	end)

	it("binds window focus navigation keys in terminal mode", function()
		require("keymaps.editor")
		for _, key in ipairs({ "<C-h>", "<C-l>", "<C-j>" }) do
			expect(vim.fn.maparg(key, "t") ~= "").toBe(true)
		end
	end)

	it("enters input on a content click in the already focused terminal, including its first row", function()
		terminal.setup()
		local buf = vim.api.nvim_create_buf(false, true)
		table.insert(created_bufs, buf)
		vim.b[buf].fox_is_multi_term = true
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
		vim.wait(20, function()
			return false
		end)
		local old_mouse, old_cmd = vim.fn.getmousepos, vim.cmd
		local inserted = false
		vim.fn.getmousepos = function()
			return { winid = vim.api.nvim_get_current_win(), line = 1, winrow = 1 }
		end
		vim.cmd = function(cmd)
			inserted = cmd == "startinsert"
		end
		local ok, err = pcall(function()
			local map = vim.fn.maparg("<LeftMouse>", "n", false, true)
			expect(map.callback()).toBe("<LeftMouse>")
			vim.wait(30, function()
				return inserted
			end, 5)
			expect(inserted).toBe(true)
		end)
		vim.fn.getmousepos, vim.cmd = old_mouse, old_cmd
		assert(ok, err)
	end)

	it("returns to terminal window when moving right from neo-tree if originated in terminal", function()
		require("keymaps.editor")
		local neotree_buf = vim.api.nvim_create_buf(false, true)
		local term_buf = vim.api.nvim_create_buf(false, true)
		table.insert(created_bufs, neotree_buf)
		table.insert(created_bufs, term_buf)

		vim.bo[neotree_buf].filetype = "neo-tree"
		vim.b[term_buf].fox_is_multi_term = true

		local win_neotree = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win_neotree, neotree_buf)

		vim.cmd("rightbelow split")
		local win_term = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win_term, term_buf)

		-- Start in terminal window, press left (C-h)
		_G._fox_last_win_before_neotree = win_term
		vim.api.nvim_set_current_win(win_neotree)

		-- From Neo-tree, press right (C-l)
		local map_r = vim.fn.maparg("<C-l>", "n", false, true)
		expect(type(map_r) == "table" and map_r.callback).toBeTruthy()

		map_r.callback()

		expect(vim.api.nvim_get_current_win()).toBe(win_term)
	end)
end)
