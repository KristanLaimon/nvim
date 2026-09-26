-- ============================================================================
-- fox.core.z_index -- Centralized In-Memory Dynamic Z-Index Manager
-- ============================================================================
-- WHY THIS EXISTS
--   Multiple floating UI components (Git Center, File Explorer / Neo-tree,
--   Input Modal, Task Runner, etc.) can be opened simultaneously or toggled in
--   any order. Without a centralized z-index stack, fixed z-index values (e.g.
--   100, 130) cause clipping or hidden popups depending on opening order.
--
-- DESIGN
--   * In-memory stack tracking active top-level UI components.
--   * Stacks layer dynamically: opening UI A gets base z-index 50; opening UI B
--     second gets base z-index 100 so it sits cleanly on top.
--   * Sub-components (e.g. commit log, diff modal, tabs) register with a `parent`
--     or `offset` relative to their parent component's base z-index.
--   * `WinClosed` autocmds automatically unregister windows on close.
--   * Fully in-memory -- no disk persistence.
-- ============================================================================

local M = {}

--- Default base z-index for the lowest floating layer.
M.BASE_ZINDEX = 50

--- Step increment between top-level stack layers.
M.STEP = 50

--- Active top-level stack component names, ordered from bottom to top.
--- @type string[]
M._stack = {}

--- Map of component name -> metadata
--- { name: string, base_zindex: number, windows: table<integer, number>, parent: string|nil }
--- @type table<string, table>
M._components = {}

--- Map of window ID -> component name
--- @type table<integer, string>
M._win_to_component = {}

--- Returns a shallow copy of the active component stack (bottom to top).
--- @return string[]
function M.active_stack()
	return vim.list_slice(M._stack)
end

--- Resets all in-memory z-index tracking.
function M.clear()
	M._stack = {}
	M._components = {}
	M._win_to_component = {}
end

--- Gets or allocates the base z-index for `name`.
---
--- @param name string Component identifier (e.g. "git_center", "file_explorer", "input_modal").
--- @param opts table|nil { parent?: string, offset?: number, step?: number, base?: number }
--- @return integer zindex Calculated z-index.
function M.next_zindex(name, opts)
	opts = opts or {}
	local offset = opts.offset or 0
	local step = opts.step or M.STEP
	local base_floor = opts.base or M.BASE_ZINDEX

	-- If a parent component is specified and exists, derive from parent's base_zindex
	if opts.parent and M._components[opts.parent] then
		return M._components[opts.parent].base_zindex + (opts.offset or 10)
	end

	-- If this component is already registered in the stack, reuse its base_zindex
	if M._components[name] then
		return M._components[name].base_zindex + offset
	end

	-- Otherwise compute top-of-stack base_zindex
	local max_base = base_floor - step
	for _, comp_name in ipairs(M._stack) do
		local comp = M._components[comp_name]
		if comp and comp.base_zindex > max_base then
			max_base = comp.base_zindex
		end
	end

	local new_base = math.max(base_floor, max_base + step)
	return new_base + offset
end

--- Registers a UI component and its window(s) in the z-index stack.
---
--- @param name string Component identifier.
--- @param wins integer|integer[]|nil Window handle or list of handles.
--- @param opts table|nil { parent?: string, offset?: number, zindex?: number }
--- @return integer zindex The assigned z-index for the main window / component.
function M.register(name, wins, opts)
	opts = opts or {}
	local offset = opts.offset or 0
	local z_assigned = opts.zindex or M.next_zindex(name, opts)

	-- Ensure component entry exists in M._components
	if not M._components[name] then
		local base_z = opts.parent and M._components[opts.parent] and M._components[opts.parent].base_zindex
			or (z_assigned - offset)

		M._components[name] = {
			name = name,
			base_zindex = base_z,
			windows = {},
			parent = opts.parent,
		}

		-- If not a child of another component, add to top of stack
		if not opts.parent then
			local exists_in_stack = false
			for _, n in ipairs(M._stack) do
				if n == name then
					exists_in_stack = true
					break
				end
			end
			if not exists_in_stack then
				table.insert(M._stack, name)
			end
		end
	end

	local comp = M._components[name]

	-- Attach windows if provided
	if wins then
		local handle_list = (type(wins) == "table" and not wins.relative) and wins or { wins }
		for _, win in ipairs(handle_list) do
			if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
				pcall(vim.api.nvim_win_set_config, win, { zindex = z_assigned })
				comp.windows[win] = offset
				M._win_to_component[win] = name

				-- Auto-unregister window on WinClosed
				local win_id = win
				vim.api.nvim_create_autocmd("WinClosed", {
					pattern = tostring(win_id),
					once = true,
					callback = function()
						vim.schedule(function()
							M.unregister_window(win_id)
						end)
					end,
				})
			end
		end
	end

	return z_assigned
end

--- Promotes a component to the top of the stack and updates all its windows.
---
--- @param name string Component identifier.
function M.bring_to_front(name)
	local comp = M._components[name]
	if not comp then
		return
	end

	-- Remove from current position in stack
	for idx, comp_name in ipairs(M._stack) do
		if comp_name == name then
			table.remove(M._stack, idx)
			break
		end
	end

	-- Insert at top of stack
	table.insert(M._stack, name)

	-- Recalculate stack base z-indices
	for idx, comp_name in ipairs(M._stack) do
		local c = M._components[comp_name]
		if c then
			c.base_zindex = M.BASE_ZINDEX + (idx - 1) * M.STEP
			for win, offset in pairs(c.windows) do
				if vim.api.nvim_win_is_valid(win) then
					pcall(vim.api.nvim_win_set_config, win, { zindex = c.base_zindex + offset })
				end
			end
		end
	end
end

--- Unregisters a specific window handle. If no windows remain for the component,
--- unregisters the entire component from the stack.
---
--- @param win integer Window handle.
function M.unregister_window(win)
	local name = M._win_to_component[win]
	if not name then
		return
	end

	M._win_to_component[win] = nil

	local comp = M._components[name]
	if comp then
		comp.windows[win] = nil

		-- Check if any valid windows remain
		local has_valid = false
		for w, _ in pairs(comp.windows) do
			if vim.api.nvim_win_is_valid(w) then
				has_valid = true
				break
			end
		end

		if not has_valid then
			M.unregister(name)
		end
	end
end

--- Unregisters a component and removes it from the active stack.
---
--- @param name string Component identifier.
function M.unregister(name)
	local comp = M._components[name]
	if not comp then
		return
	end

	for win, _ in pairs(comp.windows) do
		M._win_to_component[win] = nil
	end

	M._components[name] = nil

	for idx, comp_name in ipairs(M._stack) do
		if comp_name == name then
			table.remove(M._stack, idx)
			break
		end
	end
end

--- Returns the active z-index for a component, or computes what it would be if opened now.
---
--- @param name string Component identifier.
--- @param offset number|nil Optional relative offset.
--- @return integer zindex
function M.get_zindex(name, offset)
	offset = offset or 0
	if M._components[name] then
		return M._components[name].base_zindex + offset
	end
	return M.next_zindex(name, { offset = offset })
end

return M
