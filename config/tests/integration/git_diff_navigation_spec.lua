local t = require("fox.lib.foxnvim.test")
local mode = require("plugins.fox.git.diff_mode")
require("lazy").load({ plugins = { "neo-tree.nvim" } })

t.describe("Git diff navigation and branch scope", function()
	local root, original_cwd, tab, original_select, base
	local function git(...)
		local command = { "git", "-C", root }
		vim.list_extend(command, { ... })
		local result = vim.system(command, { text = true }):wait()
		assert(result.code == 0, result.stderr)
		return vim.trim(result.stdout)
	end
	local function write(name, text)
		vim.fn.writefile({ text }, root .. "/" .. name)
	end
	t.beforeEach(function()
		original_cwd, original_select = vim.fn.getcwd(), vim.ui.select
		vim.cmd("tabnew")
		tab = vim.api.nvim_get_current_tabpage()
		root = vim.fs.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
		git("init", "-b", "main")
		git("config", "user.email", "test@example.invalid")
		git("config", "user.name", "FOX Test")
		write("main-only.lua", "return 'main'")
		write("feature1.lua", "return 'before feature'")
		git("add", ".")
		git("commit", "-m", "last main commit")
		base = git("rev-parse", "HEAD")
		git("checkout", "-b", "feature")
		for i = 1, 5 do
			write("feature" .. i .. ".lua", "return " .. i)
			git("add", ".")
			git("commit", "-m", "feature " .. i)
		end
		write("feature1.lua", "return 'working tree'")
		vim.api.nvim_set_current_dir(root)
		vim.cmd.edit(root .. "/feature1.lua")
	end)
	t.afterEach(function()
		vim.ui.select = original_select
		mode.close()
		vim.cmd("Neotree close")
		vim.wait(50)
		if vim.api.nvim_tabpage_is_valid(tab) then
			vim.api.nvim_set_current_tabpage(tab)
			vim.cmd("tabclose!")
		end
		vim.api.nvim_set_current_dir(original_cwd)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf):gsub("\\", "/"):find(root, 1, true) == 1 then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.fn.delete(root, "rf")
	end)
	local function choose_main()
		vim.ui.select = function(items, _, callback)
			t.expect(vim.tbl_contains(items, "main")).toBe(true)
			callback("main")
		end
		mode.pick_ancestor_branch_and_start(root)
		t.expect(mode.state.base_ref).toBe(base)
		t.expect(#mode.state.files).toBe(5)
		for _, item in ipairs(mode.state.files) do
			t.expect(item.file == "main-only.lua").toBe(false)
		end
	end
	t.it("excludes the last base commit and keeps exactly five feature commits plus the worktree", function()
		choose_main()
		t.expect(git("rev-list", "--count", mode.state.base_ref .. "..HEAD")).toBe("5")
	end)
	t.it("uses the fork point even after main advances and preserves cancellation", function()
		write("feature1.lua", "return 1")
		git("checkout", "main")
		write("main-only.lua", "return 'advanced main'")
		git("add", "main-only.lua")
		git("commit", "-m", "advance main")
		git("checkout", "feature")
		write("feature1.lua", "return 'working tree'")
		choose_main()
		vim.ui.select = function(_, _, callback)
			callback(nil)
		end
		mode.pick_ancestor_branch_and_start(root)
		t.expect(mode.state.base_ref).toBe(base)
	end)
	t.it("keeps both sidebars usable and restores highlights when Neo-tree opens files", function()
		choose_main()
		local sidebar, sidebar_buf = mode.state.file_list_win, mode.state.file_list_buf
		local first_buf = vim.api.nvim_win_get_buf(mode.state.editor_win)
		local function marked(buf)
			return #vim.api.nvim_buf_get_extmarks(buf, mode.namespace, 0, -1, {}) > 0
		end
		t.expect(marked(first_buf)).toBe(true)
		local marks = vim.api.nvim_buf_get_extmarks(first_buf, mode.namespace, 0, -1, { details = true })
		t.expect(vim.iter(marks):any(function(mark)
			return mark[4].virt_lines ~= nil
		end)).toBe(true)
		for _ = 1, 2 do
			vim.api.nvim_set_current_win(sidebar)
			vim.cmd("Neotree show left dir=" .. vim.fn.fnameescape(root))
			local state = require("neo-tree.sources.manager").get_state("filesystem")
			t.expect(vim.wait(2000, function()
				return state.winid and vim.api.nvim_win_is_valid(state.winid)
			end)).toBe(true)
			vim.api.nvim_set_current_win(state.winid)
			require("neo-tree.utils").open_file(state, root .. "/feature2.lua", "edit")
			vim.wait(50)
			t.expect(mode.state.is_active).toBe(true)
			t.expect(vim.api.nvim_win_get_buf(sidebar)).toBe(sidebar_buf)
			t.expect(vim.bo[sidebar_buf].filetype).toBe("fox_diff_sidebar")
			t.expect(mode.state.active_file).toBe("feature2.lua")
			t.expect(marked(vim.api.nvim_win_get_buf(mode.state.editor_win))).toBe(true)
			vim.cmd("Neotree close")
			vim.api.nvim_set_current_win(sidebar)
			mode.open_file_same_branch("feature1.lua", { keep_focus = true })
			t.expect(marked(first_buf)).toBe(true)
			t.expect(vim.api.nvim_get_current_win()).toBe(sidebar)
		end
	end)
end)
