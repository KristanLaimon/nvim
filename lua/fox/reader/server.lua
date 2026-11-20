local workspace = require("fox.reader.workspace")
local renderer = require("fox.markdown.render")
local state = require("fox.reader.state")
local http = require("fox.markdown.http")
local M = {}
local sessions = {}
local assets = vim.fn.stdpath("config") .. "/tools/fox-reader/"

function M.stop()
	for _, session in pairs(sessions) do
		session.http:stop()
	end
	sessions = {}
end

local function decode(value)
	return (value:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

local function editor_theme()
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
	local dark = vim.o.background == "dark"
	return {
		background = string.format("#%06x", normal.bg or (dark and 0x191919 or 0xffffff)),
		foreground = string.format("#%06x", normal.fg or (dark and 0xe6e0d5 or 0x222222)),
		muted = string.format("#%06x", comment.fg or (dark and 0xaaaaaa or 0x777777)),
		dark = dark,
	}
end

local function document(content)
	local lines = vim.split(content, "\n", { plain = true, trimempty = false })
	if vim.trim(lines[1] or "") == "---" then
		local has_field = false
		for index = 2, #lines do
			local line = lines[index]:gsub("\r$", "")
			if line:match("^%-%-%-%s*$") or line:match("^%.%.%.%s*$") then
				if has_field then
					return renderer.render(vim.list_slice(lines, index + 1), index),
						table.concat(vim.list_slice(lines, 2, index - 1), "\n"):gsub("\r\n", "\n")
				end
				break
			end
			if line:match("^[^%s:#][^:]*:%s*") then
				has_field = true
			end
		end
	end
	return renderer.render(lines)
end

local function response(session, target)
	if target:sub(1, #session.prefix) ~= session.prefix then
		return 404, "Not found", "text/plain"
	end
	local route = target:sub(#session.prefix + 1)
	if route:match("^%?path=") then
		route = ""
	end
	local path = route:match("^document%?path=(.*)$")
	if path then
		path = decode(path)
		local content, err = workspace.read(session.root, path)
		if not content then
			return 404, err, "text/plain"
		end
		local html, frontmatter = document(content)
		return 200, vim.json.encode({ html = html, frontmatter = frontmatter, path = path }), "application/json"
	end
	local state_path = route:match("^state%?path=(.*)$")
	if route == "state" or state_path then
		return 200, vim.json.encode(state.get(session.root, state_path and decode(state_path))), "application/json"
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
	if route == "theme" then
		return 200, vim.json.encode(editor_theme()), "application/json"
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
			local data = http.read_file(image_path)
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
		["fonts/trebuc.ttf"] = { assets .. "fonts/trebuc.ttf", "font/ttf" },
		["fonts/trebucbd.ttf"] = { assets .. "fonts/trebucbd.ttf", "font/ttf" },
		["fonts/trebucit.ttf"] = { assets .. "fonts/trebucit.ttf", "font/ttf" },
		["fonts/trebucbi.ttf"] = { assets .. "fonts/trebucbi.ttf", "font/ttf" },
		["mermaid.min.js"] = {
			vim.fn.stdpath("config") .. "/tools/fox-markdown-gh/mermaid.min.js",
			"text/javascript",
		},
	})[route]
	if asset then
		local data = http.read_file(asset[1])
		if data and route == "" then
			local theme = editor_theme()
			local choice = state.get(session.root).preferences.theme
			if not vim.tbl_contains({ "editor", "paper", "light", "dark" }, choice) then
				choice = "editor"
			end
			data = data:gsub('<html lang="en">', '<html lang="en" data-theme="' .. choice .. '">', 1)
			local style = string.format(
				"<style>:root{--editor-background:%s;--editor-foreground:%s;--editor-muted:%s;--editor-scheme:%s}</style>",
				theme.background,
				theme.foreground,
				theme.muted,
				theme.dark and "dark" or "light"
			)
			data = data:gsub("<head>", "<head>" .. style, 1)
		end
		return data and 200 or 404, data or "Resource missing", asset[2]
	end
	return 404, "Not found", "text/plain"
end

function M.start(root)
	if sessions[root] then
		return sessions[root].url
	end
	local session = { root = root, files = {}, scanning = true }
	local csp =
		"default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'"
	session.http = http.start({
		max_request = 16384,
		csp = csp,
		error_message = "Reader request failed",
		handle = function(service, method, target, headers, body, length)
			if method == "GET" then
				return response(session, target)
			end
			if
				method == "POST"
				and target == service.prefix .. "state"
				and headers:match("\r\norigin:%s*([^\r\n]+)") == "http://" .. service.origin
				and headers:match("\r\ncontent%-type:%s*([^\r\n]+)") == "application/json"
				and length
				and length <= 8192
				and #body == length
			then
				local decoded, value = pcall(vim.json.decode, body)
				local saved, save_error = state.save(session.root, decoded and value or nil)
				return saved and 200 or 400, saved and "Saved" or save_error, "text/plain"
			end
			return 403, "Forbidden", "text/plain"
		end,
	})
	session.prefix = session.http.prefix
	session.url = session.http.url
	sessions[root] = session
	workspace.list(root, function(files)
		session.files = files
		session.scanning = false
		session.last_scan = vim.uv.now()
	end)
	return session.url
end

return M
