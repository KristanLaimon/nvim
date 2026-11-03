local t = require("fox.lib.foxnvim.test")

t.describe("WakaTime local tracking", function()
	t.it("throttles activity, records saves, and never attributes external edits to humans", function()
		local saved_system = vim.system
		local original = vim.api.nvim_get_current_buf()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".lua")
		local tracker = dofile(vim.fn.stdpath("config") .. "/lua/fox/wakatime/init.lua")
		tracker.cli = function()
			return "fake-wakatime-cli"
		end
		local calls = {}
		vim.system = function(args)
			table.insert(calls, args)
		end
		local ok, err = pcall(function()
			tracker.heartbeat(false)
			tracker.heartbeat(false)
			t.expect(#calls).toBe(1)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "AI line 1", "AI line 2", "AI line 3" })
			tracker.heartbeat(true)
			t.expect(#calls).toBe(2)
			local command = table.concat(calls[2], " ")
			t.expect(command:find("--write", 1, true) ~= nil).toBe(true)
			t.expect(command:find("--lines-in-file 3", 1, true) ~= nil).toBe(true)
			t.expect(command:find("--human-line-changes", 1, true)).toBe(nil)
			t.expect(command:find("--ai-line-changes", 1, true)).toBe(nil)
			vim.bo[buf].buftype = "nofile"
			tracker.heartbeat(true)
			t.expect(#calls).toBe(2)
		end)
		vim.system = saved_system
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)

	t.it("counts typed additions and deletions but excludes external edits", function()
		local tracker = dofile(vim.fn.stdpath("config") .. "/lua/fox/wakatime/init.lua")
		local saved_system = vim.system
		local original = vim.api.nvim_get_current_buf()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".lua")
		local calls = {}
		tracker.cli = function()
			return "fake-wakatime-cli"
		end
		vim.system = function(args, _, callback)
			table.insert(calls, args)
			if callback then
				callback({ code = 0 })
			end
		end
		local function manual_total()
			local total = 0
			for _, args in ipairs(calls) do
				for i, arg in ipairs(args) do
					if arg == "--human-line-changes" then
						total = total + tonumber(args[i + 1])
					end
				end
			end
			return total
		end
		local ok, err = pcall(function()
			tracker.setup()
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ohello<Esc>", true, false, true), "xt", false)
			t.expect(vim.api.nvim_buf_line_count(buf)).toBe(2)
			tracker.heartbeat(true)
			t.expect(manual_total()).toBe(1)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "external 1", "external 2", "external 3", "external 4" })
			tracker.heartbeat(true)
			t.expect(manual_total()).toBe(1)
			vim.api.nvim_feedkeys("dd", "xt", false)
			t.expect(vim.api.nvim_buf_line_count(buf)).toBe(3)
			tracker.heartbeat(true)
			t.expect(manual_total()).toBe(0)
		end)
		vim.api.nvim_exec_autocmds("VimLeavePre", { group = "FoxWakaTime" })
		vim.on_key(nil, vim.api.nvim_create_namespace("FoxWakaTimeInput"))
		vim.api.nvim_del_augroup_by_name("FoxWakaTime")
		vim.system = saved_system
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)

	t.it("syncs agent transcripts without an editor file and prevents overlapping syncs", function()
		local tracker = dofile(vim.fn.stdpath("config") .. "/lua/fox/wakatime/init.lua")
		tracker.cli = function()
			return "fake-wakatime-cli"
		end
		local saved_system = vim.system
		local calls, complete = {}, nil
		vim.system = function(args, _, callback)
			table.insert(calls, args)
			complete = callback
		end
		local ok, err = pcall(function()
			tracker.sync_ai()
			tracker.sync_ai()
			t.expect(#calls).toBe(1)
			local args = table.concat(calls[1], " ")
			t.expect(args:find("--sync-ai-activity", 1, true) ~= nil).toBe(true)
			t.expect(args:find("--sync-offline-activity 0", 1, true) ~= nil).toBe(true)
			t.expect(args:find("--entity", 1, true)).toBe(nil)
			complete({ code = 0 })
			tracker.sync_ai()
			t.expect(#calls).toBe(2)
		end)
		vim.system = saved_system
		assert(ok, err)
	end)

	t.it("saves a masked key without replacing privacy settings or other INI sections", function()
		local saved_home, saved_input = vim.env.WAKATIME_HOME, vim.fn.inputsecret
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		local path = directory .. "/.wakatime.cfg"
		vim.fn.writefile(
			{ "[settings]", "api_key = old", "hide_file_names = true", "[other]", "api_key = untouched" },
			path
		)
		vim.env.WAKATIME_HOME = directory
		vim.fn.inputsecret = function()
			return "12345678-1234-1234-1234-123456789abc"
		end
		local ok, err = pcall(function()
			require("fox.wakatime").set_api_key()
			local content = table.concat(vim.fn.readfile(path), "\n")
			t.expect(content:find("api_key = 12345678-1234-1234-1234-123456789abc", 1, true) ~= nil).toBe(true)
			t.expect(content:find("hide_file_names = true", 1, true) ~= nil).toBe(true)
			t.expect(content:find("api_key = untouched", 1, true) ~= nil).toBe(true)
			if vim.fn.has("win32") == 0 then
				t.expect(vim.fn.getfperm(path)).toBe("rw-------")
			end
		end)
		vim.env.WAKATIME_HOME, vim.fn.inputsecret = saved_home, saved_input
		vim.fn.delete(directory, "rf")
		assert(ok, err)
	end)
end)
