-- ============================================================================
-- config/tests/spec/statusline_spec.lua -- Statusline engine & theme picker.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local statusline = require("plugins.fox.ui.statusline_picker")

describe("plugins.fox.ui.statusline_picker", function()
	it("shows Editor and Query with only the current workspace mode in normal color", function()
		local saved = package.loaded["fox.query"]
		local ok, err = pcall(function()
			package.loaded["fox.query"] = nil
			local editor = statusline.workflow_status()
			expect(vim.api.nvim_eval_statusline(editor, {}).str).toBe("[Editor | Query]")
			expect(editor).toContain("%#StatusLine#Editor")
			expect(editor).toContain("%#FoxWorkflowInactive#Query")
			local state = { mode = "query", tab = vim.api.nvim_get_current_tabpage() }
			package.loaded["fox.query"] = { states = { test = state } }
			local query = statusline.workflow_status()
			expect(vim.api.nvim_eval_statusline(query, {}).str).toBe("[Editor | Query]")
			expect(query).toContain("%#FoxWorkflowInactive#Editor")
			expect(query).toContain("%#StatusLine#Query")
			state.tab = -1
			expect(statusline.workflow_status()).toBe(editor)
		end)
		package.loaded["fox.query"] = saved
		if not ok then
			error(err)
		end
	end)

	it("formats modes into NvChad icon pills", function()
		expect(statusline.format_mode("NORMAL")).toBe(" NORMAL")
		expect(statusline.format_mode("INSERT")).toBe("󰏫 INSERT")
		expect(statusline.format_mode("VISUAL")).toBe("󰈈 VISUAL")
		expect(statusline.format_mode("COMMAND")).toBe("󰘳 COMMAND")
	end)

	it("formats current buffer line ending into LF / CRLF / CR labels", function()
		local buf = vim.api.nvim_get_current_buf()
		local saved = vim.bo[buf].fileformat

		vim.bo[buf].fileformat = "unix"
		expect(statusline.fileformat_status()).toBe("⏎ LF")

		vim.bo[buf].fileformat = "dos"
		expect(statusline.fileformat_status()).toBe("⏎ CRLF")

		vim.bo[buf].fileformat = "mac"
		expect(statusline.fileformat_status()).toBe("⏎ CR")

		vim.bo[buf].fileformat = saved
	end)

	it("is placed first in the left statusbar section for every theme", function()
		local themes = { "nvchad_pills", "nvchad_blocks", "nvchad_round", "nagatoro_classic", "vscode", "minimal" }
		for _, name in ipairs(themes) do
			local cfg = statusline.get_config(name)
			local secs = cfg.sections
			local left = name == "nagatoro_classic" and secs.a or secs.b
			expect(left[1]).toBe(statusline.fileformat_status)
		end
	end)

	it("returns formatted LSP status string", function()
		expect(statusline.lsp_status()).toBeDefined()
		expect(type(statusline.lsp_status())).toBe("string")
	end)

	it("cleans up raw terminal URLs into readable badges", function()
		expect(statusline.format_filename("term://~\\AppData\\Local\\nvim//14964:C:\\PROGRA~1\\Git\\bin\\bash.exe")).toBe(
			"󰞷 Terminal (bash)"
		)
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal (powershell)")
		expect(statusline.format_filename("lua/config/options.lua")).toBe("lua/config/options.lua")
	end)

	it("formats multi-terminal labels with process title (Terminal #number - process)", function()
		vim.b.fox_term_num = 2
		vim.b.term_title = nil
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal #2 - powershell")

		vim.b.term_title = "claude"
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal #2 - claude")

		vim.b.term_title = "Administrator: Windows PowerShell"
		expect(statusline.format_filename("term://code//5120:powershell.exe")).toBe("󰞷 Terminal #2 - powershell")

		vim.b.fox_term_num = nil
		vim.b.term_title = nil
	end)

	it("returns valid native layouts for all supported themes", function()
		local themes = { "nvchad_pills", "nvchad_blocks", "nvchad_round", "nagatoro_classic", "vscode", "minimal" }
		for _, name in ipairs(themes) do
			local cfg = statusline.get_config(name)
			expect(cfg).toBeDefined()
			expect(cfg.options).toBeDefined()
			expect(cfg.sections).toBeDefined()
			expect(cfg.sections.a).toBeDefined()
			expect(cfg.sections.c[1]).toBe(statusline.workflow_status)
		end
	end)

	it("registers FoxStatuslineTheme user command", function()
		statusline.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["FoxStatuslineTheme"]).toBeDefined()
	end)

	it("dynamically resolves git branch from directory instead of defaulting to main", function()
		-- In current repo
		statusline.resolve_git_branch(vim.fn.getcwd())
		vim.wait(3000, function()
			return statusline.resolve_git_branch(vim.fn.getcwd()) ~= ""
		end)
		local cur_branch = statusline.resolve_git_branch(vim.fn.getcwd())
		expect(type(cur_branch)).toBe("string")
		expect(cur_branch ~= "").toBeTruthy()

		-- In non-git directory, returns empty string
		local tmp_dir = vim.fn.tempname()
		vim.fn.mkdir(tmp_dir, "p")
		expect(statusline.resolve_git_branch(tmp_dir)).toBe("")

		-- In a repo with custom branch name
		local test_repo = vim.fn.tempname()
		vim.fn.mkdir(test_repo, "p")
		vim.fn.system({ "git", "-C", test_repo, "init", "-b", "feature-statusline-test" })
		statusline.resolve_git_branch(test_repo)
		vim.wait(3000, function()
			return statusline.resolve_git_branch(test_repo) ~= ""
		end)
		local resolved = statusline.resolve_git_branch(test_repo)
		expect(resolved).toBe("feature-statusline-test")

		-- Test git_branch() function
		local branch_label = statusline.git_branch()
		expect(type(branch_label)).toBe("string")

		vim.fn.delete(tmp_dir, "rf")
		vim.fn.delete(test_repo, "rf")
	end)
