local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local picker = require("fox.core.window_picker")

describe("local Neo-tree window picker", function()
	local original_tab, test_tab, source, buffers, getcharstr
	local function split(filetype, buftype)
		vim.cmd("vnew")
		local win = vim.api.nvim_get_current_win()
		local buf = vim.api.nvim_get_current_buf()
		table.insert(buffers, buf)
		vim.bo[buf].filetype = filetype or ""
		if buftype == "terminal" then
			vim.api.nvim_open_term(buf, {})
		else
			vim.bo[buf].buftype = buftype or ""
		end
		vim.api.nvim_set_current_win(source)
		return win
	end

	t.beforeEach(function()
		original_tab = vim.api.nvim_get_current_tabpage()
		getcharstr = vim.fn.getcharstr
		vim.cmd("tabnew")
		test_tab = vim.api.nvim_get_current_tabpage()
		source = vim.api.nvim_get_current_win()
		buffers = { vim.api.nvim_get_current_buf() }
	end)
	t.afterEach(function()
		vim.fn.getcharstr = getcharstr
		vim.api.nvim_set_current_tabpage(test_tab)
		vim.cmd("tabclose!")
		vim.api.nvim_set_current_tabpage(original_tab)
		for _, buf in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
	end)

	it("exports the module name required by Neo-tree", function()
		expect(require("window-picker")).toBe(picker)
	end)

	it("returns nil when no other window is eligible", function()
		expect(picker.pick_window({})).toBe(nil)
	end)

	it("selects a single target without prompting or changing focus", function()
		local target = split()
		vim.fn.getcharstr = function()
			error("must not prompt")
		end
		expect(picker.pick_window({})).toBe(target)
		expect(vim.api.nvim_get_current_win()).toBe(source)
	end)

	it("excludes trees, notifications, quickfix, terminals, floats and other tabs", function()
		for _, ft in ipairs({ "neo-tree", "neo-tree-popup", "notify", "snacks_notif", "NvimTree" }) do
			split(ft)
		end
		split(nil, "quickfix")
		split(nil, "terminal")
		local buf = vim.api.nvim_create_buf(false, true)
		table.insert(buffers, buf)
		vim.api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 5, height = 1 })
		local other_tab_window = vim.api.nvim_tabpage_get_win(original_tab)
		expect(vim.api.nvim_win_is_valid(other_tab_window)).toBe(true)
		local target = split()
		expect(picker.pick_window()).toBe(target)
	end)

	it("shows labels, accepts lowercase and restores local winbars", function()
		local first, second = split(), split()
		vim.wo[first].winbar = "First %f"
		vim.wo[second].winbar = "Second %f"
		local selected
		vim.fn.getcharstr = function()
			for _, win in ipairs({ first, second }) do
				local label = vim.wo[win].winbar:match("IncSearch# (.) ")
				if label == "F" then
					selected = win
				end
			end
			expect(selected ~= nil).toBe(true)
			return "f"
		end
		expect(picker.pick_window()).toBe(selected)
		expect(vim.wo[first].winbar).toBe("First %f")
		expect(vim.wo[second].winbar).toBe("Second %f")
		expect(vim.api.nvim_get_current_win()).toBe(source)
	end)

	it("restores winbars on cancellation, invalid input and interrupted input", function()
		local first, second = split(), split()
		for _, input in ipairs({ "\027", "?", "interrupt" }) do
			vim.fn.getcharstr = function()
				if input == "interrupt" then
					error("Keyboard interrupt")
				end
				return input
			end
			expect(picker.pick_window()).toBe(nil)
			expect(vim.wo[first].winbar).toBe("")
			expect(vim.wo[second].winbar).toBe("")
		end
	end)

	it("does not return a target that closed while waiting for input", function()
		split()
		split()
		vim.fn.getcharstr = function()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.wo[win].winbar:find("IncSearch# F ", 1, true) then
					vim.api.nvim_win_close(win, true)
				end
			end
			return "F"
		end
		expect(picker.pick_window()).toBe(nil)
	end)

	it("uses two-letter labels when there are more targets than selection characters", function()
		local targets = {}
		for _ = 1, 19 do
			local win = split()
			vim.api.nvim_win_set_width(win, 1)
			table.insert(targets, win)
		end
		local selected, reads = nil, 0
		vim.fn.getcharstr = function()
			reads = reads + 1
			for _, win in ipairs(targets) do
				if vim.wo[win].winbar:find("IncSearch# FF ", 1, true) then
					selected = win
				end
			end
			return "f"
		end
		local result = picker.pick_window()
		expect(selected ~= nil).toBe(true)
		expect(result).toBe(selected)
		expect(reads).toBe(2)
		for _, win in ipairs(targets) do
			expect(vim.wo[win].winbar).toBe("")
		end
	end)
end)
