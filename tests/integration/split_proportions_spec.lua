local t = require("fox.lib.foxnvim.test")

t.describe("editor split proportions", function()
	t.it("preserves nested split ratios through a sidebar, bottom panel, and editor resize", function()
		local previous = { columns = vim.o.columns, lines = vim.o.lines }
		vim.o.columns, vim.o.lines = 160, 54
		vim.cmd.tabnew()
		local upper_left = vim.api.nvim_get_current_win()
		vim.cmd("rightbelow vsplit")
		local right = vim.api.nvim_get_current_win()
		vim.cmd("vertical resize 52")
		vim.api.nvim_set_current_win(upper_left)
		vim.cmd("rightbelow split")
		local lower_left = vim.api.nvim_get_current_win()
		vim.cmd("resize 17")

		local function settle()
			vim.api.nvim_exec_autocmds("WinResized", {})
			vim.wait(20)
		end
		local function proportions()
			local width = vim.api.nvim_win_get_width(upper_left)
			local height = vim.api.nvim_win_get_height(upper_left)
			return width / (width + vim.api.nvim_win_get_width(right)),
				height / (height + vim.api.nvim_win_get_height(lower_left))
		end
		local function check(width, height)
			settle()
			local actual_width, actual_height = proportions()
			assert(math.abs(actual_width - width) < 0.02, ("width: %.3f vs %.3f"):format(actual_width, width))
			assert(math.abs(actual_height - height) < 0.04, ("height: %.3f vs %.3f"):format(actual_height, height))
		end

		local ok, err = pcall(function()
			settle()
			vim.api.nvim_set_current_win(right)
			vim.cmd("vertical resize 47")
			settle()
			local width, height = proportions()
			vim.cmd("topleft 30vnew")
			local sidebar = vim.api.nvim_get_current_win()
			vim.bo.buftype = "nofile"
			vim.bo.filetype = "neo-tree"
			check(width, height)

			vim.api.nvim_set_current_win(right)
			vim.cmd("botright 8new")
			local panel = vim.api.nvim_get_current_win()
			vim.bo.buftype = "nofile"
			vim.wo.winfixheight = true
			check(width, height)

			vim.o.columns, vim.o.lines = 120, 40
			check(width, height)
			vim.o.columns, vim.o.lines = 170, 60
			check(width, height)

			vim.api.nvim_win_close(panel, true)
			vim.api.nvim_win_close(sidebar, true)
			check(width, height)
		end)
		vim.cmd.tabclose()
		vim.o.columns, vim.o.lines = previous.columns, previous.lines
		assert(ok, err)
	end)
end)
