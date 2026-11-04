-- Native, literal project replacement. Preview snapshots guard every write.
local M = {}
local uv = vim.uv
local excluded = {
	[".git"] = true,
	[".hg"] = true,
	[".svn"] = true,
	[".foxnvim"] = true,
	[".krsnvim"] = true,
	node_modules = true,
	vendor = true,
	[".venv"] = true,
	target = true,
	dist = true,
	build = true,
}

local function read(filename)
	local file, err = io.open(filename, "rb")
	if not file then
		error(err)
	end
	local data = file:read("*a")
	file:close()
	assert(data, "Cannot read " .. filename)
	return data
end

local function buffer_data(buf)
	local options = vim.bo[buf]
	local eol = options.fileformat == "dos" and "\r\n" or options.fileformat == "mac" and "\r" or "\n"
	local data = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), eol)
	if options.endofline then
		data = data .. eol
	end
	if options.fileencoding ~= "" and options.fileencoding ~= "utf-8" then
		data = vim.iconv(data, "utf-8", options.fileencoding)
	end
	if options.bomb then
		assert(options.fileencoding == "utf-8", "Only UTF-8 byte order marks are supported")
		data = "\239\187\191" .. data
	end
	return data
end

function M.replace(text, search, replacement)
	assert(search ~= "", "Search must not be empty")
	local parts, start, count = {}, 1, 0
	while true do
		local first, last = text:find(search, start, true)
		if not first then
			parts[#parts + 1] = text:sub(start)
			return table.concat(parts), count
		end
		parts[#parts + 1] = text:sub(start, first - 1) .. replacement
		start, count = last + 1, count + 1
	end
end

local function compile(search, replacement, options)
	local expression = options.regex and ("\\m" .. search) or ("\\V" .. vim.fn.escape(search, "\\"))
	if options.word then
		expression = "\\<\\%(" .. expression .. "\\m\\)\\>"
	end
	expression = (options.case_sensitive == false and "\\c" or "\\C") .. expression
	local regex = vim.regex(expression)
	local function transform(text)
		if not regex:match_str(text) then
			return text, 0, {}
		end
		local spans, offset, previous_end = {}, 0, -1
		while offset <= #text do
			local found = vim.fn.matchstrpos(text, expression, offset, 1)
			local first, last = found[2], found[3]
			if first < 0 then
				break
			end
			-- Vim skips a trailing empty match immediately after the preceding match.
			if first ~= last or first ~= #text or first ~= previous_end then
				spans[#spans + 1] = { first, last }
				assert(#spans <= 10000, "Too many matches; narrow the search")
				previous_end = last
			end
			if last == first then
				local char = vim.fn.strcharpart(text:sub(last + 1), 0, 1)
				offset = last + math.max(1, #char)
			else
				offset = last
			end
		end
		local replace = options.regex and replacement or function()
			return replacement
		end
		return vim.fn.substitute(text, expression, replace, "g"), #spans, spans
	end
	return regex, transform
end

-- Ripgrep only selects candidate files; Vim still owns match/replacement semantics.
function M.command(search, options)
	local command = { "rg", "--no-config", "--null", "--hidden", "--max-filesize", "2M" }
	for name in pairs(excluded) do
		vim.list_extend(command, { "--glob", "!**/" .. name .. "/**" })
	end
	if options.regex then
		command[#command + 1] = "--files"
	else
		vim.list_extend(command, {
			"--files-with-matches",
			"--fixed-strings",
			options.case_sensitive and "--case-sensitive" or "--ignore-case",
			"--",
			search,
			".",
		})
	end
	return command
end

-- Search is line-based; lazy snapshots do not load editor buffers.
function M.preview(root, search, replacement, glob, options)
	options = options or {}
	assert(search ~= "" and not search:find("[\r\n]"), "Enter a nonempty, single-line search")
	assert(not replacement:find("[\r\n]"), "Replacement must be a single line")
	local regex, transform = compile(search, replacement, options)
	root = vim.fs.normalize(vim.fn.fnamemodify(root, ":p"))
	local plan = { root = root, files = {}, count = 0, skipped = 0 }
	local filter = vim.regex(vim.fn.glob2regpat(glob and glob ~= "" and glob or "*"))
	local visited = 0
	local function visit()
		visited = visited + 1
		assert(visited <= 50000, "Project too large; choose a smaller directory")
		if options.yield and visited % 25 == 0 then
			options.yield()
		end
	end
	local function process(filename, relative)
		if not filter:match_str(relative) then
			return
		end
		local stat = uv.fs_lstat(filename)
		if not stat or stat.type ~= "file" then
			return
		end
		if stat.size > 2 * 1024 * 1024 then
			plan.skipped = plan.skipped + 1
			return
		end
		local data = read(filename)
		if data:find("\0", 1, true) then
			plan.skipped = plan.skipped + 1
			return
		end
		local buf = vim.fn.bufnr(filename)
		local loaded = buf > 0 and vim.api.nvim_buf_is_loaded(buf)
		local unsaved = loaded and vim.bo[buf].modified
		if not regex:match_str(data) and not (options.include_unsaved and unsaved) then
			return
		end
		local before, tick, replacement_error
		if loaded or not options.lazy then
			buf = vim.fn.bufadd(filename)
			vim.fn.bufload(buf)
			if not options.include_unsaved then
				assert(not vim.bo[buf].modified, "Save unsaved changes first: " .. relative)
				assert(not vim.bo[buf].readonly, "Read-only file: " .. relative)
			end
			if not vim.bo[buf].modified then
				vim.api.nvim_buf_call(buf, function()
					vim.cmd("silent checktime")
				end)
			end
			assert(read(filename) == data, "File changed while searching; preview again: " .. relative)
			if not vim.bo[buf].modified and buffer_data(buf) ~= data then
				replacement_error = "Mixed line endings or encoding differ from the buffer"
			end
			before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			tick = vim.api.nvim_buf_get_changedtick(buf)
		else
			buf = nil
			local text = data:gsub("^\239\187\191", "")
			before = vim.split(text, "\n", { plain = true })
			if text:sub(-1) == "\n" then
				table.remove(before)
			end
			local crlf = select(2, text:gsub("\r\n", ""))
			local lf = select(2, text:gsub("\n", ""))
			if crlf > 0 and crlf ~= lf then
				replacement_error = "Mixed line endings; replacement is disabled to preserve file bytes"
			end
			for index, line in ipairs(before) do
				before[index] = line:gsub("\r$", "")
			end
		end
		local after, matches = {}, {}
		for line, text in ipairs(before) do
			local updated, count, spans = transform(text)
			assert(not updated:find("[\n%z]"), "Replacement must stay on one line")
			if updated:find("\r", 1, true) then
				local _, before_cr = text:gsub("\r", "")
				local _, after_cr = updated:gsub("\r", "")
				assert(after_cr <= before_cr, "Replacement must stay on one line")
			end
			after[line] = updated
			if count > 0 then
				plan.count = plan.count + count
				assert(plan.count <= 10000, "Too many matches; narrow the file filter")
				matches[#matches + 1] = { line = line, before = text, after = updated, spans = spans }
			end
		end
		if #matches > 0 then
			plan.files[#plan.files + 1] = {
				filename = filename,
				relative = relative,
				buf = buf,
				data = data,
				tick = tick,
				before = before,
				after = after,
				matches = matches,
				replacement_error = replacement_error,
				selected = replacement_error == nil,
			}
		end
	end
	local function scan(directory, prefix)
		local handle, err = uv.fs_scandir(directory)
		assert(handle, err)
		while true do
			local name, kind = uv.fs_scandir_next(handle)
			if not name then
				break
			end
			visit()
			local filename, relative = vim.fs.joinpath(directory, name), prefix .. name
			if kind == "directory" and not excluded[name] then
				scan(filename, relative .. "/")
			elseif kind == "file" then
				process(filename, relative)
			end
		end
	end
	if options.files then
		local candidates = {}
		local function add(filename)
			local relative = require("fox.core.path").relative_to(filename, root)
			if not relative then
				return
			end
			for part in relative:gmatch("[^/]+") do
				if excluded[part] then
					return
				end
			end
			candidates[filename] = relative
		end
		for _, filename in ipairs(options.files) do
			add(
				vim.fs.normalize(require("fox.core.path").is_absolute(filename) and filename or vim.fs.joinpath(root, filename))
			)
		end
		if options.include_unsaved then
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buftype == "" then
					add(vim.fs.normalize(vim.api.nvim_buf_get_name(buf)))
				end
			end
		end
		for filename, relative in pairs(candidates) do
			visit()
			process(filename, relative)
		end
	else
		scan(root, "")
	end
	table.sort(plan.files, function(a, b)
		return a.relative < b.relative
	end)
	return plan
end

function M.apply(plan)
	assert(not plan.applied, "Preview already applied; search again")
	local selected = {}
	for _, file in ipairs(plan.files) do
		if file.selected then
			assert(
				not file.replacement_error,
				"Cannot safely replace " .. file.relative .. ": " .. tostring(file.replacement_error)
			)
			local stat = uv.fs_lstat(file.filename)
			assert(stat and stat.type == "file", "File type changed: " .. file.relative)
			assert(read(file.filename) == file.data, "File changed on disk; preview again: " .. file.relative)
			if not file.buf then
				local buf = vim.fn.bufadd(file.filename)
				vim.fn.bufload(buf)
				assert(
					not vim.bo[buf].modified and not vim.bo[buf].readonly,
					"Save edits or check permissions: " .. file.relative
				)
				assert(
					vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), file.before),
					"File decoding differs; replacement blocked: " .. file.relative
				)
				assert(buffer_data(buf) == file.data, "File format differs; replacement blocked: " .. file.relative)
				file.buf, file.tick = buf, vim.api.nvim_buf_get_changedtick(buf)
			end
			assert(
				vim.api.nvim_buf_is_loaded(file.buf)
					and vim.api.nvim_buf_get_name(file.buf):gsub("\\", "/") == file.filename
					and not vim.bo[file.buf].modified
					and not vim.bo[file.buf].readonly
					and vim.api.nvim_buf_get_changedtick(file.buf) == file.tick
					and buffer_data(file.buf) == file.data,
				"Buffer changed; preview again: " .. file.relative
			)
			selected[#selected + 1] = file
		end
	end
	assert(#selected > 0, "No files selected")
	-- Validate the whole selection before writing; leave failed writes undoable.
	plan.applied = true
	local written = 0
	for _, file in ipairs(selected) do
		local ok, err = pcall(vim.api.nvim_buf_call, file.buf, function()
			vim.api.nvim_buf_set_lines(file.buf, 0, -1, false, file.after)
			local fixeol = vim.bo[file.buf].fixendofline
			vim.bo[file.buf].fixendofline = false
			local saved, message = pcall(vim.cmd, "silent noautocmd keepalt write")
			vim.bo[file.buf].fixendofline = fixeol
			assert(saved, message)
		end)
		assert(ok, string.format("%d files written; failed at %s: %s", written, file.relative, tostring(err)))
		written = written + 1
	end
	return written
end

return M
