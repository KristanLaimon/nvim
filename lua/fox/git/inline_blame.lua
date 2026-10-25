-- Async inline blame, sharing FOX's Git argv builder (including WSL routing).
local M = { ns = vim.api.nvim_create_namespace("fox_inline_blame") }
local git = require("fox.git.cmd")
local options, enabled, states = {}, true, {}
M.parse = require("fox.git.blame").parse_line

local function cancel(buf)
	local state = states[buf]
	if state then
		state.cancelled = true
		if state.job then
			pcall(state.job.kill, state.job, 15)
		end
	end
	states[buf] = nil
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
	end
end
M.cancel = cancel
local function valid(state)
	return not state.cancelled
		and vim.api.nvim_buf_is_loaded(state.buf)
		and vim.api.nvim_buf_get_name(state.buf) == state.filename
		and vim.api.nvim_buf_get_changedtick(state.buf) == state.tick
end
function M.fetch(buf, row, callback)
	local state = { buf = buf, filename = vim.api.nvim_buf_get_name(buf), tick = vim.api.nvim_buf_get_changedtick(buf) }
	local cwd = vim.fs.dirname(state.filename)
	if not cwd or state.filename == "" or vim.bo[buf].buftype ~= "" then
		callback(nil, "No file to blame")
		return state
	end
	local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
	local function run(args, stdin, done)
		local ok, job = pcall(
			vim.system,
			git.build(args, cwd),
			{ text = true, stdin = stdin, timeout = 3000 },
			function(result)
				vim.schedule(function()
					if valid(state) then
						done(result)
					end
				end)
			end
		)
		if ok then
			state.job = job
		elseif valid(state) then
			callback(nil, tostring(job))
		end
	end
	run({ "rev-parse", "--show-prefix" }, nil, function(result)
		if result.code ~= 0 then
			callback(nil, result.stderr)
			return
		end
		local relative = vim.trim(result.stdout or "") .. vim.fs.basename(state.filename)
		run({ "check-ignore", "-q", "--", vim.fs.basename(state.filename) }, nil, function(ignored)
			if ignored.code == 0 then
				callback(nil)
				return
			end

			run(
				{
					"-c",
					"core.quotepath=false",
					"blame",
					"--line-porcelain",
					"--contents",
					"-",
					"-L",
					row .. "," .. row,
					"--",
					vim.fs.basename(state.filename),
				},
				content,
				function(blame)
					local info = blame.code == 0 and M.parse(blame.stdout or "") or nil
					if not info then
						local err = blame.stderr or ""
						if not err:match("no such path") and not err:match("no such ref") and not err:match("bad revision") then
							callback(nil, err ~= "" and err or "Git blame returned no metadata")
							return
						end
						info = { sha = string.rep("0", 40), line = row, original_line = row, author = "Not Committed Yet" }
					end
					if info.filename and not info.sha:match("^0+$") then
						local name = info.filename
						if name:sub(1, 1) == '"' then
							local ok, value = pcall(vim.json.decode, name)
							if ok then
								name = value
							end
						end
						relative = name
					end
					info.cwd, info.relative = cwd, relative

					callback(info, blame.code ~= 0 and blame.stderr or nil)
				end
			)
		end)
	end)
	return state
end
function M.relative_date(timestamp, now)
	local delta = math.max(0, (now or os.time()) - (timestamp or os.time()))
	for _, unit in ipairs({
		{ 31536000, "year" },
		{ 2592000, "month" },
		{ 86400, "day" },
		{ 3600, "hour" },
		{
			60,
			"minute",
		},
		{
			1,
			"second",
		},
	}) do
		if delta >= unit[1] then
			local n = math.floor(delta / unit[1])
			return n .. " " .. unit[2] .. (n ~= 1 and "s" or "") .. " ago"
		end
	end
	return "just now"
