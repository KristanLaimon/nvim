local M = {}
local storage = require("fox.query.storage")
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
function M.executable()
	local platform = (vim.uv or vim.loop).os_uname()
	local os = ({ Windows_NT = "windows", Linux = "linux" })[platform.sysname]
	local arch = ({ x86_64 = "amd64", amd64 = "amd64", AMD64 = "amd64" })[platform.machine]
	if not os or not arch then
		return nil, "FoxQuery has no bundled worker for " .. platform.sysname .. "/" .. platform.machine
	end
	local path = source:gsub("lua/fox/query/client.lua$", "config/tools/foxquery/")
		.. "foxquery-"
		.. os
		.. "-"
		.. arch
		.. (os == "windows" and ".exe" or "")
	if vim.fn.filereadable(path) ~= 1 then
		return nil, "FoxQuery worker missing; run the build script in config/tools/repos/foxquery"
	end
	if os ~= "windows" and vim.fn.executable(path) ~= 1 then
		local ok = (vim.uv or vim.loop).fs_chmod(path, 493)
		if not ok then
			return nil, "FoxQuery worker is not executable; chmod +x " .. path
		end
	end
	return path
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
		local executable, err = M.executable()
		if not executable then
			return nil, err
		end
		local fragment = ""
		self.job = vim.fn.jobstart({ executable }, {
			cwd = self.root,
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
			return nil, "Could not start bundled FoxQuery worker"
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
