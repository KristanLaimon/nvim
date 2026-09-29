-- ============================================================================
-- FOX PLUGIN: Git Log Diff Dashboard
-- ============================================================================
-- WHAT IT PROVIDES
--   A full-screen tiled 4-panel dashboard for inspecting Git commit history diffs:
--     1. Files Changed List (Top-Left):
--        Files modified in the currently selected commit with status badges.
--     2. Commit Logs List (Bottom-Left):
--        Commits ordered newest to oldest with SHA, badges, author, and relative date.
--        Switch branch with [b], toggle --all with [a].
--     3. Before Code (Middle):
--        File content before the commit (commit~1 or parent) with diff syntax highlighting.
--     4. After Code (Right):
--        File content after the commit with diff syntax highlighting and synchronized scrolling.
--
-- PANEL NAVIGATION SHORTCUTS
--   <C-h>       Jump to Left column (Files or Logs)
--   <C-l>       Jump to Right column (After Code)
--   <C-k>       Jump Up (Logs -> Files) or scroll up
--   <C-j>       Jump Down (Files -> Logs) or scroll down
--   <Tab>       Cycle forward across panels (Files -> Logs -> Before -> After)
--   <S-Tab>     Cycle backward across panels
--   f / l / b / a Direct panel focus shortcuts
--   ]c / ]d     Jump to next diff change / hunk
--   [c / [d     Jump to previous diff change / hunk
--   y           Yank commit SHA to clipboard
--   K           Checkout selected commit
--   ? / <F1>    Show keymap reference popup
--   q / <Esc>   Close dashboard and return to previous workspace / Git Center
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local git = lazy_req("fox.git.cmd")
local diff = lazy_req("fox.git.diff")
local ui = lazy_req("fox.core.ui")
local project = lazy_req("fox.core.project")
local store = lazy_req("fox.core.store")
local path_util = lazy_req("fox.core.path")

local M = {}

M.ns_files = vim.api.nvim_create_namespace("fox_git_log_diff_files")
M.ns_logs = vim.api.nvim_create_namespace("fox_git_log_diff_logs")
M.ns_diff = vim.api.nvim_create_namespace("fox_git_log_diff_content")

M.GLOBAL_CONFIG_FILE = vim.fn.stdpath("data") .. "/fox_git_log_diff.json"

M.settings = {
	left_ratio = 0.28,
	top_ratio = 0.40,
	notify_title = "Git Log Diff",
}

M.state = {
	is_open = false,
	cwd = nil,
	tab = nil,
	prev_win = nil,
	prev_tab = nil,
	mode = "branch", -- "branch" | "all"
	branch = "HEAD",
	current_branch = "HEAD",
	commits = {},
	active_commit_idx = 1,
	active_commit_hash = nil,
	files = {},
	active_file_idx = 1,
	active_file = nil,
	last_left_win = nil,
	last_right_win = nil,
	files_win = nil,
	files_buf = nil,
	logs_win = nil,
	logs_buf = nil,
	before_win = nil,
	before_buf = nil,
	after_win = nil,
	after_buf = nil,
	left_ratio = 0.28,
	top_ratio = 0.40,
	line_to_commit_idx = {},
	commit_idx_to_line = {},
	line_to_file_idx = {},
}

local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

--- Resolves the per-project `.foxnvim/git_log_diff.json` persistence path.
--- @param cwd string|nil
--- @return string
function M.get_session_path(cwd)
	cwd = cwd or M.state.cwd or vim.fn.getcwd()
	local root = project.root() or cwd
	if project.config_path then
		return project.config_path("git_log_diff.json", root)
	end
	return root .. "/.foxnvim/git_log_diff.json"
end

--- Loads saved dashboard state from global nvim-data and project `.foxnvim/git_log_diff.json`.
--- @param cwd string|nil
--- @return table
function M.load_session(cwd)
	local global_data = store.load(M.GLOBAL_CONFIG_FILE, {})
	local path = M.get_session_path(cwd)
	local project_data = store.load(path, nil)
	local merged = {}
	if type(global_data) == "table" then
		for k, v in pairs(global_data) do
			merged[k] = v
		end
	end
	if type(project_data) == "table" then
		for k, v in pairs(project_data) do
			merged[k] = v
		end
	end
	return merged
end

local save_timer = nil
--- Saves dashboard state to `.foxnvim/git_log_diff.json` and global `nvim-data` (debounced).
function M.save_session()
	if not M.state.is_open or not M.state.cwd then
		return
	end
	if save_timer then
		save_timer:stop()
		save_timer:close()
		save_timer = nil
	end
	local uv = vim.uv or vim.loop
	save_timer = uv.new_timer()
	if save_timer then
		save_timer:start(
			300,
			0,
			vim.schedule_wrap(function()
				if save_timer then
					save_timer:stop()
					save_timer:close()
					save_timer = nil
				end
				if not M.state.is_open or not M.state.cwd then
					return
				end
				local path = M.get_session_path(M.state.cwd)
				local data = {
					cwd = M.state.cwd,
					commit = M.state.active_commit_hash,
					mode = M.state.mode,
					branch = M.state.branch,
					file = M.state.active_file,
					left_ratio = M.state.left_ratio,
					top_ratio = M.state.top_ratio,
					timestamp = os.time(),
				}
				store.save(path, data)
				store.save(M.GLOBAL_CONFIG_FILE, {
					left_ratio = M.state.left_ratio,
					top_ratio = M.state.top_ratio,
					mode = M.state.mode,
				})
			end)
		)
	end
end

--- Resizes the left column width narrower or wider and persists globally.
--- @param delta integer Column offset (e.g. -2 or +2)
function M.resize_left(delta)
	if not M.state.is_open then
		return
	end
	local total_w = vim.o.columns or 80
	local cur_w = math.floor(total_w * (M.state.left_ratio or M.settings.left_ratio))
	local new_w = math.max(22, math.min(total_w - 30, cur_w + delta))
	M.state.left_ratio = new_w / total_w
	if M.state.files_win and vim.api.nvim_win_is_valid(M.state.files_win) then
		pcall(vim.api.nvim_win_set_width, M.state.files_win, new_w)
	end
	if M.state.logs_win and vim.api.nvim_win_is_valid(M.state.logs_win) then
		pcall(vim.api.nvim_win_set_width, M.state.logs_win, new_w)
	end
	M.save_session()
end

--- Resizes the top Files section height smaller or larger.
--- @param delta integer Row offset (e.g. -1 or +1)
function M.resize_top(delta)
	if not M.state.is_open then
		return
	end
	local total_h = vim.o.lines or 24
	local cur_h = math.floor(total_h * (M.state.top_ratio or M.settings.top_ratio))
	local new_h = math.max(4, math.min(total_h - 6, cur_h + delta))
	M.state.top_ratio = new_h / total_h
	if M.state.files_win and vim.api.nvim_win_is_valid(M.state.files_win) then
		pcall(vim.api.nvim_win_set_height, M.state.files_win, new_h)
	end
	M.save_session()
end

--- Setup highlight groups.
function M.setup_highlights()
	diff.setup_highlights()
	vim.api.nvim_set_hl(0, "FoxLogDiffActiveItem", { fg = "#89dceb", bg = "#1e293b", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffSha", { fg = "#eed49f", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffAuthor", { fg = "#89dceb", default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffDate", { fg = "#a6adc8", default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffSubject", { fg = "#cdd6f4", default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffHeader", { fg = "#89dceb", bg = "#181825", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffStatusM", { fg = "#89dceb", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffStatusA", { fg = "#a6e3a1", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffStatusD", { fg = "#f38ba8", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffStatusR", { fg = "#fab387", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffBadgeBranch", { fg = "#11111b", bg = "#cba6f7", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffBadgeHead", { fg = "#11111b", bg = "#a6e3a1", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffBadgeTag", { fg = "#11111b", bg = "#f9e2af", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxLogDiffBadgeRemote", { fg = "#11111b", bg = "#89b4fa", bold = true, default = true })
end

--- Returns true if the Git Log Diff Dashboard is open.
--- @return boolean
function M.is_open()
	return M.state.is_open
		and M.state.files_win ~= nil
		and pcall(vim.api.nvim_win_is_valid, M.state.files_win)
		and vim.api.nvim_win_is_valid(M.state.files_win)
end

--- Parses ref decoration string into badges.
--- @param refs_str string|nil
--- @return table[] badges
local function parse_refs(refs_str)
	if not refs_str or refs_str == "" then
		return {}
	end
	local clean = refs_str:gsub("^%s*%(?", ""):gsub("%)?%s*$", "")
	if clean == "" then
		return {}
	end

	local items = vim.split(clean, ", ", { plain = true })
	local badges = {}
	for _, item in ipairs(items) do
		item = item:gsub("^%s*", ""):gsub("%s*$", "")
		if item ~= "" and item ~= "origin/HEAD" then
			if item:match("^HEAD %-> (.+)$") then
				local b = item:match("^HEAD %-> (.+)$")
				table.insert(badges, { text = "🌿 " .. b, hl = "FoxLogDiffBadgeHead" })
			elseif item:match("^tag:%s*(.+)$") then
				local t = item:match("^tag:%s*(.+)$")
				table.insert(badges, { text = "🏷️ " .. t, hl = "FoxLogDiffBadgeTag" })
			elseif item:match("^remotes/origin/(.+)$") or item:match("^origin/(.+)$") then
				local r = item:gsub("^remotes/origin/", ""):gsub("^origin/", "")
				table.insert(badges, { text = "☁️ " .. r, hl = "FoxLogDiffBadgeRemote" })
			else
				table.insert(badges, { text = "🌲 " .. item, hl = "FoxLogDiffBadgeBranch" })
			end
		end
	end
	return badges
end

--- Fetches commit history list from Git.
--- @param cwd string
--- @param mode "branch"|"all"
--- @param branch string|nil
--- @param limit integer|nil
--- @return table[] commits
function M.fetch_commits(cwd, mode, branch, limit)
	limit = limit or 120
	local cmd = {
		"log",
		"--pretty=format:%H%x1f%h%x1f%an%x1f%cr%x1f%s%x1f%d",
		"-n",
		tostring(limit),
	}
	if mode == "all" then
		table.insert(cmd, 2, "--all")
	elseif branch and branch ~= "" and branch ~= "HEAD" then
		table.insert(cmd, branch)
	else
		table.insert(cmd, "HEAD")
	end

	local raw_lines = git.lines(cmd, cwd)
	local commits = {}
	for _, line in ipairs(raw_lines) do
		local parts = vim.split(line, "\x1f", { plain = true })
		if #parts >= 5 then
			table.insert(commits, {
				full_hash = parts[1] or "",
				hash = parts[2] or (parts[1] and parts[1]:sub(1, 7)) or "",
				author = parts[3] or "",
				rel_date = parts[4] or "",
				subject = parts[5] or "",
				refs = parts[6] or "",
			})
		end
	end
	return commits
end

--- Fetches changed files list for a specific commit.
--- @param cwd string
--- @param commit_hash string
--- @return table[] files
function M.fetch_commit_files(cwd, commit_hash)
	if not commit_hash or commit_hash == "" then
		return {}
	end
	local raw_lines = git.lines({ "show", "--name-status", "--pretty=format:", commit_hash }, cwd)
	local files = {}
	for _, line in ipairs(raw_lines) do
		line = vim.trim(line)
		if line ~= "" then
			local status_char, filepath = line:match("^([A-Z%d]+)%s+(.+)$")
			if status_char and filepath then
				local s = status_char:sub(1, 1)
				local old_file = nil
				if s == "R" or s == "C" then
					local p1, p2 = filepath:match("^([^\t]+)\t(.+)$")
					if p1 and p2 then
						old_file = p1
						filepath = p2
					end
				end
				table.insert(files, {
					status = s,
					filepath = filepath,
					old_filepath = old_file,
				})
			end
		end
	end
	return files
end

--- Fetches side-by-side diff data for a specific file in a commit.
--- @param cwd string
--- @param commit_hash string
--- @param filepath string
--- @param status string|nil
--- @return string[] left_lines
--- @return string[] left_kinds
--- @return string[] right_lines
--- @return string[] right_kinds
function M.fetch_file_diff(cwd, commit_hash, filepath, status)
	if not filepath or filepath == "" or not commit_hash then
		return { " [No file selected] " }, { "context" }, { " [No file selected] " }, { "context" }
	end

	local raw_diff = git.lines({ "show", "--format=", "--color=never", commit_hash, "--", filepath }, cwd)

	if #raw_diff == 0 then
		-- Try diff against parent explicitly
		raw_diff = git.lines({ "diff", "--color=never", commit_hash .. "~1", commit_hash, "--", filepath }, cwd)
	end

	if #raw_diff == 0 then
		-- File might be newly added or initial commit
		local after_content = git.lines({ "show", commit_hash .. ":" .. filepath }, cwd)
		if #after_content > 0 then
			local l_lines, l_kinds, r_lines, r_kinds = {}, {}, {}, {}
			table.insert(
				l_lines,
				" ─── 📄 Before: (File did not exist) ──────────────────────────"
			)
			table.insert(l_kinds, "header")
			table.insert(
				r_lines,
				string.format(
					" ─── 📄 After: %s (Created) ──────────────────────────",
					filepath
				)
			)
			table.insert(r_kinds, "header")
			for _, line in ipairs(after_content) do
				table.insert(l_lines, "")
				table.insert(l_kinds, "filler")
				table.insert(r_lines, "+ " .. line)
				table.insert(r_kinds, "add")
			end
			return l_lines, l_kinds, r_lines, r_kinds
		end
	end

	local is_untracked = status == "A" or status == "?"
	local left_lines, left_kinds, right_lines, right_kinds =
		diff.format_side_by_side_dual(raw_diff, is_untracked, filepath)
	return left_lines, left_kinds, right_lines, right_kinds
end

--- Sets filetype syntax highlighting on a buffer based on filepath.
--- @param buf integer
--- @param filepath string
local function apply_filetype(buf, filepath)
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not filepath then
		return
	end
	local ft = vim.filetype.match({ filename = filepath })
	if ft and ft ~= "" then
		pcall(function()
			vim.bo[buf].filetype = ft
		end)
	else
		vim.bo[buf].filetype = ""
	end
end

--- Renders the Files Changed list in the Top-Left pane.
function M.render_files_list()
	local buf = M.state.files_buf
	local win = M.state.files_win
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local lines = {}
	local spans = {}
	M.state.line_to_file_idx = {}

	table.insert(lines, string.format(" 📁 Files Changed in Commit (%d)", #M.state.files))
	table.insert(spans, { col_start = 0, col_end = -1, hl = "FoxLogDiffHeader" })

	table.insert(
		lines,
		" ──────────────────────────────────────────────────────────"
	)
	table.insert(spans, { col_start = 0, col_end = -1, hl = "GitCenterDiffFiller" })

	if #M.state.files == 0 then
		table.insert(lines, "   (no files changed in this commit)")
		table.insert(spans, { col_start = 0, col_end = -1, hl = "FoxGitKrakenDim" })
	else
		for idx, item in ipairs(M.state.files) do
			local is_active = idx == M.state.active_file_idx
			local prefix = is_active and " ▶ " or "   "
			local status_hl = "FoxLogDiffStatusM"
			if item.status == "A" then
				status_hl = "FoxLogDiffStatusA"
			elseif item.status == "D" then
				status_hl = "FoxLogDiffStatusD"
			elseif item.status == "R" then
				status_hl = "FoxLogDiffStatusR"
			end

			local line_text = string.format("%s[%s] %s", prefix, item.status, item.filepath)
			local line_row = #lines + 1
			table.insert(lines, line_text)
			M.state.line_to_file_idx[line_row] = idx

			local row_spans = {}
			if is_active then
				table.insert(row_spans, { col_start = 0, col_end = -1, hl = "FoxLogDiffActiveItem" })
			end
			local status_start = #prefix
			local status_end = status_start + 3
			table.insert(row_spans, { col_start = status_start, col_end = status_end, hl = status_hl })
			table.insert(spans, row_spans)
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, M.ns_files, 0, -1)
	for r_idx, span_list in ipairs(spans) do
		if span_list.hl then
			pcall(
				vim.api.nvim_buf_add_highlight,
				buf,
				M.ns_files,
				span_list.hl,
				r_idx - 1,
				span_list.col_start or 0,
				span_list.col_end or -1
			)
		elseif type(span_list) == "table" then
			for _, s in ipairs(span_list) do
				pcall(vim.api.nvim_buf_add_highlight, buf, M.ns_files, s.hl, r_idx - 1, s.col_start or 0, s.col_end or -1)
			end
		end
	end

	if win and vim.api.nvim_win_is_valid(win) then
		local cur_commit = M.state.commits[M.state.active_commit_idx]
		local sha_str = cur_commit and cur_commit.hash or "none"
		vim.api.nvim_win_set_config(win, {
			title = string.format(" 📁 Files (%d) │ Commit: %s │ [Tab]: Focus ", #M.state.files, sha_str),
			title_pos = "center",
		})
	end
end

--- Renders the Commit Logs list in the Bottom-Left pane.
function M.render_logs_list()
	local buf = M.state.logs_buf
	local win = M.state.logs_win
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local lines = {}
	local spans = {}
	M.state.line_to_commit_idx = {}
	M.state.commit_idx_to_line = {}

	local total_commits = #M.state.commits
	local active_idx = M.state.active_commit_idx or 1
	local newer_count = active_idx - 1
	local older_count = total_commits - active_idx

	local mode_label = M.state.mode == "all" and "🌐 All Branches (--all)"
		or string.format("🌿 Branch: %s", M.state.branch)
	table.insert(lines, string.format(" 📜 Commit History │ %s", mode_label))
	table.insert(spans, { { col_start = 0, col_end = -1, hl = "FoxLogDiffHeader" } })

	table.insert(
		lines,
		" ──────────────────────────────────────────────────────────"
	)
	table.insert(spans, { { col_start = 0, col_end = -1, hl = "GitCenterDiffFiller" } })

	if total_commits == 0 then
		table.insert(lines, "   (no commits found)")
		table.insert(spans, { { col_start = 0, col_end = -1, hl = "FoxGitKrakenDim" } })
	else
		-- Top edge indicator: if there are newer commits above
		if newer_count > 0 then
			local top_text =
				string.format("   ▲ (%d newer commit%s left above)", newer_count, newer_count == 1 and "" or "s")
			table.insert(lines, top_text)
			table.insert(spans, { { col_start = 0, col_end = -1, hl = "FoxLogDiffBadgeHead" } })
			table.insert(lines, "   │")
			table.insert(spans, { { col_start = 0, col_end = -1, hl = "GitCenterDiffFiller" } })
		end

		for idx, commit in ipairs(M.state.commits) do
			local is_active = idx == active_idx
			local prefix = is_active and " ▶ " or "   "
			local bullet = "● "

			-- Add subtle gap connector line between commits for breathing room
			if idx > 1 then
				table.insert(lines, "   │")
				table.insert(spans, { { col_start = 0, col_end = -1, hl = "GitCenterDiffFiller" } })
			end

			local line_text = prefix .. bullet .. commit.hash .. " "
			local row_spans = {}
			local cur_byte = #line_text

			if is_active then
				table.insert(row_spans, { col_start = 0, col_end = -1, hl = "FoxLogDiffActiveItem" })
			end
			table.insert(row_spans, { col_start = #prefix + #bullet, col_end = #line_text - 1, hl = "FoxLogDiffSha" })

			local badges = parse_refs(commit.refs)
			for _, badge in ipairs(badges) do
				local badge_str = badge.text .. " "
				table.insert(row_spans, { col_start = cur_byte, col_end = cur_byte + #badge_str, hl = badge.hl })
				line_text = line_text .. badge_str
				cur_byte = cur_byte + #badge_str
			end

			local subject_str = commit.subject ~= "" and commit.subject or "(no message)"
			table.insert(row_spans, { col_start = cur_byte, col_end = cur_byte + #subject_str, hl = "FoxLogDiffSubject" })
			line_text = line_text .. subject_str
			cur_byte = cur_byte + #subject_str

			if commit.author ~= "" then
				local author_str = " 👤 " .. commit.author
				table.insert(row_spans, { col_start = cur_byte, col_end = cur_byte + #author_str, hl = "FoxLogDiffAuthor" })
				line_text = line_text .. author_str
				cur_byte = cur_byte + #author_str
			end

			if commit.rel_date ~= "" then
				local date_str = " (" .. commit.rel_date .. ")"
				table.insert(row_spans, { col_start = cur_byte, col_end = cur_byte + #date_str, hl = "FoxLogDiffDate" })
				line_text = line_text .. date_str
			end

			local line_row = #lines + 1
			table.insert(lines, line_text)
			M.state.line_to_commit_idx[line_row] = idx
			M.state.commit_idx_to_line[idx] = line_row
			table.insert(spans, row_spans)
		end

		-- Bottom edge indicator: if there are older commits below
		if older_count > 0 then
			table.insert(lines, "   │")
			table.insert(spans, { { col_start = 0, col_end = -1, hl = "GitCenterDiffFiller" } })
			local bottom_text =
				string.format("   ▼ (%d older commit%s left below)", older_count, older_count == 1 and "" or "s")
			table.insert(lines, bottom_text)
			table.insert(spans, { { col_start = 0, col_end = -1, hl = "FoxLogDiffBadgeBranch" } })
		end
	end

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_clear_namespace(buf, M.ns_logs, 0, -1)
	for r_idx, span_list in ipairs(spans) do
		for _, s in ipairs(span_list) do
			pcall(vim.api.nvim_buf_add_highlight, buf, M.ns_logs, s.hl, r_idx - 1, s.col_start or 0, s.col_end or -1)
		end
	end

	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_set_config(win, {
			title = string.format(" 📜 Commits (%d) │ [a]: Toggle --all │ [b]: Branch ", total_commits),
			title_pos = "center",
		})
	end
end

--- Renders the Before Code and After Code diff panes.
function M.render_diff_panes()
	local before_buf = M.state.before_buf
	local before_win = M.state.before_win
	local after_buf = M.state.after_buf
	local after_win = M.state.after_win

	if not before_buf or not vim.api.nvim_buf_is_valid(before_buf) then
		return
	end
	if not after_buf or not vim.api.nvim_buf_is_valid(after_buf) then
		return
	end

	local commit = M.state.commits[M.state.active_commit_idx]
	local file_item = M.state.files[M.state.active_file_idx]

	if not commit or not file_item then
		local empty_lines = { "   [No commit or file selected] " }
		vim.bo[before_buf].modifiable = true
		vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, empty_lines)
		vim.bo[before_buf].modifiable = false

		vim.bo[after_buf].modifiable = true
		vim.api.nvim_buf_set_lines(after_buf, 0, -1, false, empty_lines)
		vim.bo[after_buf].modifiable = false
		return
	end

	local l_lines, l_kinds, r_lines, r_kinds =
		M.fetch_file_diff(M.state.cwd, commit.full_hash, file_item.filepath, file_item.status)

	vim.bo[before_buf].modifiable = true
	vim.api.nvim_buf_set_lines(before_buf, 0, -1, false, l_lines)
	vim.bo[before_buf].modifiable = false

	vim.bo[after_buf].modifiable = true
	vim.api.nvim_buf_set_lines(after_buf, 0, -1, false, r_lines)
	vim.bo[after_buf].modifiable = false

	apply_filetype(before_buf, file_item.filepath)
	apply_filetype(after_buf, file_item.filepath)

	for _, w in ipairs({ before_win, after_win }) do
		if w and vim.api.nvim_win_is_valid(w) then
			vim.wo[w].wrap = true
			vim.wo[w].linebreak = true
			vim.wo[w].breakindent = true
			vim.wo[w].scrollbind = true
		end
	end

	diff.apply_highlights_side_by_side_dual(before_buf, l_kinds, after_buf, r_kinds, file_item.filepath)

	-- Collect hunk indices for ]c / [c navigation
	M.state.hunks = {}
	for idx, kind in ipairs(r_kinds) do
		if kind == "add" or kind == "header" or (l_kinds[idx] == "delete") then
			if #M.state.hunks == 0 or (idx - M.state.hunks[#M.state.hunks]) > 3 then
				table.insert(M.state.hunks, idx)
			end
		end
	end
	M.state.current_hunk_idx = 1

	if before_win and vim.api.nvim_win_is_valid(before_win) then
		vim.api.nvim_win_set_config(before_win, {
			title = string.format(" ◀ Before Code (%s~1) │ %s ", commit.hash, file_item.filepath),
			title_pos = "center",
		})
	end
	if after_win and vim.api.nvim_win_is_valid(after_win) then
		vim.api.nvim_win_set_config(after_win, {
			title = string.format(" ▶ After Code (%s) │ %s ", commit.hash, file_item.filepath),
			title_pos = "center",
		})
	end
end

--- Selects a commit by index or hash and refreshes files and diffs.
--- Keeps the selected commit centered in the vertical Y-axis.
--- @param target integer|string
function M.select_commit(target)
	local target_idx = 1
	if type(target) == "number" then
		target_idx = math.max(1, math.min(target, #M.state.commits))
	elseif type(target) == "string" then
		for idx, c in ipairs(M.state.commits) do
			if c.full_hash:find("^" .. target) or c.hash == target then
				target_idx = idx
				break
			end
		end
	end

	M.state.active_commit_idx = target_idx
	local cur_commit = M.state.commits[target_idx]
	if cur_commit then
		M.state.active_commit_hash = cur_commit.full_hash
		M.state.files = M.fetch_commit_files(M.state.cwd, cur_commit.full_hash)
		M.state.active_file_idx = 1
		local cur_file = M.state.files[1]
		M.state.active_file = cur_file and cur_file.filepath or nil
	else
		M.state.files = {}
		M.state.active_file = nil
	end

	M.render_files_list()
	M.render_logs_list()
	M.render_diff_panes()

	-- Center the selected commit in the vertical Y-axis in logs_win
	local logs_win = M.state.logs_win
	local target_line = M.state.commit_idx_to_line and M.state.commit_idx_to_line[target_idx]
	if logs_win and vim.api.nvim_win_is_valid(logs_win) and target_line then
		pcall(vim.api.nvim_win_set_cursor, logs_win, { target_line, 0 })
		pcall(vim.api.nvim_win_call, logs_win, function()
			vim.cmd("normal! zz")
		end)
	end

	M.save_session()
end

--- Move chronologically to the next older commit (downwards in list).
function M.next_older_commit()
	if not M.state.commits or #M.state.commits == 0 then
		return
	end
	local next_idx = math.min(#M.state.commits, (M.state.active_commit_idx or 1) + 1)
	if next_idx ~= M.state.active_commit_idx then
		M.select_commit(next_idx)
	end
end

--- Move chronologically to the next newer commit (upwards in list).
function M.next_newer_commit()
	if not M.state.commits or #M.state.commits == 0 then
		return
	end
	local prev_idx = math.max(1, (M.state.active_commit_idx or 1) - 1)
	if prev_idx ~= M.state.active_commit_idx then
		M.select_commit(prev_idx)
	end
end

--- Selects a file by index or filepath and refreshes diff panes.
--- @param target integer|string
function M.select_file(target)
	local target_idx = 1
	if type(target) == "number" then
		target_idx = math.max(1, math.min(target, #M.state.files))
	elseif type(target) == "string" then
		for idx, f in ipairs(M.state.files) do
			if f.filepath == target then
				target_idx = idx
				break
			end
		end
	end

	M.state.active_file_idx = target_idx
	local cur_file = M.state.files[target_idx]
	M.state.active_file = cur_file and cur_file.filepath or nil

	M.render_files_list()
	M.render_diff_panes()
	M.save_session()
end

--- Toggles between current branch and --all modes.
function M.toggle_mode()
	M.state.mode = M.state.mode == "all" and "branch" or "all"
	M.state.commits = M.fetch_commits(M.state.cwd, M.state.mode, M.state.branch)
	M.select_commit(1)
	notify(
		string.format("Switched mode to %s", M.state.mode == "all" and "🌐 All Branches (--all)" or "🌿 Current Branch")
	)
end

--- Prompts to select and switch branch in dashboard view.
function M.select_branch()
	local raw_branches = git.lines({ "branch", "--sort=-committerdate" }, M.state.cwd)
	local branch_names = {}
	for _, line in ipairs(raw_branches) do
		local name = line:gsub("^%*%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
		if name ~= "" and not name:match("HEAD detached") then
			table.insert(branch_names, name)
		end
	end

	if #branch_names == 0 then
		notify("No local branches available", vim.log.levels.WARN)
		return
	end

	vim.ui.select(branch_names, { prompt = "Select Branch to Inspect:" }, function(choice)
		if choice and choice ~= "" then
			M.state.branch = choice
			M.state.mode = "branch"
			M.state.commits = M.fetch_commits(M.state.cwd, "branch", choice)
			M.select_commit(1)
			notify(string.format("Inspecting branch: %s", choice))
		end
	end)
end

--- Jump to next diff hunk.
function M.jump_next_hunk()
	if #M.state.hunks == 0 then
		return
	end
	M.state.current_hunk_idx = M.state.current_hunk_idx + 1
	if M.state.current_hunk_idx > #M.state.hunks then
		M.state.current_hunk_idx = 1
	end
	local line = M.state.hunks[M.state.current_hunk_idx]
	if line then
		for _, win in ipairs({ M.state.before_win, M.state.after_win }) do
			if win and vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
			end
		end
	end
end

--- Jump to previous diff hunk.
function M.jump_prev_hunk()
	if #M.state.hunks == 0 then
		return
	end
	M.state.current_hunk_idx = M.state.current_hunk_idx - 1
	if M.state.current_hunk_idx < 1 then
		M.state.current_hunk_idx = #M.state.hunks
	end
	local line = M.state.hunks[M.state.current_hunk_idx]
	if line then
		for _, win in ipairs({ M.state.before_win, M.state.after_win }) do
			if win and vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
			end
		end
	end
end

--- Focus navigation helpers.
function M.focus_files()
	if M.state.files_win and vim.api.nvim_win_is_valid(M.state.files_win) then
		M.state.last_left_win = M.state.files_win
		vim.api.nvim_set_current_win(M.state.files_win)
	end
end

function M.focus_logs()
	if M.state.logs_win and vim.api.nvim_win_is_valid(M.state.logs_win) then
		M.state.last_left_win = M.state.logs_win
		vim.api.nvim_set_current_win(M.state.logs_win)
	end
end

function M.focus_left()
	local cur = vim.api.nvim_get_current_win()
	if cur == M.state.after_win then
		M.focus_before()
	elseif cur == M.state.before_win then
		local target = M.state.last_left_win or M.state.files_win
		if target and vim.api.nvim_win_is_valid(target) then
			vim.api.nvim_set_current_win(target)
		else
			M.focus_files()
		end
	else
		M.focus_files()
	end
end

function M.focus_before()
	if M.state.before_win and vim.api.nvim_win_is_valid(M.state.before_win) then
		M.state.last_right_win = M.state.before_win
		vim.api.nvim_set_current_win(M.state.before_win)
	end
end

function M.focus_after()
	if M.state.after_win and vim.api.nvim_win_is_valid(M.state.after_win) then
		M.state.last_right_win = M.state.after_win
		vim.api.nvim_set_current_win(M.state.after_win)
	end
end

function M.focus_right()
	local cur = vim.api.nvim_get_current_win()
	if cur == M.state.files_win or cur == M.state.logs_win then
		M.focus_before()
	elseif cur == M.state.before_win then
		M.focus_after()
	else
		M.focus_after()
	end
end

function M.cycle_next_panel()
	local cur = vim.api.nvim_get_current_win()
	if cur == M.state.files_win then
		M.focus_logs()
	elseif cur == M.state.logs_win then
		M.focus_before()
	elseif cur == M.state.before_win then
		M.focus_after()
	else
		M.focus_files()
	end
end

function M.cycle_prev_panel()
	local cur = vim.api.nvim_get_current_win()
	if cur == M.state.files_win then
		M.focus_after()
	elseif cur == M.state.after_win then
		M.focus_before()
	elseif cur == M.state.before_win then
		M.focus_logs()
	else
		M.focus_files()
	end
end

--- Shows keymap help modal.
function M.show_help()
	local lines = {
		" 📊 Git Log Diff Dashboard Shortcuts",
		" ──────────────────────────────────────────────────────────",
		"  <Tab> / <S-Tab> Cycle panels (Files -> Logs -> Before -> After)",
		"  <C-h> / <C-l>   Jump Left (Files/Logs) / Jump Right (Code Diff)",
		"  <C-k> / <C-j>   Jump Up (Files) / Jump Down (Logs) / Scroll",
		"  < / > / , / .   Resize left column width narrower / wider",
		"  _ / + / - / =   Resize top files height smaller / larger",
		"  [<A-j> / <C-n>] Next Older commit (chronologically downwards)",
		"  [<A-k> / <C-p>] Next Newer commit (chronologically upwards)",
		"  []m / [m]       Jump to Next Older / Newer commit",
		"  [j / k]         In Logs pane: Step through commits (centered in Y)",
		"  f / l           Direct jump to Files List / Commit Logs List",
		"  b               In Logs: Switch Branch │ In Code: Focus Before",
		"  a               In Logs: Toggle Mode (🌿 Current <-> 🌐 --all)",
		"  <CR> / Enter    In Files: Select File │ In Logs: Select Commit",
		"  ]c / ]d         Jump to next diff change / hunk",
		"  [c / [d         Jump to previous diff change / hunk",
		"  y               Yank Commit SHA to clipboard",
		"  K               Checkout selected commit",
		"  r / <F5>        Refresh commit history & diffs from Git",
		"  q / <Esc>       Close Dashboard & return to previous workspace",
		" ──────────────────────────────────────────────────────────",
		"  Press 'q', '<Esc>', '<CR>', or '<Space>' to dismiss",
	}
	local h_buf, h_win = ui.float({
		title = " ❓ Help: Git Log Diff Dashboard ",
		lines = lines,
		width = 0.62,
		height = #lines + 2,
		zindex = 100,
		close_on_keys = { "q", "<Esc>", "<CR>", "<Space>", "?", "<F1>", "<C-?>", "<C-/>", "<C-_>" },
	})
	if h_buf and h_win and vim.api.nvim_win_is_valid(h_win) then
		for _, k in ipairs({ "q", "<Esc>", "<CR>", "<Space>", "?", "<F1>", "<C-?>", "<C-/>", "<C-_>" }) do
			vim.keymap.set({ "n", "v" }, k, function()
				if vim.api.nvim_win_is_valid(h_win) then
					pcall(vim.api.nvim_win_close, h_win, true)
				end
			end, { buffer = h_buf, silent = true, nowait = true })
		end
	end
end

--- Closes the Git Log Diff Dashboard and cleans up windows/tabpage.
function M.close()
	if not M.state.is_open then
		return
	end
	M.state.is_open = false

	local tab = M.state.tab
	local prev_win = M.state.prev_win
	local prev_tab = M.state.prev_tab

	M.state.files_win, M.state.files_buf = nil, nil
	M.state.logs_win, M.state.logs_buf = nil, nil
	M.state.before_win, M.state.before_buf = nil, nil
	M.state.after_win, M.state.after_buf = nil, nil
	M.state.tab = nil

	if tab and vim.api.nvim_tabpage_is_valid(tab) then
		pcall(vim.cmd, "tabclose")
	end

	if prev_tab and vim.api.nvim_tabpage_is_valid(prev_tab) then
		pcall(vim.api.nvim_set_current_tabpage, prev_tab)
	end
	if prev_win and vim.api.nvim_win_is_valid(prev_win) then
		pcall(vim.api.nvim_set_current_win, prev_win)
	end
end

--- Opens the Git Log Diff Dashboard.
--- @param opts? { cwd?: string, commit?: string, mode?: "branch"|"all", branch?: string, file?: string }
function M.open(opts)
	opts = opts or {}
	local orig_win = vim.api.nvim_get_current_win()
	local orig_tab = vim.api.nvim_get_current_tabpage()

	local target_cwd = opts.cwd or (project.root() or vim.fn.getcwd())
	target_cwd = path_util.normalize(target_cwd)

	if not git.is_repository(target_cwd) then
		notify("Current directory is not a valid Git repository", vim.log.levels.WARN)
		return
	end

	if M.is_open() then
		M.close()
	end

	M.setup_highlights()

	-- Load per-project and global session persistence
	local saved_session = M.load_session(target_cwd) or {}

	local mode = opts.mode or saved_session.mode or "branch"
	local current_branch_res = git.lines({ "branch", "--show-current" }, target_cwd)[1] or "HEAD"
	local branch = opts.branch or saved_session.branch or current_branch_res
	local initial_commit = opts.commit or saved_session.commit
	local initial_file = opts.file or saved_session.file

	M.state.cwd = target_cwd
	M.state.prev_win = orig_win
	M.state.prev_tab = orig_tab
	M.state.mode = mode
	M.state.branch = branch
	M.state.current_branch = current_branch_res
	M.state.left_ratio = saved_session.left_ratio or M.settings.left_ratio
	M.state.top_ratio = saved_session.top_ratio or M.settings.top_ratio

	-- Fetch commit list
	M.state.commits = M.fetch_commits(target_cwd, mode, branch)
	if #M.state.commits == 0 then
		notify("No commit history found in repository", vim.log.levels.INFO)
		return
	end

	-- Open dedicated workspace tabpage
	vim.cmd("tabnew")
	M.state.tab = vim.api.nvim_get_current_tabpage()
	local base_win = vim.api.nvim_get_current_win()

	local total_w = vim.o.columns or 80
	local total_h = vim.o.lines or 24
	local left_w = math.max(24, math.floor(total_w * M.state.left_ratio))
	local files_h = math.max(6, math.floor(total_h * M.state.top_ratio))

	-- 1. Create Files Changed buffer & window (Top-Left)
	local files_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[files_buf].buftype = "nofile"
	vim.bo[files_buf].bufhidden = "wipe"
	vim.bo[files_buf].swapfile = false
	vim.bo[files_buf].buflisted = false

	local files_win = vim.api.nvim_open_win(files_buf, false, {
		win = base_win,
		split = "left",
		width = left_w,
	})
	M.state.files_buf = files_buf
	M.state.files_win = files_win
	vim.wo[files_win].cursorline = true
	vim.wo[files_win].wrap = true
	vim.wo[files_win].linebreak = true
	vim.wo[files_win].breakindent = true
	vim.wo[files_win].winfixwidth = true
	vim.wo[files_win].winbar =
		"%#FoxLogDiffHeader# 📁 Files Changed %#GitCenterDiffFiller#│ %#FoxGitKrakenDim#[<CR>: Select | Tab: Focus | </>: Width]"

	-- 2. Create Commit Logs buffer & window (Bottom-Left)
	local logs_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[logs_buf].buftype = "nofile"
	vim.bo[logs_buf].bufhidden = "wipe"
	vim.bo[logs_buf].swapfile = false
	vim.bo[logs_buf].buflisted = false

	local logs_win = vim.api.nvim_open_win(logs_buf, false, {
		win = files_win,
		split = "below",
		height = total_h - files_h - 2,
	})
	M.state.logs_buf = logs_buf
	M.state.logs_win = logs_win
	vim.wo[logs_win].cursorline = true
	vim.wo[logs_win].wrap = true
	vim.wo[logs_win].linebreak = true
	vim.wo[logs_win].breakindent = true
	vim.wo[logs_win].breakindentopt = "shift:4"
	vim.wo[logs_win].winfixwidth = true
	vim.wo[logs_win].scrolloff = 6
	vim.wo[logs_win].winbar =
		"%#FoxLogDiffHeader# 📜 Commit History %#GitCenterDiffFiller#│ %#FoxGitKrakenDim#[j/k: Step | a: All | b: Branch | y: SHA | ?: Help]"

	-- 3. Setup Before Code (Middle pane) using base_win
	local before_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[before_buf].buftype = "nofile"
	vim.bo[before_buf].bufhidden = "wipe"
	vim.bo[before_buf].swapfile = false
	vim.bo[before_buf].buflisted = false

	local before_win = base_win
	vim.api.nvim_win_set_buf(before_win, before_buf)
	M.state.before_buf = before_buf
	M.state.before_win = before_win
	vim.wo[before_win].number = true
	vim.wo[before_win].cursorline = true
	vim.wo[before_win].wrap = true
	vim.wo[before_win].linebreak = true
	vim.wo[before_win].breakindent = true
	vim.wo[before_win].scrollbind = true
	vim.wo[before_win].winbar =
		"%#FoxLogDiffBadgeHead# ⏮️ Before (Parent Commit) %#GitCenterDiffFiller#│ %#FoxGitKrakenDim#[]c/[c: Hunk | q: Close]"

	-- 4. Setup After Code (Right pane)
	local after_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[after_buf].buftype = "nofile"
	vim.bo[after_buf].bufhidden = "wipe"
	vim.bo[after_buf].swapfile = false
	vim.bo[after_buf].buflisted = false

	local after_win = vim.api.nvim_open_win(after_buf, false, {
		win = before_win,
		split = "right",
	})
	M.state.after_buf = after_buf
	M.state.after_win = after_win
	vim.wo[after_win].number = true
	vim.wo[after_win].cursorline = true
	vim.wo[after_win].wrap = true
	vim.wo[after_win].linebreak = true
	vim.wo[after_win].breakindent = true
	vim.wo[after_win].scrollbind = true
	vim.wo[after_win].winbar =
		"%#FoxLogDiffBadgeBranch# ⏭️ After (Selected Commit) %#GitCenterDiffFiller#│ %#FoxGitKrakenDim#[scrollbind active]"

	M.state.is_open = true

	-- Autocmds for window closing
	for _, win in ipairs({ files_win, logs_win, before_win, after_win }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = function()
				vim.schedule(function()
					if M.state.is_open then
						M.close()
					end
				end)
			end,
		})
	end

	-- Keybindings
	local f_opts = { buffer = files_buf, noremap = true, silent = true, nowait = true }
	local l_opts = { buffer = logs_buf, noremap = true, silent = true, nowait = true }
	local b_opts = { buffer = before_buf, noremap = true, silent = true, nowait = true }
	local a_opts = { buffer = after_buf, noremap = true, silent = true, nowait = true }
	local all_opts = { f_opts, l_opts, b_opts, a_opts }

	-- Panel cycle & jump keymaps
	for _, op in ipairs(all_opts) do
		vim.keymap.set({ "n", "v" }, "<Tab>", M.cycle_next_panel, op)
		vim.keymap.set({ "n", "v" }, "<S-Tab>", M.cycle_prev_panel, op)
		vim.keymap.set({ "n", "v" }, "<C-h>", M.focus_left, op)
		vim.keymap.set({ "n", "v" }, "<C-l>", M.focus_right, op)
		for _, hk in ipairs({ "?", "<F1>", "<C-?>", "<C-/>", "<C-_>" }) do
			vim.keymap.set("n", hk, M.show_help, op)
		end
		vim.keymap.set("n", "]c", M.jump_next_hunk, op)
		vim.keymap.set("n", "]d", M.jump_next_hunk, op)
		vim.keymap.set("n", "[c", M.jump_prev_hunk, op)
		vim.keymap.set("n", "[d", M.jump_prev_hunk, op)
		vim.keymap.set("n", "q", M.close, op)
		vim.keymap.set("n", "<Esc>", M.close, op)

		-- Column width and section height resizing across all panels
		for _, k in ipairs({ "<", ",", "<M-,>", "<A-,>", "<C-Left>" }) do
			vim.keymap.set({ "n", "v" }, k, function()
				M.resize_left(-2)
			end, op)
		end
		for _, k in ipairs({ ">", ".", "<M-.>", "<A-.>", "<C-Right>" }) do
			vim.keymap.set({ "n", "v" }, k, function()
				M.resize_left(2)
			end, op)
		end
		for _, k in ipairs({ "_", "-", "<C-Up>" }) do
			vim.keymap.set({ "n", "v" }, k, function()
				M.resize_top(-1)
			end, op)
		end
		for _, k in ipairs({ "+", "=", "<C-Down>" }) do
			vim.keymap.set({ "n", "v" }, k, function()
				M.resize_top(1)
			end, op)
		end

		-- Global chronological commit navigation across ALL panels:
		-- Alt+j / Alt+Down / Ctrl+n / ]m -> next older commit (downwards)
		for _, k in ipairs({ "<A-j>", "<M-j>", "<A-Down>", "<C-n>", "]m", "]g" }) do
			vim.keymap.set({ "n", "v" }, k, M.next_older_commit, op)
		end
		-- Alt+k / Alt+Up / Ctrl+p / [m -> next newer commit (upwards)
		for _, k in ipairs({ "<A-k>", "<M-k>", "<A-Up>", "<C-p>", "[m", "[g" }) do
			vim.keymap.set({ "n", "v" }, k, M.next_newer_commit, op)
		end
	end

	-- Vertical navigation across left column & scroll trap
	vim.keymap.set({ "n", "v" }, "<C-j>", function()
		M.focus_logs()
	end, f_opts)
	vim.keymap.set({ "n", "v" }, "<C-k>", function()
		M.focus_files()
	end, l_opts)
	vim.keymap.set({ "n", "v" }, "<C-k>", function()
		vim.cmd("normal! \x15")
	end, f_opts)
	vim.keymap.set({ "n", "v" }, "<C-j>", function()
		vim.cmd("normal! \x04")
	end, l_opts)
	vim.keymap.set({ "n", "v" }, "<C-k>", function()
		vim.cmd("normal! \x15")
	end, b_opts)
	vim.keymap.set({ "n", "v" }, "<C-j>", function()
		vim.cmd("normal! \x04")
	end, b_opts)
	vim.keymap.set({ "n", "v" }, "<C-k>", function()
		vim.cmd("normal! \x15")
	end, a_opts)
	vim.keymap.set({ "n", "v" }, "<C-j>", function()
		vim.cmd("normal! \x04")
	end, a_opts)

	-- Direct jump keys
	vim.keymap.set("n", "f", M.focus_files, b_opts)
	vim.keymap.set("n", "f", M.focus_files, a_opts)
	vim.keymap.set("n", "f", M.focus_files, l_opts)
	vim.keymap.set("n", "l", M.focus_logs, f_opts)
	vim.keymap.set("n", "l", M.focus_logs, b_opts)
	vim.keymap.set("n", "l", M.focus_logs, a_opts)
	vim.keymap.set("n", "b", M.focus_before, f_opts)
	vim.keymap.set("n", "b", M.focus_before, a_opts)

	-- Files List specific keys
	vim.keymap.set("n", "<CR>", function()
		local row = vim.api.nvim_win_get_cursor(files_win)[1]
		local file_idx = M.state.line_to_file_idx[row]
		if file_idx then
			M.select_file(file_idx)
			M.focus_after()
		end
	end, f_opts)

	-- Commit Logs List specific keys
	-- In logs pane: j/k and Up/Down directly step through commits chronologically and auto-center
	vim.keymap.set("n", "j", M.next_older_commit, l_opts)
	vim.keymap.set("n", "<Down>", M.next_older_commit, l_opts)
	vim.keymap.set("n", "k", M.next_newer_commit, l_opts)
	vim.keymap.set("n", "<Up>", M.next_newer_commit, l_opts)
	vim.keymap.set("n", "J", M.next_older_commit, l_opts)
	vim.keymap.set("n", "K", M.next_newer_commit, l_opts)
	vim.keymap.set("n", "G", function()
		M.select_commit(#M.state.commits)
	end, l_opts)
	vim.keymap.set("n", "gg", function()
		M.select_commit(1)
	end, l_opts)

	vim.keymap.set("n", "<CR>", function()
		local row = vim.api.nvim_win_get_cursor(logs_win)[1]
		local commit_idx = M.state.line_to_commit_idx[row]
		if commit_idx then
			M.select_commit(commit_idx)
			M.focus_files()
		end
	end, l_opts)

	vim.keymap.set("n", "a", M.toggle_mode, l_opts)
	vim.keymap.set("n", "b", M.select_branch, l_opts)

	-- Yank SHA & Checkout commit
	local function yank_sha()
		local cur = M.state.commits[M.state.active_commit_idx]
		if cur then
			vim.fn.setreg("+", cur.full_hash)
			vim.fn.setreg("*", cur.full_hash)
			notify("📋 Copied Commit SHA to clipboard: " .. cur.hash)
		end
	end

	local function checkout_cur()
		local cur = M.state.commits[M.state.active_commit_idx]
		if cur then
			if
				vim.fn.confirm(string.format("⚠️ Checkout commit %s (%s)?", cur.hash, cur.subject), "&Yes\n&No", 2) == 1
			then
				git.run({ "checkout", cur.full_hash }, function(ok, output)
					if ok then
						notify("✅ Checked out commit: " .. cur.hash)
						M.state.commits = M.fetch_commits(M.state.cwd, M.state.mode, M.state.branch)
						M.select_commit(1)
					else
						notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
					end
				end, M.state.cwd)
			end
		end
	end

	for _, op in ipairs(all_opts) do
		vim.keymap.set("n", "y", yank_sha, op)
		vim.keymap.set("n", "K", checkout_cur, op)
		vim.keymap.set("n", "r", function()
			M.state.commits = M.fetch_commits(M.state.cwd, M.state.mode, M.state.branch)
			M.select_commit(M.state.active_commit_idx)
			notify("🔄 Refreshed commit history and diffs")
		end, op)
	end

	-- Cursor movement sync
	local augroup = vim.api.nvim_create_augroup("FoxGitLogDiffSync", { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = files_buf,
		callback = function()
			vim.schedule(function()
				if not M.is_open() or not (files_win and vim.api.nvim_win_is_valid(files_win)) then
					return
				end
				local row = vim.api.nvim_win_get_cursor(files_win)[1]
				local file_idx = M.state.line_to_file_idx[row]
				if file_idx and file_idx ~= M.state.active_file_idx then
					M.select_file(file_idx)
				end
			end)
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = logs_buf,
		callback = function()
			vim.schedule(function()
				if not M.is_open() or not (logs_win and vim.api.nvim_win_is_valid(logs_win)) then
					return
				end
				local row = vim.api.nvim_win_get_cursor(logs_win)[1]
				local commit_idx = M.state.line_to_commit_idx[row]
				if commit_idx and commit_idx ~= M.state.active_commit_idx then
					M.select_commit(commit_idx)
				end
			end)
		end,
	})

	-- Select initial commit & file
	local target_commit = initial_commit or 1
	M.select_commit(target_commit)

	if initial_file then
		M.select_file(initial_file)
	end

	-- Start with focus in Files list (or Logs list if initial commit was passed)
	if initial_commit then
		M.focus_files()
	else
		M.focus_logs()
	end
end

return setmetatable({
	name = "fox_git_log_diff",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = {
		"GitLogDiff",
		"GitCenterLogDiff",
		"FoxGitLogDiff",
	},
	config = function()
		pcall(vim.api.nvim_create_user_command, "GitLogDiff", function(cmd_opts)
			local args = cmd_opts.fargs or {}
			local commit = args[1] ~= "" and args[1] or nil
			local mode = args[2] ~= "" and args[2] or nil
			M.open({ commit = commit, mode = mode })
		end, { nargs = "*", desc = "Open Git Log Diff 4-Panel Dashboard" })

		pcall(vim.api.nvim_create_user_command, "GitCenterLogDiff", function(cmd_opts)
			local args = cmd_opts.fargs or {}
			local commit = args[1] ~= "" and args[1] or nil
			local mode = args[2] ~= "" and args[2] or nil
			M.open({ commit = commit, mode = mode })
		end, { nargs = "*", desc = "Open Git Log Diff 4-Panel Dashboard" })

		pcall(vim.api.nvim_create_user_command, "FoxGitLogDiff", function(cmd_opts)
			local args = cmd_opts.fargs or {}
			local commit = args[1] ~= "" and args[1] or nil
			local mode = args[2] ~= "" and args[2] or nil
			M.open({ commit = commit, mode = mode })
		end, { nargs = "*", desc = "Open Git Log Diff 4-Panel Dashboard" })
	end,
}, { __index = M })
