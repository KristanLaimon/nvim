local t = require("fox.lib.foxnvim.test")
local installer = require("fox.core.installer")

t.describe("installer operation selection", function()
	local bundles, status, install, uninstall, defer, notify
	local win, buf, calls

	local function key(lhs)
		vim.fn.maparg(lhs, "n", false, true).callback()
	end

	local function row(text)
		for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			if line:find(text, 1, true) then
				vim.api.nvim_win_set_cursor(win, { index, 0 })
				return line
			end
		end
		error("Missing installer row: " .. text)
	end

	t.beforeEach(function()
		bundles, status = installer.language_bundles, installer.get_bundle_status
		install, uninstall = installer.install_batch, installer.uninstall_batch
		defer, notify = vim.defer_fn, vim.notify
		calls = {}
		installer.language_bundles = {}
		for index, name in ipairs({ "Lua default", "Markdown default", "Installed optional" }) do
			table.insert(installer.language_bundles, {
				name = name,
				is_minimal = index < 3,
				mason_pkgs = { "pkg" .. index },
				mason_components = { { pkg = "pkg" .. index, type = "lsp", label = "Tool " .. index } },
				treesitter = { "parser" .. index },
			})
		end
		installer.get_bundle_status = function()
			return { installed_count = 2, total_count = 2, badge = "Installed", blocked = false }
		end
		installer.install_batch = function(jobs)
			table.insert(calls, { action = "install", jobs = jobs })
		end
		installer.uninstall_batch = function(jobs)
			table.insert(calls, { action = "uninstall", jobs = jobs })
		end
		vim.defer_fn = function(callback)
			callback()
		end
		vim.notify = function() end
		installer.open_language_manager()
		win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	end)

	t.afterEach(function()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		installer.language_bundles, installer.get_bundle_status = bundles, status
		installer.install_batch, installer.uninstall_batch = install, uninstall
		vim.defer_fn, vim.notify = defer, notify
	end)

	t.it("starts with no selections, including defaults and already installed bundles", function()
		for _, bundle in ipairs(installer.language_bundles) do
			t.expect(row(bundle.name):find("[ ]", 1, true) ~= nil).toBe(true)
		end
		-- A cursor on an unselected row must not install or remove anything.
		key("i")
		key("u")
		t.expect(#calls).toBe(0)
	end)

	t.it("installs and uninstalls only the one or multiple checked bundles in a single batch", function()
		row("Installed optional")
		key("<Space>")
		key("i")
		t.expect(#calls).toBe(1)
		t.expect(#calls[1].jobs).toBe(1)
		t.expect(calls[1].jobs[1].bundle.name).toBe("Installed optional")
		t.expect(calls[1].jobs[1].sel).toEqual({ mason = { "pkg3" }, ts = { "parser3" }, dotnet = {} })
		row("Markdown default")
		key("<Space>")
		key("u")
		t.expect(#calls).toBe(2)
		t.expect(calls[2].action).toBe("uninstall")
		t.expect(#calls[2].jobs).toBe(2)
		t.expect(calls[2].jobs[1].bundle.name).toBe("Markdown default")
		t.expect(calls[2].jobs[2].bundle.name).toBe("Installed optional")
	end)

	t.it("clears every checkbox with Select None and preserves individual component selections", function()
		key("a")
		key("n")
		key("u")
		t.expect(#calls).toBe(0)
		row("Markdown default")
		key("<CR>")
		row("Tool 2")
		key("<Space>")
		key("i")
		t.expect(#calls).toBe(1)
		t.expect(#calls[1].jobs).toBe(1)
		t.expect(calls[1].jobs[1].sel).toEqual({ mason = { "pkg2" }, ts = {}, dotnet = {} })
	end)
end)
