local store = require("fox.core.store")
local M = {}

M.store_file = vim.fn.stdpath("state") .. "/neotree_center.json"
M.enabled = store.load(M.store_file, {}).enabled ~= false

function M.apply(state)
	if state.winid and vim.api.nvim_win_is_valid(state.winid) then
		-- Native scrolling already stops centering at the start and end of the tree.
		vim.wo[state.winid].scrolloff = M.enabled and 999 or -1
	end
end

function M.toggle()
	local enabled = not M.enabled
	local ok, err = store.save(M.store_file, { enabled = enabled })
	if not ok then
		vim.notify("Could not save Neo-tree cursor centering: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	M.enabled = enabled
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "neo-tree" then
			M.apply({ winid = win })
		end
	end
	vim.notify("Neo-tree cursor centering: " .. (M.enabled and "on" or "off"), vim.log.levels.INFO)
end

M.name = "fox_neotree_center"
M.dir = require("fox.core.lazyspec").for_module()
M.lazy = true

return M
