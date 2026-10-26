local t = require("fox.lib.foxnvim.test")
require("lazy").load({ plugins = { "blink.cmp" } })
local snippets = require("fox.lsp.snippets")
local catalog = vim.fn.stdpath("config") .. "/config/snippet_catalog"
local function context()
	return {
		id = 98765,
		cursor = { 1, 0 },
		bounds = { start_col = 1 },
		get_line = function()
			return ""
		end,
	}
end
local function items(source)
	local result
	source:get_completions(context(), function(value)
		result = value.items
	end)
	return result
end
local function matching(source, label)
	local result = {}
	for _, item in ipairs(items(source)) do
		if item.label == label then
			result[#result + 1] = item
		end
	end
	return result
end
local function signatures(values)
	local result = {}
	for _, value in ipairs(values) do
		result[#result + 1] = vim.json.encode({ value.prefix, value.body, value.description })
	end
	table.sort(result)
	return result
end

t.describe("local snippets with real Blink and native expansion", function()
	t.it("uses the local source and keeps friendly-snippets out of the plugin registry", function()
		t.expect(require("lazy.core.config").plugins["friendly-snippets"]).toBe(nil)
		local provider = require("blink.cmp.config").sources.providers.snippets
		t.expect(provider.module).toBe("fox.lsp.snippets")
		t.expect(provider.opts.friendly_snippets).toBe(false)
		for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
			t.expect(path:find("friendly-snippets", 1, true)).toBe(nil)
		end
	end)
	t.it("matches native loading for every bundled filetype and framework alias", function()
		local native =
			require("blink.cmp.sources.snippets.default").new({ friendly_snippets = false, search_paths = { catalog } })
		local source = snippets.new({ search_paths = {}, catalog_path = catalog })
		local count = 0
		for ft in pairs(native.registry.registry) do
			local expected = signatures(native.registry:get_snippets_for_ft(ft))
			local actual = signatures(source.defaults.registry:get_snippets_for_ft(ft))
			t.expect(vim.deep_equal(actual, expected)).toBe(true)
			count = count + 1
		end
		t.expect(count > 100).toBe(true)
	end)
	t.it("gives custom triggers precedence, rescans new files and rejects malformed entries", function()
		local dir, old_ft, notify = vim.fn.tempname(), vim.bo.filetype, vim.notify
		vim.fn.mkdir(dir, "p")
		local warnings = 0
		vim.notify = function()
			warnings = warnings + 1
		end
		local ok, err = pcall(function()
			vim.fn.writefile({
				vim.json.encode({
					["$schema"] = "metadata",
					override = { prefix = { "req", "custom" }, body = "custom ${1:name}$0" },
					malformed = { prefix = "bad" },
				}),
			}, dir .. "/lua.json")
			vim.fn.writefile({ "not JSON" }, dir .. "/all.json")
			local source = snippets.new({ search_paths = { dir }, catalog_path = catalog })
			vim.bo.filetype = "lua"
			t.expect(#matching(source, "req")).toBe(1)
			t.expect(matching(source, "req")[1].insertText).toBe("custom ${1:name}$0")
			t.expect(#matching(source, "bad")).toBe(0)
			t.expect(warnings).toBe(1)
			vim.fn.writefile(
				{ vim.json.encode({ created = { prefix = "newtrigger", body = "new $0" } }) },
				dir .. "/zig.json"
			)
			source:reload()
			vim.bo.filetype = "zig"
			t.expect(#matching(source, "newtrigger")).toBe(1)
			vim.fn.writefile({ vim.json.encode({ updated = { prefix = "req", body = "updated $0" } }) }, dir .. "/lua.json")
			source:reload()
			vim.bo.filetype = "lua"
			t.expect(matching(source, "req")[1].insertText).toBe("updated $0")
			vim.fn.delete(dir .. "/lua.json")
			source:reload()
			t.expect(matching(source, "req")[1].insertText).toContain("require(")
		end)
		vim.notify, vim.bo.filetype = notify, old_ft
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
	t.it("reloads the active Blink provider through saves, manager writes and its command", function()
		local provider = require("blink.cmp.sources.lib").get_provider_by_id("snippets")
		local source = provider.module
		local manager = require("plugins.fox.tools.snippet_manager")
		local dir, previous = vim.fn.tempname(), vim.api.nvim_get_current_buf()
		local old_paths, old_dir = source.options.search_paths, manager.settings.snippets_dir
		vim.fn.mkdir(dir, "p")
		source.options.search_paths, manager.settings.snippets_dir = { dir }, dir
		manager.setup()
		local buf
		local ok, err = pcall(function()
			require("blink.cmp").reload("snippets")
			vim.cmd.enew()
			buf = vim.api.nvim_get_current_buf()
			vim.bo.filetype = "lua"
			t.expect(#matching(source, "fox_reload_test")).toBe(0)
			manager.write_snippets("lua", { test = { prefix = "fox_reload_test", body = "first $0" } })
			t.expect(matching(source, "fox_reload_test")[1].insertText).toBe("first $0")
			vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/lua.json"))
			buf = vim.api.nvim_get_current_buf()
			vim.bo.filetype = "lua"
			vim.api.nvim_buf_set_lines(
				buf,
				0,
				-1,
				false,
				{ vim.json.encode({ test = { prefix = "fox_reload_test", body = "saved $0" } }) }
			)
			vim.cmd.write()
			t.expect(matching(source, "fox_reload_test")[1].insertText).toBe("saved $0")
			vim.fn.writefile(
				{ vim.json.encode({ test = { prefix = "fox_reload_test", body = "command $0" } }) },
				dir .. "/lua.json"
			)
			vim.cmd.FoxSnippetReload()
			t.expect(matching(source, "fox_reload_test")[1].insertText).toBe("command $0")
		end)
		source.options.search_paths, manager.settings.snippets_dir = old_paths, old_dir
		require("blink.cmp").reload("snippets")
		vim.api.nvim_set_current_buf(previous)
		if buf and vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
	t.it("expands a bundled snippet and traverses real native tabstops", function()
		local previous = vim.api.nvim_get_current_buf()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.bo.filetype = "lua"
		local ok, err = pcall(function()
			local source = snippets.new({ search_paths = {}, catalog_path = catalog })
			local item = matching(source, "fori")[1]
			assert(item, "Missing bundled fori snippet")
			vim.snippet.expand(item.insertText)
			t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("ipairs(")
			t.expect(vim.snippet.active({ direction = 1 })).toBe(true)
			vim.snippet.jump(1)
			t.expect(vim.snippet.active()).toBe(true)
			vim.snippet.stop()
		end)
		vim.snippet.stop()
		vim.api.nvim_set_current_buf(previous)
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)
end)