end
function M.message(info)
	if info.sha:match("^0+$") then
		return options.message_when_not_committed or "  Not Committed Yet"
	end
	local date = options.date_format == "%r" and M.relative_date(info.time)
		or os.date(options.date_format or "%Y-%m-%d", info.time)
	local values = { author = info.author or "", date = date, summary = info.summary or "", sha = info.sha:sub(1, 8) }
	return (options.message_template or "  <author>, <date> • <summary>"):gsub("<([%w_]+)>", function(key)
		return values[key] or ""
	end)
end
function M.refresh(buf)
	cancel(buf)
	if
		not enabled
		or buf ~= vim.api.nvim_get_current_buf()
		or vim.bo[buf].buftype ~= ""
		or vim.tbl_contains(options.ignored_filetypes or {}, vim.bo[buf].filetype)
	then
		return
	end
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local state
	state = M.fetch(buf, row, function(info)
		if
			states[buf] ~= state
			or buf ~= vim.api.nvim_get_current_buf()
			or vim.api.nvim_win_get_cursor(0)[1] ~= row
			or not info
		then
			return
		end
		state.info = info
		vim.api.nvim_buf_set_extmark(buf, M.ns, row - 1, 0, {
			id = 1,
			virt_text = { { M.message(info), options.highlight_group or "GitBlame" } },
			virt_text_pos = "eol",
			hl_mode = "combine",
		})
	end)
	states[buf] = state
end
local pending = {}
function M.schedule(buf)
	cancel(buf)
	local token = {}
	pending[buf] = token
	vim.defer_fn(function()
		if pending[buf] == token and vim.api.nvim_buf_is_loaded(buf) then
			pending[buf] = nil
			M.refresh(buf)
		end
	end, options.delay or 150)
end
local function encode(value, slash)
	return (
		value:gsub(slash and "[^%w_~./-]" or "[^%w_~.-]", function(c)
			return string.format("%%%02X", c:byte())
		end)
	)
end
function M.repo_url(remote)
	remote = vim.trim(remote):gsub("/+$", ""):gsub("%.git$", "")
	local org, project, repo = remote:match("ssh.dev.azure.com[:/]v%d+/([^/]+)/([^/]+)/(.+)")
	if org then
		return "https://dev.azure.com/" .. org .. "/" .. project .. "/_git/" .. repo, "azure"
	end
	local host, repo_path = remote:match("^ssh://[^@]+@([^/:]+):?%d*/(.+)")
	if not host then
		host, repo_path = remote:match("^[^@]+@([^:]+):(.+)")
	end
	if host then
		remote = "https://" .. host .. "/" .. repo_path
	end
	remote = remote:gsub("^(https?://)[^/@]+@", "%1")
	local domain = remote:match("^https?://([^/]+)")
	if not domain then
		return
	end
	local forge = (vim.g.gitblame_remote_domains or {})[domain]
		or ({
			["gitlab.com"] = "gitlab",
			["bitbucket.org"] = "bitbucket",
			["dev.azure.com"] = "azure",
			["git.sr.ht"] = "sourcehut",
			["codeberg.org"] = "forgejo",
		})[domain]
		or "github"
	return remote, forge
end
function M.url(remote, info, kind, first, last, ref)
	local base, forge = M.repo_url(remote)
	if not base then
		return
	end
	ref = ref or info.sha
	if kind == "commit" then
		if info.sha:match("^0+$") then
			return
		end
		return base
			.. (forge == "bitbucket" and "/commits/" or forge == "gitlab" and "/-/commit/" or forge == "azure" and "/commit/" or "/commit/")
			.. info.sha
	end
	local file = encode(info.relative, true)
	local anchor = "#L" .. first .. ((last and last ~= first) and "-L" .. last or "")
	if forge == "azure" then
		return base
			.. "?path="
			.. encode("/" .. info.relative, false)
			.. "&version=GC"
			.. encode(ref, false)
			.. "&line="
			.. first
			.. "&lineEnd="
			.. ((last or first) + 1)
			.. "&lineStartColumn=1&lineEndColumn=1"
	end
	if forge == "bitbucket" then
		anchor = "#lines-" .. first .. ((last and last ~= first) and ":" .. last or "")
	end
	if forge == "sourcehut" then
		anchor = "#L" .. first .. ((last and last ~= first) and "-" .. last or "")
	end
	local route = forge == "gitlab" and "/-/blob/"
		or forge == "bitbucket" and "/src/"
		or forge == "forgejo" and "/src/commit/"
		or forge == "sourcehut" and "/tree/"
		or "/blob/"
	return base .. route .. encode(ref, false) .. "/" .. file .. anchor
