local t = require("fox.lib.foxnvim.test")
require("lazy").load({ plugins = { "fox_project_replace" } })
local sidebar = require("plugins.fox.tools.project_replace")

t.describe("project search keyboard and preview", function()
	t.it("searches from its native field and previews cursor movement without extra tabs", function()
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		local original_tab = vim.api.nvim_get_current_tabpage()
		vim.fn.mkdir(root, "p")
		vim.fn.writefile({ "Docker one" }, root .. "/one.txt")
		vim.fn.writefile({ "docker two" }, root .. "/two.txt")
		local test_tab
		local function feed(keys)
			vim.api.nvim_feedkeys(vim.keycode(keys), "xt", false)
		end
		local ok, err = pcall(function()
			vim.api.nvim_set_current_dir(root)
			vim.cmd("tabnew")
			test_tab = vim.api.nvim_get_current_tabpage()
			vim.cmd("ProjectSearch")
			local state = sidebar.state
			t.expect(state ~= nil).toBe(true)
			feed("idocker<Esc>")
			assert(
				vim.wait(3000, function()
					return state.plan ~= nil
				end),
				tostring(state.status)
					.. " | input="
					.. vim.inspect(vim.api.nvim_buf_get_lines(state.fields[1].buf, 0, -1, false))
			)
			t.expect(state.plan.count).toBe(2)
			feed("4")
			t.expect(vim.api.nvim_get_current_win()).toBe(state.fields[4].win)
			local visited = {}
			local lines = vim.api.nvim_buf_line_count(state.fields[4].buf)
			for _ = 1, lines do
				feed("j")
				-- Scripted feedkeys postpones CursorMoved until the command returns.
				vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.fields[4].buf })
				vim.wait(20)
				local current = state.preview.current
				if current then
					visited[vim.fn.fnamemodify(vim.api.nvim_buf_get_name(current), ":t")] = true
				end
			end
			t.expect(visited["one.txt"]).toBe(true)
			t.expect(visited["two.txt"]).toBe(true)
			t.expect(vim.api.nvim_get_current_win()).toBe(state.fields[4].win)
			local temporary = {}
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.b[buf].fox_preview_owner == "Search" and vim.bo[buf].buflisted then
					temporary[#temporary + 1] = buf
				end
			end
			t.expect(#temporary).toBe(1)
			feed("q")
			t.expect(sidebar.state).toBe(nil)
			t.expect(vim.bo[temporary[1]].buflisted).toBe(false)
		end)
		sidebar.close()
		if test_tab and vim.api.nvim_tabpage_is_valid(test_tab) then
			vim.api.nvim_set_current_tabpage(test_tab)
			vim.cmd("tabclose!")
		end
		vim.api.nvim_set_current_tabpage(original_tab)
		vim.api.nvim_set_current_dir(cwd)
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf):gsub("\\", "/"):find(root:gsub("\\", "/"), 1, true) == 1 then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
