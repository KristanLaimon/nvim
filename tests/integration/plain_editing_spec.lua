local t = require("fox.lib.foxnvim.test")

t.describe("opt-in plain editing", function()
	t.it("persists the toggle, types literally, selects, restores maps and clicks dashboard buttons", function()
		local channel = vim.fn.jobstart(
			{ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
			{ rpc = true }
		)
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local function lua(code, args)
			return call("nvim_exec_lua", code, args or {})
		end
		local function await(code)
			assert(
				vim.wait(2000, function()
					return lua(code)
				end, 10),
				code
			)
		end
		local preference = vim.fn.tempname() .. ".json"
		local ok, err = xpcall(function()
			call("nvim_ui_attach", 100, 40, { rgb = true })
			lua(
				[[
				local root, preference = ...
				vim.opt.rtp:prepend(root)
				vim.o.mouse = 'a'
				vim.o.keymodel = ''
				vim.o.selectmode = ''
				vim.g.clipboard = {
					name = 'Plain editing test', cache_enabled = 0,
					copy = { ['+'] = function(lines) _G.copied = lines end, ['*'] = function() end },
					paste = { ['+'] = function() return {{'pasted'}, 'v'} end, ['*'] = function() return {{}, 'v'} end },
				}
				_G.plain = require('fox.core.plain_editing')
				plain.settings_file = preference
				plain.setup()
				assert(not plain.enabled and vim.fn.filereadable(preference) == 0)
				vim.keymap.set('i', '<Esc>', '<Esc>', {buffer=true, desc='Original Escape'})
				assert(plain.toggle())
			]],
				{ vim.fn.stdpath("config"), preference }
			)
			await("return vim.fn.mode() == 'i'")
			call("nvim_input", "hjkl<Esc>word")
			await("return vim.api.nvim_get_current_line() == 'hjklword' and vim.fn.mode() == 'i'")
			call("nvim_input", "<S-Left>")
			await("return vim.fn.mode() == 's'")
			call("nvim_input", "X")
			await("return vim.api.nvim_get_current_line() == 'hjklworX'")
			call("nvim_input", "<C-a>replacement")
			await("return vim.api.nvim_get_current_line() == 'replacement'")
			call("nvim_input", "<C-a><C-c>")
			await("return _G.copied and table.concat(_G.copied, '\\n') == 'replacement' and vim.fn.mode() == 'i'")
			call("nvim_input", "<C-a><C-x>")
			await("return vim.api.nvim_get_current_line() == '' and vim.fn.mode() == 'i'")
			lua("vim.api.nvim_set_current_line('seed')")
			call("nvim_input", "<C-a><C-v>")
			await("return vim.api.nvim_get_current_line() == 'pasted' and vim.fn.mode() == 'i'")
			lua([[
				assert(require('fox.core.store').load(plain.settings_file).enabled == true)
				assert(plain.toggle())
				assert(vim.fn.maparg('<Esc>', 'i', false, true).desc == 'Original Escape')
				assert(vim.o.keymodel == '' and vim.o.selectmode == '')
				plain.setup()
				assert(not plain.enabled)
				assert(plain.toggle())
				plain.setup()
				assert(plain.enabled)
				local dashboard = require('fox.ui.dashboard')
				local layout = dashboard.layout()
				layout.section.header.val = {'Test dashboard'}
				layout.section.buttons.val = {
					layout.button('a', 'First action', ':let g:clicked = 1<CR>'),
					layout.button('b', 'Open file', ':enew!<CR>'),
				}
				dashboard.setup(layout.opts)
				dashboard.start()
			]])
			await("return vim.bo.filetype == 'alpha' and vim.fn.mode() == 'n' and vim.o.keymodel == ''")
			local function click(label, outside)
				local position = lua(
					[[
					local label = ...
					for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
						local col = line:find(label, 1, true)
						if col then return {row - 1, col - 1} end
					end
				]],
					{ label }
				)
				call("nvim_input_mouse", "left", "press", "", 0, position[1], outside and 0 or position[2])
				call("nvim_input_mouse", "left", "release", "", 0, position[1], outside and 0 or position[2])
			end
			click("First action", true)
			t.expect(lua("return vim.g.clicked == nil")).toBe(true)
			click("First action")
			await("return vim.g.clicked == 1")
			click("Open file")
			await("return vim.bo.filetype ~= 'alpha' and vim.fn.mode() == 'i'")
			lua([[
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_open_win(buf, true, {relative='editor',row=1,col=1,width=20,height=4})
				vim.cmd.stopinsert()
			]])
			await("return vim.fn.mode() == 'n' and vim.o.keymodel == ''")
			lua("assert(plain.toggle())")
		end, debug.traceback)
		vim.fn.jobstop(channel)
		vim.fn.delete(preference)
		assert(ok, err)
	end)
end)
