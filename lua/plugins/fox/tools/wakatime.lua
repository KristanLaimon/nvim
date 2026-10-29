local M = {}
local token
local buf, win
local loading = false

local function duration(seconds)
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
end

local function seconds(value)
	assert(type(value) == "number" and value >= 0 and value < math.huge, "Invalid duration")
	return value
end

local function label(value)
	assert(type(value) == "string", "Invalid label")
	return value:gsub("[%c]", " ")
end

function M.render(response)
	assert(type(response) == "table" and vim.islist(response.data), "Invalid summaries")
	local days, languages, projects = {}, {}, {}
	local total = 0
	for _, day in ipairs(response.data) do
		local amount = seconds(day.grand_total.total_seconds)
		total = total + amount
		table.insert(days, { name = label(day.range.date), total_seconds = amount })
		for field, totals in pairs({ languages = languages, projects = projects }) do
			assert(day[field] == nil or vim.islist(day[field]), "Invalid breakdown")
			for _, item in ipairs(day[field] or {}) do
				local name = label(item.name)
				totals[name] = (totals[name] or 0) + seconds(item.total_seconds)
			end
		end
	end
	local lines = {
		"  +------------------------------------------+",
		"  |             W A K A T I M E              |",
		"  +------------------------------------------+",
		"  Last 7 days (including today; account timezone)",
		"  Total: " .. duration(total) .. "    Daily average: " .. duration(total / math.max(#days, 1)),
		"",
	}
	local function chart(title, entries)
		table.insert(lines, "  " .. title)
		local maximum = 0
		for _, entry in ipairs(entries) do
			maximum = math.max(maximum, entry.total_seconds)
		end
		for i = 1, math.min(#entries, 8) do
			local entry = entries[i]
			local count = maximum > 0 and math.floor(entry.total_seconds / maximum * 24 + 0.5) or 0
			local name = vim.fn.strcharpart(entry.name, 0, 20)
			local padding = string.rep(" ", math.max(0, 20 - vim.fn.strdisplaywidth(name)))
			table.insert(
				lines,
				"  "
					.. name
					.. padding
					.. " |"
					.. string.rep("#", count)
					.. string.rep(" ", 24 - count)
					.. "| "
					.. duration(entry.total_seconds)
			)
		end
		if #entries == 0 then
			table.insert(lines, "  No activity recorded.")
		end
		table.insert(lines, "")
	end
	chart("DAILY ACTIVITY (bars relative to busiest day)", days)
	for _, group in ipairs({ { "LANGUAGES (top 8)", languages }, { "PROJECTS (top 8)", projects } }) do
		local entries = {}
		for name, amount in pairs(group[2]) do
			table.insert(entries, { name = name, total_seconds = amount })
		end
		table.sort(entries, function(a, b)
			return a.total_seconds > b.total_seconds or (a.total_seconds == b.total_seconds and a.name < b.name)
		end)
		chart(group[1], entries)
	end
	if response.daily_average and response.daily_average.days_including_holidays then
		-- The API can return only the history available on the account's plan.
		table.insert(lines, "  Showing " .. #days .. " returned days; history depends on your WakaTime plan.")
	end
	return lines
end

local function write(lines)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
	end
end

function M.set_token()
	local ok, value = pcall(vim.fn.inputsecret, "WakaTime OAuth token (session only): ")
	vim.cmd("redraw")
	if ok and value ~= "" then
		if value:find("[%s%c]") then
			vim.notify("WakaTime: token must not contain whitespace.", vim.log.levels.ERROR)
			return false
		end
		token = value
		return true
	end
	return false
end

function M.refresh()
	if loading then
		return
	end
	local secret = token or vim.env.WAKATIME_ACCESS_TOKEN
	if not secret or secret == "" or secret:find("[%s%c]") then
		write({
			"  Get a personal OAuth token with read_summaries at https://wakatime.com/oauth",
			"  Press t to enter it, then r to refresh. Tracking uses :WakaTimeApiKey separately.",
		})
		return
	end
	if vim.fn.executable("curl") ~= 1 then
		write({ "  WakaTime stats requires curl on PATH." })
		return
	end
	loading = true
	write({ "  Loading WakaTime stats..." })
	-- Pass the token through stdin so it never appears in process arguments or URLs.
	local ok = pcall(vim.system, {
		"curl",
		"--disable",
		"--silent",
		"--show-error",
		"--connect-timeout",
		"10",
		"--max-time",
		"25",
		"--header",
		"@-",
		"--write-out",
		"\n%{http_code}",
		"https://api.wakatime.com/api/v1/users/current/summaries?range=Last%207%20Days",
	}, { text = true, stdin = "Authorization: Bearer " .. secret .. "\n" }, function(result)
		vim.schedule(function()
			loading = false
			if result.code ~= 0 then
				write({ "  Cannot reach WakaTime. Check your network and retry with r." })
				return
			end
			local body, status = (result.stdout or ""):match("^(.*)\n(%d%d%d)%s*$")
			if status ~= "200" then
				local message = ({
					["401"] = "Token rejected. Press t to replace your OAuth token, then r.",
					["403"] = "Access denied. Your OAuth token needs read_summaries permission.",
					["429"] = "Rate limited. Wait a minute, then press r.",
				})[status] or ("WakaTime returned HTTP " .. (status or "unknown") .. ". Try r later.")
				write({ "  " .. message })
				return
			end
			local parsed, lines = pcall(function()
				return M.render(vim.json.decode(body))
			end)
			write(parsed and lines or { "  Invalid WakaTime response. Try r later." })
		end)
	end)
	if not ok then
		loading = false
		write({ "  Could not start curl. Check your installation." })
	end
end

function M.open()
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
		return
	end
	local ui = require("fox.core.ui")
	buf, win = ui.float({
		title = " WakaTime | r refresh | t token | q/Esc close ",
		width = math.max(1, math.min(82, vim.o.columns - 4)),
		height = math.max(1, math.min(38, vim.o.lines - 4)),
		lines = { "  Loading..." },
	})
	vim.wo[win].wrap = false
	ui.close_on_keys(buf, win)
	vim.keymap.set("n", "r", M.refresh, { buffer = buf, silent = true })
	vim.keymap.set("n", "t", function()
		if M.set_token() then
			M.refresh()
		end
	end, { buffer = buf, silent = true })
	M.refresh()
end

return setmetatable({
	name = "fox_wakatime_stats",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = { "WakaTimeStats", "WakaTimeStatsToken" },
	config = function()
		vim.api.nvim_create_user_command("WakaTimeStats", M.open, { desc = "WakaTime ASCII stats dashboard" })
		vim.api.nvim_create_user_command(
			"WakaTimeStatsToken",
			M.set_token,
			{ desc = "Set WakaTime stats OAuth token for this session" }
		)
	end,
}, { __index = M })
