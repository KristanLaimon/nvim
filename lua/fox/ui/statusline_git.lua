-- Cached Git metadata. No filesystem or process waits during statusline evaluation.
local M = {}
local cache, pending = {}, {}
local clock = function()
	return vim.uv.now()
end
local diff_state, diff_cache
local function cancel_diff()
	if diff_state and diff_state.job then
		pcall(diff_state.job.kill, diff_state.job, 15)
	end
	diff_state = nil
end
local function cancel_branch()
	for dir, state in pairs(pending) do
		pending[dir] = nil
		if state.job then
			pcall(state.job.kill, state.job, 15)
		end
	end
end
function M.cancel()
	cancel_branch()
	cancel_diff()
end
function M.invalidate()
	M.cancel()
	diff_cache = nil
	cache = {}
end
function M.branch(dir)
	local entry = cache[dir]
	if not pending[dir] and (not entry or clock() - entry.time > 2000) then
		-- Only the current directory needs refreshing; don't accumulate jobs on navigation.
		cancel_branch()
		local state = {}
		pending[dir] = state
		local function finish(value)
			if pending[dir] ~= state then
				return
			end
			pending[dir] = nil
			cache[dir] = { value = value, time = clock() }
			vim.cmd.redrawstatus()
		end
		local function run(args, callback)
			local ok, job = pcall(
				vim.system,
				require("fox.git.cmd").build(args, dir),
				{ text = true, timeout = 1500 },
				vim.schedule_wrap(function(result)
					if pending[dir] == state then
						callback(result)
					end
				end)
			)
			if ok then
				state.job = job
			else
				finish("")
			end
		end
		run({ "symbolic-ref", "--quiet", "--short", "HEAD" }, function(result)
			if result.code == 0 then
				finish(vim.trim(result.stdout or ""))
			else
				run({ "rev-parse", "--short", "HEAD" }, function(detached)
					finish(detached.code == 0 and vim.trim(detached.stdout or "") or "")
				end)
			end
		end)
	end
	return entry and entry.value or ""
end
function M.parse_diff(output)
	local counts = { added = 0, changed = 0, removed = 0 }
	for _, oldcount, _, newcount in output:gmatch("@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@") do
		local deleted = oldcount == "" and 1 or tonumber(oldcount)
		local added = newcount == "" and 1 or tonumber(newcount)
		local common = math.min(deleted, added)
		counts.changed = counts.changed + common
		counts.added = counts.added + added - common
		counts.removed = counts.removed + deleted - common
	end
	return counts
end
function M.diff()
	local filename = vim.api.nvim_buf_get_name(0)
	if filename == "" or vim.bo.buftype ~= "" then
		return {}
	end
	local entry = diff_cache and diff_cache.filename == filename and diff_cache or nil
	if diff_state and diff_state.filename ~= filename then
		cancel_diff()
	end
	if not diff_state and (not entry or clock() - entry.time > 2000) then
		local state = { filename = filename }
		diff_state = state
		local ok, job = pcall(
			vim.system,
			require("fox.git.cmd").build(
				{ "--no-pager", "diff", "--no-ext-diff", "--no-textconv", "--no-color", "-U0", "--", vim.fs.basename(filename) },
				vim.fs.dirname(filename)
			),
			{ text = true, timeout = 1500 },
			vim.schedule_wrap(function(result)
				if diff_state ~= state then
					return
				end
				diff_state = nil
				diff_cache =
					{ filename = filename, time = clock(), value = result.code == 0 and M.parse_diff(result.stdout or "") or {} }
				vim.cmd.redrawstatus()
			end)
		)
		if ok then
			state.job = job
		else
			diff_state = nil
			diff_cache = { filename = filename, time = clock(), value = {} }
		end
	end
	return entry and entry.value or {}
end
return M
