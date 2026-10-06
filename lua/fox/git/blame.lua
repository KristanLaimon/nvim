-- ============================================================================
-- fox.git.blame -- Per-line authorship for a file at a given revision.
-- ============================================================================
-- WHAT IT DOES
--   Wraps `git blame --line-porcelain` and turns it into the simple shape the
--   diff dashboards need: a table mapping every final line number to the name
--   of the author who last touched it.
--
-- WHY LINE-PORCELAIN
--   The header line `<sha> <orig> <final> [<group>]` is printed for *every*
--   line, while the author metadata is printed only once per commit block.
--   That lets a single pass remember the current commit's author and attach it
--   to each following line without a second git call.
-- ============================================================================

local M = {}

--- Parses `git blame --line-porcelain` output.
--- @param lines string[]
--- @return table<integer, string> authors_by_line
function M.parse_porcelain(lines)
	local authors = {}
	local commit_authors = {}
	local cur_sha, cur_final, cur_author

	for _, line in ipairs(lines) do
		local sha, final_line = line:match("^(%x+) %d+ (%d+)")
		if sha then
			cur_sha = sha
			cur_final = tonumber(final_line)
			cur_author = commit_authors[sha] or cur_author
			if cur_final and cur_author then
				authors[cur_final] = cur_author
			end
		elseif line:sub(1, 7) == "author " then
			cur_author = line:sub(8)
			if cur_sha then
				commit_authors[cur_sha] = cur_author
			end
			if cur_final then
				authors[cur_final] = cur_author
			end
		end
	end

	return authors
end

--- Queries per-line authors for `file` at `rev`.
--- @param file string Path relative to the repository.
--- @param rev string|nil Revision/branch; nil or "WORKTREE" blames the working tree.
--- @param cwd string|nil Repository directory.
--- @return table<integer, string> authors_by_line
function M.query(file, rev, cwd)
	local git = require("fox.git.cmd")
	local args = { "blame", "--line-porcelain" }
	if rev and rev ~= "" and rev ~= "WORKTREE" then
		table.insert(args, rev)
	end
	table.insert(args, "--")
	table.insert(args, file)
	return M.parse_porcelain(git.lines(args, cwd))
end

return M
