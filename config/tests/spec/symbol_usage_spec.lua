local t = require("fox.lib.foxnvim.test")
local usage = require("fox.lsp.symbol_usage")
local range = { start = { line = 0, character = 9 }, ["end"] = { line = 0, character = 12 } }
local function symbol(row, kind)
	local r = vim.deepcopy(range)
	r.start.line = row
	r["end"].line = row
	return { name = "fun", kind = kind or 12, range = r, selectionRange = r }
end
t.describe("Native LSP reference badges", function()
	local buf, client, pending, saved, attached, cancelled
	local function respond(i, result, err)
		pending[i].callback(err, result)
	end
	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, usage.namespace, 0, -1, { details = true })
	end
	t.beforeEach(function()
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "function fun() end", "function other() end" })
		vim.api.nvim_set_current_buf(buf)
		saved = vim.lsp.get_clients
		pending = {}
		attached = true
		cancelled = {}
		client = {
			id = 123,
			offset_encoding = "utf-16",
			supports_method = function()
				return true
			end,
		}
		client.request = function(_, method, params, callback, b)
			assert(b == buf)
			pending[#pending + 1] = { method = method, params = params, callback = callback }
			return true, #pending
		end
		client.cancel_request = function(_, id)
			cancelled[#cancelled + 1] = id
		end
		vim.lsp.get_clients = function(opts)
			return opts.bufnr == buf and attached and { client } or {}
		end
		usage.setup({
			debounce = 5,
			text_format = function(value)
				return tostring(value.references) .. ":" .. value.stacked_count
			end,
		})
		usage.clear(buf)
	end)
	t.afterEach(function()
		usage.clear(buf)
		vim.lsp.get_clients = saved
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
	t.it("flattens symbols, filters kinds and renders deduplicated references above declarations", function()
		usage.refresh(buf)
		local parent = symbol(0, 5)
		parent.children = { symbol(1), symbol(1, 13) }
		respond(1, { parent })
		t.expect(#pending).toBe(3)
		t.expect(pending[2].params.context.includeDeclaration).toBe(false)
		local ref = { uri = vim.uri_from_bufnr(buf), range = range }
		respond(2, { ref, ref })
		respond(3, {})
		local rendered = marks()
		t.expect(#rendered).toBe(2)
		t.expect(rendered[1][4].virt_lines[1][1][1]).toBe("1:0")
		t.expect(rendered[1][4].virt_lines_above).toBe(true)
	end)
	t.it("rejects old responses after edits and a newer refresh", function()
		usage.refresh(buf)
		respond(1, { symbol(0) })
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "changed" })
		respond(2, { { uri = "file:///late", range = range } })
		t.expect(#marks()).toBe(0)
		usage.refresh(buf)
		respond(3, { symbol(0) })
		respond(2, {})
		t.expect(#marks()).toBe(0)
		respond(4, {})
		t.expect(#marks()).toBe(1)
		t.expect(#cancelled > 0).toBe(true)
	end)
	t.it("ignores replies after detach and reports no badge on server errors", function()
		usage.refresh(buf)
		attached = false
		respond(1, { symbol(0) })
		t.expect(#pending).toBe(1)
		attached = true
		usage.refresh(buf)
		respond(2, { symbol(0) })
		respond(3, nil, { message = "failed" })
		t.expect(#marks()).toBe(0)
	end)
	t.it("bounds concurrent references and merges declarations on one line", function()
		usage.refresh(buf)
		local symbols = {}
		for _ = 1, 8 do
			symbols[#symbols + 1] = symbol(0)
		end
		respond(1, symbols)
		t.expect(#pending).toBe(5)
		for i = 2, 9 do
			respond(i, {})
		end
		t.expect(#marks()).toBe(1)
		t.expect(marks()[1][4].virt_lines[1][1][1]).toBe("0:7")
	end)
	t.it("debounces rapid changes into one document request", function()
		usage.schedule(buf)
		usage.schedule(buf)
		usage.schedule(buf)
		vim.wait(100, function()
			return #pending > 0
		end, 5)
		t.expect(#pending).toBe(1)
	end)
	t.it("accepts all three existing theme formatters", function()
		local picker = require("plugins.fox.tools.usages_picker")
		for _, style in ipairs({ "plain", "labels", "bubbles" }) do
			usage.setup({ text_format = picker.get_text_format(style) })
			usage.refresh(buf)
			local n = #pending
			respond(n, { symbol(0) })
			respond(n + 1, {})
			t.expect(#marks()).toBe(1)
		end
	end)
end)
