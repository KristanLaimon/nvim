local t = require("fox.lib.foxnvim.test")
t.describe("Blade editor integration", function()
	t.it("discovers bundled runtime files under config", function()
		local runtime = vim.fs.normalize(vim.fn.stdpath("config") .. "/config")
		for _, path in ipairs({ "syntax/blade.vim", "indent/blade.vim", "after/queries/blade/injections.scm" }) do
			local relative = path:gsub("^after/", "")
			local files = vim.api.nvim_get_runtime_file(relative, true)
			t.expect(vim.tbl_contains(vim.tbl_map(vim.fs.normalize, files), runtime .. "/" .. path)).toBe(true)
		end
	end)
	t.it("loads local syntax/indent and formats a mixed template with =", function()
		local file = vim.fn.tempname() .. ".blade.php"
		vim.fn.writefile({ "<div>", "@if($ok)", "<p>{{ $value }}</p>", "@else", "<br>", "@endif", "</div>" }, file)
		vim.cmd.edit(file)
		local b = vim.api.nvim_get_current_buf()
		vim.bo.shiftwidth = 2
		t.expect(vim.bo.filetype).toBe("blade")
		t.expect(vim.bo.indentexpr:find("fox.langs.php.blade", 1, true) ~= nil).toBe(true)
		vim.cmd("normal! gg=G")
		t.expect(vim.api.nvim_buf_get_lines(b, 0, -1, false))
			.toEqual({ "<div>", "  @if($ok)", "    <p>{{ $value }}</p>", "  @else", "    <br>", "  @endif", "</div>" })
		-- An installed Tree-sitter parser disables regex syntax; stopping it must restore the fallback.
		vim.treesitter.stop(b)
		t.expect(vim.b.current_syntax).toBe("blade")
		vim.api.nvim_buf_delete(b, { force = true })
		vim.fn.delete(file)
	end)

	t.it("completes directive names and shows offline documentation through K", function()
		local file = vim.fn.tempname() .. ".blade.php"
		vim.cmd.edit(file)
		local buf = vim.api.nvim_get_current_buf()
		local line = "  @foreach($items as $item)"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
		local source = require("fox.langs.php.blink").new()
		local result
		source:get_completions({ bufnr = buf, cursor = { 1, #"  @forea" }, line = line }, function(value)
			result = value
		end)
		local item = result.items[1]
		t.expect(item.label).toBe("@foreach")
		t.expect(item.textEdit.newText).toBe("@foreach")
		t.expect(item.textEdit.range["end"].character).toBe(#"  @foreach")
		t.expect(item.documentation.value).toContain("$items as $item")

		vim.api.nvim_win_set_cursor(0, { 1, 2 })
		local hover = vim.fn.maparg("K", "n", false, true).callback
		hover()
		local float = vim.api.nvim_list_wins()[2]
		local docs = vim.api.nvim_win_get_buf(float)
		t.expect(vim.api.nvim_buf_get_lines(docs, 0, -1, false)[1]).toContain("@foreach($items as $item)")
		hover()
		t.expect(vim.api.nvim_get_current_win()).toBe(float)
		vim.api.nvim_win_close(float, true)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	t.it("ignores escaped directives and inline Blade comments", function()
		local directives = require("fox.langs.php.blade_directives")
		t.expect(directives.complete("@@fore", 0, #"@@fore")).toBe(nil)
		t.expect(directives.under_cursor("{{-- @csrf --}}", 5)).toBe(nil)
		t.expect(directives.under_cursor("user@guest.example", 4)).toBe(nil)
	end)

	t.it("completes Alpine directives in Blade attributes", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].filetype = "blade"
		local result
		require("fox.langs.php.blink")
			.new()
			:get_completions({ bufnr = buf, line = "<div x-show", cursor = { 1, 8 } }, function(value)
				result = value
			end)
		t.expect(result.items[1].label).toBe("x-show")
		t.expect(result.items[1].textEdit.range["end"].character).toBe(#"<div x-show")
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
