-- Invoked by agent hooks with Neovim -l; no user configuration is loaded.
local agent = arg[1]
local directory, terminal = vim.env.FOXVIM_AGENT_EVENT_DIR, vim.env.FOXVIM_TERMINAL_ID
local function report()
	if not directory or not terminal or not terminal:match("^[%w_-]+$") then
		return
	end
	local payload = vim.json.decode(io.read("*a"))
	if type(payload) ~= "table" then
		return
	end
	local id = agent == "agy" and payload.conversationId or payload.session_id
	if type(id) ~= "string" or id == "" or #id > 1024 then
		return
	end
	local event = payload.hook_event_name
	if agent ~= "agy" and event ~= "SessionStart" and event ~= "SessionEnd" then
		return
	end
	if payload.agent_id or payload.cursor_version or vim.env.CURSOR_VERSION then
		return
	end
	if agent == "codex" and vim.env.CODEX_THREAD_ID and vim.env.CODEX_THREAD_ID ~= id then
		return
	end
	if agent ~= "codex" and agent ~= "claude" and agent ~= "agy" then
		return
	end
	local target = directory .. "/" .. terminal .. ".json"
	local temporary = target .. "." .. vim.fn.getpid() .. ".tmp"
	local handle = io.open(temporary, "w")
	if not handle then
		return
	end
	local written =
		handle:write(vim.json.encode({ agent = agent, id = id, event = event == "SessionEnd" and "end" or "start" }))
	local closed = handle:close()
	if not written or not closed or not vim.uv.fs_rename(temporary, target) then
		os.remove(temporary)
	end
end
pcall(report)
if agent == "agy" then
	io.write("{}\n")
end
