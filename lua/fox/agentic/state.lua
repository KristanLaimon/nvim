local M = {}
local path = require("fox.core.path")

function M.new(session)
	return { session = session, files = {}, order = {}, seen = {}, status = "Connecting", updated = nil }
end

function M.reduce(state, event)
	if type(event) ~= "table" or type(event.kind) ~= "string" then
		return
	end
	if event.kind == "usage" then
		state.usage = event.usage
	elseif event.kind == "session" then
		state.session = vim.tbl_extend("force", state.session, event.session)
	elseif event.kind == "status" then
		state.status = event.status
	elseif event.kind == "scan" then
		state.scan = { turns = event.turns, items = event.items }
	elseif event.kind == "file" and type(event.path) == "string" and event.path ~= "" then
		if type(event.id) ~= "string" or state.seen[event.id] then
			return
		end
		state.seen[event.id] = true
		local filename = path.normalize(event.path)
		local key = vim.fn.has("win32") == 1 and filename:lower() or filename
		local file = state.files[key]
		if not file then
			file = { path = filename, reads = 0, writes = 0, added = 0, removed = 0 }
			state.files[key] = file
			state.order[#state.order + 1] = key
		end
		if event.action == "read" then
			file.reads = file.reads + 1
			if type(event.estimated_tokens) == "number" then
				file.estimated_tokens = (file.estimated_tokens or 0) + event.estimated_tokens
			end
			file.context = file.context
				or filename:match("[/\\]SKILL%.md$") ~= nil
				or filename:match("[/\\]AGENTS%.md$") ~= nil
			file.evidence = event.evidence
		elseif event.action == "change" then
			file.writes = file.writes + 1
			file.added = file.added + (event.added or 0)
			file.removed = file.removed + (event.removed or 0)
			file.change = event.change
		end
	end
	state.updated = os.time()
end

return M
