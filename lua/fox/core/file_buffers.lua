-- Buffer reconciliation after successful Neo-tree filesystem operations.
local M = {}
function M.deleted(filename)
	local path = require("fox.core.path")
	filename = path.normalize(filename)
	local prefix = filename .. "/"
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = path.normalize(vim.api.nvim_buf_get_name(buf))
		if name == filename or name:sub(1, #prefix) == prefix then
			if vim.bo[buf].modified then
				vim.notify("Deleted file has unsaved changes; buffer preserved: " .. name, vim.log.levels.WARN)
			else
				-- :bdelete preserves windows and leaves a recoverable unlisted buffer.
				pcall(vim.api.nvim_buf_delete, buf, { force = false })
			end
		end
	end
end
-- Neo-tree recreates buffers after its own rename. Complete the disk operation
-- here so its follow-up no longer finds the old names and undo survives.
function M.rename(args)
	if M.before then
		M.before("Rename", args.source, args.destination)
	end
	local parent = vim.fs.dirname(args.destination)
	if vim.fn.isdirectory(parent) == 0 then
		vim.fn.mkdir(parent, "p")
	end
	local ok, err = vim.uv.fs_rename(args.source, args.destination)
	if not ok then
		vim.notify("Rename failed: " .. tostring(err), vim.log.levels.ERROR)
		return -- let Neo-tree report/retry its normal filesystem failure
	end
	local target = vim.fn.bufnr(args.destination)
	if target > 0 and vim.bo[target].modified then
		vim.api.nvim_buf_set_name(target, "fox-recovered://" .. target .. "/" .. args.destination)
		vim.notify("Preserved modified destination in fox-recovered buffer", vim.log.levels.WARN)
	end
	require("fox.core.buffer_rename").update_buffers_path(args.source, args.destination)
	return { handled = true }
end
function M.before_delete(filename)
	if M.before then
		M.before("Delete", filename)
	end
	local path = require("fox.core.path")
	local prefix = path.normalize(filename) .. "/"
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		local name = path.normalize(vim.api.nvim_buf_get_name(buf))
		if vim.bo[buf].modified and (path.equals(name, filename) or path.equals(name:sub(1, #prefix), prefix)) then
			-- Keep the original buffer and undo tree out of Neo-tree's force-delete path.
			vim.api.nvim_buf_set_name(buf, "fox-recovered://" .. buf .. "/" .. name)
			vim.notify("Deleted-file edits preserved in recovery buffer; use :saveas to save", vim.log.levels.WARN)
		end
	end
end
function M.setup()
	local events = require("neo-tree.events")
	for event, handler in pairs({
		[events.FILE_DELETED] = M.deleted,
		[events.BEFORE_FILE_RENAME] = M.rename,
		[events.BEFORE_FILE_MOVE] = M.rename,
		[events.BEFORE_FILE_DELETE] = M.before_delete,
	}) do
		local id = "fox_file_buffers_" .. event
		events.unsubscribe({ id = id, event = event })
		events.subscribe({ id = id, event = event, handler = handler })
	end
end
return M
