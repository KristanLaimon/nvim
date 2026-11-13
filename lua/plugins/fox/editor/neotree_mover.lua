-- ============================================================================
-- FOX PLUGIN: Neo-tree Mover ("En la mano" cut & paste workflow)
-- ============================================================================
-- WHAT IT DOES:
--   1. Replaces the old move picker menu in Neo-tree with a two-step move:
--      - First 'm' on a file or folder: picks it up "En la mano" and shows
--        a persistent toast notification.
--      - Second 'm' on a target node / directory in Neo-tree: moves the item
--        into that destination directory.
--   2. Same-directory detection: If the destination is the same place where the
--      item already was, cancels the move and warns the user.
--   3. Circular move prevention: If moving a directory, prevents moving it into
--      itself or any of its subdirectories.
--   4. Conflict detection: If an item with the same name already exists in the
--      target directory, cancels the move and reports the conflict.
--   5. Escape to cancel: Pressing <Esc> while holding an item cancels the move
--      and dismisses the persistent toast.
--   6. Buffer updates: Uses buffer_rename to keep open editor buffers and
--      bufferline tabs in sync.
--   7. LSP notifications: Fires neo-tree FILE_MOVED event for lsp file operations.
-- ============================================================================

local M = {}

M.held_item = nil
M.held_items = nil
M.toast_record = nil
M.toast_id = "neotree_mover_toast"

--- Normalizes a path, stripping trailing slashes and converting slashes.
--- @param p string|nil
--- @return string
function M.normalize_path(p)
	if not p or p == "" then
		return ""
	end
	local clean = vim.fs.normalize(p)
	if #clean > 1 and clean:sub(-1) == "/" then
		clean = clean:sub(1, -2)
	end
	return clean
end

--- Returns true if an item is currently held in hand.
--- @return boolean
function M.is_holding()
	return M.held_item ~= nil
end

--- Returns a copy of the held item, or nil.
--- @return table|nil
function M.get_held_item()
	if not M.held_item then
		return nil
	end
	return vim.deepcopy(M.held_item)
end

--- Resolves the target directory based on the selected Neo-tree node.
--- If the node is a directory, returns its path.
--- If the node is a file, returns its containing directory.
--- Falls back to state.path or getcwd().
--- @param node table|nil
--- @param state table|nil
--- @return string dir_path
function M.resolve_target_dir(node, state)
	if node and node.path and node.path ~= "" then
		local norm_path = M.normalize_path(node.path)
		if node.type == "directory" or vim.fn.isdirectory(norm_path) == 1 then
			return norm_path
		else
			return M.normalize_path(vim.fn.fnamemodify(norm_path, ":h"))
		end
	end

	if state and state.path and state.path ~= "" then
		return M.normalize_path(state.path)
	end

	return M.normalize_path(vim.fn.getcwd())
end

--- Displays a persistent toast notification indicating the item is "En la mano".
--- @param item table
function M.show_persistent_toast(item)
	local icon = item.is_dir and "📁" or "📄"
	local msg = string.format(
		"✋ En la mano: %s %s\n\n➜ Navega a la carpeta destino y presiona 'm' para moverlo aquí.\n➜ Presiona 'm' en el mismo lugar o <Esc> para cancelar.",
		icon,
		item.name
	)

	-- 1. Use the native notification compatibility API
	local ok_notify, notify = pcall(require, "notify")
	if ok_notify and type(notify) == "table" and type(notify.notify) == "function" then
		pcall(function()
			M.toast_record = notify.notify(msg, vim.log.levels.INFO, {
				title = "Neo-tree",
				timeout = false,
				keep = function()
					return M.is_holding()
				end,
			})
		end)
		return
	end

	-- 2. Try fox.core.notify
	local ok_fox, fox_notify = pcall(require, "fox.core.notify")
	if ok_fox and fox_notify.notify_progress then
		pcall(fox_notify.notify_progress, M.toast_id, msg, vim.log.levels.INFO, { title = "Neo-tree" })
		return
	end

	-- 3. Fallback to vim.notify
	vim.notify(msg, vim.log.levels.INFO, { title = "Neo-tree" })
end

--- Dismisses or replaces the persistent toast notification.
--- If result_msg is provided, updates the toast with the result message and auto-dismisses.
--- If omitted, closes the toast silently.
--- @param result_msg string|nil
--- @param level number|nil
function M.dismiss_toast(result_msg, level)
	level = level or vim.log.levels.INFO

	-- 1. Update the native notification record
	local ok_notify, notify = pcall(require, "notify")
	if ok_notify and type(notify) == "table" and type(notify.notify) == "function" then
		if M.toast_record and M.toast_record.id then
			if result_msg and result_msg ~= "" then
				pcall(notify.notify, result_msg, level, {
					title = "Neo-tree",
					replace = M.toast_record.id,
					timeout = 2500,
				})
			else
				pcall(notify.notify, "", vim.log.levels.INFO, {
					replace = M.toast_record.id,
					timeout = 1,
					hide_from_history = true,
				})
			end
			M.toast_record = nil
			return
		end
	end

	-- 2. Handle fox.core.notify
	local ok_fox, fox_notify = pcall(require, "fox.core.notify")
	if ok_fox and fox_notify then
		if result_msg and result_msg ~= "" then
			if fox_notify.notify_progress and fox_notify.finish_progress then
				pcall(fox_notify.notify_progress, M.toast_id, result_msg, level, { title = "Neo-tree" })
				pcall(fox_notify.finish_progress, M.toast_id, 2500)
				return
			end
		else
			if fox_notify.dismiss_progress then
				pcall(fox_notify.dismiss_progress, M.toast_id)
				return
			elseif fox_notify.finish_progress then
				pcall(fox_notify.finish_progress, M.toast_id, 0)
				return
			end
		end
	end

	-- 3. Fallback
	if result_msg and result_msg ~= "" then
		vim.notify(result_msg, level, { title = "Neo-tree" })
	end
