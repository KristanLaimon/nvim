local M = {}
local storage = require("fox.query.storage")
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
M.bridge = source:gsub("lua/fox/query/client.lua$", "scripts/query_bridge.py")

function M.python()
	for _, executable in ipairs({ "python3", "python" }) do
		if vim.fn.executable(executable) == 1 then
			return executable
		end
	end
	return nil
end

function M.new(root, changed)
	local instance = { root = storage.root(root), pending = {}, sequence = 0, changed = changed, connected = false }
	function instance:start()
		if self.closing then
			return nil, "Database session closed; reconnect"
		end
		if self.job then
			return true
		end
		local python = M.python()
		if not python then
			return nil, "Python 3 is required for database connections"
		end
		local fragment = ""
		self.job = vim.fn.jobstart({ python, "-u", "-B", M.bridge }, {
			cwd = self.root,
			env = { PYTHONDONTWRITEBYTECODE = "1", PYTHONPATH = storage.path(self.root, "private/drivers") },
			on_stdout = function(_, data)
				for i, part in ipairs(data) do
					fragment = fragment .. part
					if i < #data then
						local ok, response = pcall(vim.json.decode, fragment)
						fragment = ""
						if ok then
							if response.event then
								if self.changed then
									self.changed(response)
								end
							else
								local callback = self.pending[response.id]
								self.pending[response.id] = nil
								if response.disconnected then
									self.connected = false
								end
								if callback then
									callback(response.result, response.error, response.error_detail)
								end
							end
						end
					end
				end
			end,
			on_exit = function()
				self.job, self.connected = nil, false
				local pending = self.pending
				self.pending = {}
				for _, callback in pairs(pending) do
					callback(nil, "Database worker stopped; reconnect")
				end
			end,
		})
		if self.job <= 0 then
			self.job = nil
			return nil, "Could not start Python database worker"
		end
		return true
	end
	function instance:request(operation, data, callback)
		local ok, err = self:start()
		if not ok then
			callback(nil, err)
			return
		end
		self.sequence = self.sequence + 1
		local request = vim.tbl_extend("force", data or {}, { op = operation, id = self.sequence })
		self.pending[self.sequence] = callback
		vim.fn.chansend(self.job, vim.json.encode(request) .. "\n")
	end
	function instance:cancel()
		if self.job then
			vim.fn.chansend(self.job, '{"op":"cancel"}\n')
		end
		vim.defer_fn(function()
			if self.busy then
				self:close()
			end
		end, 3000)
	end
	function instance:close()
		if self.job and not self.closing then
			self.closing = true
			pcall(vim.fn.chansend, self.job, '{"op":"cancel"}\n')
			pcall(vim.fn.chanclose, self.job, "stdin")
			local job = self.job
			vim.defer_fn(function()
				if self.job == job then
					vim.fn.jobstop(job)
				end
			end, 1000)
		end
		self.connected, self.busy = false, false
	end
	return instance
end

return M
