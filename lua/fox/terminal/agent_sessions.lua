local M = {}
local store = require("fox.core.store")
local uv = vim.uv or vim.loop
local commands = {
	codex = { "codex", "resume" },
	claude = { "claude", "--resume" },
	opencode = { "opencode", "--session" },
	agy = { "agy", "--conversation" },
}

local function valid(session)
	return type(session) == "table"
		and commands[session.agent] ~= nil
		and type(session.id) == "string"
		and #session.id > 0
		and #session.id <= 256
		and session.id:match("^[%w_][%w_%-]*$") ~= nil
		and type(session.slot) == "number"
		and session.slot >= 1
		and session.slot <= 9
		and session.slot % 1 == 0
end

function M.file(root)
	return vim.fn.stdpath("state") .. "/fox/agent-sessions/" .. vim.fn.sha256(vim.fs.normalize(root)) .. ".json"
end

function M.load(root)
	local data = store.load(M.file(root), {})
	if data.root ~= vim.fs.normalize(root) or type(data.sessions) ~= "table" then
		return {}
	end
	local sessions, used = {}, {}
	for _, session in ipairs(data.sessions) do
		if valid(session) and not used[session.slot] then
			used[session.slot] = true
			sessions[#sessions + 1] = { agent = session.agent, id = session.id, slot = session.slot }
		end
	end
	table.sort(sessions, function(a, b)
		return a.slot < b.slot
	end)
	return sessions
end

function M.save(root, sessions)
	local used = {}
	for _, session in ipairs(sessions) do
		if not valid(session) or used[session.slot] then
			return false, "Invalid or duplicate agent session"
		end
		used[session.slot] = true
	end
	local filename = M.file(root)
	vim.fn.mkdir(vim.fs.dirname(filename), "p", 448)
	local temporary = filename .. "." .. vim.fn.getpid() .. ".tmp"
	local ok, err = store.save(temporary, { root = vim.fs.normalize(root), sessions = sessions })
	if not ok then
		return false, err
	end
	uv.fs_chmod(temporary, 384)
	local renamed, rename_err = uv.fs_rename(temporary, filename)
	if not renamed then
		uv.fs_unlink(temporary)
		return false, rename_err
	end
	return true
end

function M.command(session)
	if not valid(session) then
		return nil
	end
	local command = vim.list_extend({}, commands[session.agent])
	command[#command + 1] = session.id
	return command
end

function M.compact(sessions)
	local result = vim.deepcopy(sessions)
	table.sort(result, function(a, b)
		return a.slot < b.slot
	end)
	for slot, session in ipairs(result) do
		session.slot = slot
	end
	return result
end

return M
