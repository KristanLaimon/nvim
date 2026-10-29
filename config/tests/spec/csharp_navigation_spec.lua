local t = require("fox.lib.foxnvim.test")
local nav = require("fox.langs.csharp.navigation")
local range = { Start = { Line = 1, Column = 2 }, End = { Line = 1, Column = 5 } }
t.describe("Local OmniSharp navigation", function()
	local buf, client, pending, saved, tmp, created
	local function reply(i, result, err)
		pending[i].callback(err, result)
	end
	t.beforeEach(function()
		tmp = vim.fn.tempname()
		vim.fn.mkdir(tmp, "p")
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp .. "/Program.cs")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "😀 Foo" })
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_win_set_cursor(0, { 1, 5 })
		pending = {}
		created = {}
		saved = {
			clients = vim.lsp.get_clients,
			client = vim.lsp.get_client_by_id,
			show = nav.show,
			attach = vim.lsp.buf_attach_client,
			notify = vim.notify,
		}
		client = { id = 941, name = "omnisharp", offset_encoding = "utf-16" }
		client.request = function(_, method, params, callback, b)
			pending[#pending + 1] = { method = method, params = params, callback = callback, buf = b }
			return true, #pending
		end
		vim.lsp.get_clients = function()
			return { client }
		end
		vim.lsp.get_client_by_id = function(id)
			return id == client.id and client or nil
		end
		vim.lsp.buf_attach_client = function(b)
			created[#created + 1] = b
			return true
		end
		vim.notify = function() end
	end)
	t.afterEach(function()
		vim.lsp.get_clients = saved.clients
		vim.lsp.get_client_by_id = saved.client
		vim.lsp.buf_attach_client = saved.attach
		vim.notify = saved.notify
		nav.show = saved.show
		for _, b in ipairs(created) do
			if vim.api.nvim_buf_is_valid(b) then
				vim.api.nvim_buf_delete(b, { force = true })
			end
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(tmp, "rf")
	end)
	t.it("preserves zero-based locations and escapes file paths", function()
		local result
		nav.resolve(
			client,
			{ Definitions = { { Location = { FileName = tmp .. "/with spaces.cs", Range = range } } } },
			function(value)
				result = value
			end
		)
		t.expect(result[1].uri).toBe(vim.uri_from_fname(tmp .. "/with spaces.cs"))
		t.expect(result[1].range.start.line).toBe(1)
		t.expect(result[1].range.start.character).toBe(2)
	end)
	t.it("loads metadata and generated sources asynchronously in response order", function()
		local result
		nav.resolve(client, {
			Definitions = {
				{
					Location = { FileName = "ignored", Range = range },
					MetadataSource = {
						AssemblyName = "System",
						TypeName = "String",
					},
				},
				{
					Location = { FileName = "ignored", Range = range },
					SourceGeneratedFileInfo = { ProjectGuid = "project", DocumentGuid = "document" },
				},
			},
		}, function(value)
			result = value
		end)
		t.expect(pending[1].method).toBe("o#/metadata")
		t.expect(pending[2].method).toBe("o#/sourcegeneratedfile")
		reply(2, { SourceName = "generated.cs", Source = "class Generated {}" })
		t.expect(result).toBe(nil)
		reply(1, { SourceName = "$metadata$/System/String.cs", Source = "// metadata\r\nclass String {}" })
		t.expect(#result).toBe(2)
		local source = vim.uri_to_bufnr(result[1].uri)
		t.expect(vim.bo[source].readonly).toBe(true)
		t.expect(vim.bo[source].modifiable).toBe(false)
		t.expect(vim.bo[source].filetype).toBe("cs")
		t.expect(vim.b[source].fox_omnisharp_filename).toBe("$metadata$/System/String.cs")
		t.expect(vim.api.nvim_buf_get_lines(source, 1, 2, false)[1]).toBe("class String {}")
	end)
	t.it("skips missing metadata and server errors without losing normal locations", function()
		local result
		nav.resolve(client, {
			QuickFixes = {
				{ FileName = "unused", Line = 0, Column = 1, GeneratedFileInfo = { DocumentGuid = "x" } },
				{ FileName = tmp .. "/real.cs", Line = 0, Column = 1, EndLine = 0, EndColumn = 4 },
			},
		}, function(value)
			result = value
		end)
		reply(1, nil, { message = "metadata unavailable" })
		t.expect(#result).toBe(1)
		t.expect(result[1].range["end"].character).toBe(4)
	end)
	t.it("sends UTF-16 positions and navigates from metadata with its server filename", function()
		nav.request("definition")
		t.expect(pending[1].method).toBe("o#/v2/gotodefinition")
		t.expect(pending[1].params.column).toBe(3)
		vim.b[buf].fox_omnisharp_filename = "$metadata$/String.cs"
		nav.request("references", { excludeDefinition = true })
		t.expect(pending[2].params.fileName).toBe("$metadata$/String.cs")
		t.expect(pending[2].params.excludeDefinition).toBe(true)
	end)
	t.it("rejects late replies after cursor movement or a newer request", function()
		local calls = 0
		nav.show = function()
			calls = calls + 1
		end
		nav.request("definition")
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		reply(1, { Definitions = { { Location = { FileName = tmp .. "/other.cs", Range = range } } } })
		t.expect(calls).toBe(0)
		nav.request("definition")
		nav.request("definition")
		reply(2, { Definitions = {} })
		t.expect(calls).toBe(0)
		reply(3, { Definitions = {} })
		t.expect(calls).toBe(1)
	end)
	t.it("does not overwrite unlocked metadata with unsaved edits", function()
		local uri = nav.source_buffer(client, { SourceName = "unique.cs", Source = "original" })
		local b = vim.uri_to_bufnr(uri)
		vim.bo[b].modifiable = true
		vim.api.nvim_buf_set_lines(b, 0, -1, false, { "user edits" })
		t.expect(nav.source_buffer(client, { SourceName = "unique.cs", Source = "replacement" })).toBe(nil)
		t.expect(vim.api.nvim_buf_get_lines(b, 0, 1, false)[1]).toBe("user edits")
	end)
	t.it("opens multiple locations in native quickfix without Telescope", function()
		vim.fn.writefile({ "a", "b" }, tmp .. "/one.cs")
		local loc = {
			uri = vim.uri_from_fname(tmp .. "/one.cs"),
			range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
		}
		nav.show({ loc, loc }, client)
		t.expect(#vim.fn.getqflist()).toBe(2)
		vim.cmd.cclose()
	end)
	t.it("preserves all four navigation entrypoints and redirects metadata handlers", function()
		nav.lsp_definition()
		nav.lsp_type_definition()
		nav.lsp_references()
		nav.lsp_implementation()
		t.expect(pending[2].method).toBe("o#/gototypedefinition")
		t.expect(pending[4].method).toBe("o#/findimplementations")
		nav.handler(
			nil,
			{
				{
					uri = "file:///$metadata$/String.cs",
					range = { start = { line = 0, character = 0 }, ["end"] = {
						line = 0,
						character = 1,
					} },
				},
			},
			{ bufnr = buf, client_id = client.id }
		)
		t.expect(pending[5].method).toBe("o#/v2/gotodefinition")
	end)
end)
