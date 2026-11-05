-- ============================================================================
-- FOX PLUGIN: Git Center -- GitKraken Style Commit Graph Viewer
-- ============================================================================
-- Interactive dual-pane commit graph viewer with:
--   - 2 modes: "branch" (Actual/Current Branch only) and "all" (--all branches)
--   - GitKraken visual aesthetics: colored branch lanes, circular commit nodes,
--     capsule ref/branch/tag badges, SHA, author, and relative dates.
--   - On-the-fly lazy loading / pagination when scrolling down via Vim motions
--     (d, u, Ctrl+d, Ctrl+u, j, k, G, gg).
--   - Side preview pane with full commit details, changed files, and side-by-side diff.
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local ui = lazy_req("fox.core.ui")
local diff = lazy_req("fox.git.diff")
local config = require("plugins.fox.git.git_center.config")
local queries = require("plugins.fox.git.git_center.queries")
local z_index = require("fox.core.z_index")

local M = {}

M.ns_graph = vim.api.nvim_create_namespace("FoxGitKrakenGraphSpans")

local LANE_COLORS = {
	{ name = "FoxGitKrakenLane1", fg = "#89dceb" }, -- Cyan
	{ name = "FoxGitKrakenLane2", fg = "#cba6f7" }, -- Lavender / Purple
	{ name = "FoxGitKrakenLane3", fg = "#a6e3a1" }, -- Green
	{ name = "FoxGitKrakenLane4", fg = "#f9e2af" }, -- Warm Gold / Yellow
	{ name = "FoxGitKrakenLane5", fg = "#f38ba8" }, -- Coral / Red
	{ name = "FoxGitKrakenLane6", fg = "#fab387" }, -- Peach / Orange
	{ name = "FoxGitKrakenLane7", fg = "#94e2d5" }, -- Teal
	{ name = "FoxGitKrakenLane8", fg = "#89b4fa" }, -- Sky Blue
}

