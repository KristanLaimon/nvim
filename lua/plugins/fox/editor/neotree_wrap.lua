local M = { enabled = false }
local ns = vim.api.nvim_create_namespace("FoxNeoTreeWrap")

-- Keep full names before Neovim wraps them; the default container truncates them.
function M.container(config, node, state, remaining_width)
	if M.enabled then
		config = vim.tbl_extend("force", config, { width = "fit_content", enable_character_fade = false })
		-- One layer lets status badges share space without clipping the name.
		config.content = vim.tbl_map(function(component)
			return vim.tbl_extend("force", component, { zindex = 10 })
		end, config.content)
	end
	return require("neo-tree.sources.common.components").container(config, node, state, remaining_width)
end

function M.apply(state)
	if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
		return
	end
	if state.winid and vim.api.nvim_win_is_valid(state.winid) then
		local wo = vim.wo[state.winid]
		wo.wrap = M.enabled
		wo.linebreak = M.enabled
		wo.breakindent = M.enabled
	end
	vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
	if M.enabled and state.tree then
		for line = 1, vim.api.nvim_buf_line_count(state.bufnr) do
			local node, _, last = state.tree:get_node(line)
			if node and line == last then
				-- Virtual spacing keeps file actions and node-to-line lookup intact.
				vim.api.nvim_buf_set_extmark(state.bufnr, ns, line - 1, 0, {
					virt_lines = { { { "", "Normal" } } },
				})
			end
		end
	end
end

function M.prepare(state)
	state.components.container = M.container
end

function M.toggle()
	M.enabled = not M.enabled
	require("neo-tree.sources.manager")._for_each_state(nil, function(state)
		M.prepare(state)
		require("neo-tree.ui.renderer").redraw(state)
		M.apply(state)
	end)
	vim.notify("Neo-tree word wrap: " .. (M.enabled and "on" or "off"), vim.log.levels.INFO)
end

M.name = "fox_neotree_wrap"
M.dir = require("fox.core.lazyspec").for_module()
M.lazy = true

return M