end)

describe("native statusline rendering", function()
	local engine = require("fox.ui.statusline")
	local buf, previous, old_status, old_last
	t.beforeEach(function()
		previous = vim.api.nvim_get_current_tabpage()
		-- A previous explorer test may leave window-local navigation hooks behind.
		vim.cmd("tabnew")
		old_status, old_last = vim.o.statusline, vim.o.laststatus
		buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "-100%#Error#-🦊.lua")
		vim.bo.filetype = "lua"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
	end)
	t.afterEach(function()
		vim.diagnostic.reset(nil, buf)
		vim.cmd("tabclose!")
		vim.api.nvim_set_current_tabpage(previous)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.o.statusline, vim.o.laststatus = old_status, old_last
		require("fox.ui.statusline_git").invalidate()
	end)
	it("renders all saved layouts with real statusline parsing and narrow widths", function()
		for name in pairs(statusline.available_themes) do
			engine.setup(statusline.get_config(name))
			local rendered = engine.render()
			local wide = vim.api.nvim_eval_statusline(rendered, { maxwidth = 300, highlights = true })
			expect(wide.str).toContain("100%#Error#-🦊.lua")
			expect(wide.str).toContain("[Editor | Query]")
			expect(wide.str).toContain("󰏫")
			expect(wide.str).toContain("1:1")
			local narrow = vim.api.nvim_eval_statusline(rendered, { maxwidth = 40 })
			expect(narrow.width <= 40).toBe(true)
			expect(vim.o.laststatus).toBe(3)
		end
	end)
	it("updates diagnostics, diff counters, readonly and cursor position", function()
		engine.setup(statusline.get_config("nvchad_pills"))
		local ns = vim.api.nvim_create_namespace("statusline_test_diagnostics")
		vim.diagnostic.set(ns, buf, { { lnum = 0, col = 0, message = "error", severity = vim.diagnostic.severity.ERROR } })
		vim.b.gitsigns_status_dict = { added = 3, changed = 2, removed = 1 }
		vim.bo.readonly = true
		vim.api.nvim_win_set_cursor(0, { 2, 1 })
		local text = vim.api.nvim_eval_statusline(engine.render(), { maxwidth = 400 }).str
		expect(text).toContain(" 1")
		expect(text).toContain(" 3")
		expect(text).toContain("󰝤 2")
		expect(text).toContain(" 1")
		expect(text).toContain("󰌾")
		expect(text).toContain("2:2")
		vim.diagnostic.reset(ns, buf)
		expect(vim.api.nvim_eval_statusline(engine.render(), { maxwidth = 400 }).str:find(" 1", 1, true)).toBe(nil)
	end)
	it("escapes client and environment names while retaining workflow highlights", function()
		local get_clients, env = vim.lsp.get_clients, _G.Environments
		vim.lsp.get_clients = function()
			return { { name = "test%#Error#" } }
		end
		_G.Environments = {
			indicator_status = function()
				return "env%name"
			end,
		}
		engine.setup(statusline.get_config("nvchad_pills"))
		local ok, text = pcall(function()
			return vim.api.nvim_eval_statusline(engine.render(), { maxwidth = 500 }).str
		end)
		vim.lsp.get_clients, _G.Environments = get_clients, env
		assert(ok, text)
		expect(text).toContain("test%#Error#")
		expect(text).toContain("env%name")
	end)
	it("keeps other components visible if a provider fails", function()
		local cfg = statusline.get_config("minimal")
		table.insert(cfg.sections.b, function()
			error("provider failed")
		end)
		engine.setup(cfg)
		expect(vim.api.nvim_eval_statusline(engine.render(), { maxwidth = 300 }).str).toContain("100%#Error#")
	end)
