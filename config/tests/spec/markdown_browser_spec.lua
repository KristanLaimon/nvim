local t = require("fox.lib.foxnvim.test")
local browser = require("fox.markdown.browser")
local server = require("fox.markdown.server")
local render = require("fox.markdown.render")

t.describe("Markdown browser launcher", function()
	local original_has, original_spawn, original_system, original_notify, original_handler, original_browser
	local cmd, opts, callback, messages, platform
	t.beforeEach(function()
		original_has, original_spawn, original_system = vim.fn.has, vim.uv.spawn, vim.system
		original_notify, original_handler, original_browser = vim.notify, vim.g.mkdp_browserfunc, vim.g.mkdp_browser
		vim.g.mkdp_browserfunc, vim.g.mkdp_browser = nil, nil
		messages, platform = {}, "linux"
		vim.fn.has = function(feature)
			return feature == platform and 1 or 0
		end
		vim.system = function(args, options, cb)
			cmd, opts, callback = args, options, cb
		end
		vim.uv.spawn = function(command, options, cb)
			cmd, opts = { command, options.args[1] }, options
			callback = function(result)
				cb(result.code)
			end
			return {
				is_closing = function()
					return false
				end,
				close = function() end,
			}
		end
		vim.notify = function(message)
			messages[#messages + 1] = message
		end
	end)
	t.afterEach(function()
		vim.fn.has, vim.uv.spawn, vim.system = original_has, original_spawn, original_system
		vim.notify, vim.g.mkdp_browserfunc, vim.g.mkdp_browser = original_notify, original_handler, original_browser
	end)
	t.it("launches Windows Explorer visibly without detached flags", function()
		platform = "win32"
		local url = "http://127.0.0.1:8080/page/?a=1&b=2"
		browser.open(url)
		t.expect(cmd).toEqual({ "explorer.exe", url })
		t.expect(opts.hide).toBe(false)
		t.expect(opts.detached).toBe(nil)
		callback({ code = 1 })
		vim.wait(10)
		t.expect(#messages).toBe(0)
	end)
	t.it("passes a Windows browser path and URL as separate arguments", function()
		platform = "win32"
		vim.g.mkdp_browser = "C:/Program Files/Browser/browser.exe"
		browser.open("http://localhost:1234/")
		t.expect(cmd).toEqual({ vim.g.mkdp_browser, "http://localhost:1234/" })
	end)
	t.it("reports browser failure with a manually usable URL", function()
		browser.open("http://localhost:8080/")
		callback({ code = 3, stderr = "No browser configured" })
		vim.wait(100, function()
			return #messages > 0
		end)
		t.expect(messages[1]).toContain("No browser configured")
		t.expect(messages[1]).toContain("http://localhost:8080/")
	end)
	t.it("reports Windows process creation errors", function()
		platform = "win32"
		vim.uv.spawn = function()
			return nil, "ENOENT"
		end
		browser.open("http://localhost:8080/")
		vim.wait(100, function()
			return #messages > 0
		end)
		t.expect(messages[1]).toContain("ENOENT")
	end)
end)

t.describe("Native Markdown renderer", function()
	t.it("renders the GFM fixture without external tools", function()
		local html = render.render(vim.fn.readfile("config/tests/fixtures/markdown/gfm.md"))
		for _, expected in ipairs({
			"<table>",
			"text-align:right",
			"a|b",
			'type="checkbox" disabled checked',
			"<s>Obsolete</s>",
			'<a href="https://github.com">',
			'href="mailto:test@example.com"',
			"<code>~~inline literal~~</code>",
			"<details>",
			"<summary>More information</summary>",
			'<pre class="mermaid">',
			"three dots... and (c).",
		}) do
			t.expect(html).toContain(expected)
		end
	end)
	t.it("escapes scripts, handlers and unsafe link schemes", function()
		local html = render.render({
			"<script>alert(1)</script>",
			"[click](javascript:alert)",
			"![image](data:evil)",
			'![quote](https://example.com/"onerror="alert)',
		})
		t.expect(html).not_.toContain("<script>")
		t.expect(html).not_.toContain('href="javascript:')
		t.expect(html).not_.toContain('src="data:')
		t.expect(html).toContain("&quot;")
	end)
	t.it("keeps unfinished code fences and Unicode literal", function()
		local html = render.render({ "```lua", 'print("á ~~ok~~")' })
		t.expect(html).toContain("á ~~ok~~")
		t.expect(html).not_.toContain("<s>")
	end)
end)

local function get(url, headers)
	local result
	local cmd = { "curl", "--silent", "--show-error", "--max-time", "5", "--include", "--path-as-is", url }
	for _, header in ipairs(headers or {}) do
		vim.list_extend(cmd, { "-H", header })
	end
	vim.system(cmd, { text = true }, function(value)
		result = value
	end)
	assert(
		vim.wait(6000, function()
			return result ~= nil
		end),
		"HTTP request timed out"
	)
	assert(result.code == 0, result.stderr)
	return result.stdout
end

t.describe("Native Markdown HTTP preview", function()
	local source, url, original_open, original_notify
	t.beforeEach(function()
		original_open, original_notify = browser.open, vim.notify
		vim.notify = function() end
		browser.open = function(value)
			url = value
		end
		source = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(source)
		vim.bo.filetype = "markdown"
		vim.api.nvim_buf_set_lines(source, 0, -1, false, { "# Windows preview" })
		browser.setup()
		browser.setup_commands()
		vim.cmd("MarkdownPreview")
	end)
	t.afterEach(function()
		server.stop()
		browser.open, vim.notify = original_open, original_notify
		vim.api.nvim_buf_delete(source, { force = true })
		for _, name in ipairs({ "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" }) do
			vim.api.nvim_del_user_command(name)
		end
	end)
	t.it("serves the page, browser assets and unsaved buffer edits over real TCP", function()
		t.expect(get(url)).toContain("FoxVim Markdown Preview")
		t.expect(get(url .. "preview.js")).toContain("mermaid.initialize")
		t.expect(get(url .. "mermaid.min.js")).toContain("HTTP/1.1 200")
		t.expect(get(url .. "content")).toContain("Windows preview")
		vim.api.nvim_buf_set_lines(source, 0, -1, false, { "# Unsaved á" })
		t.expect(get(url .. "content")).toContain("Unsaved á")
	end)
	t.it("rejects missing tokens, foreign Host headers and path traversal", function()
		local root = url:match("^(http://[^/]+)")
		t.expect(get(root .. "/content")).toContain("HTTP/1.1 404")
		t.expect(get(url, { "Host: attacker.example" })).toContain("HTTP/1.1 403")
		t.expect(get(url .. "../../secret.png")).toContain("HTTP/1.1 404")
	end)
	t.it("serves document images but rejects encoded traversal to a real sibling", function()
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory .. "/docs", "p")
		vim.fn.writefile({ "inside" }, directory .. "/docs/image.png")
		vim.fn.writefile({ "secret" }, directory .. "/outside.png")
		local ok, err = pcall(function()
			vim.api.nvim_buf_set_name(source, directory .. "/docs/preview.md")
			t.expect(get(url .. "image.png")).toContain("inside")
			t.expect(get(url .. "%2e%2e/outside.png")).toContain("HTTP/1.1 404")
			t.expect(get(url .. "image.png", { "Host: localhost" })).toContain("HTTP/1.1 403")
		end)
		vim.fn.delete(directory, "rf")
		assert(ok, err)
	end)
	t.it("executes the palette command without the upstream plugin", function()
		vim.cmd("MarkdownPreviewStop")
		require("plugins.fox.tools.command_palette").execute_item({ cmd = "MarkdownPreviewToggle" })
		t.expect(server.active(source)).toBe(true)
	end)
	t.it("previews standalone Mermaid without modifying the buffer", function()
		vim.bo.filetype = "mermaid"
		vim.api.nvim_buf_set_lines(source, 0, -1, false, { "graph TD", "A-->B" })
		t.expect(get(url .. "content")).toContain('class=\\"mermaid\\"')
		t.expect(vim.api.nvim_buf_get_lines(source, 0, -1, false)).toEqual({ "graph TD", "A-->B" })
	end)
	t.it("rejects wiped buffers and stops through the existing command", function()
		local other = vim.api.nvim_create_buf(false, true)
		local other_url = server.start(other)
		vim.api.nvim_buf_delete(other, { force = true })
		t.expect(get(other_url .. "content")).toContain("HTTP/1.1 410")
		vim.cmd("MarkdownPreviewToggle")
		t.expect(server.active(source)).toBe(false)
		vim.cmd("MarkdownPreview")
		t.expect(server.active(source)).toBe(true)
		vim.cmd("MarkdownPreviewStop")
		t.expect(server.active(source)).toBe(false)
	end)
end)
