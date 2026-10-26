local t = require("fox.lib.foxnvim.test")
t.describe("native notification integration", function()
	t.it("registers the local plugin, commands and compatibility API", function()
		require("lazy").load({ plugins = { "fox_notify" } })
		t.expect(require("lazy.core.config").plugins["nvim-notify"]).toBe(nil)
		t.expect(require("notify")).toBe(require("fox.core.notify"))
		for _, name in ipairs({ "Notifications", "NotificationsClear", "NotifyCopyLast", "NotifyDismiss", "ClearToasts" }) do
			t.expect(vim.fn.exists(":" .. name)).toBe(2)
		end
		require("notify").dismiss_all()
	end)
	t.it("opens notification history through the retained Telescope extension", function()
		require("lazy").load({ plugins = { "telescope.nvim" } })
		local notify = require("notify")
		notify("History picker check", 2, { timeout = false })
		require("telescope").load_extension("notify")
		require("telescope").extensions.notify.notify({})
		local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
		t.expect(picker.prompt_title).toBe("Notifications")
		require("telescope.actions").close(picker.prompt_bufnr)
		notify.dismiss_all()
	end)
	t.it("copies the clicked toast through the clipboard provider and closes it with real mouse input", function()
		local channel = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE" }, { rpc = true })
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local ok, err = pcall(function()
			call("nvim_ui_attach", 100, 35, { rgb = true })
			local initial = call(
				"nvim_exec_lua",
				[[
				local root = ...
				vim.opt.rtp:prepend(root)
				package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
				vim.o.mouse = 'a'
				vim.g.clipboard = {
					name = 'Notification test clipboard', cache_enabled = 0,
					copy = { ['+'] = function(lines, kind) _G.copied = {lines=lines,kind=kind} end, ['*'] = function() end },
					paste = { ['+'] = function() return {{},'v'} end, ['*'] = function() return {{},'v'} end },
				}
				local notify = require('fox.core.notify')
				notify.setup({stages='static', timeout=false, max_width=30,max_height=4})
				local text = 'Chosen notification\n\n' .. string.rep('🦊full text ',40)
				local first = notify(text,2,{title='First'})
				notify('Newest notification',3,{title='Second'})
				return {win=vim.api.nvim_get_current_win(), text=text, first=first.id}
			]],
				{ vim.fn.stdpath("config") }
			)
			t.expect(vim.wait(2000, function()
				return call("nvim_exec_lua", "return #require('notify').active_wins", {}) == 2
			end, 10)).toBe(true)
			local position = call(
				"nvim_exec_lua",
				[[
				local item = require('notify').active_wins[1]
				local cfg = vim.api.nvim_win_get_config(item.win)
				assert(cfg.focusable == false and cfg.mouse == true)
				return {row=math.floor(cfg.row)+1,col=math.floor(cfg.col)+2}
			]],
				{}
			)
			call("nvim_input_mouse", "left", "press", "", 0, position.row, position.col)
			call("nvim_input_mouse", "left", "release", "", 0, position.row, position.col)
			t.expect(vim.wait(2000, function()
				return call("nvim_exec_lua", "return _G.copied ~= nil", {})
			end, 10)).toBe(true)
			local result = call(
				"nvim_exec_lua",
				[[
				return {text=table.concat(_G.copied.lines,'\n'),kind=_G.copied.kind,win=vim.api.nvim_get_current_win(),active=#require('notify').active_wins,message=require('notify').active_wins[1].record.message[1]}
			]],
				{}
			)
			t.expect(result.text).toBe(initial.text)
			t.expect(result.kind).toBe("v")
			t.expect(result.win).toBe(initial.win)
			t.expect(result.active).toBe(1)
			t.expect(result.message).toBe("Newest notification")
			call("nvim_ui_try_resize", 35, 12)
			t.expect(vim.wait(1000, function()
				return call(
					"nvim_exec_lua",
					[[
					for _,item in ipairs(require('notify').active_wins) do
						local cfg=vim.api.nvim_win_get_config(item.win)
						if cfg.width>vim.o.columns-2 or cfg.height>vim.o.lines-3 then return false end
					end
					return true
				]],
					{}
				)
			end, 10)).toBe(true)
		end)
		vim.fn.jobstop(channel)
		assert(ok, err)
	end)
end)
