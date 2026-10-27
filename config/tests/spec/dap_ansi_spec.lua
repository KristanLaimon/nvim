local t = require("fox.lib.foxnvim.test")
local ansi = require("fox.dap.ansi")

t.describe("DAP ANSI output", function()
	local buf
	t.afterEach(function()
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
	end)
	local function flush()
		vim.wait(30)
	end
	local function start(lines)
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		ansi.attach(buf)
		ansi.attach(buf)
		flush()
	end
	local function append(text)
		local row = vim.api.nvim_buf_line_count(buf) - 1
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
		vim.api.nvim_buf_set_text(buf, row, #line, row, #line, { text })
	end
	t.it("parses every possible split of SGR, Unicode and OSC hyperlinks", function()
		local text = "\27[1;38;2;12;34;56márbol\27[0m\27]8;;https://example.test\27\\link\27]8;;\7"
		for split = 1, #text do
			local a, _, seed = ansi.parse(text:sub(1, split))
			local b, _, state = ansi.parse(text:sub(split + 1), seed)
			t.expect(a .. b).toBe("árbollink")
			t.expect(state.pending).toBe("")
			t.expect(state.style).toEqual({})
		end
	end)
	t.it("supports indexed colors, backgrounds, attributes and individual resets", function()
		local text, spans = ansi.parse("\27[38;5;196;48;5;232;1;3;4;7;9mX\27[22;23;24;27;29;39;49mY")
		t.expect(text).toBe("XY")
		t.expect(#spans).toBe(1)
		t.expect(spans[1][3]).toEqual({
			fg = "#ff0000",
			bg = "#080808",
			bold = true,
			italic = true,
			underline = true,
			reverse = true,
			strikethrough = true,
		})
	end)
	t.it("strips cursor controls and tolerates invalid extended colors", function()
		local text, _, state = ansi.parse("a\27[2Kb\27[38;2;999;0;0mc\27[0m")
		t.expect(text).toBe("abc")
		t.expect(state.style).toEqual({})
	end)
	t.it("retains split escapes and highlights across scheduled appends", function()
		start({ "prefix \27[3" })
		t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "prefix " })
		append("1mrojo")
		flush()
		append(" más")
		append("\27[0m fin")
		flush()
		t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "prefix rojo más fin" })
		local marks = vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, { details = true })
		t.expect(#marks).toBe(1)
		t.expect(marks[1][3]).toBe(7)
		t.expect(marks[1][4].end_col).toBe(#"prefix rojo más")
	end)
	t.it("propagates style changes through following lines and preserves readonly buffers", function()
		start({ "\27[31mred", "still red", "\27[0mplain" })
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "\27[32mgreen" })
		vim.bo[buf].modifiable = false
		flush()
		t.expect(vim.bo[buf].modifiable).toBe(false)
		local marks = vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, { details = true })
		t.expect(#marks).toBe(2)
		t.expect(marks[1][4].hl_group).toBe(marks[2][4].hl_group)
	end)
	t.it("handles clearing, concurrent output, themes and deletion before the queued flush", function()
		ansi.setup()
		start({ "\27[31mold", "old too" })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
		append("new")
		flush()
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, {})).toBe(0)
		append("\27[32mgreen")
		flush()
		vim.api.nvim_exec_autocmds("ColorScheme", {})
		flush()
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, {})).toBe(1)
		append("\27[3")
		vim.api.nvim_buf_delete(buf, { force = true })
		flush()
	end)
	t.it("clears a style-only line without leaking it into later output", function()
		start({ "\27[31m" })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
		append("plain")
		flush()
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, ansi.namespace, 0, -1, {})).toBe(0)
	end)
end)
