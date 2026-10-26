local t = require("fox.lib.foxnvim.test")
local notify = require("fox.core.notify")
t.describe("native notification queue", function()
	local old_notify, original
	t.beforeEach(function()
		old_notify = vim.notify
		original = vim.api.nvim_get_current_win()
		notify.setup({ timeout = false, stages = "static", fps = 100, max_height = 3, max_width = 35 })
		notify.clear_history()
	end)
	t.afterEach(function()
		notify.dismiss_all()
		notify.clear_history()
		vim.notify = old_notify
	end)
	local function open(count)
		t.expect(vim.wait(500, function()
			return #notify.active_wins == count
		end, 5)).toBe(true)
	end
	t.it("queues overflow without overlap or stealing focus, then drains pending messages", function()
		for i = 1, 12 do
			notify("Message " .. i)
		end
		vim.wait(30, function()
			return #notify.active_wins > 0
		end, 5)
		t.expect(#notify.pending() > 0).toBe(true)
		local last = 0
		for _, item in ipairs(notify.active_wins) do
			local cfg = vim.api.nvim_win_get_config(item.win)
			t.expect(cfg.row >= last).toBe(true)
			last = cfg.row + cfg.height + 2
			t.expect(cfg.focusable).toBe(false)
			t.expect(vim.bo[item.buf].buflisted).toBe(false)
			t.expect(vim.bo[item.buf].filetype).toBe("notify")
		end
		t.expect(vim.api.nvim_get_current_win()).toBe(original)
		local pending = #notify.pending()
		notify.close(notify.active_wins[1].record)
		t.expect(vim.wait(500, function()
			return #notify.pending() < pending
		end, 5)).toBe(true)
		notify.dismiss_all()
		t.expect(#notify.pending()).toBe(0)
		t.expect(#notify.active_wins).toBe(0)
		t.expect(#notify.history()).toBe(12)
	end)
	t.it("replaces a persistent toast in place and invalidates the old expiration", function()
		local first = notify("Before", "warn", { timeout = 25, title = "Progress" })
		open(1)
		local win, buf = notify.active_wins[1].win, notify.active_wins[1].buf
		local second = notify("After", nil, { replace = first, timeout = false })
		vim.wait(70, function()
			return false
		end, 5)
		t.expect(#notify.active_wins).toBe(1)
		t.expect(notify.active_wins[1].win).toBe(win)
		t.expect(notify.active_wins[1].buf).toBe(buf)
		t.expect(second.level).toBe("WARN")
		t.expect(second.title[1]).toBe("Progress")
		t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("After")
		notify(nil, "ERROR", { replace = first.id, timeout = 15 })
		t.expect(vim.wo[win].winhl).toContain("NotifyERRORBorder")
		t.expect(vim.wait(500, function()
			return #notify.active_wins == 0
		end, 5)).toBe(true)
	end)
	t.it("honors keep callbacks and closes windows and buffers exactly once", function()
		local keep, closed = true, 0
		notify("Hold", 2, {
			timeout = 10,
			keep = function()
				return keep
			end,
			on_close = function()
				closed = closed + 1
			end,
		})
		open(1)
		local win, buf = notify.active_wins[1].win, notify.active_wins[1].buf
		vim.wait(35, function()
			return false
		end, 5)
		t.expect(#notify.active_wins).toBe(1)
		keep = false
		t.expect(vim.wait(500, function()
			return #notify.active_wins == 0
		end, 5)).toBe(true)
		t.expect(vim.api.nvim_win_is_valid(win)).toBe(false)
		t.expect(vim.api.nvim_buf_is_valid(buf)).toBe(false)
		notify.dismiss_all()
		t.expect(closed).toBe(1)
	end)
	t.it("copies the chosen full message and closes it without copying the newest toast", function()
		local setreg, copied = vim.fn.setreg, {}
		vim.fn.setreg = function(reg, text, kind)
			copied = { reg, text, kind }
			return 0
		end
		local ok, err = pcall(function()
			local first = notify("Chosen\n\n" .. string.rep("🦊", 100), 2)
			notify("Newest", 2)
			open(2)
			t.expect(notify.copy(first, true)).toBe(true)
			t.expect(copied[1]).toBe("+")
			t.expect(copied[2]).toBe(table.concat(first.message, "\n"))
			t.expect(copied[3]).toBe("v")
			t.expect(#notify.active_wins).toBe(1)
			t.expect(notify.active_wins[1].record.message[1]).toBe("Newest")
		end)
		vim.fn.setreg = setreg
		assert(ok, err)
	end)
	t.it("keeps the message available when clipboard copying fails", function()
		local setreg = vim.fn.setreg
		vim.fn.setreg = function()
			error("clipboard unavailable")
		end
		local record = notify("Keep on failure")
		open(1)
		local ok, result = pcall(notify.copy, record, true)
		vim.fn.setreg = setreg
		assert(ok, result)
		t.expect(result).toBe(false)
		t.expect(#notify.active_wins).toBe(1)
	end)
	t.it("keeps hidden history private, returns copies and supports explicit clearing", function()
		notify("visible")
		notify("hidden", 2, { hide_from_history = true })
		t.expect(#notify.history()).toBe(1)
		t.expect(#notify.history({ include_hidden = true })).toBe(2)
		local records = notify.history()
		records[1].message[1] = "mutated"
		t.expect(notify.history()[1].message[1]).toBe("visible")
		notify.clear_history()
		t.expect(#notify.history()).toBe(0)
	end)
	t.it("updates, finishes and cancels the existing progress API without orphan floats", function()
		notify.notify_progress("download", "20%")
		open(1)
		local win = notify.active_wins[1].win
		notify.notify_progress("download", "80%")
		t.expect(notify.active_wins[1].win).toBe(win)
		notify.finish_progress("download", 10)
		t.expect(vim.wait(500, function()
			return #notify.active_wins == 0
		end, 5)).toBe(true)
		notify.notify_progress("download", "Again")
		open(1)
		notify.dismiss_progress("download")
		t.expect(#notify.active_wins).toBe(0)
	end)
	t.it("cleans up after a rendering error or an on_open callback closes the window", function()
		local closed = 0
		notify("Closed by callback", 2, {
			on_open = function(win)
				vim.api.nvim_win_close(win, true)
			end,
			on_close = function()
				closed = closed + 1
			end,
		})
		t.expect(vim.wait(500, function()
			return closed == 1
		end, 5)).toBe(true)
		t.expect(#notify.active_wins).toBe(0)
		notify("Still usable", 2)
		open(1)
		local win = notify.active_wins[1].win
		vim.api.nvim_win_close(win, true)
		t.expect(vim.wait(500, function()
			return #notify.active_wins == 0
		end, 5)).toBe(true)
		notify("After manual close", 2)
		open(1)
	end)
	t.it("animates desktop entry and exit while leaving editor focus unchanged", function()
		notify.setup({ stages = "fade_in_slide_out", timeout = 60, fps = 100, max_height = 3 })
		notify("Animated message")
		open(1)
		local item = notify.active_wins[1]
		local first = vim.api.nvim_win_get_config(item.win).col
		t.expect(vim.wait(300, function()
			return vim.api.nvim_win_is_valid(item.win) and vim.wo[item.win].winblend == 0
		end, 5)).toBe(true)
		t.expect(vim.api.nvim_win_get_config(item.win).col < first).toBe(true)
		t.expect(vim.api.nvim_get_current_win()).toBe(original)
		t.expect(vim.wait(600, function()
			return #notify.active_wins == 0
		end, 5)).toBe(true)
	end)
	t.it("animates explicit closes, allows replacement during exit and fires on_close once", function()
		notify.setup({ stages = "fade_in_slide_out", timeout = false, fps = 100, max_height = 3 })
		local closed = 0
		local record = notify("Close with motion", 2, {
			on_close = function()
				closed = closed + 1
			end,
		})
		open(1)
		local item = notify.active_wins[1]
		item.opened = vim.uv.hrtime() / 1e6 - 500
		notify._tick()
		local col = vim.api.nvim_win_get_position(item.win)[2]
		notify.close(record)
		t.expect(vim.api.nvim_win_is_valid(item.win)).toBe(true)
		t.expect(closed).toBe(0)
		item.exiting = vim.uv.hrtime() / 1e6 - 125
		notify._tick()
		t.expect(vim.api.nvim_win_get_position(item.win)[2] > col).toBe(true)
		local updated = notify("Keep visible", 2, { replace = record, timeout = false })
		notify._tick()
		t.expect(item.exiting).toBe(nil)
		t.expect(vim.api.nvim_win_get_position(item.win)[2]).toBe(col)
		notify.close(updated)
		item.exiting = vim.uv.hrtime() / 1e6 - 300
		notify._tick()
		t.expect(closed).toBe(1)
		t.expect(vim.api.nvim_win_is_valid(item.win)).toBe(false)
		notify.dismiss_all()
		t.expect(closed).toBe(1)
	end)
	t.it("slides dismissed toasts but keeps emergency cleanup and static closes immediate", function()
		notify.setup({ stages = "fade_in_slide_out", timeout = false })
		notify("Dismiss with motion")
		open(1)
		vim.cmd.NotifyDismiss()
		t.expect(#notify.active_wins).toBe(1)
		t.expect(notify.active_wins[1].exiting ~= nil).toBe(true)
		notify.dismiss_all()
		t.expect(#notify.active_wins).toBe(0)
		local record = notify("Disable animation", 2, { animate = false })
		open(1)
		notify.close(record)
		t.expect(#notify.active_wins).toBe(0)
	end)

	t.it("handles Unicode wrapping, blank lines and safe calls from fast events", function()
		local lines = notify.wrap({ "🦊α🦊", "", "third" }, 4)
		t.expect(lines[1]).toBe("🦊α")
		t.expect(lines[2]).toBe("🦊")
		t.expect(lines[3]).toBe("")
		local timer = vim.uv.new_timer()
		timer:start(0, 0, function()
			notify("From uv")
			timer:close()
		end)
		t.expect(vim.wait(500, function()
			return #notify.history() > 0
		end, 5)).toBe(true)
		t.expect(notify.history()[1].message[1]).toBe("From uv")
	end)
end)
