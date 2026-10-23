local t = require("fox.lib.foxnvim.test")
local browser = require("fox.markdown.browser")

t.describe("Markdown browser launcher", function()
	local original_has, original_system, original_notify, original_executable
	local cmd, callback, messages, platform
	t.beforeEach(function()
		original_has, original_system = vim.fn.has, vim.system
		original_notify, original_executable = vim.notify, vim.fn.executable
		messages, platform = {}, "linux"
		vim.fn.has = function(feature)
			return feature == platform and 1 or 0
		end
		vim.fn.executable = function()
			return 1
		end
		vim.system = function(args, _, cb)
			cmd, callback = args, cb
		end
		vim.notify = function(message)
			messages[#messages + 1] = message
		end
	end)
	t.afterEach(function()
		vim.fn.has, vim.system = original_has, original_system
		vim.notify, vim.fn.executable = original_notify, original_executable
	end)

	t.it("reports handler failures with the preview URL instead of failing silently", function()
		local url = "http://127.0.0.1:8080/page/1"
		browser.open(url)
		t.expect(cmd).toEqual({ "xdg-open", url })
		callback({ code = 3, stderr = "No browser configured" })
		vim.wait(100, function()
			return #messages > 0
		end)
		t.expect(messages[1]).toContain("No browser configured")
		t.expect(messages[1]).toContain(url)
	end)

	t.it("hands Windows URLs directly to Explorer", function()
		platform = "win32"
		browser.open("http://localhost:8080/page/1")
		t.expect(cmd).toEqual({ "explorer.exe", "http://localhost:8080/page/1" })
		callback({ code = 1, stderr = "" })
		vim.wait(10)
		t.expect(#messages).toBe(0)
	end)

	t.it("uses the Windows browser bridge under WSL", function()
		platform = "wsl"
		browser.open("http://localhost:8080/page/1")
		t.expect(cmd[1]).toBe("wslview")
	end)

	t.it("respects an explicit browser executable", function()
		local previous = vim.g.mkdp_browser
		vim.g.mkdp_browser = "firefox"
		browser.open("http://localhost:8080/page/1")
		vim.g.mkdp_browser = previous
		t.expect(cmd).toEqual({ "firefox", "http://localhost:8080/page/1" })
	end)

	t.it("reports failures to spawn the handler", function()
		vim.system = function()
			error("ENOENT")
		end
		browser.open("http://localhost:8080/page/1")
		vim.wait(100, function()
			return #messages > 0
		end)
		t.expect(messages[1]).toContain("ENOENT")
	end)

	t.it("accepts the same RPC function call that the preview server uses", function()
		local old_handler, old_echo = vim.g.mkdp_browserfunc, vim.g.mkdp_echo_preview_url
		local old_options = vim.g.mkdp_preview_options
		vim.g.mkdp_browserfunc = nil
		browser.setup()
		vim.api.nvim_call_function(vim.g.mkdp_browserfunc, { "http://localhost:8080/page/1" })
		vim.g.mkdp_browserfunc, vim.g.mkdp_echo_preview_url = old_handler, old_echo
		vim.g.mkdp_preview_options = old_options
		vim.cmd("delfunction FoxMarkdownOpenBrowser")
		t.expect(cmd).toEqual({ "xdg-open", "http://localhost:8080/page/1" })
	end)
end)

t.describe("Markdown preview palette commands", function()
	local original_notify, original_filetype, original_toggle, original_stop
	local toggled, stopped, notices
	t.beforeEach(function()
		original_notify, original_filetype = vim.notify, vim.bo.filetype
		original_toggle, original_stop = vim.fn["mkdp#util#toggle_preview"], vim.fn["mkdp#util#stop_preview"]
		toggled, stopped, notices = 0, 0, {}
		vim.fn["mkdp#util#toggle_preview"] = function()
			toggled = toggled + 1
		end
		vim.fn["mkdp#util#stop_preview"] = function()
			stopped = stopped + 1
		end
		vim.notify = function(message)
			notices[#notices + 1] = message
		end
		browser.setup_commands()
	end)
	t.afterEach(function()
		vim.fn["mkdp#util#toggle_preview"], vim.fn["mkdp#util#stop_preview"] = original_toggle, original_stop
		vim.notify, vim.bo.filetype = original_notify, original_filetype
		for _, name in ipairs({ "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" }) do
			vim.api.nvim_del_user_command(name)
		end
	end)

	t.it("executes the palette action without upstream buffer-local commands", function()
		vim.bo.filetype = "markdown"
		require("plugins.fox.tools.command_palette").execute_item({ cmd = "MarkdownPreviewToggle" })
		t.expect(toggled).toBe(1)
	end)

	t.it("explains that a Markdown buffer is required instead of raising E492", function()
		vim.bo.filetype = "text"
		require("plugins.fox.tools.command_palette").execute_item({ cmd = "MarkdownPreviewToggle" })
		t.expect(toggled).toBe(0)
		t.expect(notices[1]).toContain("Open a Markdown or Mermaid buffer")
	end)

	t.it("recognizes standalone Mermaid file extensions", function()
		t.expect(vim.filetype.match({ filename = "diagram.mermaid" })).toBe("mermaid")
		t.expect(vim.filetype.match({ filename = "diagram.mmd" })).toBe("mermaid")
	end)

	t.it("allows stopping the preview from another filetype", function()
		vim.bo.filetype = "text"
		vim.cmd("MarkdownPreviewStop")
		t.expect(stopped).toBe(1)
	end)
end)

t.describe("Standalone Mermaid browser preview", function()
	local source, preview, original_system, original_toggle, original_channel
	local opened, notifications, original_rpcnotify
	t.beforeEach(function()
		source = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(source)
		vim.bo.filetype = "mermaid"
		vim.api.nvim_buf_set_lines(source, 0, -1, false, { "graph TD", "  A-->B" })
		original_system, original_toggle = vim.system, vim.fn["mkdp#util#toggle_preview"]
		original_channel = vim.g.mkdp_node_channel_id
		original_rpcnotify = vim.rpcnotify
		notifications = {}
		vim.g.mkdp_node_channel_id = 123
		vim.rpcnotify = function(_, method, data)
			notifications[#notifications + 1] = { method, data.bufnr }
		end
		vim.system = function(args)
			opened = args[#args]
		end
		vim.fn["mkdp#util#toggle_preview"] = function()
			browser.open("http://localhost:8080/page/" .. source)
		end
		browser.setup_commands()
		vim.cmd("MarkdownPreviewToggle")
		preview = tonumber(opened:match("/page/(%d+)$"))
	end)
	t.afterEach(function()
		vim.api.nvim_buf_delete(source, { force = true })
		vim.system, vim.fn["mkdp#util#toggle_preview"] = original_system, original_toggle
		vim.g.mkdp_node_channel_id = original_channel
		vim.rpcnotify = original_rpcnotify
		for _, name in ipairs({ "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" }) do
			vim.api.nvim_del_user_command(name)
		end
	end)

	t.it("previews a fenced copy without changing source text, filetype or focus", function()
		t.expect(preview).not_.toBe(source)
		t.expect(vim.api.nvim_buf_get_lines(preview, 0, -1, false)).toEqual({ "~~~mermaid", "graph TD", "  A-->B", "~~~" })
		t.expect(vim.api.nvim_buf_get_lines(source, 0, -1, false)).toEqual({ "graph TD", "  A-->B" })
		t.expect(vim.api.nvim_get_current_buf()).toBe(source)
		t.expect(vim.bo.filetype).toBe("mermaid")
		t.expect(vim.bo[preview].buftype).toBe("nofile")
	end)

	t.it("sends unsaved edits to the same browser page", function()
		vim.api.nvim_buf_set_lines(source, 1, -1, false, { "  A-->C" })
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = source })
		t.expect(vim.api.nvim_buf_get_lines(preview, 0, -1, false)[3]).toBe("  A-->C")
		t.expect(notifications[#notifications]).toEqual({ "refresh_content", preview })
	end)

	t.it("keeps fence-like diagram labels inside the Mermaid block", function()
		vim.api.nvim_buf_set_lines(source, 1, -1, false, { "~~~~", "```" })
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = source })
		t.expect(vim.api.nvim_buf_get_lines(preview, 0, 1, false)).toEqual({ "~~~~~mermaid" })
	end)

	t.it("releases the preview buffer when the source is wiped", function()
		vim.api.nvim_exec_autocmds("BufWipeout", { buffer = source })
		t.expect(vim.api.nvim_buf_is_valid(preview)).toBe(false)
	end)

	t.it("restores editor events and focus when the preview command fails", function()
		local eventignore = vim.o.eventignore
		vim.fn["mkdp#util#toggle_preview"] = function()
			error("server failed")
		end
		t.expect(function()
			vim.cmd("MarkdownPreviewToggle")
		end).toThrow()
		t.expect(vim.o.eventignore).toBe(eventignore)
		t.expect(vim.api.nvim_get_current_buf()).toBe(source)
	end)

	t.it("ignores a stale channel after stopping the server", function()
		vim.rpcnotify = function()
			error("Invalid channel: 123")
		end
		vim.api.nvim_exec_autocmds("TextChanged", { buffer = source })
		t.expect(#notifications).toBe(0)
	end)
end)

t.describe("GitHub Flavored Markdown preview defaults", function()
	local old_options, old_handler, old_echo
	t.beforeEach(function()
		old_options = vim.g.mkdp_preview_options
		old_handler, old_echo = vim.g.mkdp_browserfunc, vim.g.mkdp_echo_preview_url
	end)
	t.afterEach(function()
		vim.g.mkdp_preview_options = old_options
		vim.g.mkdp_browserfunc, vim.g.mkdp_echo_preview_url = old_handler, old_echo
		vim.cmd("delfunction FoxMarkdownOpenBrowser")
	end)

	t.it("preserves literal punctuation by default", function()
		vim.g.mkdp_preview_options = nil
		browser.setup()
		t.expect(vim.g.mkdp_preview_options.mkit.typographer).toBe(false)
	end)

	t.it("preserves explicit renderer options and unrelated preview settings", function()
		local options =
			{ mkit = { typographer = true, linkify = false }, maid = { theme = "forest" }, disable_sync_scroll = 1 }
		vim.g.mkdp_preview_options = options
		browser.setup()
		t.expect(vim.g.mkdp_preview_options).toEqual(options)
	end)
end)
