local workspace = require("fox.reader.workspace")
local renderer = require("fox.markdown.render")
local M = {}
local sessions = {}
local assets = vim.fn.stdpath("config") .. "/config/tools/fox-reader/"

local function close(handle)
	if handle and not handle:is_closing() then
		handle:close()
	end
end

local function read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local data = file:read("*a")
	file:close()
	return data
end

function M.stop()
	for _, session in pairs(sessions) do
		close(session.server)
		for client, timer in pairs(session.clients) do
			close(timer)
			close(client)
		end
	end
	sessions = {}
end

local function decode(value)
	return (value:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function response(session, target)
	if target:sub(1, #session.prefix) ~= session.prefix then
		return 404, "Not found", "text/plain"
	end
	local route = target:sub(#session.prefix + 1)
	local path = route:match("^document%?path=(.*)$")
	if path then
		path = decode(path)
		local content, err = workspace.read(session.root, path)
		if not content then
			return 404, err, "text/plain"
		end
		return 200,
			vim.json.encode({ html = renderer.render(vim.split(content, "\n", { plain = true })), path = path }),
			"application/json"
	end
	if route == "library" then
		if not session.scanning and vim.uv.now() - session.last_scan >= 5000 then
			session.scanning = true
			workspace.list(session.root, function(files)
				session.files = files
				session.scanning = false
				session.last_scan = vim.uv.now()
			end)
		end
		return 200, vim.json.encode({ files = session.files }), "application/json"
	end
	local image = route:match("^image%?path=(.*)$")
	if image then
		image = decode(image)
		local kind = (
			{ png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif", webp = "image/webp" }
		)[(image:match("%.(%a+)$") or ""):lower()]
		local image_path = kind and workspace.resolve(session.root, image)
		local stat = image_path and vim.uv.fs_stat(image_path)
		if stat and stat.type == "file" and stat.size <= 10 * 1024 * 1024 then
			local data = read_file(image_path)
			if data then
				return 200, data, kind
			end
		end
		return 404, "Image unavailable", "text/plain"
	end
	local asset = ({
		[""] = { assets .. "index.html", "text/html" },
		["reader.js"] = { assets .. "reader.js", "text/javascript" },
		["reader.css"] = { assets .. "reader.css", "text/css" },
		["mermaid.min.js"] = {
			vim.fn.stdpath("config") .. "/config/tools/gb-markdown-render/mermaid.min.js",
			"text/javascript",
		},
	})[route]
	if asset then
		local data = read_file(asset[1])
		return data and 200 or 404, data or "Resource missing", asset[2]
	end
	return 404, "Not found", "text/plain"
end

local function accept(session)
	local client = vim.uv.new_tcp()
	if not session.server:accept(client) then
		close(client)
		return
	end
	local timer = vim.uv.new_timer()
	session.clients[client] = timer
	local function finish()
		session.clients[client] = nil
		close(timer)
		close(client)
	end
	timer:start(5000, 0, finish)
	local request = ""
	client:read_start(function(err, data)
		if err or not data then
			finish()
			return
		end
		request = request .. data
		if #request > 8192 then
			finish()
			return
		end
		if not request:find("\r\n\r\n", 1, true) then
			return
		end
		client:read_stop()
		vim.schedule(function()
			if client:is_closing() then
				return
			end
			local method, target = request:match("^(%u+) ([^ ]+) HTTP/1%.[01]\r\n")
			local host = request:lower():match("\r\nhost:%s*([^\r\n]+)")
			local status, body, kind = 403, "Forbidden", "text/plain"
			if method == "GET" and host == session.origin then
				local ok
				ok, status, body, kind = pcall(response, session, target)
				if not ok then
					status, body, kind = 500, "Reader request failed", "text/plain"
				end
			end
			client:write(
				"HTTP/1.1 "
					.. status
					.. " OK\r\nContent-Type: "
					.. kind
					.. "; charset=utf-8\r\nContent-Length: "
					.. #body
					.. "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'\r\n\r\n"
					.. body,
				finish
			)
		end)
	end)
end

function M.start(root)
	if sessions[root] then
		return sessions[root].url
	end
	local session = { root = root, files = {}, clients = {}, server = assert(vim.uv.new_tcp()), scanning = true }
	local ok, err = session.server:bind("127.0.0.1", 0)
	if not ok then
		close(session.server)
		error(err)
	end
	session.origin = "127.0.0.1:" .. session.server:getsockname().port
	session.prefix = "/" .. vim.fn.sha256(assert(vim.uv.random(32))):sub(1, 32) .. "/"
	session.url = "http://" .. session.origin .. session.prefix
	ok, err = session.server:listen(32, function(failure)
		if not failure then
			accept(session)
		end
	end)
	if not ok then
		close(session.server)
		error(err)
	end
	sessions[root] = session
	workspace.list(root, function(files)
		session.files = files
		session.scanning = false
		session.last_scan = vim.uv.now()
	end)
	return session.url
end

return M
