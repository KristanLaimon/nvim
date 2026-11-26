local M = {}

local function close(handle)
	if handle and not handle:is_closing() then
		handle:close()
	end
end

function M.start(options)
	local listener = assert(vim.uv.new_tcp())
	local ok, err = listener:bind("127.0.0.1", 0)
	if not ok then
		close(listener)
		error(err)
	end
	local service = { server = listener, clients = {}, origin = "127.0.0.1:" .. listener:getsockname().port }
	service.prefix = "/" .. vim.fn.sha256(assert(vim.uv.random(32))):sub(1, 32) .. "/"
	service.url = "http://" .. service.origin .. service.prefix
	function service:stop()
		close(self.server)
		for client, timer in pairs(self.clients) do
			close(timer)
			close(client)
		end
		self.clients = {}
	end
	ok, err = listener:listen(32, function(failure)
		if failure or listener:is_closing() then
			return
		end
		local client = vim.uv.new_tcp()
		if not listener:accept(client) then
			close(client)
			return
		end
		local timer = vim.uv.new_timer()
		service.clients[client] = timer
		local function finish()
			service.clients[client] = nil
			close(timer)
			close(client)
		end
		timer:start(5000, 0, finish)
		local request = ""
		client:read_start(function(read_error, data)
			if read_error or not data then
				finish()
				return
			end
			request = request .. data
			if #request > options.max_request then
				finish()
				return
			end
			local header_end = request:find("\r\n\r\n", 1, true)
			if not header_end then
				return
			end
			local headers = request:sub(1, header_end + 1):lower()
			local method, target = request:match("^(%u+) ([^ ]+) HTTP/1%.[01]\r\n")
			local length = tonumber(headers:match("\r\ncontent%-length:%s*(%d+)%s*\r\n"))
			if method == "POST" and length and length <= options.max_request and #request - header_end - 3 < length then
				return
			end
			client:read_stop()
			vim.schedule(function()
				if client:is_closing() then
					return
				end
				local status, body, kind, policy = 403, "Forbidden", "text/plain", options.csp
				if headers:match("\r\nhost:%s*([^\r\n]+)") == service.origin then
					local success
					success, status, body, kind, policy =
						pcall(options.handle, service, method, target, headers, request:sub(header_end + 4), length)
					if not success then
						status, body, kind, policy = 500, options.error_message, "text/plain", options.csp
					end
				end
				client:write(
					"HTTP/1.1 "
						.. status
						.. " OK\r\nContent-Type: "
						.. kind
						.. "; charset=utf-8\r\nContent-Length: "
						.. #body
						.. "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: "
						.. (policy or options.csp)
						.. "\r\n\r\n"
						.. body,
					finish
				)
			end)
		end)
	end)
	if not ok then
		service:stop()
		error(err)
	end
	return service
end

function M.read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local data = file:read("*a")
	file:close()
	return data
end

return M
