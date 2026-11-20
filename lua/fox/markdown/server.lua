local render = require("fox.markdown.render")
local http = require("fox.markdown.http")
local M = {}
local server, prefix
local pages = {}
local assets = vim.fn.stdpath("config") .. "/tools/fox-markdown-gh/"

function M.stop()
	if server then
		server:stop()
		server = nil
	end
	pages = {}
end

local mime = {
	png = "image/png",
	jpg = "image/jpeg",
	jpeg = "image/jpeg",
	gif = "image/gif",
	webp = "image/webp",
	svg = "image/svg+xml",
}
local preview_csp =
	"default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https: http:; media-src 'self' https: http:; connect-src 'self'; font-src 'self'; base-uri 'none'; frame-ancestors 'none'"
local svg_csp = "sandbox; default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"

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
		["mona-sans.woff2"] = { "mona-sans.woff2", "font/woff2" },
		["mona-sans-italic.woff2"] = { "mona-sans-italic.woff2", "font/woff2" },
	}
	if files[resource] then
		local file = files[resource]
		local data = http.read_file(assets .. file[1])
		return data and 200 or 404, data or "Resource missing", file[2]
	end
	-- Only image files inside the current document directory are exposed.
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
				local data = http.read_file(path)
				if data then
					return 200, data, kind
				end
			end
		end
	end
	return 404, "Not found", "text/plain"
end

function M.start(buf)
	if not server then
		server = http.start({
			max_request = 8192,
			csp = preview_csp,
			error_message = "Preview could not be rendered",
			handle = function(_, method, target)
				if method ~= "GET" or not server then
					return 403, "Forbidden", "text/plain"
				end
				local status, body, kind = response(target)
				return status, body, kind, kind == mime.svg and svg_csp or preview_csp
			end,
		})
		prefix = server.prefix
	end
	local win = vim.fn.bufwinid(buf)
	pages[buf] = { line = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1 }
	return server.url .. buf .. "/"
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
