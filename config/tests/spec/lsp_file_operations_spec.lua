local t = require("fox.lib.foxnvim.test")
local m = require("fox.lsp.file_operations")
t.describe("LSP filesystem operations", function()
	local root, client, original, requests, notifications
	t.beforeEach(function()
		root = vim.fn.tempname()
		requests = {}
		notifications = {}
		original = vim.lsp.get_clients
		local caps = {}
		for _, phase in ipairs({ "will", "did" }) do
			for _, op in ipairs({ "Rename", "Create", "Delete" }) do
				caps[phase .. op] = { filters = { { scheme = "file", pattern = { glob = "**/*.ts", matches = "file" } } } }
			end
		end
		client = {
			name = "test",
			config = { root_dir = root },
			offset_encoding = "utf-16",
			server_capabilities = { workspace = { fileOperations = caps } },
			is_stopped = function()
				return false
			end,
			request_sync = function(_, method, params)
				requests[#requests + 1] = { method, params }
				return { result = { changes = {} } }
			end,
			notify = function(_, method, params)
				notifications[#notifications + 1] = { method, params }
			end,
		}
		vim.lsp.get_clients = function()
			return { client }
		end
	end)
	t.afterEach(function()
		vim.lsp.get_clients = original
	end)
	t.it("filters clients by workspace, scheme, glob and file/folder kind", function()
		t.expect(m.matches(client, "will", "Rename", root .. "/a.ts", false)).toBe(true)
		t.expect(m.matches(client, "will", "Rename", root .. "/a.lua", false)).toBe(false)
		t.expect(m.matches(client, "will", "Rename", root .. "/a.ts", true)).toBe(false)
		t.expect(m.matches(client, "will", "Rename", root .. "outside/a.ts", false)).toBe(false)
		client.server_capabilities.workspace.fileOperations.willRename.filters[1].scheme = "untitled"
		t.expect(m.matches(client, "will", "Rename", root .. "/a.ts", false)).toBe(false)
	end)
	t.it("sends will/did rename, create and delete with file URIs", function()
		for _, op in ipairs({ "Rename", "Create", "Delete" }) do
			m.dispatch("will", op, root .. "/a.ts", root .. "/b.ts")
			m.dispatch("did", op, root .. "/a.ts", root .. "/b.ts")
		end
		t.expect(#requests).toBe(3)
		t.expect(#notifications).toBe(3)
		t.expect(requests[1][2].files[1].oldUri).toBe(vim.uri_from_fname(root .. "/a.ts"))
		t.expect(notifications[2][2].files[1].uri).toBe(vim.uri_from_fname(root .. "/a.ts"))
	end)
	t.it("applies UTF-16 edits and preserves unrelated unsaved text", function()
		local b = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(b, root .. "/a.ts")
		vim.api.nvim_buf_set_lines(b, 0, -1, false, { "😀foo unchanged" })
		local uri = vim.uri_from_bufnr(b)
		local edit = { changes = { [uri] = {
			{ range = { start = { line = 0, character = 2 }, ["end"] = { line = 0, character = 5 } }, newText = "bar" },
		} } }
		t.expect(m.apply(edit, "utf-16", { [b] = vim.api.nvim_buf_get_changedtick(b) })).toBe(true)
		t.expect(vim.api.nvim_buf_get_lines(b, 0, -1, false)[1]).toBe("😀bar unchanged")
		local ok = m.apply(edit, "utf-16", { [b] = -1 })
		t.expect(ok).toBe(false)
		vim.api.nvim_buf_delete(b, { force = true })
	end)
	t.it("rejects resource operations and stale versions, tolerates request errors", function()
		t.expect(m.apply({ documentChanges = { { kind = "delete", uri = "file:///tmp/a" } } }, "utf-16", {})).toBe(false)
		t.expect(
			m.apply(
				{ documentChanges = { { textDocument = { uri = vim.uri_from_fname(root .. "/x.ts"), version = 999 }, edits = {} } } },
				"utf-16",
				{}
			)
		).toBe(false)
		client.request_sync = function()
			error("disconnected")
		end
		m.dispatch("will", "Rename", root .. "/a.ts", root .. "/b.ts")
		t.expect(#notifications).toBe(0)
	end)
end)
