local t = require("fox.lib.foxnvim.test")
local tabs = require("fox.ui.tabline")
t.describe("native buffer tab bar", function()
	local created, saved, previous
	local function buffer(name, listed)
		local buf = vim.api.nvim_create_buf(listed ~= false, false)
		vim.api.nvim_buf_set_name(buf, "/tmp/fox-tabline-tests/" .. name)
		created[#created + 1] = buf
		return buf
	end
	local function text(width)
		vim.o.columns = width or 200
		return vim.api.nvim_eval_statusline(tabs.render(), { use_tabline = true, maxwidth = width or 200 }).str
	end
	t.beforeEach(function()
		created = {}
		previous = vim.api.nvim_get_current_buf()
		saved = {
			query = package.loaded["fox.query"],
			env = _G.Environments,
			deleted = _G.Is_File_Deleted,
			close = _G.Smart_Close_Buffer,
			ws = package.loaded["plugins.fox.tools.workspaces"],
			columns = vim.o.columns,
			tabline = vim.o.tabline,
			show = vim.o.showtabline,
			positions = vim.g.BufferlinePositions,
		}
		package.loaded["fox.query"] = nil
		_G.Environments = {
			is_buffer_in_current_environment = function(buf)
				return vim.api.nvim_buf_get_name(buf):find("/fox-tabline-tests/", 1, true) ~= nil
			end,
		}
		package.loaded["plugins.fox.tools.workspaces"] = {
			get_badge_components = function()
				return {}
			end,
		}
		_G.Is_File_Deleted = nil
		vim.g.BufferlinePositions = nil
		tabs.setup()
	end)
	t.afterEach(function()
		vim.o.tabline, vim.o.showtabline, vim.o.columns = saved.tabline, saved.show, saved.columns
		vim.api.nvim_set_current_buf(previous)
		for _, buf in ipairs(created) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		package.loaded["fox.query"], package.loaded["plugins.fox.tools.workspaces"] = saved.query, saved.ws
		_G.Environments, _G.Is_File_Deleted, _G.Smart_Close_Buffer = saved.env, saved.deleted, saved.close
		vim.g.BufferlinePositions = saved.positions
	end)
	t.it("filters DAP, terminals, dependencies and other environments while retaining new and deleted files", function()
		local a = buffer("new.lua")
		local b = buffer("deleted.lua")
		_G.Is_File_Deleted = function(buf)
			return buf == b
		end
		buffer("node_modules/vendor.js")
		local scratch = buffer("scratch")
		vim.bo[scratch].buftype = "nofile"
		local hidden = buffer("unlisted.lua", false)
		local virtual = buffer("virtual")
		vim.api.nvim_buf_set_name(virtual, "dap-src://test/1")
		t.expect(#tabs.buffers()).toBe(2)
		t.expect(tabs.visible(hidden)).toBe(false)
		vim.api.nvim_set_current_buf(a)
		t.expect(text()).toContain("[D] deleted.lua")
	end)
	t.it("uses Query's buffer visibility and labels without showing editor buffers", function()
		local editor, query = buffer("editor.lua"), buffer("query.sql")
		vim.bo[query].buftype = "nofile"
		package.loaded["fox.query"] = {
			buffer_visible = function(buf)
				return buf == query
			end,
			buffer_label = function(buf)
				if buf == query then
					return "db%/query.sql"
				end
			end,
		}
		vim.api.nvim_set_current_buf(query)
		t.expect(#tabs.buffers()).toBe(1)
		t.expect(tabs.visible(editor)).toBe(false)
		t.expect(text()).toContain("db%/query.sql")
	end)
	t.it("anchors pins, reorders within groups and restores the session's existing path order", function()
		local a, b, c = buffer("a.lua"), buffer("b.lua"), buffer("c.lua")
		tabs.set_pin(c, true)
		t.expect(tabs.buffers()[1]).toBe(c)
		vim.api.nvim_set_current_buf(b)
		tabs.move(-1)
		t.expect(tabs.buffers()[2]).toBe(b)
		local positions = vim.g.BufferlinePositions
		tabs.setup()
		t.expect(tabs.buffers()[2]).toBe(b)
		t.expect(vim.g.BufferlinePositions).toBe(positions)
		tabs.move(-1)
		t.expect(tabs.buffers()[1]).toBe(c)
		tabs.cycle(1)
		t.expect(vim.api.nvim_get_current_buf()).toBe(a)
		tabs.cycle(1)
		t.expect(vim.api.nvim_get_current_buf()).toBe(c)
	end)
	t.it("escapes filenames and badges, distinguishes duplicates and renders diagnostics and modifications", function()
		local a = buffer("left/100%#Error#🦊.lua")
		local b = buffer("right/100%#Error#🦊.lua")
		vim.api.nvim_set_current_buf(a)
		vim.api.nvim_buf_set_lines(a, 0, -1, false, { "changed" })
		local ns = vim.api.nvim_create_namespace("fox_tabline_test")
		vim.diagnostic.set(ns, b, { { lnum = 0, col = 0, message = "bad", severity = 1 } })
		package.loaded["plugins.fox.tools.workspaces"].get_badge_components = function()
			return { { text = "ws%#Error#", hl = "Normal" } }
		end
		local result = text(240)
		t.expect(result).toContain("left/")
		t.expect(result).toContain("right/")
		t.expect(result).toContain("100%#Error#")
		t.expect(result).toContain("●")
		t.expect(result).toContain(" 1")
		t.expect(result).toContain("ws%#Error#")
		vim.diagnostic.reset(ns, b)
	end)
	t.it("keeps file icon colors on selected, visible and inactive tabs and refreshes color overrides", function()
		local a, b = buffer("color.lua"), buffer("other.lua")
		vim.api.nvim_set_current_buf(a)
		local icons = require("fox.ui.icons")
		local glyph, icon_group = icons.get("file", vim.api.nvim_buf_get_name(a))
		local original = vim.api.nvim_get_hl(0, { name = icon_group, link = false })
		local function check(buf, group)
			text(200)
			local name = "FoxTabIcon" .. group .. icon_group
			local actual = vim.api.nvim_get_hl(0, { name = name, link = false })
			local tab = vim.api.nvim_get_hl(0, { name = group, link = false })
			local icon = vim.api.nvim_get_hl(0, { name = icon_group, link = false })
			t.expect(actual.fg).toBe(icon.fg)
			t.expect(actual.bg).toBe(tab.bg)
			local evaluated =
				vim.api.nvim_eval_statusline(tabs.render(), { use_tabline = true, maxwidth = 200, highlights = true })
			local colored = false
			for _, span in ipairs(evaluated.highlights) do
				if span.group == name and evaluated.str:sub(span.start + 1, span.start + #glyph) == glyph then
					colored = true
				end
			end
			t.expect(colored).toBe(true)
			t.expect(tabs.visible(buf)).toBe(true)
		end
		local ok, err = pcall(function()
			check(a, "BufferLineBufferSelected")
			check(b, "BufferLineBackground")
			vim.cmd.vsplit()
			local split = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(split, b)
			check(a, "BufferLineBufferVisible")
			vim.api.nvim_win_close(split, true)
			vim.api.nvim_set_current_buf(a)
			vim.api.nvim_set_hl(0, icon_group, { fg = "#123456" })
			check(a, "BufferLineBufferSelected")
		end)
		vim.api.nvim_set_hl(0, icon_group, original)
		assert(ok, err)
	end)
	t.it("keeps the active tab visible through overflow and very small widths", function()
		local last
		for i = 1, 25 do
			last = buffer("tab-" .. i .. ".lua")
		end
		vim.api.nvim_set_current_buf(last)
		tabs.set_pin(created[1], true)
		local result = text(60)
		t.expect(result).toContain("tab-25.lua")
		t.expect(result).toContain("‹")
		t.expect(#tabs.buffers()).toBe(25)
		for _, width in ipairs({ 1, 5, 12, 20, 40, 80 }) do
			local value = text(width)
			t.expect(vim.fn.strdisplaywidth(value) <= width).toBe(true)
			t.expect(tabs.render()).toContain("%" .. last .. "@")
			if width >= 20 then
				t.expect(value).toContain("t")
			end
		end
	end)
	t.it("represents a media preview once and closes its source through the smart closer", function()
		local file, preview = buffer("image.png", false), buffer("preview")
		vim.bo[preview].buftype = "nofile"
		vim.b[preview].fox_media_source = file
		tabs.set_pin(file, true)
		vim.api.nvim_set_current_buf(preview)
		t.expect(#tabs.buffers()).toBe(1)
		t.expect(text()).toContain("image.png")
		t.expect(tabs.is_pinned(preview)).toBe(true)
		local closed, force
		_G.Smart_Close_Buffer = function(buf, value)
			closed, force = buf, value
		end
		tabs.click(preview, 1, "m")
		t.expect(closed).toBe(file)
		t.expect(force).toBe(false)
	end)
	t.it("cancels selection, rejects stale clicks and skips pins on bulk close", function()
		local a, b, c = buffer("one.lua"), buffer("two.lua"), buffer("three.lua")
		vim.api.nvim_set_current_buf(b)
		tabs.set_pin(a, true)
		local closed = {}
		_G.Smart_Close_Buffer = function(buf)
			closed[#closed + 1] = buf
		end
		tabs.close_others()
		t.expect(#closed).toBe(1)
		t.expect(closed[1]).toBe(c)
		local select = vim.ui.select
		vim.ui.select = function(_, _, cb)
			cb(nil)
		end
		tabs.pick(false)
		vim.ui.select = select
		t.expect(vim.api.nvim_get_current_buf()).toBe(b)
		vim.api.nvim_buf_delete(c, { force = true })
		tabs.click(c, 1, "l")
		t.expect(vim.api.nvim_get_current_buf()).toBe(b)
	end)
end)
