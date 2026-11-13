local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local actions = require("plugins.fox.git.git_center.actions")
local config = require("plugins.fox.git.git_center.config")
local git = require("fox.git.cmd")

describe("Git Center repository actions", function()
	local root, repo, remote, original_notify, original_refresh, original_graph_refresh
	local notices
	local function run(args, cwd)
		local result = vim.system(git.build(args, cwd or repo), { text = true }):wait()
		assert(result.code == 0, result.stderr)
		return vim.trim(result.stdout or "")
	end
	local function action(command, upstream)
		local count = #notices
		actions.run(command, repo, upstream)
		assert(
			vim.wait(10000, function()
				return #notices >= count + 2
			end, 10),
			"Git action timed out"
		)
		assert(notices[#notices]:find("completed", 1, true), notices[#notices])
	end
	beforeEach(function()
		root = vim.fn.tempname() .. "_actions"
		repo, remote = root .. "/work", root .. "/remote"
		vim.fn.mkdir(repo, "p")
		vim.fn.mkdir(remote, "p")
		run({ "init", "--bare" }, remote)
		run({ "init", "-b", "main" })
		run({ "config", "user.name", "Action Test" })
		run({ "config", "user.email", "actions@example.test" })
		run({ "commit", "--allow-empty", "-m", "base" })
		run({ "remote", "add", "origin", remote })
		run({ "push", "-u", "origin", "main" })
		original_notify, original_refresh, original_graph_refresh = config.notify, config.refresh, config.graph_refresh
		notices = {}
		config.notify = function(message)
			notices[#notices + 1] = message
		end
		config.refresh, config.graph_refresh = nil, nil
	end)
	afterEach(function()
		config.notify, config.refresh, config.graph_refresh = original_notify, original_refresh, original_graph_refresh
		vim.fn.delete(root, "rf")
	end)

	it("fetches and pulls a local remote using both pull strategies and refreshes views", function()
		local refreshed = 0
		config.refresh = function()
			refreshed = refreshed + 1
		end
		config.graph_refresh = function()
			refreshed = refreshed + 1
		end
		action("GitFetch")
		action("GitPull")
		action("GitPullRebase")
		expect(refreshed).toBe(6)
	end)

	it("rebases the current branch onto the chosen branch", function()
		run({ "checkout", "-b", "feature" })
		run({ "commit", "--allow-empty", "-m", "feature" })
		run({ "checkout", "main" })
		run({ "commit", "--allow-empty", "-m", "main update" })
		local base = run({ "rev-parse", "HEAD" })
		run({ "checkout", "feature" })
		action("GitRebase", "main")
		expect(run({ "rev-parse", "HEAD^" })).toBe(base)
		expect(run({ "branch", "--show-current" })).toBe("feature")
	end)

	it("reads real added and renamed files for the quick peek without patch output", function()
		local graph = require("plugins.fox.git.git_center.graph_viewer")
		vim.fn.writefile({ "one", "two" }, repo .. "/old.txt")
		run({ "add", "old.txt" })
		run({ "commit", "-m", "add file" })
		local function peek()
			return graph.format_file_peek(
				run({ "show", "--format=", "--root", "--first-parent", "--find-renames", "--raw", "--numstat", "HEAD", "--" })
			)
		end
		expect(peek()[1]).toContain("[A]  +2 -0  old.txt")
		run({ "mv", "old.txt", "new.txt" })
		run({ "commit", "-m", "rename" })
		expect(peek()[1]).toContain("[R100]  +0 -0  old.txt => new.txt")
	end)

	it("rejects upstream options and reports failed pulls without changing HEAD", function()
		local head = run({ "rev-parse", "HEAD" })
		actions.run("GitRebase", repo, "--abort")
		expect(notices[#notices]).toContain("not a Git option")
		run({ "branch", "--unset-upstream" })
		local count = #notices
		actions.run("GitPull", repo)
		assert(vim.wait(10000, function()
			return #notices >= count + 2
		end, 10))
		expect(notices[#notices]).toContain("failed")
		expect(run({ "rev-parse", "HEAD" })).toBe(head)
	end)

	it("continues and aborts interrupted rebases in the selected repository", function()
		vim.fn.writefile({ "base" }, repo .. "/conflict.txt")
		run({ "add", "conflict.txt" })
		run({ "commit", "-m", "shared file" })
		run({ "checkout", "-b", "feature" })
		vim.fn.writefile({ "feature" }, repo .. "/conflict.txt")
		run({ "commit", "-am", "feature edit" })
		local original = run({ "rev-parse", "HEAD" })
		run({ "checkout", "main" })
		vim.fn.writefile({ "main" }, repo .. "/conflict.txt")
		run({ "commit", "-am", "main edit" })
		local base = run({ "rev-parse", "HEAD" })
		run({ "checkout", "feature" })
		local function conflict()
			local count = #notices
			actions.run("GitRebase", repo, "main")
			assert(vim.wait(10000, function()
				return #notices >= count + 2
			end, 10))
			expect(notices[#notices]).toContain("failed")
		end
		conflict()
		action("GitRebaseAbort")
		expect(run({ "rev-parse", "HEAD" })).toBe(original)
		conflict()
		vim.fn.writefile({ "resolved" }, repo .. "/conflict.txt")
		run({ "add", "conflict.txt" })
		action("GitRebaseContinue")
		expect(run({ "rev-parse", "HEAD^" })).toBe(base)
		expect(run({ "branch", "--show-current" })).toBe("feature")
	end)
end)
