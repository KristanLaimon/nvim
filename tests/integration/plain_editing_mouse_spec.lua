local t = require("fox.lib.foxnvim.test")

t.describe("plain editing mouse and unsaved files", function()
	t.it(
		"hovers without moving the caret, follows definitions, confirms close with clicks and toggles from the dashboard",
		function()
			local dir = vim.fn.tempname()
			vim.fn.mkdir(dir, "p")
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
					vim.wait(3000, function()
						return lua(code)
					end, 10),
					code
						.. " "
						.. vim.inspect(
							lua(
								"return {mode=vim.fn.mode(),ft=vim.bo.filetype,mouse=vim.fn.getmousepos(),win=vim.fn.win_screenpos(0)}"
							)
						)
				)
			end
			local function click(row, col, modifiers)
				call("nvim_input_mouse", "left", "press", modifiers or "", 0, row, col)
				call("nvim_input_mouse", "left", "release", modifiers or "", 0, row, col)
			end
			local function click_choice(row)
				local pos = lua("local p=vim.fn.win_screenpos(0); return {p[1],p[2]}")
				click(pos[1] + row - 1, pos[2] + 2)
			end
			local ok, err = xpcall(function()
				call("nvim_ui_attach", 100, 40, { rgb = true })
				lua(
					[[
				local root, dir = ...
				vim.opt.rtp:prepend(root)
				vim.o.mouse, vim.o.hidden = 'a', true
				vim.api.nvim_buf_set_name(0, dir .. '/source.txt')
				vim.api.nvim_buf_set_lines(0,0,-1,false,{'é😀 target()', 'caret stays here', 'definition'})
				vim.cmd.write()
				_G.source = vim.api.nvim_get_current_buf()
				vim.api.nvim_win_set_cursor(0,{2,0})
				_G.plain = require('fox.core.plain_editing')
				plain.settings_file = dir .. '/preference.json'
				plain.setup()
				plain.toggle()
				_G.client = vim.lsp.start({name='mouse_fixture', root_dir=dir, cmd=function(dispatchers)
					local closing, id = false, 0
					return {
						request=function(method, params, callback, replied)
							id=id+1
							local request_id=id
							local result
							if method=='initialize' then
								result={capabilities={hoverProvider=true, definitionProvider=true, positionEncoding='utf-16'}}
							elseif method=='textDocument/hover' then
								_G.hover_position=params.position
								result={contents={kind='markdown',value='**Target documentation**'}}
							elseif method=='textDocument/definition' then
								_G.definition_position=params.position
								result={{uri=vim.uri_from_bufnr(source),range={start={line=2,character=0},['end']={line=2,character=10}}}}
							end
							local function respond() callback(nil,result); if replied then replied(request_id) end end
							if method=='textDocument/hover' and _G.hold_hover then
								_G.pending_hover=respond
							else
								vim.schedule(respond)
							end
							return true, request_id
						end,
						notify=function() return true end,
						is_closing=function() return closing end,
						terminate=function() closing=true; vim.schedule(function() dispatchers.on_exit(0,0) end) end,
					}
				end})
			]],
					{ vim.fn.stdpath("config"), dir }
				)
				await("local c=vim.lsp.get_client_by_id(client); return c and c.initialized and vim.fn.mode()=='i'")
				call("nvim_input_mouse", "move", "", "", 0, 0, 6)
				await([[
				for _,w in ipairs(vim.api.nvim_list_wins()) do
					local b=vim.api.nvim_win_get_buf(w)
					if table.concat(vim.api.nvim_buf_get_lines(b,0,-1,false)):find('Target documentation',1,true) then
						return vim.api.nvim_win_get_config(w).focusable==false
					end
				end
				return false
			]])
				t.expect(lua("return hover_position")).toEqual({ line = 0, character = 6 })
				t.expect(lua("return vim.api.nvim_win_get_cursor(0)")).toEqual({ 2, 0 })
				t.expect(lua("return vim.fn.mode()")).toBe("i")
				call("nvim_input_mouse", "move", "", "", 0, 8, 0)
				await("return #vim.api.nvim_list_wins()==1")
				lua("_G.hold_hover=true")
				call("nvim_input_mouse", "move", "", "", 0, 0, 6)
				await("return _G.pending_hover~=nil")
				call("nvim_input_mouse", "move", "", "", 0, 8, 0)
				await("return vim.fn.getmousepos().screenrow==9")
				lua("_G.pending_hover(); _G.hold_hover=false")
				t.expect(lua("return #vim.api.nvim_list_wins()")).toBe(1)
				click(0, 6, "C")
				await("return _G.definition_position and vim.api.nvim_win_get_cursor(0)[1]==3 and vim.fn.mode()=='i'")
				t.expect(lua("return definition_position")).toEqual({ line = 0, character = 6 })

				lua([[
				require('plugins.fox.editor.buffer_cleaner')
				vim.api.nvim_buf_set_lines(source,0,-1,false,{'unsaved edit'})
				_G.code_win=vim.api.nvim_get_current_win()
				Smart_Close_Buffer(source)
				Smart_Close_Buffer(source)
			]])
				await("return vim.bo.filetype=='fox_unsaved_changes' and vim.fn.mode()=='n'")
				t.expect(lua("return vim.api.nvim_win_get_buf(code_win)==source and vim.bo[source].modified")).toBe(true)
				t.expect(lua("return #vim.api.nvim_list_wins()")).toBe(2)
				click_choice(5)
				await("return vim.api.nvim_get_current_buf()==source and vim.fn.mode()=='i'")
				t.expect(lua("return vim.fn.readfile(vim.api.nvim_buf_get_name(source))[1]")).toBe("é😀 target()")
				lua("Smart_Close_Buffer(source)")
				await("return vim.bo.filetype=='fox_unsaved_changes'")
				click_choice(3)
				await("return not vim.api.nvim_buf_is_loaded(source)")
				t.expect(vim.fn.readfile(dir .. "/source.txt")).toEqual({ "unsaved edit" })

				lua(
					[[
				local dir=...
				vim.cmd.edit(dir .. '/source.txt')
				_G.source=vim.api.nvim_get_current_buf()
				vim.api.nvim_set_current_line('must survive failed save')
				vim.bo.readonly=true
				vim.notify=function(msg) _G.save_error=msg end
				Smart_Close_Buffer(source)
			]],
					{ dir }
				)
				await("return vim.bo.filetype=='fox_unsaved_changes'")
				click_choice(3)
				await("return _G.save_error and vim.api.nvim_get_current_buf()==source and vim.bo[source].modified")
				t.expect(vim.fn.readfile(dir .. "/source.txt")).toEqual({ "unsaved edit" })
				lua("vim.bo[source].readonly=false; Smart_Close_Buffer(source,true)")

				lua(
					[[
				local dir=...
				vim.cmd.edit(dir .. '/source.txt')
				_G.source=vim.api.nvim_get_current_buf()
				vim.api.nvim_set_current_line('discard this')
				Smart_Close_Buffer(source)
			]],
					{ dir }
				)
				await("return vim.bo.filetype=='fox_unsaved_changes'")
				click_choice(4)
				await("return not vim.api.nvim_buf_is_loaded(source)")
				t.expect(vim.fn.readfile(dir .. "/source.txt")).toEqual({ "unsaved edit" })

				lua([[
				require('plugins.ui.dashboard').config()
				vim.cmd.Alpha()
			]])
				await("return vim.bo.filetype=='alpha' and vim.fn.mode()=='n'")
				local function click_toggle()
					local pos = lua([[
					for row,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do
						local col=line:find('Vim motions:',1,true)
						if col then
							local screen=vim.fn.screenpos(vim.api.nvim_get_current_win(),row,col)
							assert(screen.row>0, 'Dashboard toggle must be visible')
							return {screen.row-1,screen.col-1}
						end
					end
				]])
					click(pos[1], pos[2])
				end
				click_toggle()
				await(
					"return not plain.enabled and table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false)):find('Vim motions: ON',1,true)~=nil"
				)
				t.expect(lua("return vim.o.mousemoveevent")).toBe(false)
				click_toggle()
				await(
					"return plain.enabled and table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false)):find('Vim motions: OFF',1,true)~=nil"
				)
				call("nvim_ui_try_resize", 100, 24)
				await([[
				for row,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do
					if line:find('Vim motions:',1,true) then return row<=vim.api.nvim_win_get_height(0) end
				end
				return false
			]])
				click_toggle()
				await("return not plain.enabled")
				lua("vim.lsp.get_client_by_id(client):stop(true)")
			end, debug.traceback)
			vim.fn.jobstop(channel)
			vim.fn.delete(dir, "rf")
			assert(ok, err)
		end
	)
end)
