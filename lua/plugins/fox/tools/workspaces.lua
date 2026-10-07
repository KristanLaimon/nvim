-- ============================================================================
-- FOX PLUGIN: Workspaces -- named sessions per project.
-- ============================================================================
-- WHAT IT DOES
--   1. Saves the exact window/tab/buffer layout with `mksession!`.
--   2. Keeps every session file in `stdpath("data")/workspaces`, indexed by a
--      single `index.json` holding names, project paths, dates and open buffers.
--   3. Offers a Telescope picker (`<C-S-w>`) to load, delete, rename, overwrite,
--      or filter workspaces, plus Harpoon-style slots 1..9.
--   4. Returns to the dashboard with `<leader>wm`, optionally saving first.
--
-- PICKER KEYS
--   <CR> load   d delete   r rename   a new   s overwrite   g all/current   1-9 slot
--
-- WHY NEO-TREE AND TERMINALS ARE PURGED AROUND A SESSION
--   `mksession!` serializes them as ordinary buffers, and restoring that produces
--   dead neo-tree windows and detached terminals. They are closed before saving,
--   re-opened after, and never written into the session file.
--
-- INDEX FORMAT -- `<data>/workspaces/index.json`
--   [{ "id": "ws_1712345678_4821", "name": "API work", "cwd": "C:/proj",
--      "cwd_name": "proj", "created_at": 0, "updated_at": 0,
--      "session_file": "<data>/workspaces/ws_....vim",
--      "buffers": ["src/app.ts"], "tab_count": 2, "neotree_open": true,
--      "terminal_open": true, "terminal_slot": 1 }]
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local store = lazy_req("fox.core.store")
local path = lazy_req("fox.core.path")
local project = lazy_req("fox.core.project")

local M = {}

--- Currently active loaded workspace record.
M.current_workspace = nil

--- Returns the currently active workspace record, or nil.
--- @return table|nil
function M.get_active_workspace()
	return M.current_workspace
end

--- Sets the active workspace record.
--- @param ws table|nil
function M.set_active_workspace(ws)
	M.current_workspace = ws
end

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

M.settings = {
	--- Where session files and the index live.
	storage_dir = vim.fn.stdpath("data") .. "/workspaces",

	--- Index file name inside `storage_dir`.
	index_file = "index.json",

	--- Title on every notification from this module.
	notify_title = "FOX Workspaces",

	--- What `mksession!` records. `terminal` is deliberately absent so workspaces
	--- never restore terminal splits.
	session_options = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,localoptions",

	--- Quick-load slots exposed as `<leader>w1..9` and `1..9` inside the picker.
	quick_slots = 9,

	--- Filetypes treated as transient UI: closed before saving, purged on load.
	transient_filetypes = { "TaskRunner", "toggleterm" },

	keys = {
		--- Open the workspace picker.
		select = { "<C-S-w>", "<C-S-W>", "<leader>ws" },
		--- Close everything and return to the dashboard.
		menu = { "<leader>wm" },
		--- Focus floating workspace indicator badge.
		focus_badge = { "<C-S-b>", "<C-S-B>", "<leader>wb", "<leader>wf", "<A-w>", "<M-w>" },
		--- Leader mappings: save, select, back to menu.
		leader_save = nil,
		leader_select = nil,
		leader_menu = nil,
		--- Prefix for quick slots, the slot number is appended.
		leader_slot_prefix = nil,
	},
}

--- Notification helper carrying the module's title.
--- @param msg string
--- @param level integer|nil Defaults to INFO.
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = M.settings.notify_title })
end

-- ============================================================================
-- ============================================================================
-- INDEX STORAGE & SESSION DISCOVERY
-- ============================================================================

--- Session storage directory, created on first use.
--- Defaults to `<data>/workspaces` unless explicitly overridden (e.g. in unit tests).
--- @param root_dir string|nil
--- @return string dir
local function storage_dir(_root_dir)
	if M.settings.storage_dir and M.settings.storage_dir ~= (vim.fn.stdpath("data") .. "/workspaces") then
		return path.ensure_dir(M.settings.storage_dir)
	end
	return path.ensure_dir(path.join(vim.fn.stdpath("data"), "workspaces"))
end

--- Absolute path of the index file.
--- @param root_dir string|nil
--- @return string filepath
local function index_path(root_dir)
	return path.join(storage_dir(root_dir), M.settings.index_file)
end

