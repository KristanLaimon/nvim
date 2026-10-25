local t = require("fox.lib.foxnvim.test")
local dashboard = require("fox.ui.dashboard")
t.describe("Native dashboard", function()
	local original, buf
	t.beforeEach(function()
		original = vim.api.nvim_get_current_buf()
		local d = dashboard.layout()
		d.section.header.val = { "FoxVim" }
		d.section.header.opts.hl = "Title"
		d.section.buttons.val = {
			d.button("x", "Run action", ":let g:fox_dashboard_action = 1<CR>"),
			d.button("z", "Other", ":let g:fox_dashboard_action = 2<CR>"),
		}
		d.section.footer.val = "Footer"
		dashboard.setup(d.opts)
		dashboard.start()
		buf = vim.api.nvim_get_current_buf()
	end)
	t.afterEach(function()
		vim.api.nvim_win_set_buf(0, original)
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.g.fox_dashboard_action = nil
	end)
	t.it("renders a centered, unlisted scratch buffer and restores window options", function()
		t.expect(vim.bo[buf].filetype).toBe("alpha")
		t.expect(vim.bo[buf].buftype).toBe("nofile")
		t.expect(vim.bo[buf].modifiable).toBe(false)
		local line = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
		t.expect(vim.trim(line)).toBe("FoxVim")
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("fox_dashboard"), 0, -1, {})).toBe(4)
	end)
	t.it("moves between buttons and executes Enter and direct shortcuts", function()
		local maps = vim.api.nvim_buf_get_keymap(buf, "n")
		local function press(key)
			for _, map in ipairs(maps) do
				if map.lhs == key then
					map.callback()
					return
				end
			end
			error("missing " .. key)
		end
		press("j")
		press("<CR>")
		t.expect(vim.g.fox_dashboard_action).toBe(2)
		press("x")
		t.expect(vim.g.fox_dashboard_action).toBe(1)
		vim.api.nvim_win_set_width(0, 40)
		dashboard.redraw()
		t.expect(vim.api.nvim_buf_is_valid(buf)).toBe(true)
	end)
	t.it("keeps a modified buffer intact when opened explicitly", function()
		local other = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(0, other)
		vim.api.nvim_buf_set_lines(other, 0, -1, false, { "unsaved" })
		dashboard.start()
		t.expect(vim.api.nvim_buf_get_lines(other, 0, 1, false)[1]).toBe("unsaved")
		t.expect(vim.bo[other].modified).toBe(true)
		vim.api.nvim_buf_delete(other, { force = true })
	end)
end)
