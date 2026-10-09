-- ============================================================================
-- FOX PLUGIN: Git Center -- Repository Queries & Actions
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local git = lazy_req("fox.git.cmd")
local status = lazy_req("fox.git.status")
local diff = lazy_req("fox.git.diff")
local path_util = lazy_req("fox.core.path")
local config = require("plugins.fox.git.git_center.config")

local M = {}

local env_ok, env_mod = pcall(require, "fox.core.environment")
local env = env_ok and env_mod.detect() or {}
local is_mobile_or_proot = env.is_termux or env.is_proot or env.is_mobile or (vim.env.TERMUX_VERSION ~= nil)

--- Runs git synchronously in the active repository target.
--- @param args string[] Arguments after `git`.
--- @param cwd string|nil
--- @return string[] output
function M.git_lines(args, cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	if target and target.is_secondary and target.repo_alias then
		local sec_ok, sec = pcall(require, "fox.git.secondary")
		if sec_ok and sec then
			return sec.lines(target.repo_alias, args, cwd)
		end
	end
	return git.lines(args, cwd)
end

--- Runs git asynchronously in the active repository target.
--- @param args string[] Arguments after `git`.
--- @param on_done function(ok, output)
--- @param cwd string|nil
function M.git_run(args, on_done, cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	if target and target.is_secondary and target.repo_alias then
		local sec_ok, sec = pcall(require, "fox.git.secondary")
		if sec_ok and sec then
			sec.run(target.repo_alias, args, on_done, cwd)
			return
		end
	end
	git.run(args, on_done, cwd)
end

--- Gets list of local branches.
--- @param cwd string|nil
--- @return table[] branches
function M.get_local_branches(cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	local raw = M.git_lines({ "branch", "--sort=-committerdate" }, cwd)
	local branches = {}
	for _, line in ipairs(raw) do
		local is_current = line:sub(1, 1) == "*"
		local name = line:gsub("^%*%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
		if name ~= "" and not name:match("HEAD detached") and not name:match("no branch") then
			table.insert(branches, { name = name, is_current = is_current })
		end
	end
	return branches
end

--- Gets recent commit history graph lines with ANSI colors, author and relative date for current branch.
--- @param cwd string|nil
--- @param limit integer|nil
--- @return string[] lines
function M.get_commit_graph(cwd, limit)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	limit = limit or 15
	return M.git_lines({
		"log",
		"--graph",
		"--color=always",
		"--pretty=format:%C(yellow)%h%C(reset)%C(auto)%d%C(reset) %C(cyan)%an%C(reset) %C(green)(%cr)%C(reset) %s",
		"-n",
		tostring(limit),
	}, cwd)
end

--- Gets recent commit history graph lines with ANSI colors, author and relative date across all branches.
--- @param cwd string|nil
--- @param limit integer|nil
--- @return string[] lines
function M.get_all_commit_graph(cwd, limit)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	limit = limit or 150
	return M.git_lines({
		"log",
		"--all",
		"--graph",
		"--color=always",
		"--pretty=format:%C(yellow)%h%C(reset)%C(auto)%d%C(reset) %C(cyan)%an%C(reset) %C(green)(%cr)%C(reset) %s",
		"-n",
		tostring(limit),
	}, cwd)
end

--- Snapshot of the repository at `cwd` (defaults to active submodule/root).
--- @param cwd string|nil Target repository directory.
--- @return table|nil info nil when the working directory is not a repository.
function M.get_git_info(cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	local is_sec = target and target.is_secondary and target.repo_alias
	local alias = is_sec and target.repo_alias or nil

	local status_handle = status.info_start(cwd, alias)
	if not status_handle then
		return nil
	end

	local branch_proc = git.spawn({ "branch", "--sort=-committerdate" }, cwd)
	local graph_proc = git.spawn({
		"log",
		"--graph",
		"--color=always",
		"--pretty=format:%C(yellow)%h%C(reset)%C(auto)%d%C(reset) %C(cyan)%an%C(reset) %C(green)(%cr)%C(reset) %s",
		"-n",
		"10",
	}, cwd)
	local stash_proc = git.spawn({ "stash", "list", "--pretty=format:%gd%x1f%s%x1f%gs" }, cwd)

	local info = status.info_finish(status_handle)
	if not info then
		return nil
	end

	local branch_lines = git.collect(branch_proc)
	local branches = {}
	for _, line in ipairs(branch_lines) do
		local is_current = line:sub(1, 1) == "*"
		local name = line:gsub("^%*%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
		if name ~= "" and not name:match("HEAD detached") and not name:match("no branch") then
			table.insert(branches, { name = name, is_current = is_current })
		end
	end
	info.local_branches = branches
	info.commit_graph = git.collect(graph_proc)

	local stash_lines = git.collect(stash_proc)
	local stashes = {}
	for _, line in ipairs(stash_lines) do
		local index, subject, gs = line:match("([^\31]+)\31([^\31]*)\31?(.*)")
		if index then
			local branch = gs:match("on ([^:]+)") or ""
			table.insert(stashes, { index = index, message = subject, branch = branch })
		end
	end
	info.stash_list = stashes

	return info
end

--- Gets the panel snapshot without blocking Neovim.  Network mounts and large
--- worktrees can make even `git status` take seconds; callers must therefore
--- render a cheap placeholder first and apply this result when it arrives.
---@param cwd string|nil
---@param on_done fun(info: table|nil)
function M.get_git_info_async(cwd, on_done)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	local is_sec = target and target.is_secondary and target.repo_alias

	local function argv(args)
		if is_sec then
			local sec_ok, sec = pcall(require, "fox.git.secondary")
			if sec_ok and sec then
				return sec.build_cmd_args(target.repo_alias, args, cwd)
			end
		end
		return git.build(args, cwd)
	end

	if not is_sec and not git.is_repository(cwd) then
		on_done(nil)
		return
	end

	local commands = {
		status = { "status", "--porcelain=v1", "-b", "--ignore-submodules=dirty" },
		numstat = { "diff", "--numstat", "--ignore-submodules=dirty" },
		numstat_cached = { "diff", "--cached", "--numstat", "--ignore-submodules=dirty" },
		branches = { "branch", "--sort=-committerdate" },
		graph = {
			"log", "--graph", "--color=always",
			"--pretty=format:%C(yellow)%h%C(reset)%C(auto)%d%C(reset) %C(cyan)%an%C(reset) %C(green)(%cr)%C(reset) %s",
			"-n", "10",
		},
		stash = { "stash", "list", "--pretty=format:%gd%x1f%s%x1f%gs" },
	}
	local results, remaining = {}, 0

	local function lines(result)
		return vim.split((result and result.stdout) or "", "[\r\n]+", { trimempty = true })
	end
	local function finish()
		local info = status.info_from_outputs(results.status or {}, results.numstat or {}, results.numstat_cached or {})
		local branches = {}
		for _, line in ipairs(results.branches or {}) do
			local is_current = line:sub(1, 1) == "*"
			local name = line:gsub("^%*%s*", ""):gsub("^%s*", ""):gsub("%s*$", "")
			if name ~= "" and not name:match("HEAD detached") and not name:match("no branch") then
				table.insert(branches, { name = name, is_current = is_current })
			end
		end
		info.local_branches = branches
		info.commit_graph = results.graph or {}
		info.stash_list = {}
		for _, line in ipairs(results.stash or {}) do
			local index, subject, gs = line:match("([^\31]+)\31([^\31]*)\31?(.*)")
			if index then
				table.insert(info.stash_list, { index = index, message = subject, branch = gs:match("on ([^:]+)") or "" })
			end
		end
		on_done(info)
	end

	for name, args in pairs(commands) do
		local command = argv(args)
		if command then
			remaining = remaining + 1
			vim.system(command, { text = true }, vim.schedule_wrap(function(result)
				results[name] = lines(result)
				remaining = remaining - 1
				if remaining == 0 then
					finish()
				end
			end))
		end
	end
	if remaining == 0 then
		on_done(nil)
	end
end

--- Raw diff lines for one file, or its contents when it is untracked.
--- @param file string Path relative to the repository.
--- @param file_type string "staged" | "unstaged" | "untracked" | "commit".
--- @param cwd string|nil Repository directory.
--- @param commit_hash string|nil Optional commit hash for commit diffs.
--- @return string[] lines
--- @return boolean is_untracked
function M.raw_diff_for(file, file_type, cwd, commit_hash)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()

	if diff.is_binary_file(file) then
		return {
			string.format("Binary files for %s differ (binary blacklist)", file),
			"[ Binary file: preview and diff analysis disabled ]",
		},
			false
	end

	if commit_hash or file_type == "commit" then
		local hash = commit_hash or (file_type ~= "commit" and file_type or nil)
		if hash then
			return git.lines({ "show", "--color=never", hash, "--", file }, cwd), false
		end
	end

	if target and target.is_secondary and target.repo_alias then
		local sec_ok, sec = pcall(require, "fox.git.secondary")
		if sec_ok and sec then
			if file_type == "staged" then
				return sec.lines(target.repo_alias, { "diff", "--cached", "--color=never", "--", file }, cwd), false
			end
			if file_type == "unstaged" then
				return sec.lines(target.repo_alias, { "diff", "--color=never", "--", file }, cwd), false
			end
		end
	end

	if file_type == "staged" then
		return git.lines({ "diff", "--cached", "--color=never", "--", file }, cwd), false
	end
	if file_type == "unstaged" then
		return git.lines({ "diff", "--color=never", "--", file }, cwd), false
	end

	local full_path = cwd and (cwd .. "/" .. file) or file
	if vim.fn.filereadable(full_path) == 1 then
		local max_lines = is_mobile_or_proot and 500 or 5000
		local ok_read, lines = pcall(vim.fn.readfile, full_path, "", max_lines)
		if ok_read and lines then
			for _, line in ipairs(lines) do
				if line:find("\0", 1, true) then
					return {
						string.format("Binary files for %s differ (binary content detected)", file),
						"[ Binary file: preview and diff analysis disabled ]",
					},
						false
				end
			end
			return lines, true
		end
		return { "[ Error reading file contents ]" }, true
	end
	return { "[ Empty or New File ]" }, true
end

--- Counts files with unstaged/untracked changes, without paying for the full
--- snapshot (branch list, commit graph, stash). Used by "stage all".
--- @param cwd string|nil Repository directory.
--- @return integer pending
function M.pending_count(cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()

	local raw
	if target and target.is_secondary and target.repo_alias then
		local sec_ok, sec = pcall(require, "fox.git.secondary")
		if sec_ok and sec then
			raw = sec.lines(target.repo_alias, { "status", "--porcelain=v1", "--ignore-submodules=dirty" }, cwd)
		end
	end
	if not raw then
		raw = git.lines({ "status", "--porcelain=v1", "--ignore-submodules=dirty" }, cwd)
	end

	local pending = 0
	for _, line in ipairs(raw) do
		if #line >= 3 then
			local index_state = line:sub(1, 1)
			local worktree_state = line:sub(2, 2)
			-- Same rule as status.parse_files: count unstaged and untracked,
			-- never a file that is only staged.
			if (index_state == "?" and worktree_state == "?") or (worktree_state ~= " " and worktree_state ~= "?") then
				pending = pending + 1
			end
		end
	end
	return pending
end

--- Stages every unstaged and untracked change without first doing a blocking
--- status scan.  `git add -A` already determines whether there is work, while
--- a separate `git status` doubles the delay on large worktrees.
--- Retries once after clearing a stale `index.lock`.
--- @param cwd string|nil Repository directory.
function M.stage_all_with_modal(cwd)
	cwd = cwd or (config.get_active_target() and config.get_active_target().full_path) or vim.fn.getcwd()
	git.clean_stale_lock(cwd)

	local target = config.get_active_target()
	local args = { "add", "-A" }
	if target and target.is_secondary then
		args = { "add", "-u" }
	end

	local function execute(is_retry)
		local run_fn = git.run
		if target and target.is_secondary and target.repo_alias then
			local sec_ok, sec = pcall(require, "fox.git.secondary")
			if sec_ok and sec then
				run_fn = function(cmd_args, cb, dir)
					sec.run(target.repo_alias, cmd_args, cb, dir)
				end
			end
		end

		run_fn(args, function(ok, output)
			if ok then
				config.notify(
					"✅ Stage all completed in " .. ((target and target.name) or "repository") .. "!",
					vim.log.levels.INFO,
					config.settings.control_title
				)
			elseif output:match("index%.lock") and not is_retry and git.clean_stale_lock(cwd) then
				execute(true)
				return
			else
				config.notify(
					"❌ Failed to stage changes:\n" .. (output ~= "" and output or "Error executing git add"),
					vim.log.levels.ERROR,
					config.settings.control_title
				)
			end

			local gc = package.loaded["plugins.fox.git.git_center"]
			if gc and gc.is_open and gc.is_open() and gc.refresh then
				gc.refresh()
			end
		end, cwd)
	end

	execute(false)
end

--- Gets the list of stash entries.
--- @param cwd string|nil
--- @return table[] stashes Each entry has { index, message, branch }
function M.get_stash_list(cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	local raw = M.git_lines({ "stash", "list", "--pretty=format:%gd%x1f%s%x1f%gs" }, cwd)
	local stashes = {}
	for _, line in ipairs(raw) do
		local index, subject, gs = line:match("([^\31]+)\31([^\31]*)\31?(.*)")
		if index then
			local branch = gs:match("on ([^:]+)") or ""
			table.insert(stashes, { index = index, message = subject, branch = branch })
		end
	end
	return stashes
end

--- Simulates merge of incoming_branch into target_branch without modifying CWD or index.
--- @param target_branch string|nil Defaults to active branch.
--- @param incoming_branch string
--- @param cwd string|nil
--- @return table result
function M.simulate_merge(target_branch, incoming_branch, cwd)
	local sim = require("fox.git.simulate")
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	return sim.simulate_merge(target_branch, incoming_branch, cwd)
end

--- Simulates rebase of topic_branch onto upstream_branch without modifying CWD or index.
--- @param upstream_branch string
--- @param topic_branch string|nil Defaults to active branch.
--- @param cwd string|nil
--- @return table result
function M.simulate_rebase(upstream_branch, topic_branch, cwd)
	local sim = require("fox.git.simulate")
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	return sim.simulate_rebase(upstream_branch, topic_branch, cwd)
end

return M
