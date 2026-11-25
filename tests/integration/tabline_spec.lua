local t = require("fox.lib.foxnvim.test")
local tabs = require("fox.ui.tabline")
t.describe("native tab bar integration", function()
	t.it("boots without bufferline, offsets Neo-tree, and retains the selected tab and workspace badge", function()
		require("lazy").load({ plugins = { "fox_tabline" } })
		t.expect(require("lazy.core.config").plugins["bufferline.nvim"]).toBe(nil)
		t.expect(package.loaded.bufferline).toBe(nil)
		t.expect(vim.o.tabline).toContain("fox.ui.tabline")
		local previous, width = vim.api.nvim_get_current_win(), vim.o.columns
		vim.o.columns = 160
		local buf = vim.api.nvim_create_buf(true, false)
		local file = vim.fn.tempname() .. "/native-tab.lua"
		vim.fn.mkdir(vim.fs.dirname(file), "p")
		vim.fn.writefile({ "test" }, file)
		vim.api.nvim_buf_set_name(buf, file)
		vim.api.nvim_win_set_buf(previous, buf)
		vim.cmd("topleft vnew")
		local side = vim.api.nvim_get_current_win()
		local sidebar = vim.api.nvim_get_current_buf()
		vim.bo[sidebar].buftype = "nofile"
		vim.bo[sidebar].filetype = "neo-tree"
		vim.api.nvim_win_set_width(side, 30)
		local ok, err = pcall(function()
			local text = vim.api.nvim_eval_statusline(tabs.render(), { use_tabline = true, maxwidth = 160 }).str
			t.expect(text:sub(1, #"🦊 Explorer")).toBe("🦊 Explorer")
			t.expect(text).toContain("native-tab.lua")
			t.expect(text).toContain("🦊 1")
			tabs.click(buf, 1, "l")
			t.expect(vim.api.nvim_get_current_win()).toBe(previous)
			t.expect(vim.bo[vim.api.nvim_win_get_buf(side)].filetype).toBe("neo-tree")
		end)
		vim.api.nvim_win_close(side, true)
		vim.api.nvim_buf_delete(sidebar, { force = true })
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.o.columns = width
		vim.fn.delete(vim.fs.dirname(file), "rf")
		assert(ok, err)
	end)
	t.it("returns to the dashboard when the final visible file is closed", function()
		local env, previous = _G.Environments, vim.api.nvim_get_current_buf()
		local file = vim.fn.tempname() .. ".txt"
		vim.fn.writefile({ "saved" }, file)
		local buf = vim.fn.bufadd(file)
		vim.fn.bufload(buf)
		vim.bo[buf].buflisted = true
		_G.Environments = {
			is_buffer_in_current_environment = function(candidate)
				return candidate == buf
			end,
		}
		vim.api.nvim_set_current_buf(buf)
		local ok, err = pcall(function()
			require("plugins.fox.editor.buffer_cleaner")
			tabs.close(buf)
			t.expect(vim.api.nvim_buf_is_valid(buf)).toBe(false)
			t.expect(vim.bo.filetype).toBe("alpha")
		end)
		_G.Environments = env
		vim.api.nvim_set_current_buf(previous)
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.fn.delete(file)
		assert(ok, err)
	end)
	t.it("closes an empty split and shows the dashboard after closing the last editor tab", function()
		require("lazy").load({ plugins = { "fox_tabline" } })
		require("plugins.fox.editor.buffer_cleaner")
		vim.cmd.tabnew()
		local upper = vim.api.nvim_get_current_win()
		local files = { vim.fn.tempname() .. ".lua", vim.fn.tempname() .. ".lua" }
		for _, file in ipairs(files) do
			vim.fn.writefile({ "" }, file)
		end
		local a = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(a, files[1])
		vim.api.nvim_win_set_buf(upper, a)
		local ok, err = pcall(function()
			local action = vim.fn.maparg("<C-S-j>", "n", false, true).callback
			action()
			local menu = vim.api.nvim_get_current_win()
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			t.expect(lines[1]).toContain("EDITOR  /  OPEN SPLIT")
			t.expect(lines[5]).toContain("Open current buffer")
			t.expect(lines[6]).toContain("Select a file")
			vim.fn.maparg("q", "n", false, true).callback()
			t.expect(vim.api.nvim_win_is_valid(menu)).toBe(false)
			t.expect(vim.api.nvim_get_current_win()).toBe(upper)
			action()
			vim.fn.maparg("<CR>", "n", false, true).callback()
			local lower = vim.api.nvim_get_current_win()
			t.expect(lower ~= upper).toBe(true)
			t.expect(vim.api.nvim_win_get_buf(lower)).toBe(a)
			tabs.close(a)
			t.expect(vim.api.nvim_win_is_valid(lower)).toBe(false)
			t.expect(vim.api.nvim_win_get_buf(upper)).toBe(a)

			local b = vim.api.nvim_create_buf(true, false)
			vim.api.nvim_buf_set_name(b, files[2])
			vim.cmd("belowright split")
			lower = vim.api.nvim_get_current_win()
			vim.api.nvim_win_set_buf(lower, b)
			tabs.close(a)
			t.expect(vim.api.nvim_win_get_buf(lower)).toBe(b)
			tabs.close(b)
			t.expect(vim.api.nvim_win_is_valid(lower)).toBe(false)
			t.expect(vim.api.nvim_buf_is_valid(b)).toBe(false)
			tabs.close(a)
			t.expect(vim.api.nvim_win_is_valid(upper)).toBe(true)
			t.expect(vim.bo[vim.api.nvim_win_get_buf(upper)].filetype).toBe("alpha")
		end)
		vim.cmd.tabclose()
		for _, file in ipairs(files) do
			vim.fn.delete(file)
		end
		assert(ok, err)
	end)

	t.it("routes actual UI mouse targets and protects modified files on close", function()
		local channel = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE" }, { rpc = true })
		assert(channel > 0)
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local root = vim.fn.stdpath("config")
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile({ "one" }, dir .. "/one.lua")
		vim.fn.writefile({ "two" }, dir .. "/two.lua")
		local ok, err = pcall(function()
			call("nvim_ui_attach", 100, 25, { rgb = true })
			local ids = call(
				"nvim_exec_lua",
				[[
				local root, dir = ...
				vim.opt.rtp:prepend(root)
				package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
				-- Isolate the mouse test from workspaces; it only needs the native UI.
				package.loaded['plugins.fox.tools.workspaces'] = { get_badge_components = function() return {} end }
				require('fox.ui.tabline').setup()
				vim.o.mouse = 'a'
				local a = vim.fn.bufadd(dir .. '/one.lua'); vim.fn.bufload(a); vim.bo[a].buflisted = true
				local b = vim.fn.bufadd(dir .. '/two.lua'); vim.fn.bufload(b); vim.bo[b].buflisted = true
				vim.api.nvim_set_current_buf(a)
				vim.cmd.redraw()
				return {a,b}
			]],
				{ root, dir }
			)
			local function mouse(button, column)
				call("nvim_input_mouse", button, "press", "", 0, 0, column)
				call("nvim_input_mouse", button, "release", "", 0, 0, column)
			end
			local function column(close)
				return call(
					"nvim_exec_lua",
					[[
					local close = ...
					local text = vim.api.nvim_eval_statusline(require('fox.ui.tabline').render(), {use_tabline=true,maxwidth=100}).str
					local pos = assert(text:find('two.lua',1,true))
					if close then pos = assert(text:find('󰅖',pos,true)) end
					return vim.fn.strdisplaywidth(text:sub(1,pos-1))
				]],
					{ close }
				)
			end
			mouse("left", column(false))
			t.expect(vim.wait(1000, function()
				return call("nvim_get_current_buf") == ids[2]
			end)).toBe(true)
			call("nvim_buf_set_lines", ids[2], 0, -1, false, { "unsaved" })
			call("nvim_exec_lua", "vim.cmd.redraw()", {})
			mouse("middle", column(false))
			vim.wait(100)
			t.expect(call("nvim_buf_is_valid", ids[2])).toBe(true)
			t.expect(call("nvim_buf_get_lines", ids[2], 0, -1, false)[1]).toBe("unsaved")
			t.expect(call("nvim_exec_lua", "return vim.bo.filetype", {})).toBe("fox_unsaved_changes")
			local cancel = call("nvim_exec_lua", "return vim.fn.screenpos(vim.api.nvim_get_current_win(),5,3)", {})
			call("nvim_input_mouse", "left", "press", "", 0, cancel.row - 1, cancel.col - 1)
			call("nvim_input_mouse", "left", "release", "", 0, cancel.row - 1, cancel.col - 1)
			t.expect(vim.wait(1000, function()
				return call("nvim_get_current_buf") == ids[2]
			end)).toBe(true)
			t.expect(call("nvim_buf_get_lines", ids[2], 0, -1, false)[1]).toBe("unsaved")
			-- The close icon and right-click both invoke the same smart closer.
			call("nvim_exec_lua", "_G.Smart_Close_Buffer = function(b,f) _G.closed = {b,f} end; vim.cmd.redraw()", {})
			mouse("right", column(false))
			t.expect(vim.wait(1000, function()
				return call("nvim_exec_lua", "return _G.closed and _G.closed[1]", {}) == ids[2]
			end)).toBe(true)
			t.expect(call("nvim_exec_lua", "return _G.closed[2]", {})).toBe(false)
			call("nvim_exec_lua", "_G.closed = nil; vim.cmd.redraw()", {})
			mouse("left", column(true))
			t.expect(vim.wait(1000, function()
				return call("nvim_exec_lua", "return _G.closed and _G.closed[1]", {}) == ids[2]
			end)).toBe(true)
			local split = call(
				"nvim_exec_lua",
				[[
				local a, b = ...
				local upper = vim.api.nvim_get_current_win()
				vim.cmd("belowright split")
				local lower = vim.api.nvim_get_current_win()
				vim.api.nvim_win_set_buf(lower, a)
				assert(vim.wait(1000, function() return vim.wo[lower].winbar ~= "" end))
				vim.api.nvim_set_current_win(upper)
				vim.cmd.redraw()
				local tabs = require("fox.ui.tabline")
				local line = vim.api.nvim_eval_statusline(tabs.render(100, lower),
					{ winid = lower, use_winbar = true, maxwidth = 100 }).str
				local pos = assert(line:find("two.lua", 1, true))
				local row, col = unpack(vim.api.nvim_win_get_position(lower))
				return { lower, upper, row, col + vim.fn.strdisplaywidth(line:sub(1, pos - 1)) }
			]],
				ids
			)
			call("nvim_input_mouse", "left", "press", "", 0, split[3], split[4])
			call("nvim_input_mouse", "left", "release", "", 0, split[3], split[4])
			t.expect(vim.wait(1000, function()
				return call("nvim_get_current_win") == split[1] and call("nvim_get_current_buf") == ids[2]
			end)).toBe(true)
			t.expect(call("nvim_win_get_buf", split[2])).toBe(ids[2])
		end)
		vim.fn.jobstop(channel)
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
end)
