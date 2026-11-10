local M = { id = "codex", capabilities = { reads = true, writes = true, usage = true } }
local path = require("fox.core.path")

local function clean(value)
	return tostring(value or ""):gsub("[%z\1-\31\127]", " ")
end

local function absolute(filename, cwd)
	if type(filename) ~= "string" or filename == "" then
		return nil
	end
	if not filename:match("^[/\\]") and not filename:match("^%a:[/\\]") then
		if type(cwd) ~= "string" then
			return nil
		end
		filename = cwd .. "/" .. filename
	end
	return path.normalize(filename)
end

-- commandActions is Codex's best-effort interpretation, not filesystem read auditing.
function M.item_events(item, cwd, turn)
	local events = {}
	if type(item) ~= "table" or type(item.id) ~= "string" then
		return events
	end
	local prefix = tostring(turn or "") .. ":" .. item.id
	if item.type == "commandExecution" and item.status == "completed" and item.exitCode == 0 then
		local actions = type(item.commandActions) == "table" and item.commandActions or {}
		local single_read = #actions == 1 and type(item.aggregatedOutput) == "string"
		for index, action in ipairs(actions) do
			local filename = type(action) == "table" and action.type == "read" and absolute(action.path, item.cwd or cwd)
			if filename then
				events[#events + 1] = {
					kind = "file",
					id = prefix .. ":read:" .. index,
					action = "read",
					path = filename,
					evidence = "Codex command classification (best effort)",
					estimated_tokens = single_read and math.ceil(vim.fn.strchars(item.aggregatedOutput) / 4) or nil,
				}
			end
		end
	elseif item.type == "fileChange" and item.status == "completed" then
		for index, change in ipairs(item.changes or {}) do
			local filename = absolute(change.path, cwd)
			if filename then
				local added, removed = 0, 0
				for line in tostring(change.diff or ""):gmatch("[^\n]+") do
					if line:sub(1, 1) == "+" and line:sub(1, 3) ~= "+++" then
						added = added + 1
					elseif line:sub(1, 1) == "-" and line:sub(1, 3) ~= "---" then
						removed = removed + 1
					end
				end
				events[#events + 1] = {
					kind = "file",
					id = prefix .. ":change:" .. index,
					action = "change",
					path = filename,
					change = type(change.kind) == "table" and change.kind.type or change.kind,
					added = added,
					removed = removed,
				}
			end
		end
	end
	return events
end

-- Versioned fallback: parse only telemetry records from the explicitly attached thread.
function M.telemetry(content)
	local usage, model, mode
	for line in content:gmatch("[^\n]+") do
		if line:find('"token_count"', 1, true) or line:find('"turn_context"', 1, true) then
			local ok, record = pcall(vim.json.decode, line)
			local payload = ok and type(record) == "table" and record.payload
			if type(payload) == "table" then
				if record.type == "turn_context" and type(payload.model) == "string" then
					model = payload.model
				end
				if
					record.type == "turn_context"
					and type(payload.collaboration_mode) == "table"
					and type(payload.collaboration_mode.mode) == "string"
				then
					mode = payload.collaboration_mode.mode
				end
				if payload.type == "token_count" and type(payload.info) == "table" then
					local function breakdown(value)
						if type(value) ~= "table" then
							return nil
						end
						return {
							inputTokens = value.input_tokens,
							outputTokens = value.output_tokens,
							cachedInputTokens = value.cached_input_tokens,
							reasoningOutputTokens = value.reasoning_output_tokens,
							totalTokens = value.total_tokens,
						}
					end
					usage = {
						total = breakdown(payload.info.total_token_usage),
						last = breakdown(payload.info.last_token_usage),
						modelContextWindow = payload.info.model_context_window,
					}
				end
			end
		end
	end
	return usage, model, mode
end

function M.read_telemetry(filename)
	if type(filename) ~= "string" or not filename:match("%.jsonl$") then
		return nil
	end
	local fd = vim.uv.fs_open(filename, "r", 0)
	if not fd then
		return nil
	end
	local stat = vim.uv.fs_fstat(fd)
	-- shortcut: older telemetry outside this tail is unavailable; use a stable usage API when exposed.
	local offset = stat and math.max(0, stat.size - 512 * 1024)
	local content = offset and vim.uv.fs_read(fd, math.min(stat.size, 512 * 1024), offset)
	vim.uv.fs_close(fd)
	if not content then
		return nil
	end
	if offset > 0 then
		content = content:match("\n(.*)") or ""
	end
	return M.telemetry(content)