end

--- Cancels any pending move operation and dismisses the persistent toast.
--- @return boolean cancelled True if an operation was cancelled
function M.cancel()
	if not M.is_holding() then
		return false
	end

	M.held_item = nil
	M.held_items = nil
	M.dismiss_toast("Movimiento cancelado.", vim.log.levels.INFO)
	return true
end

--- Resets state silently without notification (e.g. on Neo-tree close).
function M.reset()
	if M.is_holding() then
		M.held_item = nil
		M.held_items = nil
		M.dismiss_toast(nil)
	end
end

--- Picks up a node or visual selection, or drops held items at the target.
--- @param node table|nil
--- @param state table|nil
--- @param selected_nodes table[]|nil
function M.handle_move(node, state, selected_nodes)
	if not M.is_holding() then
		local items, seen = {}, {}
		for _, selected in ipairs(selected_nodes or { node }) do
			if selected.path and selected.path ~= "" and (selected.type == "file" or selected.type == "directory") then
				local path = M.normalize_path(selected.path)
				if not seen[path] then
					seen[path] = true
					table.insert(items, {
						path = path,
						name = selected.name or vim.fn.fnamemodify(path, ":t"),
						type = selected.type,
						is_dir = selected.type == "directory" or vim.fn.isdirectory(path) == 1,
						parent = M.normalize_path(vim.fn.fnamemodify(path, ":h")),
					})
				end
			end
		end
		-- Expanded folders already carry their selected descendants with them.
		items = vim.tbl_filter(function(item)
			for _, parent in ipairs(items) do
				if parent.is_dir and item.path:sub(1, #parent.path + 1) == parent.path .. "/" then
					return false
				end
			end
			return true
		end, items)
		if #items == 0 then
			vim.notify("No files or folders selected to move.", vim.log.levels.WARN, { title = "Neo-tree" })
			return
		end
		M.held_items, M.held_item = items, items[1]
		M.show_persistent_toast(#items == 1 and items[1] or { name = string.format("%d items", #items) })
		return
	end

	local items = M.held_items
	local target_dir = M.resolve_target_dir(node, state)
	local uv = vim.uv or vim.loop
	local destinations = {}
	-- Validate the entire selection before moving anything.
	for _, held in ipairs(items) do
		local dest_path = M.normalize_path(target_dir .. "/" .. held.name)
		local err
		if target_dir == held.parent or dest_path == held.path then
			err = string.format("'%s' is already in this directory. Move cancelled.", held.name)
		elseif held.is_dir and (target_dir == held.path or target_dir:sub(1, #held.path + 1) == held.path .. "/") then
			err = string.format("Cannot move '%s' into itself. Move cancelled.", held.name)
		elseif destinations[dest_path] or uv.fs_stat(dest_path) ~= nil then
			err = string.format("An item named '%s' already exists at the destination. Move cancelled.", held.name)
		end
		if err then
			M.held_item, M.held_items = nil, nil
			M.dismiss_toast(err, vim.log.levels.WARN)
			return
		end
		destinations[dest_path] = true
	end

	if vim.fn.isdirectory(target_dir) == 0 then
		vim.fn.mkdir(target_dir, "p")
	end

	local moved = 0
	local failure
	for _, held in ipairs(items) do
		local dest_path = M.normalize_path(target_dir .. "/" .. held.name)
		local ok, err = os.rename(held.path, dest_path)
		if not ok then
			ok, err = uv.fs_rename(held.path, dest_path)
		end
		if not ok then
			failure = string.format("Moved %d of %d items. Error moving '%s': %s", moved, #items, held.name, tostring(err))
			break
		end
		moved = moved + 1
		local ok_ev, events = pcall(require, "neo-tree.events")
		if ok_ev and events and events.FILE_MOVED then
			pcall(events.fire_event, events.FILE_MOVED, { source = held.path, destination = dest_path })
		end
		local ok_br, buffer_rename = pcall(require, "fox.core.buffer_rename")
		if ok_br and buffer_rename and buffer_rename.update_buffers_path then
			pcall(buffer_rename.update_buffers_path, held.path, dest_path)
		end
	end

	M.held_item, M.held_items = nil, nil
	pcall(function()
		require("neo-tree.sources.manager").refresh("filesystem")
	end)
	M.dismiss_toast(
		failure or string.format("Moved %d item(s) to %s", moved, target_dir),
		failure and vim.log.levels.ERROR or vim.log.levels.INFO
	)
end

--- Helper for Ex command / Command Palette invocation.
function M.handle_move_ex()
	local ok, manager = pcall(require, "neo-tree.sources.manager")
	if ok and manager then
		local state = manager.get_state("filesystem")
		local node = state and state.tree and state.tree:get_node()
		M.handle_move(node, state)
	else
		vim.notify("Neo-tree no está activo", vim.log.levels.WARN, { title = "Neo-tree" })
	end
end

M.name = "fox_neotree_mover"
M.dir = require("fox.core.lazyspec").for_module()
M.lazy = true
M.config = function() end

return M
