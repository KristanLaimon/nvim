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
		vim.g.mkdp_browserfunc = nil
		browser.setup()
		vim.api.nvim_call_function(vim.g.mkdp_browserfunc, { "http://localhost:8080/page/1" })
		vim.g.mkdp_browserfunc, vim.g.mkdp_echo_preview_url = old_handler, old_echo
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
		t.expect(notices[1]).toContain("Open a Markdown buffer")
	end)

	t.it("allows stopping the preview from another filetype", function()
		vim.bo.filetype = "text"
		vim.cmd("MarkdownPreviewStop")
		t.expect(stopped).toBe(1)
	end)
end)