--- Parses a session file on disk to extract its metadata (cwd, buffers, name, created_at).
--- @param filepath string
--- @return table|nil
local function parse_session_file(filepath)
	if not path.is_file(filepath) then
		return nil
	end
	local lines = vim.fn.readfile(filepath)
	local cwd = ""
	local bufs = {}
	local custom_name = nil
	for _, l in ipairs(lines) do
		local m_ws = l:match('^"%s*FoxWorkspace:%s*name=(.+)') or l:match('^"%s*Workspace:%s*(.+)')
		if m_ws and not custom_name then
			custom_name = vim.trim(m_ws)
		end
		local cd = l:match("^cd%s+(.+)")
		if cd and cwd == "" then
			cwd = vim.fn.expand(vim.trim(cd))
		end
		local b = l:match("^badd%s+%+?%d*%s*(.+)")
		if b then
			b = vim.fn.expand(vim.trim(b))
			if cwd ~= "" and b:sub(1, #cwd) == cwd then
				b = b:sub(#cwd + 2)
			end
			table.insert(bufs, b)
		end
	end

	local id = vim.fn.fnamemodify(filepath, ":t:r")
	local ts = tonumber(id:match("ws_(%d+)_")) or os.time()
	local cwd_name = cwd ~= "" and vim.fn.fnamemodify(cwd, ":t") or "Project"
	local name = custom_name
	if not name or name == "" then
		if #bufs > 0 then
			local first_buf_name = vim.fn.fnamemodify(bufs[1], ":t")
			name = string.format("%s (%s)", cwd_name, first_buf_name)
		else
			name = string.format("%s (%s)", cwd_name, os.date("%b %d %H:%M", ts))
		end
	end

	return {
		id = id,
		name = name,
		cwd = cwd ~= "" and cwd or vim.fn.getcwd(),
		cwd_name = cwd_name,
		created_at = ts,
		updated_at = ts,
		session_file = filepath,
		buffers = bufs,
		tab_count = 1,
		neotree_open = true,
	}
end

--- Loads all workspaces across all known projects and reconciles orphaned sessions.
--- @return table[]
local function load_all_workspaces()
	local sdir = storage_dir()
	local ipath = index_path()

	local entries = store.load(ipath, {})
	if type(entries) ~= "table" then
		entries = {}
	end

	local seen_ids = {}
	local result = {}

	for _, item in ipairs(entries) do
		if item and item.id and not seen_ids[item.id] then
			seen_ids[item.id] = true
			table.insert(result, item)
		end
	end

	-- Also check current project root or cwd .foxnvim/workspaces if present (when using default storage)
	local is_custom = M.settings.storage_dir and M.settings.storage_dir ~= (vim.fn.stdpath("data") .. "/workspaces")
	if not is_custom then
		local p_root = project and project.root and project.root()
		local project_dirs = { vim.fn.getcwd(), p_root }
		for _, pdir in ipairs(project_dirs) do
			if pdir and pdir ~= "" then
				local local_idx_file = path.join(pdir, ".foxnvim", "workspaces", M.settings.index_file)
				if path.is_file(local_idx_file) then
					local local_entries = store.load(local_idx_file, {})
					if type(local_entries) == "table" then
						for _, item in ipairs(local_entries) do
							if item and item.id and not seen_ids[item.id] then
								seen_ids[item.id] = true
								table.insert(result, item)
							end
						end
					end
				end
			end
		end
	end

	-- Reconcile orphaned session files in session storage directory
	if path.is_dir(sdir) then
		local disk_files = vim.fn.glob(path.join(sdir, "*.vim"), false, true)
		local recovered_any = false
		for _, f in ipairs(disk_files) do
			local id = vim.fn.fnamemodify(f, ":t:r")
			if not seen_ids[id] then
				local recovered = parse_session_file(f)
				if recovered then
					seen_ids[id] = true
					table.insert(result, recovered)
					recovered_any = true
				end
			end
		end

		if recovered_any then
			pcall(function()
				store.save(ipath, result)
			end)
		end
	end

	return result
end

--- Loads the workspace index for the given root_dir, or all workspaces if root_dir is nil.
--- @param root_dir string|nil
--- @return table[] index List of workspace records.
local function load_index(root_dir)
	local all = load_all_workspaces()
	if not root_dir then
		return all
	end

	local filtered = {}
	for _, item in ipairs(all) do
		if path.equals(item.cwd or "", root_dir) then
			table.insert(filtered, item)
		end
	end
	return filtered
end

--- Writes the workspace index back to disk, merging with the global index cache.
--- @param index table[] Workspace records.
--- @param root_dir string|nil
--- @return boolean ok
local function save_index(index, root_dir)
	if M.settings.storage_dir and M.settings.storage_dir ~= (vim.fn.stdpath("data") .. "/workspaces") then
		return store.save(index_path(), index)
	end

	local global_path = path.join(vim.fn.stdpath("data"), "workspaces", M.settings.index_file)
	local global_entries = store.load(global_path, {})
	if type(global_entries) ~= "table" then
		global_entries = {}
	end

	local by_id = {}
	for i, entry in ipairs(global_entries) do
		if entry.id then
			by_id[entry.id] = i
		end
	end

	for _, item in ipairs(index) do
		if item.id and by_id[item.id] then
			global_entries[by_id[item.id]] = item
		elseif item.id then
			table.insert(global_entries, item)
			by_id[item.id] = #global_entries
		end
	end

	path.ensure_dir(path.join(vim.fn.stdpath("data"), "workspaces"))
	local ok = store.save(global_path, global_entries)

	-- If project has a .foxnvim/workspaces dir, also save project-specific entries there
	pcall(function()
		local p_root = root_dir or (project and project.root and project.root()) or vim.fn.getcwd()
		local p_ws_dir = path.join(p_root, ".foxnvim", "workspaces")
		if path.is_dir(p_ws_dir) then
			local project_entries = {}
			for _, item in ipairs(global_entries) do
				if path.equals(item.cwd or "", p_root) then
					table.insert(project_entries, item)
				end
			end
			store.save(path.join(p_ws_dir, M.settings.index_file), project_entries)
		end
	end)

	return ok
end

--- Finds a workspace by record, id, or (case-insensitive) name.
--- @param index table[] Loaded index.
--- @param identifier table|string Workspace record, id, or name.
--- @return table|nil workspace
--- @return integer|nil position Index in the list, for removal.
local function find_workspace(index, identifier)
	for idx, item in ipairs(index) do
		local matches = (type(identifier) == "table" and item.id == identifier.id)
			or (type(identifier) == "string" and (item.id == identifier or item.name:lower() == identifier:lower()))
		if matches then
			return item, idx
		end
	end
	return nil, nil
end

-- ============================================================================
-- SESSION SNAPSHOTTING
-- ============================================================================

--- "5 mins ago" style stamp used by the picker.
--- @param timestamp integer|nil Unix time.
--- @return string
local function format_relative_time(timestamp)
	if not timestamp then
		return ""
	end

	local diff = os.time() - timestamp
	if diff < 60 then
		return "just now"
	end

	local units = {
		{ limit = 3600, seconds = 60, label = "min" },
		{ limit = 86400, seconds = 3600, label = "hour" },
		{ limit = math.huge, seconds = 86400, label = "day" },
	}
	for _, unit in ipairs(units) do
		if diff < unit.limit then
			local value = math.floor(diff / unit.seconds)
			return string.format("%d %s%s ago", value, unit.label, value > 1 and "s" or "")
		end
	end
	return ""
end

--- Listed file buffers, as paths relative to the working directory.
--- @return string[] paths
local function get_current_buffers()
	local buflist = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(buf)
		if vim.fn.buflisted(buf) == 1 and name ~= "" and vim.bo[buf].buftype == "" then
			table.insert(buflist, vim.fn.fnamemodify(name, ":."))
		end
	end
	return buflist
end

--- True when a buffer belongs to neo-tree.
--- @param buf integer
--- @return boolean
local function is_neotree_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	return vim.bo[buf].filetype == "neo-tree" or vim.api.nvim_buf_get_name(buf):match("neo%-tree") ~= nil
end

--- True when neo-tree occupies any window.
--- @return boolean
local function is_neotree_open()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and is_neotree_buffer(vim.api.nvim_win_get_buf(win)) then
			return true
		end
	end
	return false
end

--- Deletes every neo-tree buffer, so `mksession!` cannot serialize a dead one.
local function purge_neotree_buffers()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if is_neotree_buffer(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end

--- Re-opens neo-tree on a directory and refreshes it.
--- @param dir string Directory to show.
local function show_neotree(dir)
	pcall(vim.cmd, "Neotree focus dir=" .. vim.fn.fnameescape(dir))
	pcall(function()
		require("neo-tree.sources.manager").refresh("filesystem")
	end)
end

--- True when a buffer is a terminal or one of the transient UI filetypes.
--- @param buf integer
--- @return boolean
local function is_transient_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if vim.bo[buf].buftype == "terminal" or vim.b[buf].fox_is_task then
		return true
	end
	return vim.tbl_contains(M.settings.transient_filetypes, vim.bo[buf].filetype)
end

--- Slot number of a terminal currently shown on screen, if any.
--- Terminals are closed before `mksession!`, so this has to be read first.
--- @return integer|nil slot
local function open_terminal_slot()
	local terms = _G._fox_terminals or {}
	local selected = _G._fox_selected_terminal
	if selected and terms[selected] and terms[selected].win and vim.api.nvim_win_is_valid(terms[selected].win) then
		return selected
	end
	for n, t in pairs(terms) do
		if t.win and vim.api.nvim_win_is_valid(t.win) then
			return n
		end
	end
	return nil
end

--- Writes the current layout to `session_path`.
--- Neo-tree and terminals are closed first and restored afterwards.
---
--- @param session_path string Destination `.vim` session file.
--- @return boolean ok
--- @return string|nil err
--- @return boolean neotree_was_open Whether neo-tree should reopen on load.
local function save_session_file(session_path, ws_name)
	vim.opt.sessionoptions = M.settings.session_options

	local neotree_was_open = is_neotree_open()
	pcall(vim.cmd, "Neotree close")

	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and is_transient_buffer(vim.api.nvim_win_get_buf(win)) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	purge_neotree_buffers()

	local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(session_path))

	if ok and ws_name and ws_name ~= "" then
		pcall(function()
			local lines = vim.fn.readfile(session_path)
			table.insert(lines, 1, '" FoxWorkspace: name=' .. ws_name)
			vim.fn.writefile(lines, session_path)
		end)
	end

	if neotree_was_open then
		show_neotree(vim.fn.getcwd())
	end

	return ok, err, neotree_was_open
end

-- ============================================================================
-- WORKSPACE OPERATIONS
-- ============================================================================

--- Saves the current layout as a workspace.
--- With no name: overwrites this project's first workspace, or prompts for a name
--- when the project has none yet.
---
--- @param name string|nil Workspace name.
--- @param callback function|nil Called after a successful save.
function M.save_workspace(name, callback)
	local cwd = vim.fn.getcwd()
	local cwd_name = vim.fn.fnamemodify(cwd, ":t")
	local index = load_all_workspaces()

	local function perform_save(ws_name)
		if not ws_name or ws_name == "" then
			local count = 1
			for _, item in ipairs(index) do
				if path.equals(item.cwd or "", cwd) then
					count = count + 1
				end
			end
			ws_name = string.format("%s (Workspace %d)", cwd_name, count)
		end

		local ws_item
		for _, item in ipairs(index) do
			if item.name:lower() == ws_name:lower() and path.equals(item.cwd or "", cwd) then
				ws_item = item
				break
			end
		end

		local id = ws_item and ws_item.id or ("ws_" .. os.time() .. "_" .. math.random(1000, 9999))
		local session_path = path.join(storage_dir(), id .. ".vim")

		-- Read the terminal state before save_session_file closes its window.
		local terminal_slot = open_terminal_slot()

		local ok, err, neotree_open = save_session_file(session_path, ws_name)
		if not ok then
			vim.notify("Error saving workspace: " .. tostring(err), vim.log.levels.ERROR)
			return
		end

		local snapshot = {
			updated_at = os.time(),
			buffers = get_current_buffers(),
			tab_count = #vim.api.nvim_list_tabpages(),
			session_file = session_path,
			neotree_open = neotree_open,
			terminal_open = terminal_slot ~= nil,
			terminal_slot = terminal_slot or 1,
		}

		if ws_item then
			for key, value in pairs(snapshot) do
				ws_item[key] = value
			end
		else
			table.insert(
				index,
				vim.tbl_extend("force", {
					id = id,
					name = ws_name,
					cwd = cwd,
					cwd_name = cwd_name,
					created_at = os.time(),
				}, snapshot)
			)
		end

		save_index(index, cwd)
		M.current_workspace = ws_item or index[#index]
		pcall(M.update_badge)
		notify("Workspace '" .. ws_name .. "' saved successfully!")
		if callback then
			callback()
		end
	end

	if name and name ~= "" then
		perform_save(name)
		return
	end

	for _, item in ipairs(index) do
		if path.equals(item.cwd or "", cwd) then
			perform_save(item.name)
			return
		end
	end

	pcall(vim.ui.input, {
		prompt = "New Workspace Name: ",
		default = cwd_name .. " - " .. os.date("%H:%M"),
	}, function(input_name)
		if input_name and input_name ~= "" then
			perform_save(input_name)
		elseif callback then
			callback()
		end
	end)
end

--- Prompts for a new workspace name and saves the current layout as a new workspace.
--- @param callback function|nil Called after saving or cancelling.
function M.new_workspace(callback)
	local cwd = vim.fn.getcwd()
	local cwd_name = vim.fn.fnamemodify(cwd, ":t")
	local index = load_all_workspaces()

	local count = 1
	for _, item in ipairs(index) do
		if path.equals(item.cwd or "", cwd) then
			count = count + 1
		end
	end
	local default_name = count > 1 and string.format("%s (Workspace %d)", cwd_name, count)
		or string.format("%s - %s", cwd_name, os.date("%H:%M"))

	pcall(vim.ui.input, {
		prompt = "New Workspace Name: ",
		default = default_name,
	}, function(input_name)
		if input_name and input_name ~= "" then
			M.save_workspace(input_name, callback)
		elseif callback then
			callback()
		end
	end)
end

--- Resolves the argument of `load_workspace` into a workspace record.
--- @param index table[] Loaded index.
--- @param identifier table|string|number Record, id/name, or slot within this project.
--- @return table|nil workspace
local function resolve_load_target(index, identifier)
	if type(identifier) == "table" then
		return identifier
	end

	if type(identifier) == "number" then
		if index[identifier] then
			return index[identifier]
		end
		local cwd = vim.fn.getcwd()
		local count = 0
		for _, item in ipairs(index) do
			if path.equals(item.cwd or "", cwd) then
				count = count + 1
				if count == identifier then
					return item
				end
			end
		end
		return nil
	end

	if type(identifier) == "string" and identifier ~= "" then
		return (find_workspace(index, identifier))
	end
	return nil
end

--- Restores a workspace: switches directory, sources the session, and rebuilds
--- the neo-tree / terminal state around it.
---
--- @param ws_or_identifier table|string|number Record, id/name, or slot number.
--- @return boolean loaded
function M.load_workspace(ws_or_identifier)
	local all = load_all_workspaces()
	local target = resolve_load_target(all, ws_or_identifier)

	if not target then
		notify("Workspace not found", vim.log.levels.WARN)
		return false
	end

	local session_file = target.session_file
	if not (session_file and path.is_file(session_file)) then
		local filename = (target.id and (target.id .. ".vim")) or vim.fn.fnamemodify(session_file or "", ":t")
		local candidates = {
			path.join(storage_dir(), filename),
			path.join(vim.fn.stdpath("data"), "workspaces", filename),
			path.join(vim.fn.expand("~"), ".foxnvim", "workspaces", filename),
		}
		if target.cwd then
			table.insert(candidates, path.join(target.cwd, ".foxnvim", "workspaces", filename))
		end

		for _, cand in ipairs(candidates) do
			if path.is_file(cand) then
				session_file = cand
				target.session_file = cand
				break
			end
		end
	end

	if not (session_file and path.is_file(session_file)) then
		notify("Session file does not exist: " .. tostring(target.session_file), vim.log.levels.ERROR)
		return false
	end

	-- Staying inside the same project keeps its terminals and task outputs alive;
	-- switching projects clears them, because they belong to the old root.
	local is_same_project = path.equals(vim.fn.getcwd(), target.cwd or vim.fn.getcwd())

	if target.cwd and vim.fn.getcwd() ~= target.cwd then
		pcall(vim.api.nvim_set_current_dir, target.cwd)
	end

	pcall(vim.cmd, "Neotree close")
	purge_neotree_buffers()

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and not (is_same_project and is_transient_buffer(buf)) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end

	local ok, err = pcall(vim.cmd, "source " .. vim.fn.fnameescape(session_file))
	if not ok then
		notify("Error loading session: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	-- Older session files may still contain neo-tree windows; drop them.
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and is_neotree_buffer(vim.api.nvim_win_get_buf(win)) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	purge_neotree_buffers()

	if is_same_project then
		pcall(function()
			require("plugins.fox.dev.tasks").sync_task_slots()
		end)
	else
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if is_transient_buffer(buf) then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
	end

	-- Workspaces open neo-tree by default unless explicitly disabled.
	if target.neotree_open ~= false then
		show_neotree(target.cwd or vim.fn.getcwd())
	end

	target.updated_at = os.time()
	save_index(all, target.cwd)
	M.current_workspace = target

	pcall(function()
		require("plugins.fox.ui.pinned_tabs").restore_pins()
	end)

	-- Bring back the terminal that was on screen when this workspace was saved.
	if target.terminal_open then
		pcall(function()
			require("plugins.fox.dev.terminal").open_terminal(target.terminal_slot or 1)
		end)
	end

	pcall(M.update_badge)
	notify("Workspace '" .. target.name .. "' loaded!")
	return true
end

--- Deletes a workspace and its session file, after a confirmation prompt.
--- @param ws_or_id table|string Record, id, or name.
--- @param callback function|nil Called after deletion.
function M.delete_workspace(ws_or_id, callback)
	local all = load_all_workspaces()
	local target, position = find_workspace(all, ws_or_id)

	if not target then
		notify("Workspace not found to delete", vim.log.levels.WARN)
		if callback then
			callback()
		end
		return
	end

	if vim.fn.confirm("Delete workspace '" .. target.name .. "'?", "&Yes\n&No", 2) ~= 1 then
		if callback then
			callback()
		end
		return
	end

	if target.session_file and path.is_file(target.session_file) then
		pcall(os.remove, target.session_file)
	end
	local fallback_file = path.join(storage_dir(), (target.id or "") .. ".vim")
	if path.is_file(fallback_file) then
		pcall(os.remove, fallback_file)
	end

	table.remove(all, position)
	if M.settings.storage_dir and M.settings.storage_dir ~= (vim.fn.stdpath("data") .. "/workspaces") then
		store.save(index_path(), all)
	else
		local global_path = path.join(vim.fn.stdpath("data"), "workspaces", M.settings.index_file)
		store.save(global_path, all)

		if target.cwd then
			local p_ws_idx = path.join(target.cwd, ".foxnvim", "workspaces", M.settings.index_file)
			if path.is_file(p_ws_idx) then
				local p_entries = {}
				for _, it in ipairs(all) do
					if path.equals(it.cwd or "", target.cwd) then
						table.insert(p_entries, it)
					end
				end
				store.save(p_ws_idx, p_entries)
			end
		end
	end

	if M.current_workspace and (M.current_workspace.id == target.id or M.current_workspace.name == target.name) then
		M.current_workspace = nil
	end
	pcall(M.update_badge)

	notify("Workspace '" .. target.name .. "' deleted.")
	if callback then
		callback()
	end
end

--- Renames a workspace through a prompt.
--- @param ws_or_id table|string Record, id, or name.
--- @param callback function|nil Called after renaming.
function M.rename_workspace(ws_or_id, callback)
	local all = load_all_workspaces()
	local target = find_workspace(all, ws_or_id)

	if not target then
		notify("Workspace not found to rename", vim.log.levels.WARN)
		return
	end

	pcall(vim.ui.input, { prompt = "New name for '" .. target.name .. "': ", default = target.name }, function(new_name)
		if new_name and new_name ~= "" and new_name ~= target.name then
			target.name = new_name
			target.updated_at = os.time()
			save_index(all, target.cwd)
			pcall(M.update_badge)
			notify("Workspace renamed to '" .. new_name .. "'")
			if callback then
				callback()
			end
		elseif callback then
			callback()
		end
	end)
end

--- Closes the session and returns to the dashboard, offering to save first.
function M.close_to_menu()
	if vim.bo.filetype == "alpha" then
		notify("Already at main menu")
		return
	end

	local function close_all_and_open_alpha()
		M.current_workspace = nil
		pcall(M.update_badge)
		pcall(vim.cmd, "Neotree close")
		purge_neotree_buffers()
		pcall(vim.cmd, "only")
		if not pcall(vim.cmd, "Alpha") then
			pcall(vim.cmd, "enew")
		end

		local alpha_buf = vim.api.nvim_get_current_buf()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if buf ~= alpha_buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype ~= "alpha" then
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
		end
	end

	local choices = {
		"1. 💾 Save Workspace and return to Menu",
		"2. 🚪 Return to Menu without saving",
		"3. ❌ Cancel",
	}

	pcall(vim.ui.select, choices, {
		prompt = "🦊 Close session and return to Main Menu (Dashboard)?",
	}, function(choice)
		if not choice or choice:match("^3") then
			return
		end
		if choice:match("^1") then
			M.save_workspace(nil, close_all_and_open_alpha)
		else
			close_all_and_open_alpha()
		end
	end)
end

-- ============================================================================
-- TOP-RIGHT CORNER WORKSPACE BADGE
-- ============================================================================

local badge_buf = nil
local badge_win = nil
local badge_visible = true

local function setup_badge_highlights()
	-- Solid pill badge highlights matching Git Diff Dashboard (log_diff.lua)
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadge", {
		fg = "#11111b",
		bg = "#f9e2af",
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeActive", {
		fg = "#11111b",
		bg = "#f9e2af",
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeInactive", {
		fg = "#11111b",
		bg = "#cba6f7",
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeTag", {
		fg = "#11111b",
		bg = "#f9e2af",
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeHead", {
		fg = "#11111b",
		bg = "#a6e3a1",
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeBranch", {
		fg = "#11111b",
		bg = "#cba6f7",
		bold = true,
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeSep", {
		fg = "#585b70",
		default = true,
	})
	vim.api.nvim_set_hl(0, "FoxWorkspaceBadgeBorder", {
		fg = "#585b70",
		default = true,
	})
end

--- Returns the active workspace slot number (1..N). If none or 1, returns 1.
--- @return integer
function M.get_active_slot_number()
	-- If Environments are active with multiple project slots, coordinate with active environment slot
	if _G._fox_environments and _G._fox_active_env_slot then
		local env_cnt = 0
		for s = 1, 9 do
			if _G._fox_environments[s] ~= nil then
				env_cnt = env_cnt + 1
			end
		end
		if env_cnt > 1 then
			return _G._fox_active_env_slot or 1
		end
	end

	local cur = M.get_active_workspace()
	if not cur then
		return 1
	end

	local index = load_index()
	local cwd = vim.fn.getcwd()
	local count = 0
	for _, item in ipairs(index) do
		if path.equals(item.cwd or "", cwd) then
			count = count + 1
			if item.id == cur.id or item.name == cur.name then
				return count
			end
		end
	end

	for idx, item in ipairs(index) do
		if item.id == cur.id or item.name == cur.name then
			return idx
		end
	end

	return 1
end

--- Constructs component chunks for the workspace badge (for bufferline custom_areas and float).
--- Formats as styled tag badges matching Git Diff Dashboard tags (e.g. ` 🦊 1 ` and ` 2 `).
--- @return table List of `{ text = string, hl = string }`
function M.get_badge_components()
	local active_slot = M.get_active_slot_number()
	local total = 1

	if _G._fox_environments then
		local env_cnt = 0
		for s = 1, 9 do
			if _G._fox_environments[s] ~= nil then
				env_cnt = math.max(env_cnt, s)
			end
		end
		total = math.max(total, env_cnt)
	end

	local ws_list = load_index()
	if #ws_list > 0 then
		total = math.max(total, #ws_list)
	end
	total = math.max(total, active_slot)

	local comps = {}
	for i = 1, total do
		if i > 1 then
			table.insert(comps, { text = " ", hl = "Normal" })
		end
		if i == active_slot then
			table.insert(comps, { text = " 🦊 " .. i .. " ", hl = "FoxWorkspaceBadgeActive" })
		else
			table.insert(comps, { text = " " .. i .. " ", hl = "FoxWorkspaceBadgeInactive" })
		end
	end
	return comps
end

--- Lists all workspaces for the given or active project root.
--- @param root_dir? string
--- @return table
function M.list_workspaces(root_dir)
	return load_index(root_dir)
end

--- Returns the full string representation of the badge, e.g. "/🦊1\/2\" or "/🦊1\"
--- @return string
function M.get_badge_text()
	local comps = M.get_badge_components()
	local parts = {}
	for _, c in ipairs(comps) do
		table.insert(parts, c.text)
	end
	return table.concat(parts, "")
end

--- Updates or creates the floating workspace indicator badge in the top right corner.
function M.update_badge()
	pcall(vim.cmd, "redrawtabline")

	if not badge_visible then
		if badge_win and vim.api.nvim_win_is_valid(badge_win) then
			pcall(vim.api.nvim_win_close, badge_win, true)
			badge_win = nil
		end
		return
	end

	if (_G.fox_testing or vim.g.fox_testing) and vim.fn.has("nvim-0.10") == 0 then
		return
	end

	setup_badge_highlights()

	local text = M.get_badge_text()
	local width = vim.fn.strdisplaywidth(text)
	local height = 1
	local total_cols = vim.o.columns or 80
	local col = math.max(0, total_cols - width - 1)
	local row = 0

	if not (badge_buf and vim.api.nvim_buf_is_valid(badge_buf)) then
		badge_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[badge_buf].buftype = "nofile"
		vim.bo[badge_buf].filetype = "foxworkspacebadge"
		vim.bo[badge_buf].bufhidden = "wipe"
		vim.bo[badge_buf].swapfile = false
		vim.bo[badge_buf].buflisted = false
		vim.b[badge_buf].fox_workspace_badge = true
	end

	vim.bo[badge_buf].modifiable = true
	vim.api.nvim_buf_set_lines(badge_buf, 0, -1, false, { text })
	vim.bo[badge_buf].modifiable = false

	local ns_badge = vim.api.nvim_create_namespace("FoxWorkspaceBadgeNs")
	vim.api.nvim_buf_clear_namespace(badge_buf, ns_badge, 0, -1)
	local comps = M.get_badge_components()
	local curr_col = 0
	for _, comp in ipairs(comps) do
		local comp_len = #comp.text
		pcall(vim.api.nvim_buf_add_highlight, badge_buf, ns_badge, comp.hl, 0, curr_col, curr_col + comp_len)
		curr_col = curr_col + comp_len
	end

	if badge_win and vim.api.nvim_win_is_valid(badge_win) then
		pcall(vim.api.nvim_win_set_config, badge_win, {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
		})
	else
		local win_opts = {
			relative = "editor",
			row = row,
			col = col,
			width = width,
			height = height,
			style = "minimal",
			border = "none",
			focusable = false,
			zindex = 100,
		}
		local ok_win, win = pcall(vim.api.nvim_open_win, badge_buf, false, win_opts)
		if ok_win and win and vim.api.nvim_win_is_valid(win) then
			badge_win = win
			vim.w[win].fox_workspace_badge = true
			pcall(vim.api.nvim_set_option_value, "winhighlight", "Normal:FoxWorkspaceBadge", { win = win })
		end
	end
end

local prev_editor_win = nil

--- Sets up buffer-local keymaps in the workspace badge buffer for interactive navigation.
local function setup_badge_keymaps()
	if not (badge_buf and vim.api.nvim_buf_is_valid(badge_buf)) then
		return
	end

	local function bmap(keys, fn, desc)
		local key_list = type(keys) == "table" and keys or { keys }
		for _, k in ipairs(key_list) do
			vim.keymap.set("n", k, fn, { buffer = badge_buf, noremap = true, silent = true, nowait = true, desc = desc })
		end
	end

	local function return_to_editor()
		if badge_win and vim.api.nvim_win_is_valid(badge_win) then
			pcall(vim.api.nvim_win_set_config, badge_win, { focusable = false })
		end
		if prev_editor_win and vim.api.nvim_win_is_valid(prev_editor_win) then
			pcall(vim.api.nvim_set_current_win, prev_editor_win)
		else
			pcall(vim.cmd, "wincmd p")
		end
	end

	local function re_focus_badge()
		vim.schedule(function()
			M.update_badge()
			if badge_win and vim.api.nvim_win_is_valid(badge_win) then
				pcall(vim.api.nvim_win_set_config, badge_win, { focusable = true })
				pcall(vim.api.nvim_set_current_win, badge_win)
			end
		end)
	end

	local function prev_slot()
		local env_ok, env_mod = pcall(require, "plugins.fox.tools.environments")
		if env_ok and env_mod.has_multiple_environments and env_mod.has_multiple_environments() then
			local cur_slot = env_mod.get_active_slot() or 1
			local all_envs = _G._fox_environments or {}
			local active_slots = {}
			for s = 1, 9 do
				if all_envs[s] then
					table.insert(active_slots, s)
				end
			end
			if #active_slots > 1 then
				local idx = 1
				for i, s in ipairs(active_slots) do
					if s == cur_slot then
						idx = i
						break
					end
				end
				local target_idx = (idx - 2) % #active_slots + 1
				local target_slot = active_slots[target_idx]
				env_mod.switch_environment(target_slot, re_focus_badge)
				return
			end
		else
			local idx_list = load_index()
			if #idx_list > 1 then
				local cur_slot = M.get_active_slot_number()
				local target_idx = (cur_slot - 2) % #idx_list + 1
				M.load_workspace(idx_list[target_idx])
				re_focus_badge()
				return
			end
		end
		re_focus_badge()
	end

	local function next_slot()
		local env_ok, env_mod = pcall(require, "plugins.fox.tools.environments")
		if env_ok and env_mod.has_multiple_environments and env_mod.has_multiple_environments() then
			local cur_slot = env_mod.get_active_slot() or 1
			local all_envs = _G._fox_environments or {}
			local active_slots = {}
			for s = 1, 9 do
				if all_envs[s] then
					table.insert(active_slots, s)
				end
			end
			if #active_slots > 1 then
				local idx = 1
				for i, s in ipairs(active_slots) do
					if s == cur_slot then
						idx = i
						break
					end
				end
				local target_idx = (idx % #active_slots) + 1
				local target_slot = active_slots[target_idx]
				env_mod.switch_environment(target_slot, re_focus_badge)
				return
			end
		else
			local idx_list = load_index()
			if #idx_list > 1 then
				local cur_slot = M.get_active_slot_number()
				local target_idx = (cur_slot % #idx_list) + 1
				M.load_workspace(idx_list[target_idx])
				re_focus_badge()
				return
			end
		end
		re_focus_badge()
	end

	local function jump_to_slot(slot)
		local env_ok, env_mod = pcall(require, "plugins.fox.tools.environments")
		if env_ok and _G._fox_environments and _G._fox_environments[slot] then
			env_mod.switch_environment(slot, re_focus_badge)
		else
			M.load_workspace(slot)
			re_focus_badge()
		end
	end

	bmap({ "<C-h>", "<C-H>", "h", "<Left>" }, prev_slot, "Previous workspace/environment slot")
	bmap({ "<C-l>", "<C-L>", "l", "<Right>" }, next_slot, "Next workspace/environment slot")
	for s = 1, 9 do
		bmap(tostring(s), function()
			jump_to_slot(s)
		end, "Jump to workspace slot " .. s)
	end
	bmap({ "<CR>", "<Space>" }, return_to_editor, "Confirm workspace and return to editor")
	bmap({ "<Esc>", "q", "<C-c>" }, return_to_editor, "Return to editor")
end

--- Focuses the top-right workspace badge, enabling slot switching via <C-h>/<C-l>/h/l/1..9
function M.focus_badge()
	if not badge_visible then
		badge_visible = true
	end
	M.update_badge()

	if not (badge_win and vim.api.nvim_win_is_valid(badge_win)) then
		return
	end

	local cur_win = vim.api.nvim_get_current_win()
	if cur_win ~= badge_win then
		prev_editor_win = cur_win
	end

	setup_badge_keymaps()

	-- Make badge window focusable and focus it
	pcall(vim.api.nvim_win_set_config, badge_win, { focusable = true })
	pcall(vim.api.nvim_set_current_win, badge_win)

	-- Autocmd to reset focusable on leaving the badge window
	local leave_group = vim.api.nvim_create_augroup("FoxWorkspaceBadgeFocus", { clear = true })
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = leave_group,
		buffer = badge_buf,
		callback = function()
			if badge_win and vim.api.nvim_win_is_valid(badge_win) then
				pcall(vim.api.nvim_win_set_config, badge_win, { focusable = false })
			end
		end,
	})
end

--- Toggles the floating workspace indicator badge on/off.
function M.toggle_badge()
	badge_visible = not badge_visible
	M.update_badge()
	notify("Workspace badge " .. (badge_visible and "enabled" or "disabled"))
end

-- ============================================================================
-- PICKER (Telescope)
-- ============================================================================

--- One row of the picker.
--- @param entry table Workspace record with `slot_idx` set.
--- @param current_cwd string
--- @return string display
local function format_entry(entry, current_cwd)
	local buf_count = entry.buffers and #entry.buffers or 0
	local tab_count = entry.tab_count or 1

	return string.format(
		"[%d] %s  %s %s  •  %d buffer%s, %d tab%s  (%s)",
		entry.slot_idx,
		entry.name,
		entry.cwd == current_cwd and "📍" or "📁",
		entry.cwd_name or "",
		buf_count,
		buf_count == 1 and "" or "s",
		tab_count,
		tab_count == 1 and "" or "s",
		format_relative_time(entry.updated_at)
	)
end

--- Detail pane for the selected workspace.
--- @param ws table Workspace record.
--- @return string[] lines
local function format_preview(ws)
	local lines = {
		"📌 Name:         " .. ws.name,
		"📁 Project:      " .. (ws.cwd_name or ""),
		"🌐 CWD Path:     " .. ws.cwd,
		"🕒 Updated:      " .. os.date("%Y-%m-%d %H:%M:%S", ws.updated_at or os.time()),
		"📑 Tabs:         " .. tostring(ws.tab_count or 1),
		"",
		"📄 Saved Files (" .. #(ws.buffers or {}) .. "):",
		"----------------------------------------",
	}
	for i, buf in ipairs(ws.buffers or {}) do
		table.insert(lines, string.format("  %d. %s", i, buf))
	end
	if #(ws.buffers or {}) == 0 then
		table.insert(lines, "  (no files)")
	end
	return lines
end

--- Opens the workspace picker.
--- Workspaces of the current project sort first; `g` toggles between showing only
--- them and showing every workspace.
function M.select_workspace(initial_show_all)
	if not pcall(require, "telescope") then
		notify("Telescope is not available", vim.log.levels.ERROR)
		return
	end

	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")
	local themes = require("telescope.themes")

	local current_cwd = vim.fn.getcwd()
	local all_workspaces = load_all_workspaces()

	local has_cwd_workspaces = false
	for _, item in ipairs(all_workspaces) do
		if item.cwd and path.equals(item.cwd, current_cwd) then
			has_cwd_workspaces = true
			break
		end
	end

	-- If this project has saved workspaces, default to showing this project only.
	-- If this project has no saved workspaces yet, default to showing all workspaces so the picker is never empty!
	local show_all = initial_show_all
	if show_all == nil then
		show_all = not has_cwd_workspaces
	end

	--- Visible workspaces, current project first, newest first, slots assigned.
	local function get_results()
		local entries = load_all_workspaces()
		table.sort(entries, function(a, b)
			local a_curr = path.equals(a.cwd or "", current_cwd) and 1 or 0
			local b_curr = path.equals(b.cwd or "", current_cwd) and 1 or 0
			if a_curr ~= b_curr then
				return a_curr > b_curr
			end
			return (a.updated_at or 0) > (b.updated_at or 0)
		end)

		local results = {}
		for _, item in ipairs(entries) do
			if show_all or path.equals(item.cwd or "", current_cwd) then
				item.slot_idx = #results + 1
				table.insert(results, item)
			end
		end
		return results
	end

	local function open_picker()
		pickers
			.new(
				themes.get_dropdown({
					prompt_title = string.format(
						" 🦊 Workspaces [%s] (a: New | d: Del | r: Rename | s: Save | g: %s) ",
						vim.fn.fnamemodify(current_cwd, ":t"),
						show_all and "Current Only" or "View All"
					),
					width = 0.85,
					results_title = "Saved Workspaces",
				}),
				{
					finder = finders.new_table({
						results = get_results(),
						entry_maker = function(entry)
							return {
								value = entry,
								display = format_entry(entry, current_cwd),
								ordinal = entry.name .. " " .. (entry.cwd_name or "") .. " " .. tostring(entry.slot_idx),
							}
						end,
					}),
					sorter = conf.generic_sorter({}),
					previewer = previewers.new_buffer_previewer({
						title = "Workspace Details",
						define_preview = function(self, entry)
							vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, format_preview(entry.value))
							vim.api.nvim_set_option_value("filetype", "markdown", { buf = self.state.bufnr })
							if self.state.winid and vim.api.nvim_win_is_valid(self.state.winid) then
								vim.wo[self.state.winid].conceallevel = 3
								vim.wo[self.state.winid].concealcursor = "nvic"
								local ok, rm_ui = pcall(require, "render-markdown.core.ui")
								if ok and rm_ui and type(rm_ui.update) == "function" then
									rm_ui.update(self.state.bufnr, self.state.winid, "UserCommand", true)
								end
							end
						end,
					}),
					attach_mappings = function(prompt_bufnr, map)
						--- Reopens the picker after an action that changed the list.
						local function reopen()
							vim.schedule(function()
								M.select_workspace(show_all)
							end)
						end

						--- Binds one action to several key/mode pairs.
						--- @param bindings table[] `{ mode, key }` pairs.
						--- @param fn function
						local function map_all(bindings, fn)
							for _, binding in ipairs(bindings) do
								map(binding[1], binding[2], fn)
							end
						end

						--- Current selection, or nil.
						local function selected()
							local selection = action_state.get_selected_entry()
							return selection and selection.value or nil
						end

						-- <Esc> in insert mode only leaves insert mode, so the normal-mode
						-- shortcuts below stay reachable without closing the picker.
						map("i", "<Esc>", function()
							pcall(vim.cmd, "stopinsert")
						end)
						map("n", "<Esc>", actions.close)
						map("n", "q", actions.close)

						actions.select_default:replace(function()
							local value = selected()
							actions.close(prompt_bufnr)
							if value then
								M.load_workspace(value)
							end
						end)

						map_all({ { "i", "<C-d>" }, { "n", "d" }, { "n", "D" }, { "i", "<Del>" } }, function()
							local value = selected()
							if value then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.delete_workspace(value, reopen)
								end)
							end
						end)

						map_all({ { "i", "<C-r>" }, { "n", "r" }, { "n", "R" }, { "n", "<F2>" } }, function()
							local value = selected()
							if value then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.rename_workspace(value, reopen)
								end)
							end
						end)

						map_all({ { "i", "<C-a>" }, { "n", "a" }, { "n", "A" } }, function()
							actions.close(prompt_bufnr)
							vim.schedule(function()
								M.new_workspace(reopen)
							end)
						end)

						map_all({ { "i", "<C-s>" }, { "i", "<C-S-s>" }, { "n", "s" }, { "n", "S" } }, function()
							local value = selected()
							if value then
								actions.close(prompt_bufnr)
								vim.schedule(function()
									M.save_workspace(value.name, reopen)
								end)
							end
						end)

						map_all({ { "i", "<C-g>" }, { "n", "g" }, { "n", "G" } }, function()
							local next_mode = not show_all
							actions.close(prompt_bufnr)
							vim.schedule(function()
								M.select_workspace(next_mode)
							end)
						end)

						for slot = 1, M.settings.quick_slots do
							map("n", tostring(slot), function()
								local entries = get_results()
								if entries[slot] then
									actions.close(prompt_bufnr)
									M.load_workspace(entries[slot])
								else
									notify("Workspace #" .. slot .. " does not exist", vim.log.levels.WARN)
								end
							end)
						end

						return true
					end,
				}
			)
			:find()
	end

	open_picker()
