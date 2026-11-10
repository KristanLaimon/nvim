local M = {}
local terminals = {}
local wrapper_dir
local path = require("fox.core.path")

function M.prepare()
	local executable = vim.env.FOX_AGENTIC_REAL_CODEX or vim.fn.exepath("codex")
	if executable == "" or vim.fn.executable(executable) ~= 1 then
		return nil
	end
	local shell = vim.fs.basename(vim.o.shell):lower():gsub("%.exe$", "")
	if shell ~= "bash" and shell ~= "sh" and shell ~= "zsh" and shell ~= "pwsh" and shell ~= "powershell" then
		return nil
	end
	require("fox.agentic").setup()
	local root = path.normalize(vim.fn.stdpath("config"))
	local scripts = root .. "/config/tools/foxagentic"
	local directory = scripts
	if shell ~= "pwsh" and shell ~= "powershell" then
		if not wrapper_dir then
			wrapper_dir = vim.fn.tempname() .. "-fox-agentic"
			vim.fn.mkdir(wrapper_dir, "p")
			assert(vim.uv.fs_copyfile(scripts .. "/codex.sh", wrapper_dir .. "/codex"))
			assert(vim.uv.fs_chmod(wrapper_dir .. "/codex", 493))
		end
		directory = path.normalize(wrapper_dir)
	end
	local server = vim.v.servername ~= "" and vim.v.servername or vim.fn.serverstart()
	local token = vim.fn.sha256(server .. tostring(vim.uv.hrtime()) .. tostring({}))
	return {
		PATH = directory .. (vim.fn.has("win32") == 1 and ";" or ":") .. (vim.env.PATH or ""),
		FOX_AGENTIC_SERVER = server,
		FOX_AGENTIC_TOKEN = token,
		FOX_AGENTIC_REAL_CODEX = path.normalize(executable),
		FOX_AGENTIC_NVIM = path.normalize(vim.v.progpath),
		FOX_AGENTIC_BRIDGE = scripts .. "/bridge.lua",
	},
		token
end

function M.register(token, context)
	if token then
		context.automatic = true
		terminals[token] = context
	end
end

function M.accept(token, session_id, root, finished)
	local context = terminals[token]
	if not context or not vim.api.nvim_buf_is_valid(context.buf) or vim.b[context.buf].terminal_job_id ~= context.job then
		return false
	end
	if type(session_id) ~= "string" or not session_id:match("^[%w_-]+$") or type(root) ~= "string" then
		return false
	end
	local agentic = require("fox.agentic")
	if finished then
		local state = agentic.states[context.buf]
		if state and state.session.id == session_id then
			state.finished = true
			if state.subscription then
				state.subscription.refresh()
			end
			-- Let the final persisted items arrive before disconnecting the read-only observer.
			vim.defer_fn(function()
				if state.finished and state.session.id == session_id then
					agentic.detach(state)
					state.status = "Codex exited; collected activity retained"
					agentic.queue_render(state)
				end
			end, 1500)
		end
	else
		context.session, context.root = session_id, path.normalize(root)
		vim.b[context.buf].fox_agentic_session = session_id
		agentic.observe(context)
	end
	return true
end

function M.dispose()
	terminals = {}
	if wrapper_dir then
		vim.uv.fs_unlink(wrapper_dir .. "/codex")
		vim.uv.fs_rmdir(wrapper_dir)
		wrapper_dir = nil
	end
end

return M