--- Registers highlight groups for GitKraken aesthetics.
function M.setup_highlights()
	for _, lane in ipairs(LANE_COLORS) do
		vim.api.nvim_set_hl(0, lane.name, { fg = lane.fg, bold = true, default = true })
	end

	vim.api.nvim_set_hl(0, "FoxGitKrakenSha", { fg = "#eed49f", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenSubject", { fg = "#cdd6f4", default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenAuthor", { fg = "#89dceb", default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenDate", { fg = "#a6adc8", default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenDim", { fg = "#585b70", default = true })

	-- Ref badges
	vim.api.nvim_set_hl(0, "FoxGitKrakenBadgeHead", { fg = "#11111b", bg = "#a6e3a1", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenBadgeRemote", { fg = "#11111b", bg = "#89b4fa", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenBadgeTag", { fg = "#11111b", bg = "#f9e2af", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenBadgeBranch", { fg = "#11111b", bg = "#cba6f7", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenBadgeBase", { fg = "#11111b", bg = "#fab387", italic = true, default = true })

	-- Header / Mode badge
	vim.api.nvim_set_hl(0, "FoxGitKrakenHeader", { fg = "#89dceb", bold = true, default = true })
	vim.api.nvim_set_hl(0, "FoxGitKrakenModeBadge", { fg = "#11111b", bg = "#89dceb", bold = true, default = true })
end

--- Converts raw ASCII git-graph characters into GitKraken-style Unicode box glyphs.
--- @param raw_prefix string
--- @return string
function M.beautify_graph_prefix(raw_prefix)
	local res = {}
	for i = 1, #raw_prefix do
		local c = raw_prefix:sub(i, i)
		if c == "*" then
			table.insert(res, "●")
		elseif c == "|" then
			table.insert(res, "│")
		elseif c == "/" then
			table.insert(res, "╱")
		elseif c == "\\" then
			table.insert(res, "╲")
		elseif c == "_" or c == "-" then
			table.insert(res, "─")
		elseif c == "." then
			table.insert(res, "⬝")
		else
			table.insert(res, c)
		end
	end
	return table.concat(res)
end

--- Parses ref decoration string (e.g. "(HEAD -> main, origin/main, tag: v1.0.0)").
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
				table.insert(badges, { text = "🌿 " .. b, hl = "FoxGitKrakenBadgeHead" })
			elseif item:match("^tag:%s*(.+)$") then
				local t = item:match("^tag:%s*(.+)$")
				table.insert(badges, { text = "🏷️ " .. t, hl = "FoxGitKrakenBadgeTag" })
			elseif item:match("^remotes/origin/(.+)$") or item:match("^origin/(.+)$") then
				local r = item:gsub("^remotes/origin/", ""):gsub("^origin/", "")
				table.insert(badges, { text = "☁️ " .. r, hl = "FoxGitKrakenBadgeRemote" })
			else
				table.insert(badges, { text = "🌲 " .. item, hl = "FoxGitKrakenBadgeBranch" })
			end
		end
	end
	return badges
end

--- Parses a raw line from `git log --graph --pretty=format:%h%x1f%d%x1f%an%x1f%cr%x1f%s`.
--- @param raw_line string
--- @return table parsed
function M.parse_raw_graph_line(raw_line)
	local sep = "\x1f"
	local first_sep = raw_line:find(sep, 1, true)

	if not first_sep then
		-- Pure graph connector line without a commit (e.g. branch merge/split)
		return {
			is_commit = false,
			graph_raw = raw_line,
			hash = nil,
			refs = "",
			author = "",
			date = "",
			subject = "",
		}
	end

	local prefix_and_hash = raw_line:sub(1, first_sep - 1)
	local rest = raw_line:sub(first_sep + 1)
	local parts = vim.split(rest, sep, { plain = true })

	local graph_prefix, hash = prefix_and_hash:match("^(.-)%s*(%x%x%x%x%x%x%x+)$")
	if not hash then
		graph_prefix = prefix_and_hash
		hash = ""
	end

	return {
		is_commit = true,
		graph_raw = graph_prefix or "",
		hash = hash,
		full_hash = parts[5] or hash,
		refs = parts[1] or "",
		author = parts[2] or "",
		date = parts[3] or "",
		subject = parts[4] or "",
	}
end

--- Formats a parsed graph entry into a rendered line string and extmark span highlights.
--- @param parsed table
--- @return string line_text
--- @return table[] spans
function M.format_commit_line(parsed, widths)
	local line_text = ""
	local byte_len = 0
	local spans = {}
	local dim = parsed.dim == true
	local display_width = 0

	local function append(chunk, hl_group)
		if not chunk or chunk == "" then
			return
		end
		local start_byte = byte_len
		line_text = line_text .. chunk
		byte_len = byte_len + #chunk
		display_width = display_width + vim.fn.strdisplaywidth(chunk)
		if hl_group then
			table.insert(spans, {
				col_start = start_byte,
				col_end = byte_len,
				hl_group = parsed.is_header and "FoxGitKrakenHeader" or hl_group,
			})
		end
	end

	-- Left margin
	append(" ")

	-- Beautified graph with column-based lane colors
	local raw = parsed.graph_raw or ""
	for col = 1, #raw do
		local c = raw:sub(col, col)
		local lane_idx = ((col - 1) % #LANE_COLORS) + 1
		local hl = dim and "FoxGitKrakenDim" or LANE_COLORS[lane_idx].name

		if c == "*" then
			append("●", hl)
		elseif c == "|" then
			append("│", hl)
		elseif c == "/" then
			append("╱", hl)
		elseif c == "\\" then
			append("╲", hl)
		elseif c == "_" or c == "-" then
			append("─", hl)
		elseif c == "." then
			append("⬝", hl)
		elseif c == " " then
			append(" ", nil)
		else
			append(c, hl)
		end
	end

	if not parsed.is_commit or not parsed.hash or parsed.hash == "" then
		return line_text, spans
	end

	append(string.rep(" ", widths and math.max(1, widths.graph - #raw + 1) or 1))

	-- Short commit hash
	local hash_start = display_width
	append(parsed.hash, dim and "FoxGitKrakenDim" or "FoxGitKrakenSha")

	-- Ref badges
	local badges = parse_refs(parsed.refs)
	for _, badge in ipairs(badges) do
		append(" ")
		append(" " .. badge.text .. " ", badge.hl)
	end
	for _, name in ipairs(parsed.branch_bases or {}) do
		append(" ")
		append(" base: " .. name .. " ", "FoxGitKrakenBadgeBase")
	end

	append(string.rep(" ", widths and math.max(2, widths.hash - (display_width - hash_start) + 2) or 2))
	local author = parsed.author or ""
	append(author, dim and "FoxGitKrakenDim" or "FoxGitKrakenAuthor")
	append(string.rep(" ", widths and math.max(2, widths.author - vim.fn.strdisplaywidth(author) + 2) or 2))
	local date = parsed.date or ""
	append(date, dim and "FoxGitKrakenDim" or "FoxGitKrakenDate")
	append(string.rep(" ", widths and math.max(2, widths.date - vim.fn.strdisplaywidth(date) + 2) or 2))

	-- Subject stays last so long messages never shift the metadata columns.
	if parsed.subject and parsed.subject ~= "" then
		append(parsed.subject, dim and "FoxGitKrakenDim" or "FoxGitKrakenSubject")
	else
		append("(no commit message)", "FoxGitKrakenDim")
	end

	return line_text, spans
end

--- Shared ancestors are inferred bases, not a record of branch creation.
local function get_branch_bases(cwd)
	local refs = queries.git_lines({
		"for-each-ref",
		"--format=%(refname)%1f%(refname:short)%1f%(objectname)%1f%(symref)%1f%(HEAD)%1f%(upstream)",
		"refs/heads",
		"refs/remotes",
	}, cwd)
	local head = queries.git_lines({ "rev-parse", "HEAD" }, cwd)[1]
	local branches, current, upstream = {}, nil, nil
	for _, line in ipairs(refs) do
		local fields = vim.split(line, "\x1f", { plain = true })
		if fields[5] == "*" then
			current, upstream = fields[1], fields[6]
		end
		table.insert(branches, fields)
	end

	local bases, by_tip = {}, {}
	for _, ref in ipairs(branches) do
		if ref[1] ~= current and ref[1] ~= upstream and ref[3] ~= head and ref[4] == "" then
			local tip = ref[3]
			if not by_tip[tip] then
				by_tip[tip] = queries.git_lines({ "merge-base", "--all", "HEAD", tip }, cwd)
			end
			for _, hash in ipairs(by_tip[tip]) do
				-- Descendant branches share HEAD itself, rather than a base below it.
				if hash ~= head then
					bases[hash] = bases[hash] or {}
					table.insert(bases[hash], ref[2])
				end
			end
		end
	end
	return bases
end

--- Fetches commit graph lines from Git.
--- @param limit integer Number of commits to request.
--- @param cwd string Repository directory.
--- @param mode "branch"|"all" Mode to run git log in.
--- @param opts table|nil Optional rendering/selection options:
---   refs?             string[]      Explicit refs to log (overrides --all in "all" mode).
---   order?            "topo"|"date" Commit ordering (`--topo-order` when "topo").
---   connector_mode?   "dim"|"hidden" Whether to insert the synthetic lane spacer rows.
---   current_branch?   string        Branch whose reachable commits stay bright.
---   highlight_current? boolean      Dim commits not reachable from current_branch (default true).
---   branch_bases?      table        Cached inferred bases for pagination in current-branch mode.
--- @return table result
function M.fetch_commits(limit, cwd, mode, opts)
	opts = opts or {}
	local cmd = {
		"log",
		"--graph",
		"--color=never",
		"--pretty=format:%h%x1f%d%x1f%an%x1f%cr%x1f%s%x1f%H",
		"-n",
		tostring(limit),
	}
	if opts.order == "topo" then
		table.insert(cmd, 2, "--topo-order")
	end
	if mode == "all" then
		if opts.refs and #opts.refs > 0 then
			for _, ref in ipairs(opts.refs) do
				table.insert(cmd, ref)
			end
		else
			table.insert(cmd, "--all")
		end
	else
		table.insert(cmd, "HEAD")
	end

	local raw_lines = queries.git_lines(cmd, cwd)
	local branch_bases = mode ~= "all" and (opts.branch_bases or get_branch_bases(cwd)) or nil

	-- Commits reachable from the current branch; used to dim unrelated branches.
	-- Fetching the same limit is enough: every current-branch commit in the top
	-- `limit` of --all is also in the top `limit` of the branch itself.
	local current_set = nil
	if opts.current_branch and opts.current_branch ~= "" and opts.highlight_current ~= false then
		current_set = {}
		local hashes = queries.git_lines({ "rev-list", "-n", tostring(limit + 1), opts.current_branch }, cwd)
		for _, h in ipairs(hashes) do
			current_set[h] = true
		end
	end

	local show_connectors = opts.connector_mode ~= "hidden"
	local rendered_lines = {}
	local all_spans = {}
	local line_commits = {}
	local commits = {}
	local entries = {}
	local widths = {
		graph = 0,
		hash = vim.fn.strdisplaywidth("📌 Hash"),
		author = vim.fn.strdisplaywidth("👤 Author"),
		date = vim.fn.strdisplaywidth("🕒 Relative Date"),
	}

	for _, raw_line in ipairs(raw_lines) do
		local parsed = M.parse_raw_graph_line(raw_line)

		if parsed.is_commit then
			parsed.dim = current_set ~= nil and not current_set[parsed.full_hash]
			parsed.branch_bases = branch_bases and branch_bases[parsed.full_hash] or nil
			local hash_width = vim.fn.strdisplaywidth(parsed.hash)
			for _, badge in ipairs(parse_refs(parsed.refs)) do
				hash_width = hash_width + vim.fn.strdisplaywidth(badge.text) + 3
			end
			for _, name in ipairs(parsed.branch_bases or {}) do
				hash_width = hash_width + vim.fn.strdisplaywidth(name) + 8
			end
			widths.hash = math.max(widths.hash, hash_width)
			widths.author = math.max(widths.author, vim.fn.strdisplaywidth(parsed.author))
			widths.date = math.max(widths.date, vim.fn.strdisplaywidth(parsed.date))
		end
		widths.graph = math.max(widths.graph, #(parsed.graph_raw or ""))
		table.insert(entries, parsed)
	end

	if #entries > 0 then
		local header, spans = M.format_commit_line({
			is_commit = true,
			is_header = true,
			hash = "📌 Hash",
			author = "👤 Author",
			date = "🕒 Relative Date",
			subject = "💬 Subject",
		}, widths)
		table.insert(rendered_lines, header)
		table.insert(all_spans, spans)
	end

	for _, parsed in ipairs(entries) do
		if parsed.is_commit and show_connectors and #commits > 0 then
			local gap_raw = parsed.graph_raw and parsed.graph_raw:gsub("%*", "|") or "|"
			local gap_parsed = {
				is_commit = false,
				graph_raw = gap_raw ~= "" and gap_raw or "|",
				dim = true,
			}
			local gap_text, gap_spans = M.format_commit_line(gap_parsed)
			table.insert(rendered_lines, gap_text)
			table.insert(all_spans, gap_spans)
			if #commits > 0 then
				line_commits[#rendered_lines] = commits[#commits].full_hash
			end
		end

		local line_text, spans = M.format_commit_line(parsed, widths)

		table.insert(rendered_lines, line_text)
		table.insert(all_spans, spans)

		if parsed.is_commit and parsed.hash and parsed.hash ~= "" then
			line_commits[#rendered_lines] = parsed.full_hash or parsed.hash
			table.insert(commits, parsed)
		elseif #commits > 0 then
			line_commits[#rendered_lines] = commits[#commits].full_hash
		end
	end

	-- If git returned fewer commits than limit, all commits were fetched
	local all_fetched = #commits < limit

	return {
		lines = rendered_lines,
		spans = all_spans,
		line_commits = line_commits,
		commits = commits,
		total_commits = #commits,
		all_fetched = all_fetched,
		branch_bases = branch_bases,
	}
end

--- Lists branches for the graph filter/legend, newest first.
--- @param cwd string Repository directory.
--- @return table[] { name = string, current = boolean }
function M.get_branch_list(cwd)
	local names = {}
	local seen = {}
	for _, ref in
		ipairs(
			queries.git_lines(
				{ "for-each-ref", "--sort=-committerdate", "--format=%(refname:short)", "refs/heads", "refs/remotes" },
				cwd
			)
		)
	do
		local name = vim.trim(ref)
		if name ~= "" and name ~= "origin" and not name:match("/HEAD$") and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end

	local current = vim.trim(queries.git_lines({ "branch", "--show-current" }, cwd)[1] or "")
	local branches = {}
	for _, name in ipairs(names) do
		table.insert(branches, { name = name, current = (name == current) })
	end
	return branches
end

--- Opens the full-screen GitKraken-style Commit Graph Viewer.
--- @param target_cwd string|nil Repository directory.
--- @param initial_mode? "branch"|"all" Defaults to "branch".
function M.format_file_peek(output)
	local lines, statuses = {}, {}
	for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
		local status, path = line:match("^:%S+ %S+ %S+ %S+ ([A-Z]%d*)\t(.+)$")
		if status then
			statuses[path:gsub("\t", " => ")] = status
		else
			local added, removed, file = line:match("^(%d+)%s+(%d+)\t(.+)$")
			if not file then
				file = line:match("^%-\t%-\t(.+)$")
			end
			if file then
				-- Git abbreviates renames as dir/{old => new}/file in numstat.
				local old = file:gsub("{([^{}]-) => [^{}]-}", "%1")
				local new = file:gsub("{[^{}]- => ([^{}]-)}", "%1")
				local key = old ~= new and (old .. " => " .. new) or file
				table.insert(
					lines,
					string.format(
						" [%s]  %s  %s",
						statuses[key] or "M",
						added and ("+" .. added .. " -" .. removed) or "binary",
						file
					)
				)
			end
		end
	end
	return #lines > 0 and lines or { "No changed files." }
end

function M.open(target_cwd, initial_mode)
	local canvas_mode = false
	local layout
	local prev_win = vim.api.nvim_get_current_win()
	local active_cwd = target_cwd
		or (config.get_active_target() and config.get_active_target().full_path)
		or vim.fn.getcwd()

	local info = queries.get_git_info(active_cwd)
	if not info then
		config.notify("Not inside a valid Git repository", vim.log.levels.WARN)
		return
	end

	M.setup_highlights()
	diff.setup_highlights()

	local mode = initial_mode or "branch"
	local current_limit = 50
	local batch_size = 50
	local is_fetching = false
	local all_fetched
	local refs_filter = nil -- nil = every branch (--all); otherwise a list of refs
	local order = "topo" -- "topo" | "date"
	local connector_mode = "dim" -- "dim" | "hidden"
	local branch_bases

	local current_branch = (info.branch and info.branch ~= "") and info.branch
		or (queries.git_lines({ "branch", "--show-current" }, active_cwd)[1] or "HEAD")

	local function fetch_opts()
		return {
			refs = refs_filter,
			order = order,
			connector_mode = connector_mode,
			current_branch = current_branch,
			branch_bases = branch_bases,
		}
	end

	local initial_data = M.fetch_commits(current_limit, active_cwd, mode, fetch_opts())
	branch_bases = initial_data.branch_bases
	if #initial_data.lines == 0 then
		config.notify("No commit history found in repository", vim.log.levels.INFO)
		return
	end

	all_fetched = initial_data.all_fetched
	local rendered_lines = initial_data.lines
	local all_spans = initial_data.spans
	local line_commits = initial_data.line_commits
	local commits_data = initial_data.commits
	local total_commits_count = initial_data.total_commits

	-- Geometry calculation using dual panel
	local tot_w = math.floor(vim.o.columns * config.settings.width_ratio)
	local tot_h = math.floor(vim.o.lines * config.settings.height_ratio)
	local s_row = math.floor((vim.o.lines - tot_h) / 2)
	local s_col = math.floor((vim.o.columns - tot_w) / 2)

	local ratio = config.current_left_ratio or config.load_saved_left_ratio(active_cwd)
	-- For graph tree, default to 52% width so graph + message + badges fit comfortably
	if not config.current_left_ratio then
		ratio = 0.52
	end
	local left_w = math.floor(tot_w * ratio)
	local right_w = tot_w - left_w - 2

	local graph_z = z_index.next_zindex("git_center_graph", { parent = "git_center", offset = 30 })

	-- Create Left (Graph) Buffer & Window
	local left_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[left_buf].buftype = "nofile"
	vim.bo[left_buf].bufhidden = "wipe"
	vim.bo[left_buf].swapfile = false
	vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, rendered_lines)
	vim.bo[left_buf].modifiable = false

	-- Apply spans highlights
	vim.api.nvim_buf_clear_namespace(left_buf, M.ns_graph, 0, -1)
	for row_idx, spans in ipairs(all_spans) do
		for _, s in ipairs(spans) do
			pcall(vim.api.nvim_buf_add_highlight, left_buf, M.ns_graph, s.hl_group, row_idx - 1, s.col_start, s.col_end)
		end
	end

	local function format_title(loading)
		local mode_str
		if mode == "all" then
			if refs_filter and #refs_filter > 0 then
				mode_str = string.format("🎯 %d branch(es) [b: Edit Filter]", #refs_filter)
			else
				mode_str = "🌐 All Branches (--all) [a: Switch to Current]"
			end
		else
			mode_str = string.format("🌿 Current Branch (%s) [a: Switch to --all]", current_branch)
		end
		local count_str = all_fetched and string.format("(All %d commits)", total_commits_count)
			or string.format("(%d commits)", total_commits_count)
		local order_str = order == "topo" and "topo" or "date"
		local conn_str = connector_mode == "hidden" and "no-gaps" or "gaps"
		local load_str = loading and " ⏳ Loading..." or ""
		return string.format(
			" 📊 GitKraken Graph │ Mode: %s │ %s │ %s/%s%s ",
			mode_str,
			count_str,
			order_str,
			conn_str,
			load_str
		)
	end

	local left_win = vim.api.nvim_open_win(left_buf, true, {
		relative = "editor",
		width = left_w,
		height = tot_h,
		row = s_row,
		col = s_col,
		style = "minimal",
		border = "rounded",
		zindex = graph_z,
		title = format_title(false),
		title_pos = "center",
	})
	vim.api.nvim_win_set_cursor(left_win, { 2, 0 })
	vim.api.nvim_set_option_value("cursorline", true, { win = left_win })
	vim.api.nvim_set_option_value("wrap", false, { win = left_win })
	vim.api.nvim_set_option_value("linebreak", true, { win = left_win })
	vim.api.nvim_set_option_value("breakindent", true, { win = left_win })

	-- Create Right (Commit Details) Buffer & Window
	local right_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[right_buf].buftype = "nofile"
	vim.bo[right_buf].bufhidden = "wipe"
	vim.bo[right_buf].swapfile = false

	local right_win = vim.api.nvim_open_win(right_buf, false, {
		relative = "editor",
		width = right_w,
		height = tot_h,
		row = s_row,
		col = s_col + left_w + 2,
		style = "minimal",
		border = "rounded",
		zindex = graph_z,
		title = " 👁️ Commit Details & Side-by-Side Diff │ [Tab]: Open | [S-Tab]: Hide │ [Enter]: Full Diff ",
		title_pos = "center",
	})
	vim.api.nvim_set_option_value("wrap", false, { win = right_win })
	vim.api.nvim_set_option_value("number", true, { win = right_win })

	z_index.register(
		"git_center_graph",
		{ left_win, right_win },
		{ parent = "git_center", offset = 30, zindex = graph_z }
	)

	config.graph_win = left_win
	config.graph_buf = left_buf
	config.graph_right_win = right_win
	config.graph_right_buf = right_buf

	local is_closed = false

	local function update_window_title(loading)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		if canvas_mode then
			vim.api.nvim_win_set_config(left_win, {
				title = format_title(loading) .. " [F6: preview | Space: files]",
				title_pos = "center",
			})
		else
			vim.api.nvim_win_set_config(left_win, {
				title = format_title(loading),
				title_pos = "center",
			})
		end
	end

	local function render_left_buffer()
		if not (left_buf and vim.api.nvim_buf_is_valid(left_buf)) then
			return
		end
		vim.bo[left_buf].modifiable = true
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, rendered_lines)
		vim.bo[left_buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(left_buf, M.ns_graph, 0, -1)
		for row_idx, spans in ipairs(all_spans) do
			for _, s in ipairs(spans) do
				pcall(vim.api.nvim_buf_add_highlight, left_buf, M.ns_graph, s.hl_group, row_idx - 1, s.col_start, s.col_end)
			end
		end
	end

	local function close_viewer(keep_screen)
		if is_closed then
			return
		end
		is_closed = true

		if keep_screen == true then
			config.cached_view = "graph"
			config.cached_view_data.cwd = active_cwd
			config.cached_view_data.mode = mode
		elseif keep_screen == false then
			config.cached_view = "panel"
			config.cached_view_data = {}
		end

		config.graph_layout, config.graph_refresh, config.graph_peek = nil, nil, nil
		config.graph_win, config.graph_buf = nil, nil
		config.graph_right_win, config.graph_right_buf = nil, nil

		z_index.unregister("git_center_graph")
		ui.close(left_win)
		ui.close(right_win)

		if
			prev_win
			and vim.api.nvim_win_is_valid(prev_win)
			and not (config.main_win and vim.api.nvim_win_is_valid(config.main_win))
		then
			pcall(vim.api.nvim_set_current_win, prev_win)
		elseif config.main_win and vim.api.nvim_win_is_valid(config.main_win) then
			pcall(vim.api.nvim_set_current_win, config.main_win)
		end
	end

	for _, win in ipairs({ left_win, right_win }) do
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(win),
			once = true,
			callback = function()
				vim.schedule(close_viewer)
			end,
		})
	end

	-- Commit details cache & state
	local commit_cache = {}
	local current_commit_hash = nil
	local current_target_file = nil

	local function get_commit_at_row(row)
		local hash = line_commits[row]
		if not hash then
			-- Search nearest lines for commit
			for r = row, 1, -1 do
				if line_commits[r] then
					hash = line_commits[r]
					break
				end
			end
			if not hash then
				for r = row, #rendered_lines do
					if line_commits[r] then
						hash = line_commits[r]
						break
					end
				end
			end
		end
		if not hash then
			return nil
		end
		if commit_cache[hash] then
			return commit_cache[hash]
		end

		local meta = queries.git_lines(
			{ "show", "-s", "--pretty=format:%H%x1f%h%x1f%an%x1f%ae%x1f%ad%x1f%ar%x1f%s%x1f%b%x1f%d", hash },
			active_cwd
		)
		local commit = {
			full_hash = hash,
			hash = hash:sub(1, 7),
			author = "",
			email = "",
			date = "",
			rel_date = "",
			subject = "",
			body = "",
			refs = "",
		}
		if #meta > 0 then
			local parts = vim.split(meta[1], "\x1f", { plain = true })
			commit.full_hash = parts[1] or hash
			commit.hash = parts[2] or hash:sub(1, 7)
			commit.author = parts[3] or ""
			commit.email = parts[4] or ""
			commit.date = parts[5] or ""
			commit.rel_date = parts[6] or ""
			commit.subject = parts[7] or ""
			commit.body = parts[8] or ""
			commit.refs = parts[9] or ""
		end

		commit_cache[hash] = commit
		return commit
	end

	local function update_commit_details(target_filepath)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		if canvas_mode then
			return
		end
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if not commit then
			return
		end

		local raw_stat = queries.git_lines({ "show", "--name-status", "--pretty=format:", commit.full_hash }, active_cwd)
		local edited_files = {}
		for _, line in ipairs(raw_stat) do
			local status_char, filepath = line:match("^([A-Z%d]+)%s+(.+)$")
			if status_char and filepath then
				table.insert(edited_files, { status = status_char:sub(1, 1), filepath = filepath })
			end
		end

		if commit.full_hash ~= current_commit_hash then
			current_commit_hash = commit.full_hash
			current_target_file = target_filepath or (edited_files[1] and edited_files[1].filepath)
		elseif target_filepath then
			current_target_file = target_filepath
		end

		local raw_diff
		if current_target_file then
			raw_diff = queries.git_lines(
				{ "show", "--format=", "--color=never", commit.full_hash, "--", current_target_file },
				active_cwd
			)
		else
			raw_diff = queries.git_lines({ "show", "--format=", "--color=never", commit.full_hash }, active_cwd)
		end
		local combined_diff_lines, l_kinds, r_kinds, col_w =
			diff.format_side_by_side_single(raw_diff, false, vim.api.nvim_win_get_width(right_win))

		local content = {}
		table.insert(content, string.format(" 📌 Commit:      %s (%s)  [y: copy SHA]", commit.full_hash, commit.hash))
		table.insert(content, string.format(" 👤 Author:      %s <%s>", commit.author, commit.email))
		table.insert(content, string.format(" 🕒 Date:        %s (%s)", commit.date, commit.rel_date))
		if commit.refs and commit.refs ~= "" then
			table.insert(
				content,
				string.format(" 🏷️ Refs:        %s", commit.refs:gsub("^%s*%(?", ""):gsub("%)?%s*$", ""))
			)
		end
		table.insert(content, string.format(" 💬 Title:       %s", commit.subject))

		if commit.body and commit.body ~= "" then
			local body_lines = vim.split(commit.body, "\n", { plain = true })
			for _, bl in ipairs(body_lines) do
				if bl ~= "" then
					table.insert(content, "    " .. bl)
				end
			end
		end

		if #edited_files > 0 then
			table.insert(content, string.format(" 📁 Files Changed (%d): [Enter on file for diff]", #edited_files))
			for _, item in ipairs(edited_files) do
				local active_mark = item.filepath == current_target_file and "▶ " or "  "
				table.insert(content, string.format(" %s• [%s] %s", active_mark, item.status, item.filepath))
			end
		end

		table.insert(
			content,
			" ──────────────────────────────────────────────────────────────────────────"
		)

		for _, line in ipairs(combined_diff_lines) do
			table.insert(content, line)
		end

		local save_cursor = nil
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			save_cursor = vim.api.nvim_win_get_cursor(right_win)
		end

		vim.bo[right_buf].modifiable = true
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, content)
		vim.bo[right_buf].modifiable = false

		local header_line_count = 6 + (#edited_files > 0 and (#edited_files + 1) or 0)
		diff.apply_highlights_side_by_side_single(right_buf, l_kinds, r_kinds, col_w, header_line_count)

		if save_cursor and save_cursor[1] <= #content then
			pcall(vim.api.nvim_win_set_cursor, right_win, save_cursor)
		end
	end

	-- Full refresh: re-fetches from scratch respecting the current mode, order,
	-- branch filter and connector setting.
	local function reload()
		branch_bases = nil
		current_limit = 50
		all_fetched = false
		is_fetching = true
		update_window_title(true)

		vim.schedule(function()
			local result = M.fetch_commits(current_limit, active_cwd, mode, fetch_opts())
			branch_bases = result.branch_bases
			is_fetching = false
			commits_data = result.commits
			total_commits_count = result.total_commits
			all_fetched = result.all_fetched
			rendered_lines = result.lines
			all_spans = result.spans
			line_commits = result.line_commits
			render_left_buffer()
			if left_win and vim.api.nvim_win_is_valid(left_win) then
				pcall(vim.api.nvim_win_set_cursor, left_win, { 2, 0 })
			end
			update_window_title(false)
			update_commit_details(nil)
		end)
	end

	-- On-the-fly fetch implementation
	local function fetch_more(target_row)
		if is_fetching or all_fetched then
			if target_row and left_win and vim.api.nvim_win_is_valid(left_win) then
				local max_r = vim.api.nvim_buf_line_count(left_buf)
				pcall(vim.api.nvim_win_set_cursor, left_win, { math.min(target_row, max_r), 0 })
			end
			return
		end

		is_fetching = true
		current_limit = current_limit + batch_size
		update_window_title(true)

		vim.schedule(function()
			local ok, result = pcall(M.fetch_commits, current_limit, active_cwd, mode, fetch_opts())
			is_fetching = false
			if ok and result then
				branch_bases = result.branch_bases
				if result.total_commits <= #commits_data then
					all_fetched = true
				else
					commits_data = result.commits
					total_commits_count = result.total_commits
					all_fetched = result.all_fetched
					rendered_lines = result.lines
					all_spans = result.spans
					line_commits = result.line_commits
					render_left_buffer()
				end
			end

			update_window_title(false)

			if target_row and left_win and vim.api.nvim_win_is_valid(left_win) then
				local max_r = vim.api.nvim_buf_line_count(left_buf)
				pcall(vim.api.nvim_win_set_cursor, left_win, { math.min(target_row, max_r), 0 })
			end
		end)
	end

	-- Motions: Half-page down / up, Down / Up
	local function half_page_down()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		local h = vim.api.nvim_win_get_height(left_win)
		local step = math.max(1, math.floor(h / 2))
		local line_count = vim.api.nvim_buf_line_count(left_buf)
		local target_row = row + step

		if (target_row >= line_count - 10 or row >= line_count - 1) and not all_fetched and not is_fetching then
			fetch_more(target_row)
		else
			pcall(vim.api.nvim_win_set_cursor, left_win, { math.min(target_row, line_count), 0 })
		end
	end

	local function half_page_up()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		local h = vim.api.nvim_win_get_height(left_win)
		local step = math.max(1, math.floor(h / 2))
		local target_row = math.max(1, row - step)
		pcall(vim.api.nvim_win_set_cursor, left_win, { target_row, 0 })
	end

	local function move_down()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		local line_count = vim.api.nvim_buf_line_count(left_buf)
		local target_row = row + 1

		if target_row > line_count then
			if not all_fetched and not is_fetching then
				fetch_more(target_row)
			end
			return
		end

		if target_row >= line_count - 8 and not all_fetched and not is_fetching then
			fetch_more(nil)
		end

		pcall(vim.api.nvim_win_set_cursor, left_win, { target_row, 0 })
	end

	local function move_up()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local cur = vim.api.nvim_win_get_cursor(left_win)
		local row = cur[1]
		pcall(vim.api.nvim_win_set_cursor, left_win, { math.max(1, row - 1), 0 })
	end

	local function jump_bottom()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		local line_count = vim.api.nvim_buf_line_count(left_buf)
		if not all_fetched and not is_fetching then
			fetch_more(line_count + 50)
		else
			pcall(vim.api.nvim_win_set_cursor, left_win, { line_count, 0 })
		end
	end

	local function jump_top()
		if not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end
		pcall(vim.api.nvim_win_set_cursor, left_win, { 2, 0 })
	end

	-- Toggle mode (Current Branch <-> All Branches)
	local function toggle_mode()
		mode = (mode == "branch") and "all" or "branch"
		if mode == "branch" then
			refs_filter = nil
		end
		reload()

		local mode_name = (mode == "all") and "🌐 All Branches (--all)"
			or ("🌿 Current Branch (" .. current_branch .. ")")
		config.notify("Switched Git Graph Mode: " .. mode_name)
	end

	-- Toggle commit ordering (topological <-> date)
	local function toggle_order()
		order = (order == "topo") and "date" or "topo"
		reload()
		config.notify("Commit order: " .. (order == "topo" and "--topo-order" or "--date-order"))
	end

	-- Toggle the synthetic lane spacer rows that keep merges connected
	local function toggle_connectors()
		connector_mode = (connector_mode == "dim") and "hidden" or "dim"
		reload()
		config.notify("Lane spacers: " .. (connector_mode == "hidden" and "hidden" or "dimmed"))
	end

	-- Stable colour index per branch name, so a branch keeps the same colour.
	local function branch_color_idx(name)
		local h = 5381
		for i = 1, #name do
			h = (h * 33 + name:byte(i)) % 2147483647
		end
		return (h % #LANE_COLORS) + 1
	end

	-- Branch filter: choose which branches the graph logs.
	local function open_branch_filter()
		local branches = M.get_branch_list(active_cwd)
		if #branches == 0 then
			config.notify("No branches found to filter", vim.log.levels.WARN)
			return
		end

		local selected = {}
		for _, b in ipairs(branches) do
			if refs_filter == nil then
				selected[b.name] = true
			else
				selected[b.name] = vim.tbl_contains(refs_filter, b.name)
			end
		end

		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"

		local function paint()
			local lines = {}
			for _, b in ipairs(branches) do
				local box = selected[b.name] and "[x]" or "[ ]"
				local cur = b.current and "  (current)" or ""
				table.insert(lines, string.format(" %s %s%s", box, b.name, cur))
			end
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			vim.bo[buf].modifiable = false
		end
		paint()

		local _, win = ui.float({
			buf = buf,
			width = 0.5,
			height = math.min(#branches + 1, math.floor(vim.o.lines * 0.7)),
			title = " 🎯 Branch Filter │ Space: Toggle │ a: All │ n: None │ s: Apply │ q: Cancel ",
			zindex = graph_z + 25,
		})
		vim.api.nvim_set_option_value("cursorline", true, { win = win })

		local opts = { buffer = buf, noremap = true, silent = true, nowait = true }
		local function toggle_current()
			local row = vim.api.nvim_win_get_cursor(win)[1]
			local b = branches[row]
			if b then
				selected[b.name] = not selected[b.name]
				paint()
			end
		end
		local function set_all(val)
			for _, b in ipairs(branches) do
				selected[b.name] = val
			end
			paint()
		end
		local function apply()
			local refs = {}
			for _, b in ipairs(branches) do
				if selected[b.name] then
					table.insert(refs, b.name)
				end
			end
			ui.close(win)
			if #refs == 0 or #refs == #branches then
				refs_filter = nil
				config.notify("Showing all branches")
			else
				refs_filter = refs
				mode = "all"
				config.notify(string.format("Filtering %d branch(es)", #refs))
			end
			reload()
		end

		vim.keymap.set("n", "<Space>", toggle_current, opts)
		vim.keymap.set("n", "<CR>", toggle_current, opts)
		vim.keymap.set("n", "a", function()
			set_all(true)
		end, opts)
		vim.keymap.set("n", "n", function()
			set_all(false)
		end, opts)
		vim.keymap.set("n", "s", apply, opts)
		for _, k in ipairs({ "q", "<Esc>" }) do
			vim.keymap.set("n", k, function()
				ui.close(win)
			end, opts)
		end
	end

	-- Colour legend mapping branches to their stable colours.
	local function open_legend()
		local branches = M.get_branch_list(active_cwd)
		local lines = {
			" 🎨 Branch Colour Legend — commits not on the current branch are dimmed",
			" ──────────────────────────────────────────────────────────",
		}
		local swatches = {}
		for _, b in ipairs(branches) do
			local mark = b.current and "▶" or " "
			table.insert(lines, string.format(" %s ● %s%s", mark, b.name, b.current and "  (current)" or ""))
			table.insert(swatches, { row = #lines - 1, idx = b.current and 1 or branch_color_idx(b.name) })
		end
		table.insert(
			lines,
			" ──────────────────────────────────────────────────────────"
		)
		table.insert(lines, " ● commit node   │ lane   ╱╲ merge   ⬝ gap")
		table.insert(lines, " 🌿 HEAD   ☁️ remote   🏷️ tag   🌲 branch")
		table.insert(lines, "")
		table.insert(lines, " base: name (peach) = shared ancestor with another branch, inferred")
		table.insert(lines, " Press any key to dismiss")

		local buf = ui.float({
			lines = lines,
			width = 0.55,
			height = #lines + 1,
			title = " 🗂️ Git Graph Legend ",
			zindex = graph_z + 20,
			close_on_keys = { "q", "<Esc>", "<CR>", "<Space>" },
		})
		local ns = vim.api.nvim_create_namespace("FoxGitKrakenLegend")
		for _, s in ipairs(swatches) do
			pcall(vim.api.nvim_buf_add_highlight, buf, ns, LANE_COLORS[s.idx].name, s.row, 3, 4)
		end
	end

	-- Split resizing
	local function resize_split(delta)
		if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
			return
		end

		local cur_r = config.current_left_ratio or ratio
		local new_r = math.max(0.25, math.min(0.75, cur_r + delta))
		config.current_left_ratio = tonumber(string.format("%.3f", new_r))
		config.save_left_ratio(config.root_dir or active_cwd, config.current_left_ratio)

		layout.apply()
	end

	-- Actions: Copy SHA, Checkout, Full Diff
	local function yank_sha()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if commit then
			vim.fn.setreg("+", commit.full_hash)
			vim.fn.setreg("*", commit.full_hash)
			config.notify("📋 Copied Commit SHA to clipboard: " .. commit.hash)
		end
	end

	local function checkout_commit()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if not commit then
			return
		end
		if
			vim.fn.confirm("⚠️ Checkout commit " .. commit.hash .. " (" .. commit.subject .. ")?", "&Yes\n&No", 2) ~= 1
		then
			return
		end
		close_viewer()
		queries.git_run({ "checkout", commit.full_hash }, function(ok, output)
			local gc = package.loaded["plugins.fox.git.git_center"]
			if ok then
				config.notify("✅ Checked out commit: " .. commit.hash)
			else
				config.notify("❌ Checkout failed:\n" .. output, vim.log.levels.ERROR)
			end
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
			end
		end, active_cwd)
	end

	local function open_full_diff()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if commit then
			local modals = require("plugins.fox.git.git_center.modals")
			modals.open_diff_modal(current_target_file, "commit", active_cwd, commit.full_hash)
		end
	end

	local function on_right_cursor_moved()
		if is_closed or not (right_win and vim.api.nvim_win_is_valid(right_win)) then
			return
		end
		local cursor_row = vim.api.nvim_win_get_cursor(right_win)[1]
		local line_text = vim.api.nvim_buf_get_lines(right_buf, cursor_row - 1, cursor_row, false)[1] or ""

		local filepath = line_text:match("•%s*%[[A-Z%d]+%]%s+(.+)$")
		if filepath then
			filepath = filepath:gsub("^%s*", ""):gsub("%s*$", "")
			if filepath ~= current_target_file then
				update_commit_details(filepath)
			end
		end
	end

	local function focus_left()
		if layout.mode == "details" then
			layout.expand()
		end
		if left_win and vim.api.nvim_win_is_valid(left_win) then
			vim.api.nvim_set_current_win(left_win)
		end
	end

	local function focus_right()
		if layout.mode == "browse" then
			layout.toggle_preview()
		end
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			vim.api.nvim_set_current_win(right_win)
		end
	end

	local function scroll_right_preview(direction)
		if right_win and vim.api.nvim_win_is_valid(right_win) then
			vim.api.nvim_win_call(right_win, function()
				vim.cmd("normal! " .. (direction == "down" and "\x04" or "\x15"))
			end)
		end
	end

	local function open_log_diff_dashboard()
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local commit = get_commit_at_row(row)
		if commit and commit.full_hash then
			local commit_sha = commit.full_hash
			local cur_mode = mode
			local cur_branch = current_branch
			close_viewer(false)
			vim.schedule(function()
				local log_diff = require("plugins.fox.git.log_diff")
				log_diff.open({
					cwd = active_cwd,
					commit = commit_sha,
					mode = cur_mode,
					branch = cur_branch,
				})
			end)
		end
	end

	local function show_help_modal()
		local help_lines = {
			" 📊 GitKraken Commit Graph Shortcuts",
			" ──────────────────────────────────────────────────────────",
			"  [F6/F7/F8]     Toggle preview / Expand details / Maximize",
			"  [Space]        Peek changed files (Esc closes)",
			"  [F4]           Git actions (fetch, pull, rebase)",
			"  [a]            Toggle Mode (🌿 Current Branch <-> 🌐 --all)",
			"  [b]            Branch Filter (choose which branches to show)",
			"  [L]            Colour Legend (branch -> colour)",
			"  [t]            Toggle Commit Order (--topo-order <-> --date-order)",
			"  [m]            Toggle Lane Spacers (dimmed <-> hidden)",
			"  [d / <C-d>]    Half-Page Down (Fetches on the fly)",
			"  [u / <C-u>]    Half-Page Up",
			"  [j / k]        Move down / up 1 commit (Auto-fetches)",
			"  [G / gg]       Jump to Bottom (Fetch all) / Jump to Top",
			"  [<C-h> / <C-l>] Focus Left Graph / Right Details pane",
			"  [<C-k> / <C-j>] Scroll Details preview Up / Down",
			"  [Tab/S-Tab]    Open details / Dismiss details; Shift+Tab on graph exits logs",
			"  [<CR> / Enter] Open Git Log Diff 4-Panel Dashboard",
			"  [y]            Yank commit SHA to clipboard",
			"  [K]            Checkout selected commit",
			"  [D]            Open full-screen side-by-side diff modal",
			"  [r / <F5>]     Refresh graph from git",
			"  [< / >]        Resize split width",
			"  [q / <Esc>]    Close Commit Graph Viewer",
			" ──────────────────────────────────────────────────────────",
			"  Press any key to dismiss",
		}
		ui.float({
			title = " ❓ Help: GitKraken Graph Viewer ",
			lines = help_lines,
			width = 0.58,
			height = #help_lines + 2,
			zindex = graph_z + 20,
			close_on_keys = { "q", "<Esc>", "<CR>", "<Space>" },
		})
	end

	-- Autocmds
	local augroup = vim.api.nvim_create_augroup("FoxGitKrakenGraph", { clear = true })

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = left_buf,
		callback = function()
			vim.schedule(function()
				if is_closed or not (left_win and vim.api.nvim_win_is_valid(left_win)) then
					return
				end
				local cur = vim.api.nvim_win_get_cursor(left_win)
				local row = cur[1]
				local line_count = vim.api.nvim_buf_line_count(left_buf)

				if line_count > 0 and row >= (line_count - 10) and not all_fetched and not is_fetching then
					fetch_more(nil)
				end

				update_commit_details(nil)
			end)
		end,
	})

	vim.api.nvim_create_autocmd("CursorMoved", {
		group = augroup,
		buffer = right_buf,
		callback = function()
			vim.schedule(on_right_cursor_moved)
		end,
	})

	-- Keybindings
	local opts = { buffer = left_buf, noremap = true, silent = true, nowait = true }
	local right_opts = { buffer = right_buf, noremap = true, silent = true, nowait = true }

	-- Vim motions: d, u, Ctrl+d, Ctrl+u
	vim.keymap.set("n", "d", half_page_down, opts)
	vim.keymap.set("n", "<C-d>", half_page_down, opts)
	vim.keymap.set("n", "u", half_page_up, opts)
	vim.keymap.set("n", "<C-u>", half_page_up, opts)

	-- Single line motion with auto background fetch
	vim.keymap.set("n", "j", move_down, opts)
	vim.keymap.set("n", "<Down>", move_down, opts)
	vim.keymap.set("n", "k", move_up, opts)
	vim.keymap.set("n", "<Up>", move_up, opts)

	-- Jumps
	vim.keymap.set("n", "G", jump_bottom, opts)
	vim.keymap.set("n", "gg", jump_top, opts)

	-- Mode toggle: 'a'
	vim.keymap.set("n", "a", toggle_mode, opts)

	-- Multi-branch clarity: filter branches, legend, order, lane spacers
	vim.keymap.set("n", "b", open_branch_filter, opts)
	vim.keymap.set("n", "L", open_legend, opts)
	vim.keymap.set("n", "t", toggle_order, opts)
	vim.keymap.set("n", "m", toggle_connectors, opts)

	-- Panel navigation: <C-h> / <C-l>
	for _, key in ipairs({ "<C-h>", "<C-H>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_left, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_left, right_opts)
	end
	for _, key in ipairs({ "<C-l>", "<C-L>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_right, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, focus_right, right_opts)
	end

	-- Scroll trap for <C-j> / <C-k> to prevent escaping to other windows / neo-tree
	for _, key in ipairs({ "<C-j>", "<C-J>", "<C-S-j>", "<C-S-J>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_right_preview("down")
		end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_right_preview("down")
		end, right_opts)
	end
	for _, key in ipairs({ "<C-k>", "<C-K>", "<C-S-k>", "<C-S-K>" }) do
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_right_preview("up")
		end, opts)
		vim.keymap.set({ "n", "v", "i", "t" }, key, function()
			scroll_right_preview("up")
		end, right_opts)
	end

	-- Focus & Details navigation
	vim.keymap.set("n", "<CR>", open_log_diff_dashboard, opts)
	vim.keymap.set("n", "<CR>", function()
		local cursor_line = vim.api.nvim_win_get_cursor(right_win)[1]
		local line_text = vim.api.nvim_buf_get_lines(right_buf, cursor_line - 1, cursor_line, false)[1] or ""
		local filepath = line_text:match("•%s*%[[A-Z%d]+%]%s+(.+)$") or line_text:match("•%s*(.+)$")
		if filepath then
			filepath = filepath:gsub("^%s*", ""):gsub("%s*$", "")
			local row = vim.api.nvim_win_get_cursor(left_win)[1]
			local commit = get_commit_at_row(row)
			local modals = require("plugins.fox.git.git_center.modals")
			modals.open_diff_modal(filepath, "commit", active_cwd, commit and commit.full_hash)
			return
		end
		open_log_diff_dashboard()
	end, right_opts)

	-- Actions
	vim.keymap.set("n", "y", yank_sha, opts)
	vim.keymap.set("n", "K", checkout_commit, opts)
	vim.keymap.set("n", "D", open_full_diff, opts)
	vim.keymap.set("n", "?", show_help_modal, opts)
	vim.keymap.set("n", "?", show_help_modal, right_opts)

	-- Split resizing
	vim.keymap.set("n", "<", function()
		resize_split(-0.03)
	end, opts)
	vim.keymap.set("n", ">", function()
		resize_split(0.03)
	end, opts)
	vim.keymap.set("n", "<", function()
		resize_split(-0.03)
	end, right_opts)
	vim.keymap.set("n", ">", function()
		resize_split(0.03)
	end, right_opts)

	-- Refresh
	vim.keymap.set("n", "r", function()
		current_limit = 50
		all_fetched = false
		fetch_more(1)
		config.notify("🔄 Commit Graph Refreshed")
	end, opts)
	vim.keymap.set("n", "<F5>", function()
		current_limit = 50
		all_fetched = false
		fetch_more(1)
		config.notify("🔄 Commit Graph Refreshed")
	end, opts)

	-- Close
	local close_keys = { "q", "<Esc>", "<esc>", "<ESC>", "<C-[>", "<C-c>" }
	for _, k in ipairs(close_keys) do
		vim.keymap.set("n", k, function()
			close_viewer(false)
		end, opts)
		vim.keymap.set("n", k, function()
			close_viewer(false)
		end, right_opts)
	end

	local peek_cache = {}
	local peek_win
	local function peek_files()
		if peek_win and vim.api.nvim_win_is_valid(peek_win) then
			ui.close(peek_win)
			return
		end
		local row = vim.api.nvim_win_get_cursor(left_win)[1]
		local hash = line_commits[row]
		if not hash then
			local commit = get_commit_at_row(row)
			hash = commit and commit.full_hash
		end
		if not hash then
			return
		end
		local lines = peek_cache[hash] or { "Loading changed files..." }
		local buf
		buf, peek_win = ui.float({
			lines = lines,
			width = 0.9,
			height = 0.7,
			title = " Changed files: " .. hash:sub(1, 7) .. " (Space/Esc: close) ",
			zindex = graph_z + 20,
			close_on_keys = { "<Space>", "<Esc>", "q" },
		})
		vim.wo[peek_win].wrap = false
		if peek_cache[hash] then
			return
		end
		-- No patches or file contents: one asynchronous query, then cache by immutable SHA.
		queries.git_run(
			{ "show", "--format=", "--root", "--first-parent", "--find-renames", "--raw", "--numstat", hash, "--" },
			function(ok, output)
				local result = ok and M.format_file_peek(output) or vim.split(output, "\n", { trimempty = true })
				if not ok then
					table.insert(result, 1, "Could not load changed files:")
				end
				if ok then
					peek_cache[hash] = result
				end
				if not is_closed and vim.api.nvim_buf_is_valid(buf) then
					vim.bo[buf].modifiable = true
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, result)
					vim.bo[buf].modifiable = false
				end
			end,
			active_cwd
		)
	end
	config.graph_peek = peek_files
	vim.keymap.set("n", "<Space>", peek_files, opts)
	for _, map_opts in ipairs({ opts, right_opts }) do
		vim.keymap.set("n", "<F4>", function()
			require("plugins.fox.git.git_center.actions").open(active_cwd)
		end, map_opts)
	end
	layout = require("plugins.fox.git.git_center.layout").new(left_win, right_win, {
		mode = "browse",
		ratio = function()
			return config.current_left_ratio or ratio
		end,
		changed = function()
			canvas_mode = layout.mode == "browse"
			update_window_title(false)
			update_commit_details(current_target_file)
		end,
	})
	config.graph_layout = layout
	vim.keymap.set({ "n", "v", "i", "t" }, "<S-Tab>", function()
		close_viewer(false)
	end, opts)
	config.graph_refresh = function()
		if not is_closed then
			commit_cache = {}
			reload()
		end
	end
	local function leave_details()
		if layout.mode == "details" then
			layout.expand()
		else
			close_viewer(false)
		end
	end
	for _, key in ipairs({ "<Esc>", "q" }) do
		vim.keymap.set("n", key, leave_details, right_opts)
	end
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(left_win),
		once = true,
		callback = function()
			ui.close(peek_win)
		end,
	})
	layout.apply()
end

return M