end

-- ============================================================================
-- SETUP
-- ============================================================================

--- Registers the `:Workspace*` commands and every keymap.
--- Commands are only created when absent, so a config reload does not clobber a
--- command another plugin may already own.
function M.setup()
	local commands = {
		WorkspaceSave = {
			fn = function(opts)
				M.save_workspace(opts.args ~= "" and opts.args or nil)
			end,
			opts = { nargs = "?", desc = "Save state as workspace" },
		},
		WorkspaceNew = {
			fn = function()
				M.new_workspace()
			end,
			opts = { desc = "Create a new workspace prompt" },
		},
		WorkspaceLoad = {
			fn = function(opts)
				if opts.args == "" then
					M.select_workspace()
				else
					M.load_workspace(tonumber(opts.args) or opts.args)
				end
			end,
			opts = { nargs = "?", desc = "Load saved workspace" },
		},
		WorkspaceDelete = {
			fn = function(opts)
				M.delete_workspace(opts.args ~= "" and opts.args or nil)
			end,
			opts = { nargs = "?", desc = "Delete workspace" },
		},
		WorkspaceRename = {
			fn = function(opts)
				local args = vim.split(opts.args, "%s+", { trimempty = true })
				if #args >= 2 then
					M.rename_workspace(args[1], function() end)
				else
					M.select_workspace()
				end
			end,
			opts = { nargs = "*", desc = "Rename workspace" },
		},
		WorkspaceSelect = { fn = M.select_workspace, opts = { desc = "Open the workspace picker" } },
		Workspaces = { fn = M.select_workspace, opts = { desc = "Open the workspace picker" } },
		WorkspaceClose = { fn = M.close_to_menu, opts = { desc = "Close session and return to main menu" } },
		WorkspaceMenu = { fn = M.close_to_menu, opts = { desc = "Close session and return to main menu" } },
		WorkspaceBadgeToggle = { fn = M.toggle_badge, opts = { desc = "Toggle floating workspace indicator badge" } },
		WorkspaceBadgeUpdate = { fn = M.update_badge, opts = { desc = "Update floating workspace indicator badge" } },
		WorkspaceBadgeFocus = { fn = M.focus_badge, opts = { desc = "Focus floating workspace indicator badge" } },
		WorkspaceFocus = { fn = M.focus_badge, opts = { desc = "Focus floating workspace indicator badge" } },
	}

	for name, spec in pairs(commands) do
		if vim.fn.exists(":" .. name) == 0 then
			vim.api.nvim_create_user_command(name, spec.fn, spec.opts)
		end
	end

	-- Autocmds to keep floating corner workspace badge updated
	local badge_group = vim.api.nvim_create_augroup("FoxWorkspaceBadgeUpdater", { clear = true })
	vim.api.nvim_create_autocmd({ "VimEnter", "BufEnter", "DirChanged", "VimResized", "ColorScheme" }, {
		group = badge_group,
		callback = function(args)
			if args and args.event == "DirChanged" and vim.g._fox_environment_switching then
				return
			end
			vim.schedule(M.update_badge)
		end,
	})

	vim.schedule(M.update_badge)

	--- Leaves terminal mode first, so the mapping also works from a terminal.
	local function from_any_mode(fn)
		return function()
			local mode = vim.fn.mode()
			if mode == "i" or mode == "ic" or mode == "ix" or mode == "t" then
				pcall(vim.cmd, "stopinsert")
			end
			fn()
		end
	end

	for _, key in ipairs(M.settings.keys.select) do
		vim.keymap.set({ "n", "i", "v" }, key, from_any_mode(M.select_workspace), {
			noremap = true,
			silent = true,
			desc = "Open Workspaces UI",
		})
	end
	for _, key in ipairs(M.settings.keys.menu) do
		vim.keymap.set({ "n", "i", "v" }, key, from_any_mode(M.close_to_menu), {
			noremap = true,
			silent = true,
			desc = "Close and return to Menu",
		})
	end
	for _, key in ipairs(M.settings.keys.focus_badge or {}) do
		vim.keymap.set({ "n", "i", "v" }, key, from_any_mode(M.focus_badge), {
			noremap = true,
			silent = true,
			desc = "Focus Workspace / Environment Badge",
		})
	end

	if M.settings.keys.leader_save then
		vim.keymap.set("n", M.settings.keys.leader_save, function()
			M.save_workspace()
		end, { desc = "Save Workspace" })
	end
	if M.settings.keys.leader_select then
		vim.keymap.set("n", M.settings.keys.leader_select, M.select_workspace, { desc = "Select Workspace" })
	end
	if M.settings.keys.leader_menu then
		vim.keymap.set("n", M.settings.keys.leader_menu, M.close_to_menu, { desc = "Close and return to Menu" })
	end

	if M.settings.keys.leader_slot_prefix then
		for slot = 1, M.settings.quick_slots do
			vim.keymap.set("n", M.settings.keys.leader_slot_prefix .. slot, function()
				M.load_workspace(slot)
			end, { desc = "Load Workspace slot " .. slot })
		end
	end
end

-- Legacy global kept for user scripts and older keybinds that reference it.
_G.Workspaces = M

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return setmetatable({
	name = "fox_workspaces",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = {
		"WorkspaceSelect",
		"Workspaces",
		"WorkspaceSave",
		"WorkspaceNew",
		"WorkspaceManage",
		"WorkspaceClose",
		"WorkspaceMenu",
		"WorkspaceBadgeFocus",
		"WorkspaceFocus",
		"WorkspaceBadgeToggle",
		"WorkspaceBadgeUpdate",
	},
	keys = {
		{ "<C-S-w>", mode = { "n", "i" }, desc = "Select Workspace" },
		{ "<leader>ws", mode = { "n" }, desc = "Select Workspace" },
		{ "<leader>wm", mode = { "n" }, desc = "Close Workspace" },
		{ "<C-S-b>", mode = { "n", "i" }, desc = "Focus Workspace Badge" },
		{ "<leader>wb", mode = { "n" }, desc = "Focus Workspace Badge" },
		{ "<leader>wf", mode = { "n" }, desc = "Focus Workspace Badge" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope.nvim",
	},
	config = M.setup,
}, { __index = M })
