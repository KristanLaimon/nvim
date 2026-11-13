local t = require("fox.lib.foxnvim.test")
local mover = require("plugins.fox.editor.neotree_mover")
require("lazy").load({ plugins = { "neo-tree.nvim" } })

t.describe("Neo-tree visual move", function()
	t.it("picks up the visual range with m and drops every entry at the destination", function()
		local root = vim.fn.tempname()
		vim.fn.mkdir(root .. "/destination", "p")
		local paths = { root .. "/first.txt", root .. "/second.txt" }
		for _, path in ipairs(paths) do
			vim.fn.writefile({ "content" }, path)
		end
		local ok, err = pcall(function()
			vim.cmd("Neotree show")
			local state = require("neo-tree.sources.manager").get_state("filesystem")
			local renderer = require("neo-tree.ui.renderer")
			local nodes = {}
			for _, path in ipairs(paths) do
				table.insert(nodes, { id = path, path = path, name = vim.fs.basename(path), type = "file" })
			end
			table.insert(
				nodes,
				{ id = root .. "/destination", path = root .. "/destination", name = "destination", type = "directory" }
			)
			renderer.show_nodes(nodes, state)
			t.expect(vim.wait(1000, function()
				return state.tree and state.tree:get_node(paths[1]) ~= nil
			end)).toBe(true)
			vim.api.nvim_set_current_win(state.winid)
			renderer.focus_node(state, paths[1])
			vim.cmd("normal! Vj")
			vim.cmd("doautocmd CursorMoved")
			vim.api.nvim_feedkeys("m", "xt", false)
			t.expect(vim.wait(1000, mover.is_holding)).toBe(true)
			t.expect(#mover.held_items).toBe(2)
			renderer.focus_node(state, root .. "/destination")
			vim.api.nvim_feedkeys("m", "xt", false)
			t.expect(vim.wait(1000, function()
				return not mover.is_holding()
			end)).toBe(true)
			for _, path in ipairs(paths) do
				t.expect(vim.fn.filereadable(path)).toBe(0)
				t.expect(vim.fn.filereadable(root .. "/destination/" .. vim.fs.basename(path))).toBe(1)
			end
		end)
		mover.reset()
		vim.cmd("Neotree close")
		vim.fn.delete(root, "rf")
		assert(ok, err)
	end)
end)