end
function M.action(kind, copy, args)
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	M.fetch(buf, row, function(info, err)
		if not info then
			vim.notify(err or "No Git blame available", vim.log.levels.WARN)
			return
		end
		local function output(value)
			if not value then
				vim.notify("No committed URL for this line or remote", vim.log.levels.WARN)
				return
			end
			if copy then
				vim.fn.setreg("+", value)
			else
				vim.ui.open(value)
			end
		end
		if kind == "sha" then
			if info.sha:match("^0+$") then
				vim.notify("Line is not committed", vim.log.levels.WARN)
			else
				output(info.sha)
			end
			return
		end
		local remote = vim.g.gitblame_remote_name or "origin"
		git.run({ "remote", "get-url", remote }, function(ok, remote_url)
			if not ok then
				vim.notify(remote_url, vim.log.levels.WARN)
				return
			end
			local function finish(ref)
				local first, last = info.original_line, info.original_line
				if args and args.range > 0 then
					first, last = args.line1, args.line2
				end
				output(M.url(remote_url, info, kind, first, last, ref))
			end
			if kind == "file" and info.sha:match("^0+$") then
				git.run({ "rev-parse", "HEAD" }, function(success, sha)
					if success then
						finish(sha)
					else
						vim.notify("Repository has no commit", vim.log.levels.WARN)
					end
				end, info.cwd)
			else
				finish()
			end
		end, info.cwd)
	end)
end
function M.set_enabled(value)
	enabled = value
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		pending[buf] = nil
		cancel(buf)
	end
	if enabled then
		M.schedule(vim.api.nvim_get_current_buf())
	end
end
function M.setup(opts)
	options = opts or {}
	enabled = options.enabled ~= false
	local group = vim.api.nvim_create_augroup("fox_inline_blame", { clear = true })
	local function highlights()
		vim.api.nvim_set_hl(0, "GitBlame", { link = "Comment", italic = true })
	end
	highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
	vim.api.nvim_create_autocmd(
		{ "CursorMoved", "BufEnter", "TextChanged", "TextChangedI", "BufWritePost", "FocusGained" },
		{
			group = group,
			callback = function(a)
				M.schedule(a.buf)
			end,
		}
	)
	vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout", "InsertEnter" }, {
		group = group,
		callback = function(a)
			pending[a.buf] = nil
			cancel(a.buf)
		end,
	})
	for command, callback in pairs({
		GitBlameToggle = function()
			M.set_enabled(not enabled)
		end,
		GitBlameEnable = function()
			M.set_enabled(true)
		end,
		GitBlameDisable = function()
			M.set_enabled(false)
		end,
	}) do
		vim.api.nvim_create_user_command(command, callback, { desc = "Control inline Git blame" })
	end
	for suffix, action in pairs({
		CopySHA = { "sha", true },
		OpenCommitURL = { "commit", false },
		CopyCommitURL = { "commit", true },
		OpenFileURL = { "file", false },
		CopyFileURL = { "file", true },
	}) do
		vim.api.nvim_create_user_command("GitBlame" .. suffix, function(a)
			M.action(action[1], action[2], a)
		end, { range = true, desc = "Git blame " .. suffix })
	end
	M.schedule(vim.api.nvim_get_current_buf())
end
return M
