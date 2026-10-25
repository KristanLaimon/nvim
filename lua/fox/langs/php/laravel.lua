-- Laravel index and navigation. No parser or PHP runtime is needed for static
-- references; Artisan routes/component aliases are queried asynchronously.
local M = { ns = vim.api.nvim_create_namespace("fox_laravel_values") }
local caches, shown = {}, false
local function read(file)
	local ok, lines = pcall(vim.fn.readfile, file)
	return ok and table.concat(lines, "\n") or ""
end
local function json(file)
	local ok, value = pcall(vim.json.decode, read(file))
	return ok and type(value) == "table" and value or {}
end
function M.root(buf)
	local name = vim.api.nvim_buf_get_name(buf or 0)
	return vim.fs.root(name ~= "" and name or vim.fn.getcwd(), { "artisan" })
end
local function entry(index, kind, key, file, row, value)
	if key == "" then
		return
	end
	index[kind] = index[kind] or {}
	index[kind][key] = index[kind][key] or {}
	table.insert(index[kind][key], { file = file, row = row or 1, value = value })
end
local function files(root, dir, callback)
	if vim.fn.isdirectory(root .. "/" .. dir) == 0 then
		return
	end
	local count = 0
	for name, kind in vim.fs.dir(root .. "/" .. dir, { depth = 25 }) do
		if kind == "file" then
			count = count + 1
			if count > 10000 then
				break
			end
			callback(name, root .. "/" .. dir .. "/" .. name)
		end
	end
end
-- Small PHP token reader for associative config/translation arrays. It keeps
-- nesting and quoted/escaped strings without evaluating project PHP code.
local function php_value(content)
	local depth, quote, escaped = 0, nil, false
	for pos = 1, #content do
		local c = content:sub(pos, pos)
		if quote then
			if escaped then
				escaped = false
			elseif c == "\\" then
				escaped = true
			elseif c == quote then
				quote = nil
			end
		elseif c == "'" or c == '"' then
			quote = c
		elseif c == "[" or c == "(" or c == "{" then
			depth = depth + 1
		elseif c == "]" or c == ")" or c == "}" then
			if depth == 0 then
				return vim.trim(content:sub(1, pos - 1))
			end
			depth = depth - 1
		elseif c == "," and depth == 0 then
			return vim.trim(content:sub(1, pos - 1))
		end
	end
	return vim.trim(content)
