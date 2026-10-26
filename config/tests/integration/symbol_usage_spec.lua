local t = require("fox.lib.foxnvim.test")
t.describe("stable usage badges while typing with real UI and stdio LSP", function()
	t.it("retains function/method badges through Insert mode and updates them together on InsertLeave", function()
		local root, dir = vim.fn.stdpath("config"), vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		local channel = vim.fn.jobstart({ "nvim", "--embed", "--headless", "-u", "NONE" }, { rpc = true })
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local function lua(code, args)
			return call("nvim_exec_lua", code, args or {})
		end
		local function marks()
			return lua(
				[[return vim.api.nvim_buf_get_extmarks(0,require('fox.lsp.symbol_usage').namespace,0,-1,{details=true})]]
			)
		end
		local function count()
			return vim.fn.filereadable(dir .. "/requests") == 1 and #vim.fn.readfile(dir .. "/requests") or 0
		end
		local function wait(fn)
			assert(vim.wait(3000, fn, 10), "Usage fixture did not settle")
		end
		local ok, err = xpcall(function()
			call("nvim_ui_attach", 100, 35, { rgb = true })
			lua(
				[[
			local root,dir = ...
			vim.opt.rtp:prepend(root)
			vim.api.nvim_buf_set_name(0,dir .. '/sample.lua')
			vim.api.nvim_buf_set_lines(0,0,-1,false,{'function foo() end','method bar() end'})
			local usage=require('fox.lsp.symbol_usage')
			usage.setup({debounce=20,text_format=function(v) return v.references .. ' usages' end})
			_G.client=vim.lsp.start({name='fox_usage_fixture',root_dir=dir,cmd={'python',root .. '/config/tests/fixtures/symbol_usage_server.py',dir .. '/requests'}})
			]],
				{ root, dir }
			)
			wait(function()
				return #marks() == 2
			end)
			t.expect(marks()[1][4].virt_lines[1][1][1]).toBe("2 usages")
			local previous, initial = marks(), count()
			call("nvim_input", "A extra")
			wait(function()
				return lua([[return vim.api.nvim_get_mode().mode == 'i']])
			end)
			-- Stay idle beyond the debounce while still in Insert mode. Neither a
			-- new LSP round nor a clear/recreate of either badge may happen.
			lua([[vim.wait(120); return true]])
			t.expect(count()).toBe(initial)
			t.expect(marks()).toEqual(previous)
			call("nvim_input", "more")
			wait(function()
				return lua([[return vim.api.nvim_get_current_line():find('extramore',1,true) ~= nil]])
			end)
			t.expect(marks()).toEqual(previous)
			call("nvim_input", "<Esc>")
			wait(function()
				return count() > initial
			end)
			t.expect(#marks()).toBe(2)
			wait(function()
				return marks()[1][4].virt_lines[1][1][1] == "3 usages"
			end)
			t.expect(marks()[2][4].virt_lines[1][1][1]).toBe("3 usages")
			t.expect(count() - initial).toBe(3)
			lua([[vim.lsp.get_client_by_id(_G.client):stop(true)]])
		end, debug.traceback)
		vim.fn.jobstop(channel)
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
end)