end)

describe("statusline persistence errors", function()
	it("reports a failed save without applying a different layout", function()
		local store = require("fox.core.store")
		local save, notify = store.save, vim.notify
		local old_status, old_last = vim.o.statusline, vim.o.laststatus
		local message
		local engine = require("fox.ui.statusline")
		engine.setup(statusline.get_config("minimal"))
		local before = engine.render()
		store.save = function()
			return false, "read-only destination"
		end
		vim.notify = function(value)
			message = value
		end
		local ok, err = pcall(statusline.set_theme, "nvchad_pills")
		store.save, vim.notify = save, notify
		assert(ok, err)
		expect(message).toContain("read-only destination")
		expect(engine.render()).toBe(before)
		vim.o.statusline, vim.o.laststatus = old_status, old_last
		require("fox.ui.statusline_git").invalidate()
	end)
end)

describe("statusline async Git safety", function()
	it("counts changed, added, removed and binary diff hunks", function()
		local git = require("fox.ui.statusline_git")
		local counts = git.parse_diff("@@ -1,2 +1,3 @@\n@@ -6,3 +7,0 @@\n@@ -10,0 +9 @@\n")
		expect(counts.changed).toBe(2)
		expect(counts.added).toBe(2)
		expect(counts.removed).toBe(3)
		expect(git.parse_diff("Binary files differ").changed).toBe(0)
	end)

	it("ignores cancelled replies, caches failures and tolerates spawn errors", function()
		local git = require("fox.ui.statusline_git")
		git.invalidate()
		local system, callbacks, killed = vim.system, {}, 0
		vim.system = function(_, _, cb)
			callbacks[#callbacks + 1] = cb
			return {
				kill = function()
					killed = killed + 1
				end,
			}
		end
		local ok, err = pcall(function()
			expect(git.branch("/first")).toBe("")
			expect(git.branch("/second")).toBe("")
			expect(killed).toBe(1)
			callbacks[1]({ code = 0, stdout = "stale" })
			callbacks[2]({ code = 0, stdout = "current" })
			vim.wait(100, function()
				return git.branch("/second") == "current"
			end)
			expect(git.branch("/second")).toBe("current")
			git.invalidate()
			vim.system = function()
				error("missing Git")
			end
			expect(git.branch("/missing")).toBe("")
			expect(git.branch("/missing")).toBe("")
		end)
		vim.system = system
		git.invalidate()
		assert(ok, err)
	end)
end)