end
function M.php_keys(content, prefix)
	local result, stack = {}, {}
	local i, row, pending = 1, 1, nil
	while i <= #content do
		local c = content:sub(i, i)
		if c == "\n" then
			row = row + 1
			i = i + 1
		elseif content:sub(i, i + 1) == "//" or c == "#" then
			i = content:find("\n", i, true) or (#content + 1)
		elseif content:sub(i, i + 1) == "/*" then
			local stop = content:find("*/", i + 2, true) or (#content - 1)
			local _, n = content:sub(i, stop + 1):gsub("\n", "")
			row = row + n
			i = stop + 2
		elseif c == "'" or c == '"' then
			local start, start_row = i, row
			i = i + 1
			while i <= #content do
				if content:sub(i, i) == "\\" then
					i = i + 2
				elseif content:sub(i, i) == c then
					break
				else
					if content:sub(i, i) == "\n" then
						row = row + 1
					end
					i = i + 1
				end
			end
			local key = content:sub(start + 1, i - 1)
			i = i + 1
			local tail = content:sub(i)
			if tail:match("^%s*=>") then
				local parts = { prefix }
				for _, name in ipairs(stack) do
					if name ~= "" then
						parts[#parts + 1] = name
					end
				end
				parts[#parts + 1] = key
				local value = php_value(tail:match("^%s*=>%s*(.*)$") or "")
				result[table.concat(parts, ".")] = { row = start_row, value = vim.trim(value) }
				pending = key
			end
		elseif c == "[" then
			stack[#stack + 1] = pending or ""
			pending = nil
			i = i + 1
		elseif c == "]" then
			stack[#stack] = nil
			pending = nil
			i = i + 1
		elseif c == "," then
			pending = nil
			i = i + 1
		else
			i = i + 1
		end
	end
	return result
end
local function kebab(value)
	return (value:gsub("(%l)(%u)", "%1-%2"):gsub("/", "."):lower())
end
function M.class_paths(root, class)
	local composer = json(root .. "/composer.json")
	local mappings = vim.tbl_get(composer, "autoload", "psr-4") or { ["App\\"] = "app/" }
	local namespaces = vim.tbl_keys(mappings)
	table.sort(namespaces, function(a, b)
		return #a > #b
	end)
	local paths = {}
	for _, namespace in ipairs(namespaces) do
		if class:sub(1, #namespace) == namespace then
			local dirs = mappings[namespace]
			dirs = type(dirs) == "table" and dirs or { dirs }
			for _, dir in ipairs(dirs) do
				paths[#paths + 1] =
					vim.fs.normalize(root .. "/" .. dir .. "/" .. class:sub(#namespace + 1):gsub("\\", "/") .. ".php")
			end
			break
		end
	end
	return paths
end
function M.index(root)
	local cached = caches[root]
	if cached and vim.uv.hrtime() - cached.time < 5e9 then
		return cached.index
	end
	local index = {}
	local state = { time = vim.uv.hrtime(), index = index }
	caches[root] = state
	files(root, "resources/views", function(name, file)
		if name:match("%.blade%.php$") then
			local key = name:gsub("%.blade%.php$", ""):gsub("/", ".")
			entry(index, "view", key, file)
			if name:match("^vendor/") then
				entry(index, "view", key:gsub("^vendor%.([^%.]+)%.", "%1::"), file)
			end
			local component = key:match("^components%.(.+)")
			if component then
				entry(index, "component", component, file)
			end
			local livewire = key:match("^livewire%.(.+)")
			if livewire then
				entry(index, "livewire", livewire, file)
			end
		end
	end)
	for _, base in ipairs({ "app/View/Components", "app/Livewire", "app/Http/Livewire" }) do
		files(root, base, function(name, file)
			if name:match("%.php$") then
				entry(
					index,
					base:find("Components", 1, true) and "component" or "livewire",
					kebab(name:gsub("%.php$", "")),
					file
				)
			end
		end)
	end
	files(root, "resources/js/Pages", function(name, file)
		if name:match("%.[jt]sx?$") or name:match("%.vue$") then
			entry(index, "inertia", name:gsub("%.[^.]+$", ""), file)
		end
	end)
	files(root, "config", function(name, file)
		if name:match("%.php$") then
			for key, data in pairs(M.php_keys(read(file), name:gsub("%.php$", ""):gsub("/", "."))) do
				entry(index, "config", key, file, data.row, data.value)
			end
		end
	end)
	for _, base in ipairs({ "lang", "resources/lang" }) do
		files(root, base, function(name, file)
			local prefix = name:match("^[^/]+/(.+)%.php$")
			if prefix then
				for key, data in pairs(M.php_keys(read(file), prefix:gsub("/", "."))) do
					entry(index, "lang", key, file, data.row, data.value)
				end
			elseif name:match("%.json$") then
				for key, value in pairs(json(file)) do
					entry(index, "lang", key, file, 1, tostring(value))
				end
			end
		end)
	end
	local env = read(root .. "/.env")
	local env_row = 0
	for line in (env .. "\n"):gmatch("(.-)\n") do
		env_row = env_row + 1
		local key, value = line:match("^%s*([%w_]+)%s*=%s*(.*)")
		if key then
			entry(index, "env", key, root .. "/.env", env_row, value)
		end
	end
	files(root, "routes", function(_, file)
		local row = 0
		for line in (read(file) .. "\n"):gmatch("(.-)\n") do
			row = row + 1
			for key in line:gmatch("[>:]name%s*%(%s*['\"]([^'\"]+)['\"]") do
				entry(index, "route", key, file, row)
			end
		end
	end)
	-- Each root owns its job and generation. Clearing/switching projects cannot
	-- publish old process results into the new root's index.
	if vim.fn.executable("php") == 1 then
		local function run(args, consume)
			local ok, job = pcall(vim.system, args, { cwd = root, text = true, timeout = 3000 }, function(result)
				vim.schedule(function()
					if caches[root] ~= state or result.code ~= 0 then
						return
					end
					local decoded_ok, data = pcall(vim.json.decode, result.stdout)
					if decoded_ok and type(data) == "table" then
						consume(data)
					end
				end)
			end)
			if ok then
				state.jobs = state.jobs or {}
				state.jobs[#state.jobs + 1] = job
			end
		end
		run({ "php", "artisan", "route:list", "--json" }, function(routes)
			for _, route in ipairs(routes) do
				if type(route.name) == "string" then
					local class, method = (route.action or ""):match("^([^@]+)@?(.*)$")
					for _, file in ipairs(class and M.class_paths(root, class) or {}) do
						if vim.fn.filereadable(file) == 1 then
							local row, candidate_row = 1, 0
							for line in (read(file) .. "\n"):gmatch("(.-)\n") do
								candidate_row = candidate_row + 1
								if line:match("function%s+" .. vim.pesc(method ~= "" and method or "__invoke") .. "%s*%(") then
									row = candidate_row
									break
								end
							end
							entry(index, "route", route.name, file, row)
						end
					end
				end
			end
		end)
		if vim.fn.filereadable(root .. "/app/Console/Commands/BladeNav.php") == 1 then
			run({ "php", "artisan", "blade-nav:components-aliases" }, function(aliases)
				for key, file in pairs(aliases) do
					if type(file) == "string" then
						entry(index, "component", key, file)
					end
				end
			end)
		end
	end
	return index
end
function M.clear()
	for _, state in pairs(caches) do
		for _, job in ipairs(state.jobs or {}) do
			pcall(job.kill, job, 15)
		end
	end
	caches = {}
end
local calls = {
	view = "view",
	make = "view",
	markdown = "view",
	include = "view",
	includeIf = "view",
	includeWhen = "view",
	includeUnless = "view",
	includeFirst = "view",
	extends = "view",
	component = "view",
	route = "route",
	to_route = "route",
	config = "config",
	get = "config",
	set = "config",
	env = "env",
	__ = "lang",
	trans = "lang",
	trans_choice = "lang",
	lang = "lang",
	choice = "lang",
	livewire = "livewire",
	inertia = "inertia",
	render = "inertia",
}
-- Context is selected at the cursor, not by the first matching call on a line.
function M.context(line, col)
	local before = line:sub(1, col)
	for pos, tag, name in before:gmatch("()<([%w]+)[-:]([%w_.:-]*)$") do
		if tag == "x" or tag == "livewire" then
			return { kind = tag == "x" and "component" or "livewire", prefix = name, start = pos + #tag + 1 }
		end
	end
	local stack, i = {}, 1
	while i <= col do
		local c = line:sub(i, i)
		if c == "(" then
			local call = line:sub(1, i - 1):match("([%w_:]+)%s*$") or ""
			stack[#stack + 1] = { call = call, arg = 1 }
			i = i + 1
		elseif c == "[" then
			stack[#stack + 1] = { array = true }
			i = i + 1
		elseif c == ")" or c == "]" then
			stack[#stack] = nil
			i = i + 1
		elseif c == "," then
			if stack[#stack] and not stack[#stack].array then
				stack[#stack].arg = stack[#stack].arg + 1
			end
			i = i + 1
		elseif c == "'" or c == '"' then
			local begin = i
			i = i + 1
			while i <= #line do
				if line:sub(i, i) == "\\" then
					i = i + 2
				elseif line:sub(i, i) == c then
					break
				else
					i = i + 1
				end
			end
			if col >= begin and col < i then
				for n = #stack, 1, -1 do
					local ctx = stack[n]
					if not ctx.array then
						local call = ctx.call:match("([^:]+)$") or ""
						local kind = calls[call]
						if ctx.call == "Route::view" then
							kind = ctx.arg == 2 and "view" or nil
						end
						if call == "includeWhen" or call == "includeUnless" then
							kind = ctx.arg == 2 and "view" or nil
						end
						if kind then
							return { kind = kind, prefix = line:sub(begin + 1, col), start = begin }
						end
						break
					end
				end
			end
			i = i + 1
		else
			i = i + 1
		end
	end
end

function M.targets(root, context)
	local items = (M.index(root)[context.kind] or {})[context.prefix] or {}
	local result = {}
	for _, item in ipairs(items) do
		if vim.fn.filereadable(item.file) == 1 then
			result[#result + 1] = item
		end
	end
	return result
end
function M.goto_file()
	local root = M.root()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local context = M.context(line, col)
	if context then
		-- Navigation uses the whole quoted value even when cursor is in its middle.
		local tail = line:sub(col + 1):match("^([^'\"%s>/]*)") or ""
		context.prefix = context.prefix .. tail
	end
	local targets = root and context and M.targets(root, context) or {}
	local function open(item)
		if not item then
			return
		end
		vim.cmd.edit(vim.fn.fnameescape(item.file))
		vim.api.nvim_win_set_cursor(0, { item.row, 0 })
	end
	if #targets == 1 then
		open(targets[1])
	elseif #targets > 1 then
		vim.ui.select(targets, {
			prompt = "Laravel target:",
			format_item = function(item)
				return item.file .. ":" .. item.row
			end,
		}, open)
	else
		local mapping = vim.fn.maparg("gf", "n", false, true)
		-- Resolve the global fallback independently of our buffer mapping.
		for _, map in ipairs(vim.api.nvim_get_keymap("n")) do
			if map.lhs == "gf" then
				mapping = map
				break
			end
		end
		if mapping.callback and mapping.desc ~= "FOX Laravel navigation" then
			mapping.callback()
		elseif mapping.rhs and mapping.rhs ~= "" and mapping.desc ~= "FOX Laravel navigation" then
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(mapping.rhs, true, false, true), "m", false)
		else
			pcall(vim.cmd, "normal! gf")
		end
	end
end
function M.annotate(buf)
	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
	if not shown then
		return
	end
	local root = M.root(buf)
	if not root then
		return
	end
	local index = M.index(root)
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, math.min(3000, vim.api.nvim_buf_line_count(buf)), false)) do
		local kind, key = line:match("(config)%s*%(%s*['\"]([^'\"]+)['\"]")
		if not kind then
			kind, key = line:match("(env)%s*%(%s*['\"]([^'\"]+)['\"]")
		end
		if not kind then
			local name
			name, key = line:match("(__)%s*%(%s*['\"]([^'\"]+)['\"]")
			if name then
				kind = "lang"
			end
		end
		local item = kind and (index[kind] or {})[key]
		if item and item[1].value then
			local value = item[1].value:gsub("[\r\n]", " "):sub(1, 160)
			vim.api.nvim_buf_set_extmark(
				buf,
				M.ns,
				row - 1,
				0,
				{ virt_text = { { " ⟶ " .. value, "Comment" } }, virt_text_pos = "eol" }
			)
		end
	end
end
function M.install_helper()
	local root = M.root()
	if not root then
		vim.notify("No Laravel project", vim.log.levels.WARN)
		return
	end
	local dest = root .. "/app/Console/Commands/BladeNav.php"
	if vim.uv.fs_stat(dest) then
		vim.notify("BladeNav.php already exists; preserving it", vim.log.levels.WARN)
		return
	end
	local template = read(vim.fn.stdpath("config") .. "/lua/fox/langs/php/BladeNav.php")
	if template == "" then
		error("Missing FOX BladeNav helper")
	end
	local mappings = vim.tbl_get(json(root .. "/composer.json"), "autoload", "psr-4") or {}
	for namespace, dir in pairs(mappings) do
		if dir == "app/" or dir == "app" then
			template = template:gsub("namespace App\\Console\\Commands;", function()
				return "namespace " .. namespace .. "Console\\Commands;"
			end)
			break
		end
	end
	vim.fn.mkdir(vim.fs.dirname(dest), "p")
	local fd, err = vim.uv.fs_open(dest, "wx", 420)
	if not fd then
		vim.notify(tostring(err), vim.log.levels.ERROR)
		return
	end
	local bytes, write_err = vim.uv.fs_write(fd, template, -1)
	vim.uv.fs_close(fd)
	if not bytes or bytes ~= #template then
		vim.uv.fs_unlink(dest)
		vim.notify(tostring(write_err or "Incomplete helper write"), vim.log.levels.ERROR)
	end
	M.clear()
end
function M.setup()
	local group = vim.api.nvim_create_augroup("fox_laravel", { clear = true })
	local function attach(buf)
		local supported = vim.tbl_contains({ "php", "blade", "vue" }, vim.bo[buf].filetype)
		local mapping = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg("gf", "n", false, true)
		end)
		if supported and M.root(buf) and (mapping.buffer ~= 1 or mapping.desc == "FOX Laravel navigation") then
			vim.keymap.set("n", "gf", M.goto_file, { buffer = buf, desc = "FOX Laravel navigation" })
		elseif mapping.buffer == 1 and mapping.desc == "FOX Laravel navigation" then
			pcall(vim.keymap.del, "n", "gf", { buffer = buf })
		end
	end
	vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
		group = group,
		callback = function(a)
			attach(a.buf)
			M.annotate(a.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function()
			M.clear()
		end,
	})
	vim.api.nvim_create_user_command("BladeNavClearCache", M.clear, { desc = "Clear Laravel project indexes" })
	vim.api.nvim_create_user_command("BladeNavToggleShowValues", function()
		shown = not shown
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				M.annotate(buf)
			end
		end
	end, { desc = "Toggle Laravel value annotations" })
	vim.api.nvim_create_user_command(
		"BladeNavInstallArtisanCommand",
		M.install_helper,
		{ desc = "Install component alias helper without overwriting existing code" }
	)
	vim.api.nvim_create_user_command("BladeNavGoToFile", M.goto_file, { desc = "Open Laravel reference at cursor" })
	attach(vim.api.nvim_get_current_buf())
end
return M
