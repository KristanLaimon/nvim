local t = require("fox.lib.foxnvim.test")
local stats = require("plugins.fox.tools.wakatime")

local function day(date, amount, name)
	return {
		range = { date = date },
		grand_total = { total_seconds = amount },
		languages = { { name = name or "Lua", total_seconds = amount } },
		projects = { { name = "FoxVim", total_seconds = amount } },
	}
end

t.describe("WakaTime stats", function()
	t.it("totals days and aggregates languages and projects into ASCII charts", function()
		local lines = stats.render({ data = { day("2026-10-28", 3600), day("2026-10-29", 1800) } })
		local text = table.concat(lines, "\n")
		t.expect(text:find("Total: 1h 30m    Daily average: 0h 45m", 1, true) ~= nil).toBe(true)
		t.expect(text:find(string.rep("#", 24), 1, true) ~= nil).toBe(true)
		t.expect(text:find(string.rep("#", 12) .. string.rep(" ", 12), 1, true) ~= nil).toBe(true)
		t.expect(text:find("Lua                  |" .. string.rep("#", 24) .. "| 1h 30m", 1, true) ~= nil).toBe(true)
		t.expect(text:find("FoxVim", 1, true) ~= nil).toBe(true)
	end)

	t.it("handles empty and zero activity without dividing by zero", function()
		t.expect(table.concat(stats.render({ data = {} }), "\n"):find("No activity recorded.", 1, true) ~= nil).toBe(true)
		t.expect(table.concat(stats.render({ data = { day("2026-10-29", 0) } }), "\n"):find("#", 1, true)).toBe(nil)
	end)

	t.it("sanitizes control characters and rejects malformed API data", function()
		local lines = stats.render({ data = { day("2026-10-29", 1, "Lua\nInjected") } })
		for _, line in ipairs(lines) do
			t.expect(line:find("\n", 1, true)).toBe(nil)
		end
		for _, response in ipairs({ {}, { data = "bad" }, { data = { day("date", -1) } }, { data = { {} } } }) do
			local ok = pcall(stats.render, response)
			t.expect(ok).toBe(false)
		end
	end)

	t.it("fetches asynchronously with a token on stdin and handles HTTP, JSON and network failures", function()
		local saved_system, saved_token = vim.system, vim.env.WAKATIME_ACCESS_TOKEN
		local saved_executable = vim.fn.executable
		local callback
		vim.env.WAKATIME_ACCESS_TOKEN = "test-secret"
		vim.fn.executable = function()
			return 1
		end
		local ok, err = pcall(function()
			vim.system = function(args, opts, done)
				t.expect(table.concat(args, " "):find("test-secret", 1, true)).toBe(nil)
				t.expect(opts.stdin).toBe("Authorization: Bearer test-secret\n")
				callback = done
			end
			stats.open()
			local dashboard = vim.api.nvim_get_current_buf()
			local function respond(result, expected)
				callback(result)
				t.expect(vim.wait(1000, function()
					return table.concat(vim.api.nvim_buf_get_lines(dashboard, 0, -1, false), "\n"):find(expected, 1, true) ~= nil
				end, 10)).toBe(true)
			end
			respond(
				{ code = 0, stdout = vim.json.encode({ data = { day("2026-10-29", 3600) } }) .. "\n200" },
				"Total: 1h 00m"
			)
			for _, case in ipairs({
				{ { code = 0, stdout = "{}\n401" }, "Token rejected" },
				{ { code = 0, stdout = "{}\n403" }, "read_summaries" },
				{ { code = 0, stdout = "{}\n429" }, "Rate limited" },
				{ { code = 0, stdout = "bad\n200" }, "Invalid WakaTime response" },
				{ { code = 1 }, "Cannot reach WakaTime" },
			}) do
				stats.refresh()
				respond(case[1], case[2])
			end
			stats.refresh()
			vim.api.nvim_win_close(0, true)
			callback({ code = 1 })
			local drained = false
			vim.schedule(function()
				drained = true
			end)
			t.expect(vim.wait(1000, function()
				return drained
			end, 10)).toBe(true)
		end)
		vim.system, vim.env.WAKATIME_ACCESS_TOKEN = saved_system, saved_token
		vim.fn.executable = saved_executable
		if not ok then
			error(err)
		end
	end)
end)
