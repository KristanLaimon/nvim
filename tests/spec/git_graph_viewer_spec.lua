-- ============================================================================
-- tests/spec/git_graph_viewer_spec.lua -- GitKraken Commit Graph Viewer Tests
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local graph_viewer = require("plugins.fox.git.git_center.graph_viewer")
local config = require("plugins.fox.git.git_center.config")
local git_center = require("plugins.fox.git.git_center")

describe("plugins.fox.git.git_center.graph_viewer", function()
	beforeEach(function()
		if git_center.is_open() then
			git_center.close_git_center()
		end
		if config.graph_win and vim.api.nvim_win_is_valid(config.graph_win) then
			pcall(vim.api.nvim_win_close, config.graph_win, true)
		end
		if config.graph_right_win and vim.api.nvim_win_is_valid(config.graph_right_win) then
			pcall(vim.api.nvim_win_close, config.graph_right_win, true)
		end
	end)

	afterEach(function()
		if git_center.is_open() then
			git_center.close_git_center()
		end
		if config.graph_win and vim.api.nvim_win_is_valid(config.graph_win) then
			pcall(vim.api.nvim_win_close, config.graph_win, true)
		end
		if config.graph_right_win and vim.api.nvim_win_is_valid(config.graph_right_win) then
			pcall(vim.api.nvim_win_close, config.graph_right_win, true)
		end
	end)

	it("exports public API methods", function()
		expect(type(graph_viewer.open)).toBe("function")
		expect(type(graph_viewer.fetch_commits)).toBe("function")
		expect(type(graph_viewer.beautify_graph_prefix)).toBe("function")
		expect(type(graph_viewer.parse_raw_graph_line)).toBe("function")
		expect(type(graph_viewer.format_commit_line)).toBe("function")
		expect(type(graph_viewer.setup_highlights)).toBe("function")
		expect(type(git_center.open_graph_viewer)).toBe("function")
	end)

	it("beautifies raw ASCII git graph characters into GitKraken Unicode glyphs", function()
		local raw = "* | / \\ _ ."
		local beautified = graph_viewer.beautify_graph_prefix(raw)
		expect(beautified).toBe("● │ ╱ ╲ ─ ⬝")
	end)

	it("parses raw git graph commit lines with delimiter", function()
		local raw =
			"* 87a6e94\x1f (HEAD -> main, origin/main, tag: v1.0.0)\x1fFoxDeveloper\x1f25 hours ago\x1ffeat: Neo-tree mover"
		local parsed = graph_viewer.parse_raw_graph_line(raw)

		expect(parsed.is_commit).toBeTruthy()
		expect(parsed.hash).toBe("87a6e94")
		expect(parsed.author).toBe("FoxDeveloper")
		expect(parsed.date).toBe("25 hours ago")
		expect(parsed.subject).toBe("feat: Neo-tree mover")
		expect(parsed.refs).toContain("HEAD -> main")
	end)

	it("parses pure graph connector lines without commits", function()
		local raw = "|/| "
		local parsed = graph_viewer.parse_raw_graph_line(raw)

		expect(parsed.is_commit).toBeFalsy()
		expect(parsed.hash).toBeNil()
		expect(parsed.graph_raw).toBe("|/| ")
	end)

	it("captures the full commit hash for current-branch membership checks", function()
		local raw =
			"* 87a6e94\x1f (HEAD -> main)\x1fFoxDeveloper\x1f25 hours ago\x1ffeat: x\x1f87a6e94abcdef0123456789abcdef0123456789"
		local parsed = graph_viewer.parse_raw_graph_line(raw)

		expect(parsed.hash).toBe("87a6e94")
		expect(parsed.full_hash).toBe("87a6e94abcdef0123456789abcdef0123456789")
		expect(parsed.subject).toBe("feat: x")
	end)

	it("fetches commits honouring order and connector options", function()
		local cwd = vim.fn.getcwd()
		local res = graph_viewer.fetch_commits(10, cwd, "all", {
			order = "topo",
			connector_mode = "hidden",
			highlight_current = false,
		})
		expect(res).toBeDefined()
		expect(res.total_commits).toBeGreaterThan(0)
		expect(#res.lines).toBeGreaterThan(0)
	end)

	it("lists branches for the filter/legend", function()
		local branches = graph_viewer.get_branch_list(vim.fn.getcwd())
		expect(type(branches)).toBe("table")
		expect(#branches).toBeGreaterThan(0)
		expect(type(branches[1].name)).toBe("string")
	end)

	it("formats commit lines with GitKraken lane highlights and badges", function()
		graph_viewer.setup_highlights()
		local parsed = {
			is_commit = true,
			graph_raw = "*",
			hash = "87a6e94",
			refs = " (HEAD -> main, origin/main)",
			author = "FoxDeveloper",
			date = "25 hours ago",
			subject = "feat: Neo-tree mover",
		}

		local line_text, spans = graph_viewer.format_commit_line(parsed)

		expect(line_text).toContain("●")
		expect(line_text).toContain("87a6e94")
		expect(line_text).toContain("🌿 main")
		expect(line_text).toContain("☁️ main")
		expect(line_text).toContain("feat: Neo-tree mover")
		expect(line_text).toContain("87a6e94  FoxDeveloper  feat: Neo-tree mover")

		-- Spans should contain lane color, SHA hl, and ref badge hl
		expect(#spans).toBeGreaterThan(3)
		local has_lane_hl = false
		local has_sha_hl = false
		local has_head_hl = false
		for _, s in ipairs(spans) do
			if s.hl_group == "FoxGitKrakenLane1" then
				has_lane_hl = true
			elseif s.hl_group == "FoxGitKrakenSha" then
				has_sha_hl = true
			elseif s.hl_group == "FoxGitKrakenBadgeHead" then
				has_head_hl = true
				expect(line_text:sub(s.col_start + 1, s.col_end)).toBe(" 🌿 main ")
			end
		end
		expect(has_lane_hl).toBeTruthy()
		expect(has_sha_hl).toBeTruthy()
		expect(has_head_hl).toBeTruthy()
	end)

	it("aligns log headers and Unicode metadata across graph lanes and ref badges", function()
		local queries = require("plugins.fox.git.git_center.queries")
		local original = queries.git_lines
		queries.git_lines = function()
			return {
				"* abcdef1\x1f (HEAD -> feature/very-long-branch-name-that-must-not-shift-the-message, origin/main)\x1fKristan Ruíz\x1f42 seconds ago\x1ffirst",
				"|\\",
				"| * abcdef2\x1f\x1f李\x1f2 days ago\x1fsecond",
			}
		end
		local ok, result = pcall(graph_viewer.fetch_commits, 10, vim.fn.getcwd(), "all")
		queries.git_lines = original
		assert(ok, result)
		expect(result.lines[1]).toContain("📌 Hash")
		expect(result.lines[1]).toContain("👤 Author")
		expect(result.lines[1]).toContain("🌿 Branches / Tags")
		expect(result.lines[1]).toContain("💬 Subject")
		expect(result.lines[2]).toContain("●")
		expect(result.lines[3]).toContain("│╲")
		expect(result.lines[4]).toContain("│ │")
		expect(result.line_commits[2]).toBe("abcdef1")
		expect(result.line_commits[5]).toBe("abcdef2")
		local function column(row, value)
			local start = assert(result.lines[row]:find(value, 1, true))
			return vim.fn.strdisplaywidth(result.lines[row]:sub(1, start - 1))
		end
		for _, values in ipairs({
			{ "📌 Hash", "abcdef1", "abcdef2" },
			{ "👤 Author", "Kristan Ruíz", "李" },
			{ "💬 Subject", "first", "second" },
		}) do
			expect(column(1, values[1])).toBe(column(2, values[2]))
			expect(column(1, values[1])).toBe(column(5, values[3]))
		end
		local branch_start = assert(result.lines[2]:find("🌿 feature/", 1, true))
		expect(branch_start > assert(result.lines[2]:find("first", 1, true))).toBeTruthy()
		for row, spans in ipairs(result.spans) do
			for _, span in ipairs(spans) do
				expect(span.col_end <= #result.lines[row]).toBeTruthy()
			end
		end
	end)

	it("fetches commits for active repository in branch and all modes", function()
		local cwd = vim.fn.getcwd()
		local branch_res = graph_viewer.fetch_commits(5, cwd, "branch")
		expect(branch_res).toBeDefined()
		expect(branch_res.total_commits).toBeGreaterThan(0)
		expect(#branch_res.lines).toBeGreaterThan(0)

		local all_res = graph_viewer.fetch_commits(5, cwd, "all")
		expect(all_res).toBeDefined()
		expect(all_res.total_commits).toBeGreaterThan(0)
		expect(#all_res.lines).toBeGreaterThan(0)
	end)

	it("renders inferred bases with a separate badge color and exact byte spans", function()
		graph_viewer.setup_highlights()
		local line, spans = graph_viewer.format_commit_line({
			is_commit = true,
			graph_raw = "* ",
			hash = "abcdef1",
			refs = " (main)",
			branch_bases = { "main", "origin/main" },
			subject = "shared ancestor",
		})
		expect(line).toContain("base: main")
		expect(line).toContain("base: origin/main")
		local badges = {}
		for _, span in ipairs(spans) do
			if span.hl_group == "FoxGitKrakenBadgeBase" then
				table.insert(badges, line:sub(span.col_start + 1, span.col_end))
			end
		end
		expect(badges).toEqual({ " base: main ", " base: origin/main " })
		local base = vim.api.nvim_get_hl(0, { name = "FoxGitKrakenBadgeBase" })
		local branch = vim.api.nvim_get_hl(0, { name = "FoxGitKrakenBadgeBranch" })
		expect(base.bg == branch.bg).toBeFalsy()
	end)

	describe("inferred branch bases", function()
		local repo
		local function git(args)
			local cmd = { "git", "-C", repo }
			vim.list_extend(cmd, args)
			local result = vim.system(cmd, { text = true }):wait()
			assert(result.code == 0, result.stderr)
			return vim.trim(result.stdout or "")
		end

		beforeEach(function()
			repo = vim.fn.tempname() .. "_graph"
			vim.fn.mkdir(repo, "p")
			git({ "init", "-b", "main" })
			git({ "config", "user.name", "Graph Test" })
			git({ "config", "user.email", "graph@example.test" })
			git({ "config", "commit.gpgsign", "false" })
		end)

		afterEach(function()
			if repo then
				vim.fn.delete(repo, "rf")
			end
		end)

		it("keeps the end of a long wrapped commit visible with the dollar motion", function()
			git({ "commit", "--allow-empty", "-m", string.rep("long message ñ ", 30) })
			git({ "branch", "feature/" .. string.rep("long-branch-", 10) })
			graph_viewer.open(repo)
			local win = config.graph_win
			local line = vim.api.nvim_buf_get_lines(config.graph_buf, 1, 2, false)[1]
			expect(vim.fn.strdisplaywidth(line) > vim.api.nvim_win_get_width(win)).toBeTruthy()
			vim.cmd("normal! $")
			vim.api.nvim_exec_autocmds("CursorMoved", { buffer = config.graph_buf })
			vim.wait(20)
			vim.cmd("redraw")
			expect(vim.api.nvim_win_get_cursor(win)[2]).toBe(#line - 1)
			local position = vim.fn.screenpos(win, 2, #line)
			expect(position.row > 0).toBeTruthy()
			expect(position.col > 0).toBeTruthy()
		end)

		it("labels moved local and remote branches at their base across pagination", function()
			git({ "commit", "--allow-empty", "-m", "base" })
			local base = git({ "rev-parse", "HEAD" })
			git({ "branch", "feature" })
			git({ "commit", "--allow-empty", "-m", "main advanced" })
			git({ "update-ref", "refs/remotes/origin/main", "HEAD" })
			git({ "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/main" })
			git({ "checkout", "feature" })
			git({ "commit", "--allow-empty", "-m", "feature one" })
			git({ "branch", "tracking" })
			git({ "branch", "--set-upstream-to=tracking" })
			git({ "commit", "--allow-empty", "-m", "feature two" })
			git({ "branch", "alias" })
			git({ "checkout", "-b", "child" })
			git({ "commit", "--allow-empty", "-m", "child commit" })
			git({ "checkout", "--orphan", "unrelated" })
			git({ "commit", "--allow-empty", "-m", "unrelated root" })
			git({ "checkout", "feature" })

			local first = graph_viewer.fetch_commits(1, repo, "branch")
			expect(first.commits[1].branch_bases).toBeNil()
			expect(first.branch_bases[base]).toEqual({ "main", "origin/main" })
			local full = graph_viewer.fetch_commits(20, repo, "branch", { branch_bases = first.branch_bases })
			expect(full.total_commits).toBe(3)
			expect(full.commits[2].branch_bases).toBeNil()
			expect(full.commits[3].full_hash).toBe(base)
			expect(full.commits[3].branch_bases).toEqual({ "main", "origin/main" })
			local all = graph_viewer.fetch_commits(20, repo, "all")
			for _, commit in ipairs(all.commits) do
				expect(commit.branch_bases).toBeNil()
			end
		end)
	end)

	it("registers :GitGraph and :GitCenterGraph user commands", function()
		git_center.setup()
		local commands = vim.api.nvim_get_commands({})
		expect(commands.GitGraph).toBeDefined()
		expect(commands.GitCenterGraph).toBeDefined()
	end)

	it("opens a full-width graph and preserves selection through split and expanded details", function()
		graph_viewer.open()

		expect(config.graph_win).toBeDefined()
		expect(config.graph_buf).toBeDefined()
		expect(config.graph_right_win).toBeDefined()
		expect(config.graph_right_buf).toBeDefined()

		expect(vim.api.nvim_win_is_valid(config.graph_win)).toBeTruthy()
		expect(vim.api.nvim_win_is_valid(config.graph_right_win)).toBeTruthy()
		expect(vim.api.nvim_win_get_config(config.graph_right_win).hide).toBeTruthy()
		expect(vim.wo[config.graph_win].wrap).toBeTruthy()
		expect(vim.wo[config.graph_win].linebreak).toBeTruthy()
		local cursor = vim.api.nvim_win_get_cursor(config.graph_win)
		expect(cursor[1]).toBe(2)
		local function press(buf, key)
			local map = vim.api.nvim_buf_call(buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			map.callback()
		end
		press(config.graph_buf, "<Tab>")
		expect(vim.api.nvim_get_current_win()).toBe(config.graph_right_win)
		local base = vim.api.nvim_win_get_config(config.graph_win)
		local popup = vim.api.nvim_win_get_config(config.graph_right_win)
		expect(popup.width).toBe(base.width)
		expect(popup.height).toBe(base.height)
		expect(popup.row).toBe(base.row)
		expect(popup.col).toBe(base.col)
		expect(popup.zindex > base.zindex).toBeTruthy()
		press(config.graph_right_buf, "<Tab>")
		expect(vim.api.nvim_get_current_win()).toBe(config.graph_right_win)
		press(config.graph_right_buf, "<S-Tab>")
		expect(vim.api.nvim_win_get_config(config.graph_right_win).hide).toBeTruthy()
		expect(vim.api.nvim_get_current_win()).toBe(config.graph_win)
		press(config.graph_buf, "<Tab>")
		expect(vim.api.nvim_win_get_config(config.graph_right_win).hide).toBeFalsy()
		config.graph_layout.hide_preview()
		config.graph_layout.toggle_preview()
		config.graph_layout.expand()
		expect(vim.api.nvim_get_current_win()).toBe(config.graph_right_win)
		expect(vim.api.nvim_win_get_config(config.graph_win).hide).toBeFalsy()
		local esc = vim.api.nvim_buf_call(config.graph_right_buf, function()
			return vim.fn.maparg("<Esc>", "n", false, true)
		end)
		esc.callback()
		expect(vim.api.nvim_get_current_win()).toBe(config.graph_win)
		expect(vim.api.nvim_win_get_cursor(config.graph_win)).toEqual(cursor)
		expect(vim.api.nvim_win_get_config(config.graph_win).hide).toBeFalsy()

		-- Verify title contains GitKraken Graph and Mode
		local win_cfg = vim.api.nvim_win_get_config(config.graph_win)
		local title_str = type(win_cfg.title) == "string" and win_cfg.title
			or (type(win_cfg.title) == "table" and win_cfg.title[1] and win_cfg.title[1][1] or "")
		expect(title_str).toContain("GitKraken Graph")
		expect(title_str).toContain("[b]: Select branches")
		expect(title_str).toContain("[?]: Help")
		local footer = win_cfg.footer[1][1]
		expect(footer).toContain("[Space]: Files")
		expect(footer).toContain("[Enter]: Diff")

		-- Buffer should be unmodifiable nofile
		expect(vim.bo[config.graph_buf].buftype).toBe("nofile")
		expect(vim.bo[config.graph_buf].modifiable).toBeFalsy()

		-- Close using q
		pcall(vim.api.nvim_win_close, config.graph_win, true)
		pcall(vim.api.nvim_win_close, config.graph_right_win, true)
	end)

	it("returns to Git Center with Shift+Tab from the graph after dismissing details", function()
		git_center.open_git_center()
		graph_viewer.open()
		local function press(buf, key)
			local map = vim.api.nvim_buf_call(buf, function()
				return vim.fn.maparg(key, "n", false, true)
			end)
			map.callback()
		end
		press(config.graph_buf, "<Tab>")
		press(config.graph_right_buf, "<S-Tab>")
		expect(vim.api.nvim_win_is_valid(config.graph_win)).toBeTruthy()
		press(config.graph_buf, "<S-Tab>")
		expect(config.graph_win).toBeNil()
		expect(config.graph_right_win).toBeNil()
		expect(vim.api.nvim_get_current_win()).toBe(config.main_win)
	end)

	it("formats changed-file status and counts, including binary files and renames", function()
		local output = table.concat({
			":100644 100644 abc def M\tfile.lua",
			":100644 000000 abc 000 D\told.lua",
			":100644 100644 abc def R100\tdir/old.lua\tdir/new.lua",
			":000000 100644 000 def A\timage.png",
			"3\t2\tfile.lua",
			"0\t4\told.lua",
			"0\t0\tdir/{old.lua => new.lua}",
			"-\t-\timage.png",
		}, "\n")
		local lines = graph_viewer.format_file_peek(output)
		expect(lines[1]).toContain("[M]  +3 -2  file.lua")
		expect(lines[2]).toContain("[D]  +0 -4  old.lua")
		expect(lines[3]).toContain("[R100]")
		expect(lines[4]).toContain("[A]  binary  image.png")
	end)

	it("peeks files asynchronously and reuses the cached result without loading patches", function()
		graph_viewer.open()
		local queries = require("plugins.fox.git.git_center.queries")
		local original = queries.git_run
		local calls = 0
		queries.git_run = function(args, done)
			calls = calls + 1
			expect(args).toContain("--numstat")
			expect(args).toContain("--raw")
			done(true, ":000000 100644 000 abc A\tnew.lua\n1\t0\tnew.lua")
		end
		local ok, err = pcall(function()
			config.graph_peek()
			local peek = vim.api.nvim_get_current_win()
			expect(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(peek), 0, -1, false)[1]).toContain("new.lua")
			vim.api.nvim_win_close(peek, true)
			config.graph_peek()
			expect(calls).toBe(1)
			vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
		end)
		queries.git_run = original
		if not ok then
			error(err)
		end
	end)
end)
