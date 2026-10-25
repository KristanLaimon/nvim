-- LSP file operation bridge for Neo-tree. Filesystem changes remain in Neo-tree.
local M = {}
local kinds = {}
local path = require("fox.core.path")
local function under(name, root)
	return path.equals(name, root) or path.equals(name:sub(1, #root + 1), root .. "/")
end
function M.matches(client, phase, operation, filename, folder)
	local cap = vim.tbl_get(client, "server_capabilities", "workspace", "fileOperations", phase .. operation)
	if not cap or client:is_stopped() then
		return false
	end
	local scoped = false
	for _, workspace in ipairs(client.workspace_folders or {}) do
		if under(filename, vim.uri_to_fname(workspace.uri)) then
			scoped = true
		end
	end
	local root = client.root_dir or (client.config or {}).root_dir
	if type(root) == "string" and under(filename, root) then
		scoped = true
	end
	if not scoped then
		return false
	end
	for _, filter in ipairs(cap.filters or {}) do
		local p = filter.pattern or {}
		if
			(not filter.scheme or filter.scheme == "file")
			and (not p.matches or (p.matches == "folder") == folder)
			and p.glob
		then
			local regex = (p.options and p.options.ignorecase and "\\c" or "\\C") .. vim.fn.glob2regpat(p.glob)
			local ok, matched = pcall(function()
				return vim.regex(regex):match_str(filename) ~= nil
					or (folder and vim.regex(regex):match_str(filename .. "/") ~= nil)
			end)
			if ok and matched then
				return true
			end
		end
	end
	return false
end
local function snapshot()
	local ticks = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			ticks[buf] = vim.api.nvim_buf_get_changedtick(buf)
		end
	end
	return ticks
end
function M.apply(edit, encoding, ticks)
	-- A will* response may edit text; resource operations would recursively mutate
	-- the operation underway. Reject those, stale versions and intervening edits.
	local documents = {}
	for uri in pairs(edit.changes or {}) do
		documents[#documents + 1] = { uri = uri }
	end
	for _, change in ipairs(edit.documentChanges or {}) do
		if not change.textDocument then
			return false, "Resource operation in will* edit"
		end
		documents[#documents + 1] = change.textDocument
	end
	for _, doc in ipairs(documents) do
		local buf = vim.uri_to_bufnr(doc.uri)
		if ticks[buf] and ticks[buf] ~= vim.api.nvim_buf_get_changedtick(buf) then
			return false, "Buffer changed while waiting for LSP"
		end
		if doc.version and doc.version ~= vim.NIL and vim.lsp.util.buf_versions[buf] ~= doc.version then
			return false, "Stale workspace edit version"
		end
	end
	local ok, err = pcall(vim.lsp.util.apply_workspace_edit, edit, encoding)
	return ok, err
end
function M.dispatch(phase, operation, filename, destination)
	filename = path.normalize(filename)
	local stat = vim.uv.fs_stat(filename)
	if phase == "will" then
		kinds[filename] = stat and stat.type == "directory" or false
	end
	local folder = kinds[filename] or (stat and stat.type == "directory") or false
	local params = {
		files = {
			operation == "Rename" and { oldUri = vim.uri_from_fname(filename), newUri = vim.uri_from_fname(destination) }
				or { uri = vim.uri_from_fname(filename) },
		},
	}
	local deadline = vim.uv.hrtime() + 1500 * 1e6
	for _, client in ipairs(vim.lsp.get_clients()) do
		if M.matches(client, phase, operation, filename, folder) then
			local method = "workspace/" .. phase .. operation .. "Files"
			if phase == "did" then
				pcall(client.notify, client, method, params)
			else
				local timeout = math.floor((deadline - vim.uv.hrtime()) / 1e6)
				if timeout <= 0 then
					break
				end
				local ticks = snapshot()
				local ok, response = pcall(client.request_sync, client, method, params, timeout)
				if ok and response and response.result then
					local applied, err = M.apply(response.result, client.offset_encoding, ticks)
					if not applied then
						vim.notify("File operation LSP edit skipped: " .. tostring(err), vim.log.levels.WARN)
					end
				elseif not ok or not response or response.err then
					vim.notify("File operation LSP request failed: " .. client.name, vim.log.levels.WARN)
				end
			end
		end
	end
	if phase == "did" then
		kinds[filename] = nil
	end
end
function M.setup()
	local buffers = require("fox.core.file_buffers")
	buffers.before = function(operation, filename, destination)
		M.dispatch("will", operation, filename, destination)
	end
	local events = require("neo-tree.events")
	local handlers = {
		[events.BEFORE_FILE_ADD] = function(name)
			M.dispatch("will", "Create", name)
		end,
		[events.FILE_ADDED] = function(name)
			M.dispatch("did", "Create", name)
		end,
		[events.FILE_DELETED] = function(name)
			M.dispatch("did", "Delete", name)
		end,
		[events.FILE_RENAMED] = function(args)
			M.dispatch("did", "Rename", args.source, args.destination)
		end,
		[events.FILE_MOVED] = function(args)
			M.dispatch("did", "Rename", args.source, args.destination)
		end,
	}
	for event, handler in pairs(handlers) do
		local id = "fox_lsp_file_operations_" .. event
		events.unsubscribe({ id = id, event = event })
		events.subscribe({ id = id, event = event, handler = handler })
	end
end
return M
