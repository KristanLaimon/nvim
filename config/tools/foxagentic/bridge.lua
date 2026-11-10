local config = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))))
package.path = config .. "/lua/?.lua;" .. config .. "/lua/?/init.lua;" .. package.path
local action, session_id = arg[1], arg[2]
local server, token = vim.env.FOX_AGENTIC_SERVER, vim.env.FOX_AGENTIC_TOKEN
if not server or server == "" or not token or token == "" then
	io.stderr:write("FoxVim terminal binding is unavailable.\n")
	os.exit(1)
end

local function register(id, finished)
	local channel = vim.fn.sockconnect("pipe", server or "", { rpc = true })
	if channel <= 0 then
		return false
	end
	local ok, result = pcall(
		vim.rpcrequest,
		channel,
		"nvim_exec_lua",
		"return require('fox.agentic.background').accept(...)",
		{ token, id, vim.fn.getcwd(), finished }
	)
	vim.fn.chanclose(channel)
	return ok and result == true
end

if action == "finish" then
	register(session_id, true)
	os.exit(0)
end

if action == "attach" then
	os.exit(register(session_id, false) and 0 or 1)
end

if action ~= "create" then
	os.exit(1)
end

local done, failure = false, nil
local provider = require("fox.agentic.providers.codex")
local connection = provider.connect(function(ready)
	provider.create_session(ready, vim.fn.getcwd(), function(session, err)
		local id = session and session.id
		if not err and type(id) == "string" and id:match("^[%w_-]+$") and register(id, false) then
			session_id = id
		else
			failure = err or "FoxVim could not bind this terminal's Codex session"
		end
		done = true
	end)
end, function() end, function(status)
	failure = status
	done = true
end)
vim.wait(15000, function()
	return done
end, 10)
connection.detach(true)
if not done or failure or not session_id then
	io.stderr:write("FoxVim background tracking unavailable; starting Codex normally.\n")
	os.exit(1)
end
io.stdout:write(session_id .. "\n")
os.exit(0)
