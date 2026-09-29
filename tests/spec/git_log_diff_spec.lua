-- ============================================================================
-- tests/spec/git_log_diff_spec.lua -- Git Log Diff Dashboard Spec Tests
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local log_diff = require("plugins.fox.git.log_diff")
local git_center = require("plugins.fox.git.git_center")

describe("plugins.fox.git.log_diff", function()
	beforeEach(function()
		if log_diff.is_open() then
			log_diff.close()
		end
		if git_center.is_open() then
			git_center.close_git_center()
		end
	end)

	afterEach(function()
		if log_diff.is_open() then
			log_diff.close()
		end
		if git_center.is_open() then
			git_center.close_git_center()
		end
	end)

	it("exports public API methods", function()
		expect(type(log_diff.open)).toBe("function")
		expect(type(log_diff.close)).toBe("function")
		expect(type(log_diff.is_open)).toBe("function")
		expect(type(log_diff.fetch_commits)).toBe("function")
		expect(type(log_diff.fetch_commit_files)).toBe("function")
		expect(type(log_diff.fetch_file_diff)).toBe("function")
		expect(type(log_diff.select_commit)).toBe("function")
		expect(type(log_diff.select_file)).toBe("function")
		expect(type(log_diff.toggle_mode)).toBe("function")
		expect(type(log_diff.save_session)).toBe("function")
		expect(type(log_diff.load_session)).toBe("function")
		expect(type(log_diff.get_session_path)).toBe("function")
		expect(type(git_center.open_log_diff)).toBe("function")
	end)

	it("resolves per-project .foxnvim session path", function()
		local cwd = vim.fn.getcwd()
		local path = log_diff.get_session_path(cwd)
		expect(path).toContain(".foxnvim")
		expect(path).toContain("git_log_diff.json")
	end)

	it("fetches commits for current repository", function()
		local commits = log_diff.fetch_commits(vim.fn.getcwd(), "branch", "HEAD", 10)
		expect(type(commits)).toBe("table")
		if #commits > 0 then
			local first = commits[1]
			expect(first.hash).toBeTruthy()
			expect(first.full_hash).toBeTruthy()
			expect(type(first.subject)).toBe("string")
		end
	end)

	it("fetches commit files cleanly", function()
		local commits = log_diff.fetch_commits(vim.fn.getcwd(), "branch", "HEAD", 5)
		if #commits > 0 then
			local files = log_diff.fetch_commit_files(vim.fn.getcwd(), commits[1].full_hash)
			expect(type(files)).toBe("table")
			if #files > 0 then
				expect(files[1].filepath).toBeTruthy()
				expect(files[1].status).toBeTruthy()
			end
		end
	end)

	it("formats side-by-side file diff without error", function()
		local commits = log_diff.fetch_commits(vim.fn.getcwd(), "branch", "HEAD", 5)
		if #commits > 0 then
			local files = log_diff.fetch_commit_files(vim.fn.getcwd(), commits[1].full_hash)
			if #files > 0 then
				local l_lines, l_kinds, r_lines, r_kinds =
					log_diff.fetch_file_diff(vim.fn.getcwd(), commits[1].full_hash, files[1].filepath, files[1].status)
				expect(type(l_lines)).toBe("table")
				expect(type(r_lines)).toBe("table")
				expect(type(l_kinds)).toBe("table")
				expect(type(r_kinds)).toBe("table")
				expect(#l_lines).toBeGreaterThan(0)
				expect(#r_lines).toBeGreaterThan(0)
				expect(#l_lines).toBe(#r_lines)
			end
		end
	end)

	it("opens and closes the 4-panel dashboard in a dedicated tabpage", function()
		log_diff.open({ cwd = vim.fn.getcwd(), mode = "branch" })
		expect(log_diff.is_open()).toBeTruthy()
		expect(log_diff.state.files_win).toBeTruthy()
		expect(log_diff.state.logs_win).toBeTruthy()
		expect(log_diff.state.before_win).toBeTruthy()
		expect(log_diff.state.after_win).toBeTruthy()

		-- Test cycling panels
		log_diff.cycle_next_panel()
		log_diff.cycle_prev_panel()

		-- Test jump functions
		log_diff.focus_files()
		expect(vim.api.nvim_get_current_win()).toBe(log_diff.state.files_win)

		log_diff.focus_logs()
		expect(vim.api.nvim_get_current_win()).toBe(log_diff.state.logs_win)

		-- Test chronological navigation
		local init_idx = log_diff.state.active_commit_idx
		log_diff.next_older_commit()
		if #log_diff.state.commits > 1 then
			expect(log_diff.state.active_commit_idx).toBe(init_idx + 1)
		end
		log_diff.next_newer_commit()
		expect(log_diff.state.active_commit_idx).toBe(init_idx)

		log_diff.close()
		expect(log_diff.is_open()).toBeFalsy()
	end)

	it("renders top and bottom remaining commit indicators when navigating", function()
		log_diff.open({ cwd = vim.fn.getcwd(), mode = "branch" })
		if #log_diff.state.commits >= 3 then
			log_diff.select_commit(2)
			local lines = vim.api.nvim_buf_get_lines(log_diff.state.logs_buf, 0, -1, false)
			local content = table.concat(lines, "\n")
			expect(content).toContain("▲")
			expect(content).toContain("newer commit")
			expect(content).toContain("▼")
			expect(content).toContain("older commit")
		end
		log_diff.close()
	end)

	it("supports dynamic resizing of columns and rows", function()
		log_diff.open({ cwd = vim.fn.getcwd(), mode = "branch" })
		local orig_left = log_diff.state.left_ratio
		log_diff.resize_left(4)
		expect(log_diff.state.left_ratio).toBeGreaterThan(orig_left)
		log_diff.resize_left(-4)
		local orig_top = log_diff.state.top_ratio
		log_diff.resize_top(2)
		expect(log_diff.state.top_ratio).toBeGreaterThan(orig_top)
		log_diff.resize_top(-2)
		log_diff.close()
	end)

	it("opens and dismisses the help modal cleanly", function()
		log_diff.open({ cwd = vim.fn.getcwd(), mode = "branch" })
		log_diff.show_help()
		-- Find float window
		local found_float = false
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if vim.api.nvim_win_get_config(w).relative ~= "" then
				found_float = true
				pcall(vim.api.nvim_win_close, w, true)
				break
			end
		end
		expect(found_float).toBeTruthy()
		log_diff.close()
	end)

	it("registers Ex commands for GitLogDiff", function()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds.GitLogDiff ~= nil or cmds.GitCenterLogDiff ~= nil or cmds.FoxGitLogDiff ~= nil).toBeTruthy()
	end)
end)
