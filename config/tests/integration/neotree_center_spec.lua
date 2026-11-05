local t = require("fox.lib.foxnvim.test")
local center = require("plugins.fox.editor.neotree_center")
local store = require("fox.core.store")

require("lazy").load({ plugins = { "neo-tree.nvim" } })

t.describe("Neo-tree cursor centering", function()
	t.it("centers long trees, respects both ends and short lists, and persists toggles", function()
		local saved_path, saved_enabled = center.store_file, center.enabled
		center.store_file = vim.fn.tempname()
		center.enabled = true
		local code_win = vim.api.nvim_get_current_win()
		local code_scrolloff = vim.wo[code_win].scrolloff
		local ok, err = pcall(function()
			vim.cmd("Neotree focus")
			local state = require("neo-tree.sources.manager").get_state("filesystem")
			local renderer = require("neo-tree.ui.renderer")
			local nodes = {}
			local height = vim.api.nvim_win_get_height(state.winid)
			for i = 1, height * 4 do
				nodes[i] = { id = "center-" .. i, name = "file-" .. i, type = "file", path = state.path .. "/file-" .. i }
			end
			renderer.show_nodes(nodes, state)
			t.expect(vim.wait(1000, function()
				return state.tree and state.tree:get_node("center-" .. #nodes) ~= nil and vim.wo[state.winid].scrolloff == 999
			end)).toBe(true)
			t.expect(vim.wo[state.winid].scrolloff).toBe(999)
			local function move(line)
				vim.cmd("normal! " .. line .. "G")
				vim.cmd("redraw")
				return vim.fn.line("w0")
			end
			t.expect(move(2)).toBe(1)
			local middle = height * 2
			t.expect(math.abs((middle - move(middle) + 1) - (height + 1) / 2) <= 1).toBe(true)
			local last = vim.api.nvim_buf_line_count(state.bufnr)
			t.expect(move(last)).toBe(last - height + 1)
			vim.cmd("NeotreeToggleCursorCentering")
			t.expect(center.enabled).toBe(false)
			t.expect(store.load(center.store_file, {}).enabled).toBe(false)
			t.expect(vim.wo[state.winid].scrolloff).toBe(vim.go.scrolloff)
			vim.cmd("NeotreeToggleCursorCentering")
			t.expect(store.load(center.store_file, {}).enabled).toBe(true)
			vim.cmd("Neotree close")
			vim.cmd("Neotree focus")
			state = require("neo-tree.sources.manager").get_state("filesystem")
			t.expect(vim.wait(1000, function()
				return state.winid and vim.wo[state.winid].scrolloff == 999
			end)).toBe(true)
			renderer.show_nodes({ nodes[1], nodes[2], nodes[3] }, state)
			t.expect(vim.wait(1000, function()
				return vim.api.nvim_buf_line_count(state.bufnr) == 3
			end)).toBe(true)
			t.expect(move(3)).toBe(1)
			t.expect(vim.wo[code_win].scrolloff).toBe(code_scrolloff)
		end)
		vim.fn.delete(center.store_file)
		center.store_file, center.enabled = saved_path, saved_enabled
		vim.cmd("Neotree close")
		assert(ok, err)
	end)
end)
