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
	t.it("aligns option labels and shortcut columns without highlighting the whole row", function()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local first, second
		for _, line in ipairs(lines) do
			if line:find("Run action", 1, true) then
				first = line
			elseif line:find("Other", 1, true) then
				second = line
			end
		end
		t.expect(first:find("%S")).toBe(second:find("%S"))
		t.expect(vim.fn.strdisplaywidth(first)).toBe(vim.fn.strdisplaywidth(second))
		t.expect(vim.trim(first):sub(-1)).toBe("x")
		t.expect(vim.fn.strdisplaywidth(vim.trim(first))).toBe(50)
		t.expect(vim.wo.cursorline).toBe(false)
		t.expect(vim.wo.cursorcolumn).toBe(false)
		t.expect(vim.api.nvim_win_get_cursor(0)[2]).toBe(first:find("%S") + 2)
		for _, mark in
			ipairs(
				vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("fox_dashboard"), 0, -1, { details = true })
			)
		do
			t.expect(mark[4].line_hl_group).toBe(nil)
		end
	end)
	t.it("keeps every quote paired with an author and fox artwork compact", function()
		local art = require("fox.ui.dashboard_art")
		assert(#art.quotes >= 50 and #art.quotes == #art.authors)
		assert(#art.foxes == 2)
		for i, quote in ipairs(art.quotes) do
			assert(quote ~= "" and art.authors[i] ~= "")
		end
		for _, fox in ipairs(art.foxes) do
			assert(#fox > 0 and #fox <= 22)
			for _, line in ipairs(fox) do
				assert(vim.fn.strdisplaywidth(line) <= 34)
			end
		end
	end)
	t.it("selects artwork that fits a short window and keeps it on redraw", function()
		local d = dashboard.layout()
		d.section.header.val = { "FoxVim" }
		d.section.buttons.val = { d.button("x", "Run action", ":let g:fox_dashboard_action = 1<CR>") }
		d.opts.artwork = {
			quotes = { "Stay foxy" },
			foxes = { vim.fn["repeat"]({ "too tall" }, 30), { "small fox" } },
		}
		local old_columns, old_lines = vim.o.columns, vim.o.lines
		vim.o.columns, vim.o.lines = 120, 22
		dashboard.setup(d.opts)
		dashboard.start()
		for _ = 1, 2 do
			local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			assert(text:find("small fox", 1, true))
			assert(not text:find("too tall", 1, true))
			dashboard.redraw()
		end
		vim.o.columns, vim.o.lines = old_columns, old_lines
	end)
	t.it("keeps the quote and menu usable when the dashboard changes width", function()
		local d = dashboard.layout()
		d.section.header.val = { "FoxVim" }
		d.section.buttons.val = { d.button("x", "Run action", ":let g:fox_dashboard_action = 1<CR>") }
		d.opts.artwork = { quotes = { "Stay foxy" }, foxes = { { "fox" } } }
		d.opts.environment = "Windows"
		dashboard.setup(d.opts)
		dashboard.start()
		for _, width in ipairs({ 120, 30 }) do
			vim.o.columns = width
			dashboard.redraw()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local text = table.concat(lines, "\n")
			assert(text:find("Stay foxy", 1, true))
			assert(text:find("Run action", 1, true))
			for _, line in ipairs(lines) do
				assert(vim.fn.strdisplaywidth(line) <= vim.api.nvim_win_get_width(0))
			end
		end
		vim.o.columns = 80
	end)
	t.it("keeps artwork aligned and shows the quote in a short window", function()
		local d = dashboard.layout()
		d.section.header.val = { "AAA", " A" }
		d.section.buttons.val = { d.button("x", "Run action", ":let g:fox_dashboard_action = 1<CR>") }
		d.opts.artwork = { quotes = { "Stay foxy" }, foxes = { { "ABC", " A" } } }
		d.opts.environment = "Windows"
		dashboard.setup(d.opts)
		local old_columns, old_lines = vim.o.columns, vim.o.lines
		vim.o.columns, vim.o.lines = 120, 40
		dashboard.start()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local first, second
		for i, line in ipairs(lines) do
			if line:find("ABC", 1, true) then
				first, second = line, lines[i + 1]
			end
		end
		assert(first and second)
		assert(second:find("A", 1, true) == first:find("ABC", 1, true) + 1)
		vim.o.columns, vim.o.lines = 40, 12
		dashboard.redraw()
		lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		assert(#lines <= vim.api.nvim_win_get_height(0))
		assert(table.concat(lines, "\n"):find("Stay foxy", 1, true))
		vim.o.columns, vim.o.lines = old_columns, old_lines
	end)
	t.it("restores inherited cursor highlighting after leaving the dashboard", function()
		vim.api.nvim_win_set_buf(0, original)
		local saved_line, saved_column = vim.wo.cursorline, vim.wo.cursorcolumn
		vim.wo.cursorline, vim.wo.cursorcolumn = true, true
		dashboard.start()
		t.expect(vim.wo.cursorline).toBe(false)
		t.expect(vim.wo.cursorcolumn).toBe(false)
		vim.api.nvim_win_set_buf(0, original)
		t.expect(vim.wo.cursorline).toBe(true)
		t.expect(vim.wo.cursorcolumn).toBe(true)
		vim.wo.cursorline, vim.wo.cursorcolumn = saved_line, saved_column
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
