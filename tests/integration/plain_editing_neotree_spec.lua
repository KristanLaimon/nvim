local t = require("fox.lib.foxnvim.test")

t.describe("plain editing and Neo-tree focus", function()
	t.it("keeps tree clicks working after typing and selecting in a file without reopening the sidebar", function()
		local dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		vim.fn.writefile({ "first file" }, dir .. "/first.txt")
		vim.fn.writefile({ "second file" }, dir .. "/second.txt")
		local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-i", "NONE" }, { rpc = true })
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
						lua("return {ft=vim.bo.filetype,mode=vim.fn.mode(),keymodel=vim.o.keymodel,selectmode=vim.o.selectmode}")
					)
			)
		end
		local function click_node(name, double)
			if double then
				-- Begin a fresh double-click gesture, not a third click after focus.
				lua("vim.wait(vim.o.mousetime + 10)")
			end
			local pos = lua(
				[[
				local name=...
				local state=_G.tree_state
				local buf=vim.api.nvim_win_get_buf(state.winid)
				for row,line in ipairs(vim.api.nvim_buf_get_lines(buf,0,-1,false)) do
					local col=line:find(name,1,true)
					if col then
						local screen=vim.fn.screenpos(state.winid,row,col)
						assert(screen.row>0)
						return {screen.row-1,screen.col-1}
					end
				end
				error('Missing tree entry: ' .. name)
			]],
				{ name }
			)
			for _ = 1, double and 2 or 1 do
				call("nvim_input_mouse", "left", "press", "", 0, pos[1], pos[2])
				call("nvim_input_mouse", "left", "release", "", 0, pos[1], pos[2])
			end
		end
		local ok, err = xpcall(function()
			call("nvim_ui_attach", 120, 40, { rgb = true })
			lua(
				[[
				local dir=...
				_G.test_dir=dir
				_G.plain=require('fox.core.plain_editing')
				plain.settings_file=dir .. '/preference.json'
				plain.setup()
				if not plain.enabled then plain.toggle() end
				vim.o.keymodel=''
				vim.o.selectmode=''
				vim.cmd.edit(dir .. '/first.txt')
				_G.code_win=vim.api.nvim_get_current_win()
				vim.cmd('Neotree show left dir=' .. vim.fn.fnameescape(dir))
			]],
				{ dir }
			)
			await([[
				local s=require('neo-tree.sources.manager').get_state('filesystem')
				return s.tree and s.tree:get_node(vim.fs.joinpath(test_dir,'second.txt'))~=nil
			]])
			lua([[
				_G.tree_state=require('neo-tree.sources.manager').get_state('filesystem')
				_G.tree_win=tree_state.winid
				vim.api.nvim_set_current_win(code_win)
			]])
			await("return vim.fn.mode()=='i'")
			call("nvim_input", "editing")
			await("return vim.api.nvim_get_current_line():find('editing',1,true)~=nil")
			click_node("second.txt")
			await("return vim.bo.filetype=='neo-tree' and vim.fn.mode()=='n'")
			t.expect(lua("return vim.o.selectmode")).toBe("")
			t.expect(lua("return vim.o.keymodel")).toBe("")
			click_node("second.txt", true)
			await("return vim.api.nvim_buf_get_name(0):find('second.txt',1,true)~=nil and vim.fn.mode()=='i'")
			call("nvim_input", "<C-a>")
			await("return vim.fn.mode()=='s'")
			click_node("first.txt")
			await("return vim.bo.filetype=='neo-tree' and vim.fn.mode()=='n'")
			click_node("first.txt", true)
			await("return vim.api.nvim_buf_get_name(0):find('first.txt',1,true)~=nil and vim.fn.mode()=='i'")
			t.expect(lua("return require('neo-tree.sources.manager').get_state('filesystem').winid==tree_win")).toBe(true)
			lua("vim.api.nvim_set_current_win(tree_win)")
			await("return vim.fn.mode()=='n'")
			call("nvim_input", "V")
			await("return vim.fn.mode()=='V'")
			call("nvim_input", "<Esc>")
			await("return vim.fn.mode()=='n'")
			lua("vim.api.nvim_set_current_win(code_win)")
			await("return vim.fn.mode()=='i'")
			lua([[
				local files={}
				for _,buf in ipairs(vim.api.nvim_list_bufs()) do
					local name=vim.api.nvim_buf_get_name(buf)
					if vim.bo[buf].buftype=='' and name:match('%.txt$') then
						if vim.bo[buf].modified then vim.api.nvim_buf_call(buf,vim.cmd.write) end
						files[#files+1]=buf
					end
				end
				assert(#files==2)
				for _,buf in ipairs(files) do require('fox.ui.tabline').close(buf) end
			]])
			await("return vim.bo.filetype=='alpha' and vim.fn.mode()=='n'")
			click_node("second.txt")
			await("return vim.bo.filetype=='neo-tree' and vim.fn.mode()=='n'")
			click_node("second.txt", true)
			await("return vim.api.nvim_buf_get_name(0):find('second.txt',1,true)~=nil and vim.fn.mode()=='i'")
			t.expect(lua("return tree_state.winid==tree_win")).toBe(true)
			lua("plain.toggle(); require('fox.ui.tabline').close(vim.api.nvim_get_current_buf())")
			await("return vim.bo.filetype=='alpha' and vim.fn.mode()=='n'")
			click_node("first.txt")
			await("return vim.bo.filetype=='neo-tree' and vim.fn.mode()=='n'")
			click_node("first.txt", true)
			await("return vim.api.nvim_buf_get_name(0):find('first.txt',1,true)~=nil and vim.fn.mode()=='n'")
			lua("plain.toggle()")
			await("return vim.fn.mode()=='i'")
			-- Input dialogs still own their Insert mode after leaving a code window.
			lua("require('plugins.fox.ui.input_modal').open({label='New file',callback=function() end})")
			await("return vim.api.nvim_win_get_config(0).relative~='' and vim.fn.mode()=='i'")
			lua("plain.toggle()")
		end, debug.traceback)
		vim.fn.jobstop(channel)
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
end)
