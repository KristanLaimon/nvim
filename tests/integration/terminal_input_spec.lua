local t = require("fox.lib.foxnvim.test")

t.describe("immediate terminal input", function()
	t.it("navigates terminal output and copies a visual selection", function()
		local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, {
			rpc = true,
		})
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local ok, err = xpcall(function()
			call("nvim_ui_attach", 80, 24, { rgb = true })
			local buf = call(
				"nvim_exec_lua",
				[[
				vim.opt.rtp:prepend(...)
				vim.g.clipboard = {name = 'test', copy = {['+'] = function(lines) _G.copied = table.concat(lines, '\n') end}, paste = {['+'] = function() return {''} end}}
				require('plugins.fox.dev.terminal').setup()
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_set_current_buf(buf)
				local term = vim.api.nvim_open_term(buf, {})
				vim.b[buf].fox_is_multi_term = true
				vim.api.nvim_exec_autocmds('BufEnter', {buffer = buf})
				vim.api.nvim_chan_send(term, 'hello world')
				return buf
			]],
				{ vim.fn.stdpath("config") }
			)
			assert(
				vim.wait(3000, function()
					return call("nvim_get_mode").mode == "t" and call("nvim_buf_get_lines", buf, 0, 1, false)[1] == "hello world"
				end, 10),
				"terminal did not enter input mode and display the fixture output"
			)
			call("nvim_input", "<C-Space>0v4ly")
			assert(
				vim.wait(3000, function()
					return call("nvim_exec_lua", "return _G.copied", {}) == "hello"
				end, 10),
				"visual selection was not copied"
			)
			assert(call("nvim_get_current_buf") == buf)
			call("nvim_input", "i")
			assert(
				vim.wait(3000, function()
					return call("nvim_get_mode").mode == "t"
				end, 10),
				"terminal input did not resume"
			)
		end, debug.traceback)
		pcall(call, "nvim_command", "qa!")
		assert(ok, err)
	end)

	t.it("preserves queued typing when toggling or selecting from plain editing in every layout", function()
		local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, {
			rpc = true,
		})
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local function lua(code, args)
			return call("nvim_exec_lua", code, args or {})
		end
		local ok, err = xpcall(function()
			call("nvim_ui_attach", 100, 40, { rgb = true })
			lua(
				[[
				vim.opt.rtp:prepend(...)
				vim.o.hidden = true
				_G.source = vim.api.nvim_get_current_buf()
				_G.terminal = require('plugins.fox.dev.terminal')
				terminal.setup()
				local buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_set_current_buf(buf)
				vim.api.nvim_open_term(buf, {on_input=function(_, _, _, data)
					_G.received = (_G.received or '') .. data
				end})
				vim.b[buf].fox_is_multi_term, vim.b[buf].fox_term_num = true, 9
				vim.api.nvim_set_current_buf(source)
				_G._fox_selected_terminal = 9
				local plain = require('fox.core.plain_editing')
				plain.settings_file = vim.fn.tempname()
				plain.setup()
				if not plain.enabled then plain.toggle() end
			]],
				{ vim.fn.stdpath("config") }
			)
			for _, layout in ipairs({ "dock", "float", "bottom_float" }) do
				lua("_G._fox_terminal_layout = ...", { layout })
				for _, key in ipairs({ "<C-;>", "<A-9>" }) do
					assert(
						vim.wait(3000, function()
							return lua("return vim.fn.mode() == 'i' and vim.api.nvim_get_current_buf() == source")
						end, 10),
						"plain editing did not regain focus"
					)
					lua("_G.received = ''")
					call("nvim_input", key .. "abcdef")
					assert(
						vim.wait(3000, function()
							return lua("return _G.received == 'abcdef'")
						end, 10),
						layout .. " " .. key .. " received: " .. vim.inspect(lua("return _G.received"))
					)
					call("nvim_input", "<C-;>")
				end
			end
		end, debug.traceback)
		pcall(call, "nvim_command", "qa!")
		assert(ok, err)
	end)
end)
