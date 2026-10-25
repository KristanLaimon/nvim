local t = require("fox.lib.foxnvim.test")
local m = require("fox.langs.php.blade")
t.describe("Local Blade support", function()
	local b
	t.beforeEach(function()
		vim.cmd("enew")
		b = vim.api.nvim_get_current_buf()
		vim.bo.shiftwidth = 2
	end)
	t.afterEach(function()
		vim.api.nvim_buf_delete(b, { force = true })
	end)
	t.it("detects Blade and indents nested HTML/directives with branches", function()
		t.expect(vim.filetype.match({ filename = "/tmp/view.blade.php" })).toBe("blade")
		vim.api.nvim_buf_set_lines(
			b,
			0,
			-1,
			false,
			{ "<div>", "@if($ok)", "<span>{{ $x }}</span>", "@else", "<br>", "@endif", "</div>" }
		)
		for row, expected in ipairs({ 0, 2, 4, 2, 4, 2, 0 }) do
			t.expect(m.indent(row)).toBe(expected)
		end
	end)
	t.it("keeps inline section/slot/php, escaped directives and comments balanced", function()
		vim.api.nvim_buf_set_lines(b, 0, -1, false, {
			"@section('title', 'Hi')",
			"@php($x = 1)",
			"@@if($x)",
			"{{-- @if($x) --}}",
			"@script",
			"text",
			"@endscript",
			"tail",
		})
		for row, expected in ipairs({ 0, 0, 0, 0, 0, 2, 0, 0 }) do
			t.expect(m.indent(row)).toBe(expected)
		end
	end)
	t.it("supports PHP braces, custom directive pairs and verbatim", function()
		vim.api.nvim_buf_set_lines(
			b,
			0,
			-1,
			false,
			{ "@php", "if ($x) {", "echo 'value';", "}", "@endphp", "@verbatim", "{{ @if($x) }}", "@endverbatim" }
		)
		for row, expected in ipairs({ 0, 2, 4, 2, 0, 0, -1, 0 }) do
			t.expect(m.indent(row)).toBe(expected)
		end
	end)
	t.it("treats forelse empty as a branch rather than another opening block", function()
		vim.api.nvim_buf_set_lines(
			b,
			0,
			-1,
			false,
			{ "@forelse($items as $item)", "{{ $item }}", "@empty", "<p>Nothing</p>", "@endforelse", "tail" }
		)
		for row, expected in ipairs({ 0, 2, 0, 2, 0, 0 }) do
			t.expect(m.indent(row)).toBe(expected)
		end
	end)
	t.it("ignores multiline HTML comments and indents embedded script/style braces", function()
		vim.api.nvim_buf_set_lines(
			b,
			0,
			-1,
			false,
			{
				"<!--",
				"<div>",
				"-->",
				"<script>",
				"if (ready) {",
				"run();",
				"}",
				"</script>",
				"<style>",
				".foo {",
				"color: red;",
				"}",
				"</style>",
			}
		)
		for row, expected in ipairs({ 0, 0, 0, 0, 2, 4, 2, 0, 0, 2, 4, 2, 0 }) do
			t.expect(m.indent(row)).toBe(expected)
		end
	end)
	t.it("loads native HTML/PHP syntax plus Blade comments, echoes and directives", function()
		vim.cmd("syntax on")
		vim.api.nvim_buf_set_lines(
			b,
			0,
			-1,
			false,
			{ "@if($ok)", "{{-- @if ignore --}}", "{{ $value }}", "@verbatim", "@if ignored", "@endverbatim" }
		)
		vim.bo.filetype = "blade"
		vim.cmd("runtime! syntax/blade.vim")
		local function group(row, col)
			return vim.fn.synIDattr(vim.fn.synID(row, col, 1), "name")
		end
		t.expect(group(1, 1)).toBe("FoxBladeDirective")
		t.expect(group(2, 7)).toBe("FoxBladeComment")
		t.expect(group(3, 1)).toBe("FoxBladeDelimiter")
		t.expect(group(5, 1)).toBe("FoxBladeVerbatim")
	end)
end)
