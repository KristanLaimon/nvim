local config = require("plugins.fox.git.git_center.config")
local queries = require("plugins.fox.git.git_center.queries")
local M = {}

M.commands = {
	{ command = "GitFetch", label = "Fetch", args = { "fetch" } },
	{ command = "GitPull", label = "Pull (configured strategy)", args = { "-c", "core.editor=true", "pull" } },
	{ command = "GitPullRebase", label = "Pull with Rebase", args = { "-c", "core.editor=true", "pull", "--rebase" } },
	{ command = "GitRebase", label = "Rebase Current Branch onto..." },
	{
		command = "GitRebaseContinue",
		label = "Continue Rebase",
		args = { "-c", "core.editor=true", "rebase", "--continue" },
	},
	{ command = "GitRebaseAbort", label = "Abort Rebase", args = { "rebase", "--abort" } },
}

function M.run(command, cwd, upstream, target)
	target = target or config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	local entry
	for _, item in ipairs(M.commands) do
		if item.command == command then
			entry = item
			break
		end
	end
	if not entry then
		return
	end
	if command == "GitRebase" and not upstream then
		local branches =
			queries.git_lines({ "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes" }, cwd, target)
		local branch = queries.git_lines({ "branch", "--show-current" }, cwd, target)[1] or "HEAD"
		vim.ui.select(branches, { prompt = "Rebase " .. branch .. " onto:" }, function(choice)
			if choice then
				M.run(command, cwd, choice, target)
			end
		end)
		return
	end
	if upstream and (upstream == "" or upstream:sub(1, 1) == "-" or upstream:find("[\r\n]")) then
		config.notify("Choose a branch or commit, not a Git option", vim.log.levels.ERROR)
		return
	end
	local args = entry.args or { "-c", "core.editor=true", "rebase", upstream }
	config.notify(entry.label .. "...")
	queries.git_run(args, function(ok, output)
		config.notify(
			entry.label .. (ok and " completed" or " failed") .. (output ~= "" and ("\n" .. output) or ""),
			ok and vim.log.levels.INFO or vim.log.levels.ERROR
		)
		if config.refresh then
			config.refresh(true)
		end
		if config.graph_refresh then
			config.graph_refresh()
		end
	end, cwd, target)
end

function M.open(cwd)
	local target = config.get_active_target()
	cwd = cwd or (target and target.full_path) or vim.fn.getcwd()
	vim.ui.select(M.commands, {
		prompt = "Git Actions (active repository):",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if choice then
			M.run(choice.command, cwd, nil, target)
		end
	end)
end

return M