end

-- A stdio App Server reads existing local history; it never starts an inference turn.
function M.connect(on_ready, on_notification, on_status, options)
	options = options or {}
	local connection = { pending = {}, sequence = 0, closed = false, ready = false }
	local spawn = options.spawn or vim.fn.jobstart
	local send = options.send or vim.fn.chansend
	local stop = options.stop or vim.fn.jobstop
	local close_input = options.close_input or function(job)
		vim.fn.chanclose(job, "stdin")
	end
	local fragment = ""
	local function fail(message)
		on_status(clean(message))
	end
	function connection.request(method, params, callback)
		if connection.closed then
			callback(nil, "Codex connection is closed")
			return
		end
		connection.sequence = connection.sequence + 1
		local id = connection.sequence
		connection.pending[id] = callback
		local ok, err = pcall(send, connection.job, vim.json.encode({ id = id, method = method, params = params }) .. "\n")
		if not ok then
			connection.pending[id] = nil
			callback(nil, tostring(err))
			return
		end
		vim.defer_fn(function()
			if connection.pending[id] then
				connection.pending[id] = nil
				callback(nil, "Codex request timed out: " .. method)
			end
		end, 10000)
	end
	function connection.detach(graceful)
		if connection.closed then
			return
		end
		connection.closed = true
		if graceful and connection.job and connection.job > 0 then
			pcall(close_input, connection.job)
			vim.wait(3000, function()
				return connection.exited == true
			end, 10)
		end
		if not connection.exited and connection.job and connection.job > 0 then
			pcall(stop, connection.job)
		end
		local pending = connection.pending
		connection.pending = {}
		for _, callback in pairs(pending) do
			callback(nil, "Codex connection closed")
		end
	end
	local function receive(line)
		local ok, message = pcall(vim.json.decode, line)
		if not ok or type(message) ~= "table" then
			return
		end
		if message.id and connection.pending[message.id] then
			local callback = connection.pending[message.id]
			connection.pending[message.id] = nil
			callback(
				message.result,
				type(message.error) == "table" and clean(message.error.message or "Codex RPC error") or nil
			)
		elseif message.method == "thread/tokenUsage/updated" and not message.id and type(message.params) == "table" then
			on_notification({ kind = "usage", session_id = message.params.threadId, usage = message.params.tokenUsage })
		end
		-- Server approval/input requests are deliberately never answered by this observer.
	end
	local started, job = pcall(
		spawn,
		options.command or { vim.env.FOX_AGENTIC_REAL_CODEX or "codex", "app-server", "--listen", "stdio://" },
		{
			env = { FOX_AGENTIC_TOKEN = "", FOX_AGENTIC_SERVER = "" },
			stdout_buffered = false,
			on_stdout = function(_, chunks)
				if connection.closed then
					return
				end
				for index, chunk in ipairs(chunks) do
					fragment = fragment .. chunk
					if #fragment > 8 * 1024 * 1024 then
						fail("Codex message exceeded 8 MiB; reconnect to retry")
						connection.detach()
						return
					end
					if index < #chunks then
						receive(fragment)
						fragment = ""
					end
				end
			end,
			on_stderr = function(_, chunks)
				if not connection.closed then
					local message = table.concat(chunks, " ")
					if message:match("%S") then
						connection.diagnostic = clean(message)
					end
				end
			end,
			on_exit = function(_, code)
				connection.exited = true
				if not connection.closed then
					fail("Codex disconnected (" .. code .. "). " .. (connection.diagnostic or "Run Codex, then retry."))
					connection.detach()
				end
			end,
		}
	)
	connection.job = started and job or nil
	if not started or type(connection.job) ~= "number" or connection.job <= 0 then
		connection.closed = true
		fail(
			"Cannot start Codex observer. Install Codex CLI and start a session first. " .. (not started and clean(job) or "")
		)
		return connection
	end
	connection.request("initialize", {
		clientInfo = { name = "foxvim_agentic", title = "FoxVim Agentic Observer", version = "0.1.0" },
		capabilities = { experimentalApi = true },
	}, function(result, err)
		if err or not result then
			fail(err or "Codex initialization failed")
			connection.detach()
			return
		end
		send(connection.job, vim.json.encode({ method = "initialized" }) .. "\n")
		connection.ready = true
		on_ready(connection)
	end)
	return connection
