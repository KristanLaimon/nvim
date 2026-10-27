local render = require("fox.markdown.render")
local M = {}
local server, prefix, origin
local pages, clients = {}, {}
local assets = vim.fn.stdpath("config") .. "/config/markdown/"

local function close(handle)
	if handle and not handle:is_closing() then
		handle:close()
	end
end

function M.stop()
	close(server)
	server = nil
	for client, timer in pairs(clients) do
		close(timer)
		close(client)
	end
	pages, clients = {}, {}
end

local mime = { png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif", webp = "image/webp" }

local function read_file(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	return content
end

local function response(target)
	if target:sub(1, #prefix) ~= prefix then
		return 404, "Not found", "text/plain"
	end
	local id, resource = target:sub(#prefix + 1):match("^(%d+)/(.*)$")
	id = tonumber(id)
	if not id or not pages[id] or not vim.api.nvim_buf_is_valid(id) then
		return 410, "Preview stopped or buffer closed", "text/plain"
	end
	local requested_revision = resource:match("^content%?revision=(%w*)$")
	if resource == "content" or requested_revision then
		local tick = vim.api.nvim_buf_get_changedtick(id)
		local page = pages[id]
		if page.tick ~= tick or page.filetype ~= vim.bo[id].filetype then
			local lines = vim.api.nvim_buf_get_lines(id, 0, -1, false)
			page.html = vim.bo[id].filetype == "mermaid"
					and ('<pre class="mermaid" data-source-line="1" data-source-end="' .. #lines .. '">' .. render.escape(
						table.concat(lines, "\n")
					) .. "</pre>")
				or render.render(lines)
			page.tick = tick
			page.filetype = vim.bo[id].filetype
		end
		local revision = tostring(tick) .. vim.bo[id].filetype
		return 200,
			vim.json.encode({
				html = requested_revision ~= revision and page.html or nil,
				title = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(id), ":t"),
				revision = revision,
				line = page.line,
			}),
			"application/json"
	end
	local files = {
		[""] = { "page.html", "text/html" },
		["preview.js"] = { "preview.js", "text/javascript" },
		["mermaid.min.js"] = { "mermaid.min.js", "text/javascript" },
		["markdown.css"] = { "markdown.css", "text/css" },
	}
	if files[resource] then
		local file = files[resource]
		local data = read_file(assets .. file[1])
		return data and 200 or 404, data or "Resource missing", file[2]
	end
	-- Only raster images inside the current document directory are exposed.
	local decoded = resource:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	local kind = mime[(decoded:match("%.(%a+)$") or ""):lower()]
	if kind and not decoded:find("[%z\\:]") then
		local directory = vim.uv.fs_realpath(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(id), ":p:h"))
		local path = directory and vim.uv.fs_realpath(directory .. "/" .. decoded)
		if
			path and vim.fs.normalize(path):sub(1, #vim.fs.normalize(directory) + 1) == vim.fs.normalize(directory) .. "/"
		then
			local stat = vim.uv.fs_stat(path)
			if stat and stat.type == "file" and stat.size <= 10 * 1024 * 1024 then
				local data = read_file(path)
				if data then
					return 200, data, kind
				end
			end
		end
	end
	return 404, "Not found", "text/plain"
end

local function accept(err)
	if err or not server then
		return
	end
	local client = vim.uv.new_tcp()
	if not server:accept(client) then
		close(client)
		return
	end
	local timer = vim.uv.new_timer()
	clients[client] = timer
	local function finish()
		clients[client] = nil
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
			local status, body, content_type = 403, "Forbidden", "text/plain"
			if method == "GET" and host == origin and server then
				local ok
				ok, status, body, content_type = pcall(response, target)
				if not ok then
					status, body, content_type = 500, "Preview could not be rendered", "text/plain"
				end
			end
			client:write(
				"HTTP/1.1 "
					.. status
					.. " OK\r\nContent-Type: "
					.. content_type
					.. "; charset=utf-8\r\nContent-Length: "
					.. #body
					.. "\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https: http:; connect-src 'self'; font-src 'self'; base-uri 'none'; frame-ancestors 'none'\r\n\r\n"
					.. body,
				finish
			)
		end)
	end)
end

function M.start(buf)
	if not server then
		local candidate = assert(vim.uv.new_tcp())
		local ok, err = candidate:bind("127.0.0.1", 0)
		if not ok then
			close(candidate)
			error(err)
		end
		server = candidate
		origin = "127.0.0.1:" .. server:getsockname().port
		prefix = "/" .. vim.fn.sha256(assert(vim.uv.random(32))):sub(1, 32) .. "/"
		ok, err = server:listen(32, accept)
		if not ok then
			M.stop()
			error(err)
		end
	end
	local win = vim.fn.bufwinid(buf)
	pages[buf] = { line = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1 }
	return "http://" .. origin .. prefix .. buf .. "/"
end

function M.active(buf)
	return pages[buf] ~= nil
end

function M.release(buf)
	pages[buf] = nil
	if not next(pages) then
		M.stop()
	end
end

function M.follow(buf, line)
	if pages[buf] then
		pages[buf].line = line
	end
end

return M
