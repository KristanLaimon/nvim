local t = require("fox.lib.foxnvim.test")
local tag = require("fox.editor.autotag")
t.describe("Native Treesitter autotag", function()
	local buf
	local function set(source, ft, lang)
		vim.bo[buf].filetype = ft
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { source })
		assert(vim.treesitter.get_parser(buf, lang):parse())
	end
	local function line()
		return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
	end
	t.beforeEach(function()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
	end)
	t.afterEach(function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
	t.it("closes HTML and does not duplicate existing closing tags", function()
		set("<div>", "html", "html")
		t.expect(tag.close(buf, 0, 5)).toBe(true)
		t.expect(line()).toBe("<div></div>")
		t.expect(tag.close(buf, 0, 5)).toBe(false)
	end)
	t.it("prepares the syntax parser only once before looking up the tag", function()
		set("<img>", "html", "html")
		local original = vim.treesitter.get_parser
		local calls = 0
		local parser_spy = t.spyOn(vim.treesitter, "get_parser")
		local node_spy = t.spyOn(vim.treesitter, "get_node")
		parser_spy.mockImplementation(function(...)
			calls = calls + 1
			return original(...)
		end)
		node_spy.mockImplementation(function()
			return nil
		end)
		local closed = tag.close(buf, 0, 5)
		parser_spy.mockRestore()
		node_spy.mockRestore()
		t.expect(closed).toBe(false)
		t.expect(calls).toBe(1)
	end)
	t.it("skips void tags, self-closing tags, comments and quoted greater-than signs", function()
		for _, source in ipairs({ "<img>", "<input />", "<!-- <div> -->", '<div title="a > b">' }) do
			set(source, "html", "html")
			local col = source:find(">", 1, true)
			t.expect(tag.close(buf, 0, col)).toBe(false)
			t.expect(line()).toBe(source)
		end
	end)
	if pcall(vim.treesitter.language.add, "tsx") then
		t.it("closes JSX components, members and fragments", function()
			for _, source in ipairs({ "const x = <Panel>", "const x = <UI.Panel>", "const x = <>" }) do
				set(source, "typescriptreact", "tsx")
				t.expect(tag.close(buf, 0, #source)).toBe(true)
				local name = source:match("<(.*)>$")
				t.expect(line()).toBe(source .. "</" .. name .. ">")
			end
		end)
	else
		print("Skipping JSX autotag case: install/provide the optional tsx parser to run it.")
	end
	t.it("renames either side without renaming nested siblings", function()
		set("<div><span></span></div>", "html", "html")
		tag.snapshot(buf)
		vim.api.nvim_buf_set_text(buf, 0, 1, 0, 4, { "article" })
		tag.rename(buf)
		t.expect(line()).toBe("<article><span></span></article>")
		tag.snapshot(buf)
		local start = line():find("</span>", 1, true) + 1
		vim.api.nvim_buf_set_text(buf, 0, start, 0, start + 4, { "strong" })
		tag.rename(buf)
		t.expect(line()).toBe("<article><strong></strong></article>")
	end)
	t.it("does not guess when both tags changed or names are temporarily empty", function()
		set("<div></div>", "html", "html")
		tag.snapshot(buf)
		vim.api.nvim_buf_set_text(buf, 0, 1, 0, 4, { "" })
		tag.rename(buf)
		t.expect(line()).toBe("<></div>")
		set("<div></div>", "html", "html")
		tag.snapshot(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<a></b>" })
		tag.rename(buf)
		t.expect(line()).toBe("<a></b>")
	end)
end)
