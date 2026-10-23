local M = {}

function M.setup()
	local ok, lazy = pcall(require, "lazy")
	if ok then
		lazy.load({ plugins = { "neo-tree.nvim" } })
	end
	local loaded, neo = pcall(require, "neo-tree")
	if not loaded then
		return
	end
	local manager = require("neo-tree.sources.manager")
	local global_config = neo.ensure_config()
	if not M.registered then
		local function in_source_tab(action, state_index)
			return function(...)
				local state = select(state_index, ...)
				if state.tabid and not vim.api.nvim_tabpage_is_valid(state.tabid) then
					return
				end
				if state.name ~= "fox_query" and state.tabid and vim.t[state.tabid].fox_query_root then
					return
				end
				if state.tabid and state.tabid ~= vim.api.nvim_get_current_tabpage() then
					if
						not state.winid
						or not vim.api.nvim_win_is_valid(state.winid)
						or vim.api.nvim_win_get_tabpage(state.winid) ~= state.tabid
					then
						return
					end
					local previous = vim.api.nvim_get_current_win()
					vim.api.nvim_set_current_win(state.winid)
					local success, err = pcall(action, ...)
					if vim.api.nvim_win_is_valid(previous) then
						vim.api.nvim_set_current_win(previous)
					end
					if not success then
						error(err)
					end
					return
				end
				return action(...)
			end
		end
		-- Neo-tree debounces navigation and rendering; keep both in their owning tab.
		local renderer = require("neo-tree.ui.renderer")
		local filesystem = require("neo-tree.sources.filesystem")
		renderer.show_nodes = in_source_tab(renderer.show_nodes, 2)
		filesystem._navigate_internal = in_source_tab(filesystem._navigate_internal, 1)
		local config = vim.deepcopy(global_config.filesystem)
		config.name = "fox_query"
		config.window.position = "current"
		config.window.mappings = {}
		config.bind_to_cwd = false
		config.follow_current_file = { enabled = false }
		config.enable_source_selector = false
		manager.setup("fox_query", config, global_config, { setup = function() end, navigate = function() end })
		M.registered = true
	end
	return manager
end

function M.draw(query, entries)
	local win = query.queries_win
	if
		query.compact
		and query.sql_win
		and vim.api.nvim_win_is_valid(query.sql_win)
		and vim.api.nvim_win_get_buf(query.sql_win) == query.queries_buf
	then
		win = query.sql_win
	end
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local manager = M.setup()
	if not manager then
		return
	end
	local state = manager.get_state("fox_query", query.tab, win)
	state.current_position = "current"
	state.path = require("fox.query.storage").path(query.root, "queries")
	local nodes, directories = {}, {}
	for _, entry in ipairs(entries) do
		local node = {
			id = entry.relative,
			name = vim.fs.basename(entry.relative),
			path = state.path .. "/" .. entry.relative,
			type = entry.directory and "directory" or "file",
			loaded = true,
			children = entry.directory and {} or nil,
			extra = entry,
		}
		local parent = directories[vim.fs.dirname(entry.relative)]
		table.insert(parent and parent.children or nodes, node)
		if entry.directory then
			directories[entry.relative] = node
		end
	end
	state.default_expanded_nodes = vim.tbl_keys(query.query_expanded or {})
	require("neo-tree.ui.renderer").show_nodes(nodes, state)
	query.query_tree, query.queries_buf = state, state.bufnr
	vim.b[state.bufnr].fox_query_root = query.root
	vim.wo[win].winbar = "SQL FILES | a SQL  A Folder  r Rename  d Delete"
end

function M.selected(query)
	local state = query.query_tree
	local node = state
		and state.tree
		and state.winid
		and vim.api.nvim_win_is_valid(state.winid)
		and state.tree:get_node(vim.api.nvim_win_get_cursor(state.winid)[1])
	return node and node.extra
end

function M.toggle(query)
	local state = query.query_tree
	local node = state and state.tree and state.tree:get_node()
	if node then
		if node:is_expanded() then
			node:collapse()
			query.query_expanded[node:get_id()] = nil
		else
			node:expand()
			query.query_expanded[node:get_id()] = true
		end
		require("neo-tree.ui.renderer").redraw(state)
	end
end

return M