end

function M.create_session(connection, root, callback)
	connection.request("thread/start", { cwd = root }, function(result, err)
		local thread = type(result) == "table" and result.thread
		if err or type(thread) ~= "table" or type(thread.id) ~= "string" then
			callback(nil, err or "Codex did not return a session ID")
			return
		end
		local name = "Codex / " .. clean(vim.fs.basename(path.normalize(root)))
		-- Naming persists the otherwise in-memory blank thread before another client resumes it.
		connection.request("thread/name/set", { threadId = thread.id, name = name }, function(_, name_error)
			if name_error then
				callback(nil, name_error)
				return
			end
			callback({ id = thread.id, name = name, cwd = thread.cwd or root })
		end)
	end)
end

function M.list_sessions(connection, root, callback)
	local sessions = {}
	local function page(cursor)
		connection.request("thread/list", {
			cwd = root,
			sourceKinds = { "cli", "appServer" },
			sortKey = "updated_at",
			limit = 100,
			cursor = cursor,
		}, function(result, err)
			if err or type(result) ~= "table" then
				callback(nil, err or "Invalid Codex session list")
				return
			end
			for _, thread in ipairs(result.data or {}) do
				if type(thread.id) == "string" then
					sessions[#sessions + 1] = { id = thread.id, name = clean(thread.name or thread.id), cwd = thread.cwd }
				end
			end
			if type(result.nextCursor) == "string" and #sessions < 1000 then
				page(result.nextCursor)
			else
				callback(sessions)
			end
		end)
	end
	page(nil)
end

-- Read persisted items without thread/resume: observation must not re-run session hooks.
function M.attach(connection, session, emit, on_status)
	local subscription = { closed = false, busy = false, turns = {} }
	function subscription.refresh()
		if subscription.closed or subscription.busy or connection.closed then
			return
		end
		subscription.busy = true
		connection.request("thread/read", { threadId = session.id, includeTurns = false }, function(result, err)
			if subscription.closed then
				return
			end
			if err or type(result) ~= "table" or type(result.thread) ~= "table" then
				subscription.busy = false
				on_status(err or "Invalid Codex thread metadata")
				return
			end
			local thread = result.thread
			local usage, model, mode = M.read_telemetry(thread.path)
			if usage then
				emit({ kind = "usage", usage = usage })
			end
			emit({
				kind = "session",
				session = {
					id = session.id,
					name = clean(thread.name or session.id),
					cwd = thread.cwd,
					model = model or result.model,
					mode = mode,
				},
			})
			local pages = 0
			local scanned_turns, scanned_items = 0, 0
			local function page(cursor)
				pages = pages + 1
				connection.request("thread/turns/list", {
					threadId = session.id,
					itemsView = "full",
					limit = 25,
					sortDirection = "desc",
					cursor = cursor,
				}, function(history, history_err)
					if subscription.closed then
						return
					end
					if history_err or type(history) ~= "table" then
						subscription.busy = false
						on_status(history_err or "Codex history unavailable")
						return
					end
					for _, turn in ipairs(history.data or {}) do
						scanned_turns = scanned_turns + 1
						scanned_items = scanned_items + #(turn.items or {})
						if not subscription.turns[turn.id] then
							for _, item in ipairs(turn.items or {}) do
								for _, event in ipairs(M.item_events(item, thread.cwd or session.cwd, turn.id)) do
									emit(event)
								end
							end
							if turn.status == "completed" then
								subscription.turns[turn.id] = true
							end
						end
					end
					if type(history.nextCursor) == "string" and pages < 4 then
						page(history.nextCursor)
					else
						subscription.busy = false
						emit({ kind = "scan", turns = scanned_turns, items = scanned_items })
						on_status(
							type(history.nextCursor) == "string" and "Live / latest 100 turns only"
								or "Live / persisted Codex activity"
						)
					end
				end)
			end
			page(nil)
		end)
	end
	function subscription.detach()
		if subscription.closed then
			return
		end
		subscription.closed = true
		if subscription.timer then
			subscription.timer:stop()
			subscription.timer:close()
		end
	end
	subscription.timer = vim.uv.new_timer()
	subscription.timer:start(1000, 1000, vim.schedule_wrap(subscription.refresh))
	subscription.refresh()
	return subscription
end

return M
