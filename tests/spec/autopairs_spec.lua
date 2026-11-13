local t = require("fox.lib.foxnvim.test")
local pairs = require("fox.editor.autopairs")
local function key(s)
	return vim.api.nvim_replace_termcodes(s, true, false, true)
end
t.describe("native pair decisions", function()
	local buf, old, config, virtualedit
	t.beforeEach(function()
		old = vim.api.nvim_get_current_buf()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		virtualedit = vim.o.virtualedit
		vim.o.virtualedit = "onemore"
		config = vim.deepcopy(pairs.config)
	end)
	t.afterEach(function()
		pairs.config = config
		vim.o.virtualedit = virtualedit
		vim.api.nvim_set_current_buf(old)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
	local function set(before, after, ft)
		vim.bo.filetype = ft or "text"
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { before .. (after or "") })
		vim.api.nvim_win_set_cursor(0, { 1, #before })
	end
	t.it("pairs before whitespace, stops before words and preserves Unicode byte positions", function()
		set("é ", " ")
		t.expect(pairs.type("(")).toBe(key("<C-g>u()<C-g>U<Left><C-g>u"))
		set("", "word")
		t.expect(pairs.type("(")).toBe("(")
	end)
	t.it("deletes whole empty pairs and leaves ordinary backspace alone", function()
		set("(", ")")
		t.expect(pairs.backspace()).toBe(key("<BS><Del>"))
		set("(x", ")")
		t.expect(pairs.backspace()).toBe(key("<BS>"))
		set("<!--", "-->", "html")
		t.expect(pairs.backspace()).toBe(key("<BS><BS><BS><BS><Del><Del><Del>"))
	end)
	t.it("skips balanced closes but inserts a missing opening balance", function()
		set("(", ")")
		t.expect(pairs.type(")")).toBe(key("<C-g>U<Right>"))
		set("((", ")")
		t.expect(pairs.type(")")).toBe(")")
	end)
	t.it("honors filetypes, unnamed floats and read-only buffers", function()
		for _, ft in ipairs({ "TelescopePrompt", "vim" }) do
			set("", "", ft)
			t.expect(pairs.type("(")).toBe("(")
		end
		set("", "")
		vim.bo.modifiable = false
		t.expect(pairs.type("(")).toBe("(")
		vim.bo.modifiable = true
		vim.bo.filetype = ""
		local win = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 0, col = 0, width = 10, height = 2 })
		t.expect(pairs.type("(")).toBe("(")
		vim.api.nvim_win_close(win, true)
	end)
	t.it("handles apostrophes, escapes, Python prefixes and Rust lifetimes", function()
		set("don", "")
		t.expect(pairs.type("'")).toBe("'")
		set("\\", "")
		t.expect(pairs.type('"')).toBe('"')
		set("f", "", "python")
		t.expect(pairs.type("'"):find("''", 1, true) ~= nil).toBe(true)
		set("&", "", "rust")
		t.expect(pairs.type("'")).toBe("'")
	end)
	t.it("does not double quotes inside strings and allows brackets before a closing quote", function()
		set('"abc', '"')
		t.expect(pairs.type("'")).toBe("'")
		t.expect(pairs.type('"')).toBe(key("<C-g>U<Right>"))
		t.expect(pairs.type("("):find("()", 1, true) ~= nil).toBe(true)
	end)
	t.it("uses actual Lua Treesitter exclusions and works without a parser", function()
		set("-- comment ", "", "lua")
		assert(vim.treesitter.get_parser(0, "lua"):parse())
		t.expect(pairs.type("(")).toBe("(")
		pairs.config.check_ts = false
		t.expect(pairs.type("("):find("()", 1, true) ~= nil).toBe(true)
		pairs.config.check_ts = true
		set("", "", "fox_no_parser")
		t.expect(pairs.type("("):find("()", 1, true) ~= nil).toBe(true)
	end)
	t.it("allows nested shell substitution quotes", function()
		set('"$(', "", "sh")
		t.expect(pairs.type('"'):find('""', 1, true) ~= nil).toBe(true)
	end)
	t.it("provides fences, triple quotes, Nix strings and HTML comments", function()
		for _, fixture in ipairs({
			{ "``", "`", "markdown", "````" },
			{ '""', '"', "python", '""""' },
			{ "'", "'", "nix", "'''" },
			{ "<!-", "-", "html", "--->" },
		}) do
			set(fixture[1], "", fixture[3])
			t.expect(pairs.type(fixture[2]):find(fixture[4], 1, true) ~= nil).toBe(true)
		end
	end)
	t.it("expands Enter between pairs, tags and language fences only", function()
		for _, fixture in ipairs({ { "{", "}", "text" }, { "<div>", "</div>", "html" }, { "```lua", "```", "markdown" } }) do
			set(unpack(fixture))
			t.expect(pairs.enter() ~= key("<CR>")).toBe(true)
		end
		set("<!--", "-->", "html")
		t.expect(pairs.enter()).toBe(key("<CR>"))
	end)
end)
