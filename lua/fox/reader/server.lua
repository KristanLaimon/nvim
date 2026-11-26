local workspace = require("fox.reader.workspace")
local renderer = require("fox.markdown.render")
local state = require("fox.reader.state")
local http = require("fox.markdown.http")
local M = {}
local sessions = {}
local assets = vim.fn.stdpath("config") .. "/tools/fox-reader/"

function M.stop()
	for _, session in pairs(sessions) do
		for _, job in pairs(session.jobs) do
			if job.process and not job.done then
				pcall(job.process.kill, job.process, 15)
			end
		end
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
	if route:sub(1, 1) == "?" then
		route = ""
	end
	local path = route:match("^document%?path=(.*)$")
	if path then
		path = decode(path)
		local content, err = workspace.read(session.root, path)
		if not content then
			return 404, err, "text/plain"
		end
		if path:lower():match("%.js$") or path:lower():match("%.py$") then
			local disk = http.read_file(workspace.resolve(session.root, path))
			if not disk then
				return 404, "Script cannot be read", "text/plain"
			end
			return 200, vim.json.encode({ code = disk, path = path }), "application/json"
		end
		if path:lower():match("%.json$") then
			return 200, vim.json.encode({ json = content, path = path }), "application/json"
		end
		if path:lower():match("%.txt$") then
			return 200,
				vim.json.encode({ html = '<pre class="plain-text">' .. renderer.escape(content) .. "</pre>", path = path }),
				"application/json"
		end
		local html, frontmatter = document(content)
		return 200, vim.json.encode({ html = html, frontmatter = frontmatter, path = path }), "application/json"
	end
	local source = route:match("^markdown%-source%?path=(.*)$")
	if source then
		source = decode(source)
		local resolved = source:lower():match("%.md$") and workspace.resolve(session.root, source)
		if resolved then
			for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
				local name = vim.api.nvim_buf_get_name(buffer)
				if name ~= "" and vim.uv.fs_realpath(name) == vim.uv.fs_realpath(resolved) and vim.bo[buffer].modified then
					return 409, "Document has unsaved changes in Neovim", "text/plain"
				end
			end
		end
		local content = resolved and http.read_file(resolved)
		return content and 200 or 404, content or "Markdown unavailable", "text/plain"
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
		local kind = ({
			png = "image/png",
			jpg = "image/jpeg",
			jpeg = "image/jpeg",
			gif = "image/gif",
			webp = "image/webp",
			svg = "image/svg+xml",
		})[(image:match("%.(%a+)$") or ""):lower()]
		local image_path = kind and workspace.resolve(session.root, image)
		local stat = image_path and vim.uv.fs_stat(image_path)
		if stat and stat.type == "file" and stat.size <= 10 * 1024 * 1024 then
			local data = http.read_file(image_path)
			if data then
				local svg_policy = "sandbox; default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"
				return 200, data, kind, kind == "image/svg+xml" and svg_policy or nil
			end
		end
		return 404, "Image unavailable", "text/plain"
	end
	local job_id = route:match("^job%?id=([%da-f]+)$")
	if job_id then
		local job = session.jobs[job_id]
		if not job then
			return 404, "Run unavailable", "text/plain"
		end
		return 200, vim.json.encode({ output = job.output, done = job.done, code = job.code }), "application/json"
	end
	local monaco_path = route:match("^vs/([%w%._/%-]+)$")
	if monaco_path and not monaco_path:find("..", 1, true) then
		local extension = monaco_path:match("%.([%w]+)$")
		local kind = ({ js = "text/javascript", css = "text/css", ttf = "font/ttf" })[extension]
		local data = kind and http.read_file(assets .. "vs/" .. monaco_path)
		return data and 200 or 404, data or "Resource missing", kind or "text/plain"
	end
	local asset = ({
		[""] = { assets .. "index.html", "text/html" },
		["reader.js"] = { assets .. "reader.js", "text/javascript" },
		["reader.css"] = { assets .. "reader.css", "text/css" },
		["markdown-editor.min.js"] = { assets .. "markdown-editor.min.js", "text/javascript" },
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
	local session = { root = root, files = {}, scanning = true, jobs = {} }
	local csp =
		"default-src 'none'; script-src 'self' 'unsafe-eval'; worker-src 'self' blob:; style-src 'self' 'unsafe-inline'; img-src 'self' https: http:; font-src 'self'; connect-src 'self'; frame-src 'self' https: http:; base-uri 'none'; frame-ancestors 'self'"
	session.http = http.start({
		max_request = 2 * 1024 * 1024,
		csp = csp,
		error_message = "Reader request failed",
		handle = function(service, method, target, headers, body, length)
			if method == "GET" then
				return response(session, target)
			end
			if
				method == "POST"
				and (target == service.prefix .. "state" or target == service.prefix .. "run" or target == service.prefix .. "stop-run" or target == service.prefix .. "run-input" or target == service.prefix .. "save-script" or target == service.prefix .. "save-markdown")
				and headers:match("\r\norigin:%s*([^\r\n]+)") == "http://" .. service.origin
				and headers:match("\r\ncontent%-type:%s*([^\r\n]+)") == "application/json"
				and length
				and length <= ((target == service.prefix .. "save-script" or target == service.prefix .. "save-markdown") and 2 * 1024 * 1024 - 4096 or 8192)
				and #body == length
			then
				local decoded, value = pcall(vim.json.decode, body)
				if target == service.prefix .. "state" then
					local saved, save_error = state.save(session.root, decoded and value or nil)
					return saved and 200 or 400, saved and "Saved" or save_error, "text/plain"
				end
				if not decoded or type(value) ~= "table" then
					return 400, "Invalid request", "text/plain"
				end
				if target == service.prefix .. "save-script" or target == service.prefix .. "save-markdown" then
					local path = type(value.path) == "string" and value.path or ""
					local markdown = target == service.prefix .. "save-markdown"
					local resolved = (
						markdown and path:lower():match("%.md$")
						or not markdown and (path:lower():match("%.js$") or path:lower():match("%.py$"))
					) and workspace.resolve(session.root, path)
					if not resolved or type(value.code) ~= "string" or type(value.original) ~= "string" then
						return 400, "Invalid script", "text/plain"
					end
					if http.read_file(resolved) ~= value.original then
						return 409, "Script changed on disk; reload before saving", "text/plain"
					end
					for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
						local name = vim.api.nvim_buf_get_name(buffer)
						if name ~= "" and vim.uv.fs_realpath(name) == vim.uv.fs_realpath(resolved) and vim.bo[buffer].modified then
							return 409, "Script has unsaved changes in Neovim", "text/plain"
						end
					end
					local file, err = io.open(resolved, "wb")
					if not file then
						return 500, "Could not save script: " .. tostring(err), "text/plain"
					end
					local written, write_err = file:write(value.code)
					local closed, close_err = file:close()
					if not written or not closed then
						return 500, "Could not save script: " .. tostring(write_err or close_err), "text/plain"
					end
					for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
						local name = vim.api.nvim_buf_get_name(buffer)
						if
							vim.api.nvim_buf_is_loaded(buffer)
							and name ~= ""
							and vim.uv.fs_realpath(name) == vim.uv.fs_realpath(resolved)
						then
							local autoread = vim.bo[buffer].autoread
							vim.bo[buffer].autoread = true
							vim.cmd.checktime(tostring(buffer))
							vim.bo[buffer].autoread = autoread
						end
					end
					return 200, "Saved", "text/plain"
				end
				if target == service.prefix .. "run-input" then
					local job = type(value.id) == "string" and session.jobs[value.id]
					if
						not job
						or job.done
						or job.input_closed
						or not job.process
						or (not value.close and (type(value.input) ~= "string" or #value.input > 6000))
					then
						return 400, "Script input is unavailable", "text/plain"
					end
					local line = not value.close and value.input .. "\n" or nil
					local ok, err = pcall(job.process.write, job.process, line)
					if not ok then
						return 400, "Could not send input: " .. tostring(err), "text/plain"
					end
					if line then
						job.output = (job.output .. line):sub(-1024 * 1024)
					else
						job.input_closed = true
					end
					return 200, "Input sent", "text/plain"
				end
				if target == service.prefix .. "stop-run" then
					local job = session.jobs[value.id]
					if job and not job.done and job.process then
						job.process:kill(15)
					end
					return 200, "Stopped", "text/plain"
				end
				local path = type(value.path) == "string" and value.path or ""
				local extension = path:lower():match("%.([^.]+)$")
				local executable = ({ js = "node", py = "python" })[extension]
				if executable == "python" and vim.fn.executable(executable) ~= 1 and vim.fn.executable("python3") == 1 then
					executable = "python3"
				end
				local resolved = executable and workspace.resolve(session.root, path)
				local stat = resolved and vim.uv.fs_stat(resolved)
				if not stat or stat.type ~= "file" then
					return 400, "Script is unavailable", "text/plain"
				end
				if vim.fn.executable(executable) ~= 1 then
					return 400, executable .. " is not available on PATH", "text/plain"
				end
				local id = vim.fn.sha256(assert(vim.uv.random(32))):sub(1, 32)
				local job = { output = "", done = false }
				session.jobs[id] = job
				local function append(err, data)
					vim.schedule(function()
						local chunk = data or err or ""
						job.output = (job.output .. chunk):sub(-1024 * 1024)
					end)
				end
				local command = extension == "py" and { executable, "-u", resolved } or { executable, resolved }
				local ok, process = pcall(vim.system, command, {
					cwd = vim.fs.dirname(resolved),
					stdin = true,
					text = true,
					stdout = append,
					stderr = append,
				}, function(result)
					vim.schedule(function()
						job.done = true
						job.code = result.code
						vim.defer_fn(function()
							session.jobs[id] = nil
						end, 300000)
					end)
				end)
				if not ok then
					session.jobs[id] = nil
					return 500, "Could not start script: " .. tostring(process), "text/plain"
				end
				job.process = process
				return 200, vim.json.encode({ id = id }), "application/json"
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
