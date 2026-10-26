local t = require("fox.lib.foxnvim.test")
local engine = require("fox.ui.statusline")
local git = require("fox.ui.statusline_git")
local picker = require("plugins.fox.ui.statusline_picker")
local function text()
	return vim.api.nvim_eval_statusline(engine.render(), { maxwidth = 500 }).str
end
local function run(dir, args)
	local result = vim.system(vim.list_extend({ "git", "-C", dir }, args), { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end

t.describe("native statusline integration", function()
	t.it("boots without lualine and preserves theme persistence and cancellation", function()
		local plugins = require("lazy.core.config").plugins
		t.expect(plugins["lualine.nvim"]).toBe(nil)
		t.expect(plugins.fox_statusline.dir == plugins.fox_theme_startup.dir).toBe(false)
		require("lazy").load({ plugins = { "fox_statusline" } })
		t.expect(package.loaded.lualine).toBe(nil)
		t.expect(vim.o.statusline).toContain("fox.ui.statusline")
		local saved, select = picker.settings.store_file, vim.ui.select
		local path = vim.fn.tempname()
		picker.settings.store_file = path
		local ok, err = pcall(function()
			picker.set_theme("vscode")
			t.expect(picker.get_current_theme()).toBe("vscode")
			vim.ui.select = function(_, _, cb)
				cb(nil, nil)
			end
			picker.open_picker()
			t.expect(picker.get_current_theme()).toBe("vscode")
			t.expect(text():find("", 1, true)).toBe(nil)
		end)
		picker.settings.store_file, vim.ui.select = saved, select
		vim.fn.delete(path)
		engine.setup(picker.get_config())
		assert(ok, err)
	end)
	t.it("refreshes real branch, detached HEAD, worktree and file diff asynchronously", function()
		local dir, previous = vim.fn.tempname(), vim.api.nvim_get_current_buf()
		vim.fn.mkdir(dir, "p")
		local worktree = dir .. "-worktree"
		local buf = vim.api.nvim_create_buf(true, false)
		local ok, err = pcall(function()
			run(dir, { "init", "-b", "statusline-test" })
			vim.fn.writefile({ "old" }, dir .. "/sample.txt")
			run(dir, { "add", "." })
			run(dir, { "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "initial" })
			vim.api.nvim_set_current_buf(buf)
			vim.api.nvim_buf_set_name(buf, dir .. "/sample.txt")
			engine.setup(picker.get_config("nvchad_pills"))
			git.invalidate()
			t.expect(vim.wait(3000, function()
				return picker.git_branch() == "statusline-test"
			end)).toBe(true)
			t.expect(text()).toContain("statusline-test")
			vim.fn.writefile({ "new", "added" }, dir .. "/sample.txt")
			git.invalidate()
			t.expect(vim.wait(3000, function()
				return git.diff().changed == 1
			end)).toBe(true)
			t.expect(git.diff().added).toBe(1)
			t.expect(text()).toContain("󰝤 1")
			run(dir, { "checkout", "--detach" })
			local sha = run(dir, { "rev-parse", "--short", "HEAD" })
			git.invalidate()
			t.expect(vim.wait(3000, function()
				return picker.git_branch() == sha
			end)).toBe(true)
			run(dir, { "worktree", "add", "-b", "linked-status", worktree })
			t.expect(vim.wait(3000, function()
				return git.branch(worktree) == "linked-status"
			end)).toBe(true)
		end)
		git.invalidate()
		vim.api.nvim_set_current_buf(previous)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(worktree, "rf")
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
	t.it("renders real terminal task titles and active LSP attachment", function()
		local previous = vim.api.nvim_get_current_buf()
		vim.cmd.enew()
		local buf = vim.api.nvim_get_current_buf()
		local client
		local ok, err = pcall(function()
			vim.fn.jobstart({ "sh", "-c", "printf ready" }, { term = true })
			vim.b.fox_task_name = "statusline-task"
			vim.b.term_title = "test-shell"
			engine.setup(picker.get_config("nvchad_pills"))
			t.expect(text()).toContain("Task: statusline-task")
			-- Real built-in LSP transport with the existing fixture, no optional tool install.
			vim.cmd.enew()
			local lspbuf = vim.api.nvim_get_current_buf()
			client = vim.lsp.start({
				name = "statusline-fixture",
				cmd = { "python3", vim.fn.stdpath("config") .. "/config/tests/fixtures/file_operations_server.py" },
				capabilities = require("fox.lsp.file_operations").capabilities(),
				root_dir = vim.fn.getcwd(),
			})
			assert(client, "LSP did not start")
			t.expect(vim.wait(3000, function()
				return picker.lsp_status():find("statusline-fixture", 1, true) ~= nil
			end)).toBe(true)
			t.expect(text()).toContain("statusline-fixture")
			vim.lsp.buf_detach_client(lspbuf, client)
			t.expect(text():find("statusline-fixture", 1, true)).toBe(nil)
			vim.api.nvim_buf_delete(lspbuf, { force = true })
		end)
		if client then
			vim.lsp.stop_client(client, true)
		end
		vim.api.nvim_set_current_buf(previous)
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)
end)
