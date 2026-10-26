-- package.json actions. Registry reads and manager writes are always explicit.
local M = {}
M.options =
	{ package_manager = "bun", hide_up_to_date = true, hide_unstable_versions = true, ttl = 3600, timeout = 15000 }
M.namespace = vim.api.nvim_create_namespace("FoxPackageInfo")
local uv = vim.uv or vim.loop
local states, cache, locks = {}, {}, {}
local groups = { "dependencies", "devDependencies" }
local lockfiles = {
	{ "yarn.lock", "yarn" },
	{ "package-lock.json", "npm" },
	{ "npm-shrinkwrap.json", "npm" },
	{ "bun.lock", "bun" },
	{ "bun.lockb", "bun" },
	{ "pnpm-lock.yaml", "pnpm" },
}
local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Packages" })
end
local function read(path)
	local file = io.open(path, "rb")
	if not file then
		return nil
	end
	local data = file:read("*a")
	file:close()
	return data
end
local function decode(text)
	local ok, value = pcall(vim.json.decode, text or "")
	return ok and type(value) == "table" and value or nil
end
local function normalized(text)
	return text and text:gsub("\r\n", "\n"):gsub("\n$", "")
end
local function content(buf)
	return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
function M.valid_name(name)
	if type(name) ~= "string" or #name > 214 then
		return false
	end
	return name:match("^[%w_][%w_.%-]*$") ~= nil or name:match("^@[%w_][%w_.%-]*/[%w_][%w_.%-]*$") ~= nil
end
-- Position-aware JSON scanner: dependency-looking text in scripts/nested objects
-- must never select a package or receive an annotation. Native JSON validates first.
function M.parse(text)
	local data = decode(text)
	if not data or not text:match("^%s*{") then
		return nil, "Invalid package.json"
	end
	local tokens, i, row = {}, 1, 0
	while i <= #text do
		local ch = text:sub(i, i)
		if ch == '"' then
			local start, line = i, row
			i = i + 1
			while i <= #text do
				local c = text:sub(i, i)
				if c == "\\" then
					i = i + 2
				elseif c == '"' then
					i = i + 1
					break
				else
					i = i + 1
				end
			end
			local value = vim.json.decode(text:sub(start, i - 1))
			tokens[#tokens + 1] = { value = value, row = line, string = true }
		elseif ch:match("[{}:%[%],]") then
			tokens[#tokens + 1] = { value = ch, row = row }
			i = i + 1
		else
			if ch == "\n" then
				row = row + 1
			end
			i = i + 1
		end
	end
	local depth, section, entries, seen = 0, nil, {}, {}
	for index, token in ipairs(tokens) do
		local value = token.value
		if not token.string then
			if value == "{" or value == "[" then
				depth = depth + 1
			end
			if value == "}" or value == "]" then
				if depth == 2 then
					section = nil
				end
				depth = depth - 1
			end
		elseif tokens[index + 1] and tokens[index + 1].value == ":" then
			if depth == 1 then
				section = vim.tbl_contains(groups, value) and value or nil
			elseif depth == 2 and section then
				local spec = type(data[section]) == "table" and data[section][value] or nil
				entries[#entries + 1] = { name = value, spec = spec, group = section, row = token.row }
				seen[value] = (seen[value] or 0) + 1
			end
		end
	end
	for _, entry in ipairs(entries) do
		entry.invalid = not M.valid_name(entry.name) or type(entry.spec) ~= "string" or entry.spec == ""
		entry.duplicate = seen[entry.name] > 1
	end
	return { data = data, entries = entries, text = text }
end
function M.detect(dir, data)
	local source = dir
	while dir do
		local metadata = dir == source and data or decode(read(dir .. "/package.json"))
		local manager = metadata and type(metadata.packageManager) == "string" and metadata.packageManager:match("^(%w+)@")
		if manager and vim.tbl_contains({ "npm", "pnpm", "yarn", "bun" }, manager) then
			return manager, dir
		end
		for _, lock in ipairs(lockfiles) do
			if uv.fs_stat(dir .. "/" .. lock[1]) then
				return lock[2], dir
			end
		end
		local parent = vim.fs.dirname(dir)
		if parent == dir then
			break
		end
		dir = parent
	end
	return M.options.package_manager, source
end
local function snapshot(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return nil, "Buffer unavailable"
	end
	local path = vim.api.nvim_buf_get_name(buf)
	if vim.fs.basename(path) ~= "package.json" then
		return nil, "Open a package.json first"
	end
	local parsed, err = M.parse(content(buf))
	if not parsed then
		return nil, err
	end
	local dir = vim.fs.dirname(path)
	local manager, root = M.detect(dir, parsed.data)
	return {
		buf = buf,
		path = path,
		dir = dir,
		manager = manager,
		root = root,
		parsed = parsed,
		tick = vim.api.nvim_buf_get_changedtick(buf),
	}
end
local function current(ctx)
	return vim.api.nvim_buf_is_valid(ctx.buf)
		and vim.api.nvim_buf_is_loaded(ctx.buf)
		and vim.api.nvim_buf_get_name(ctx.buf) == ctx.path
		and vim.api.nvim_buf_get_changedtick(ctx.buf) == ctx.tick
end
local function saved(ctx)
	return current(ctx) and not vim.bo[ctx.buf].modified and normalized(read(ctx.path)) == ctx.parsed.text
end
local function state(buf)
	states[buf] = states[buf] or { generation = 0, jobs = {}, pending = 0, visible = false }
	return states[buf]
end
local function clear(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
	end
end
local function cancel(buf)
	local s = state(buf)
	s.generation = s.generation + 1
	local jobs = s.jobs
	s.jobs, s.pending = {}, 0
	for _, job in pairs(jobs) do
		if job and job.kill then
			pcall(job.kill, job, 15)
		end
	end
end
-- On Windows prefer the Node entrypoint over .cmd wrappers; argv stays literal.
function M.executable(argv, cwd)
	local result = vim.deepcopy(argv)
	if vim.fn.has("win32") == 1 then
		local ok, wsl = pcall(require, "plugins.fox.tools.wsl")
		local distro, path
		if ok and wsl.parse_wsl_path then
			distro, path = wsl.parse_wsl_path(cwd)
		end
		if distro then
			return vim.list_extend({ "wsl.exe", "-d", distro, "--cd", path, "--", "env" }, result), nil
		end
		local exe = vim.fn.exepath(result[1])
		if exe:lower():match("%.cmd$") or exe:lower():match("%.ps1$") then
			local dir = vim.fs.dirname(exe)
			local candidates = {
				npm = { dir .. "/node_modules/npm/bin/npm-cli.js" },
				pnpm = {
					dir .. "/node_modules/pnpm/bin/pnpm.cjs",
					dir .. "/node_modules/pnpm/bin/pnpm.js",
					dir .. "/node_modules/corepack/dist/pnpm.js",
				},
				yarn = { dir .. "/node_modules/yarn/bin/yarn.js", dir .. "/node_modules/corepack/dist/yarn.js" },
			}
			for _, script in ipairs(candidates[result[1]] or {}) do
				if uv.fs_stat(script) then
					result[1] = script
					table.insert(result, 1, "node")
					return result, cwd
				end
			end
			error("Cannot resolve native " .. result[1] .. " entrypoint from " .. exe)
		end
	end
	return result, cwd
end
-- Injectable boundary for tests; production always uses argv, never a shell string.
function M.spawn(argv, cwd, timeout, callback)
	local command, directory = M.executable(argv, cwd)
	return vim.system(command, { cwd = directory, text = true, timeout = timeout }, callback)
end
local function run(ctx, argv, timeout, callback, is_current)
	local s, generation = state(ctx.buf), state(ctx.buf).generation
	s.pending = s.pending + 1
	local token = {}
	s.jobs[token] = false
	local ok, process = pcall(M.spawn, argv, ctx.dir, timeout, function(result)
		vim.schedule(function()
			if s.generation ~= generation then
				return
			end
			s.jobs[token] = nil
			s.pending = math.max(0, s.pending - 1)
			if not is_current or current(ctx) then
				callback(result)
			end
		end)
	end)
	if ok then
		s.jobs[token] = process
	else
		s.jobs[token] = nil
		s.pending = s.pending - 1
		callback({ code = -1, stderr = tostring(process) })
	end
end
local function registry(ctx, name)
	return {
		ctx.manager == "pnpm" and "pnpm" or "npm",
		"--loglevel=error",
		"view",
		name,
		"dist-tags",
		"versions",
		"--json",
	}
end
local function semver(version)
	if type(version) ~= "string" then
		return nil
	end
	local a, b, c, tail = version:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
	if not a or (tail ~= "" and not tail:match("^[%+%-][%w%.%-]+$")) then
		return nil
	end
	return { tonumber(a), tonumber(b), tonumber(c), tail = tail }
end
function M.versions(stdout)
	local ok, data = pcall(vim.json.decode, stdout or "")
	if not ok then
		return nil, "Invalid registry JSON"
	end
	if type(data) == "table" and vim.islist(data) and #data == 1 and type(data[1]) == "table" then
		data = data[1]
	end
	local latest
	if type(data) == "table" and (type(data.versions) == "table" or type(data.versions) == "string") then
		latest = type(data["dist-tags"]) == "table" and data["dist-tags"].latest or nil
		data = data.versions
	end
	if type(data) == "string" then
		data = { data }
	end
	if type(data) ~= "table" or not vim.islist(data) then
		return nil, "Invalid registry versions"
	end
	local result = {}
	for _, version in ipairs(data) do
		local parsed = semver(version)
		if parsed and (not M.options.hide_unstable_versions or not parsed.tail:match("^%-")) then
			result[#result + 1] = version
		end
	end
	table.sort(result, function(a, b)
		local x, y = semver(a), semver(b)
		for i = 1, 3 do
			if x[i] ~= y[i] then
				return x[i] > y[i]
			end
		end
		if x.tail == "" or y.tail == "" then
			return x.tail == "" and y.tail ~= ""
		end
		return x.tail > y.tail
	end)
	if #result == 0 then
		return nil, "No matching published versions"
	end
	if not semver(latest) or (M.options.hide_unstable_versions and semver(latest).tail:match("^%-")) then
		latest = result[1]
	end
	return result, nil, latest
end
local function registry_name(entry)
	if entry.invalid or entry.duplicate then
		return nil
	end
	local alias = entry.spec:match("^npm:(.+)@[^@]+$") or entry.spec:match("^npm:(.+)$")
	if alias then
		return M.valid_name(alias) and alias or nil
	end
	if
		entry.spec:match("^(workspace:)")
		or entry.spec:match("^file:")
		or entry.spec:match("^link:")
		or entry.spec:match("^https?:")
		or entry.spec:match("^git")
		or entry.spec:find("/", 1, true)
	then
		return nil
	end
	return entry.name
end
local function result_error(result)
	if result.code == 124 then
		return "Registry/manager request timed out"
	end
	return (result.stderr or ""):sub(1, 500) ~= "" and (result.stderr or ""):sub(1, 500)
		or "Package manager exited " .. tostring(result.code)
end
local function render(ctx, values)
	if not current(ctx) or not state(ctx.buf).visible then
		return
	end
	clear(ctx.buf)
	for _, entry in ipairs(ctx.parsed.entries) do
		local text, hl
		if entry.invalid or entry.duplicate then
			text, hl = entry.duplicate and "DUPLICATED" or "INVALID VERSION", "PackageInfoInErrorVersion"
		elseif values[entry.name] then
			local latest = values[entry.name]
			local declared = entry.spec:gsub("^[~^=v%s]+", "")
			local installed = decode(read(ctx.dir .. "/node_modules/" .. entry.name .. "/package.json"))
			local version = installed and installed.version or declared
			if version ~= latest or not M.options.hide_up_to_date then
				text, hl =
					tostring(version) .. " → " .. latest,
					version == latest and "PackageInfoUpToDateVersion" or "PackageInfoOutdatedVersion"
			end
		end
		if text then
			vim.api.nvim_buf_set_extmark(
				ctx.buf,
				M.namespace,
				entry.row,
				0,
				{ virt_text = { { "  | " .. text, hl } }, virt_text_pos = "eol", priority = 200 }
			)
		end
	end
end
function M.show(opts)
	opts = opts or {}
	local ctx, err = snapshot(opts.buf)
	if not ctx then
		notify(err, vim.log.levels.WARN)
		return
	end
	cancel(ctx.buf)
	local s = state(ctx.buf)
	s.visible = true
	local values, queue = {}, {}
	for _, entry in ipairs(ctx.parsed.entries) do
		local name = registry_name(entry)
		if name then
			local key = ctx.dir .. "\0" .. name
			local hit = cache[key]
			if hit and not opts.force and os.time() - hit.time < M.options.ttl then
				values[entry.name] = hit.latest or hit.versions[1]
			else
				queue[#queue + 1] = { entry = entry, name = name, key = key }
			end
		end
	end
	render(ctx, values)
	local index, remaining, failed, generation = 1, #queue, {}, s.generation
	local function next_job()
		if s.generation ~= generation or not current(ctx) then
			return
		end
		local task = queue[index]
		if not task then
			return
		end
		index = index + 1
		run(ctx, registry(ctx, task.name), M.options.timeout, function(result)
			local versions, problem, latest
			if result.code == 0 then
				versions, problem, latest = M.versions(result.stdout)
			else
				problem = result_error(result)
			end
			if versions then
				cache[task.key] = { versions = versions, latest = latest, time = os.time() }
				values[task.entry.name] = latest
			else
				failed[#failed + 1] = task.name .. ": " .. tostring(problem)
			end
			render(ctx, values)
			remaining = remaining - 1
			if remaining == 0 and #failed > 0 then
				notify(table.concat(failed, "\n"), vim.log.levels.WARN)
			end
			next_job()
		end, true)
	end
	for _ = 1, math.min(4, #queue) do
		next_job()
	end
end
function M.hide(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	cancel(buf)
	state(buf).visible = false
	clear(buf)
end
function M.toggle(opts)
	if state(vim.api.nvim_get_current_buf()).visible then
		M.hide()
	else
		M.show(opts)
	end
end
function M.get_status()
	local s = state(vim.api.nvim_get_current_buf())
	if s.mutating then
		return "Changing packages"
	end
	return s.pending > 0 and "Fetching package information" or ""
end
local function selected(ctx)
	local row = vim.api.nvim_win_get_cursor(0)[1] - 1
	local found
	for _, entry in ipairs(ctx.parsed.entries) do
		if entry.row == row then
			if found then
				return nil, "Put one dependency on each line before selecting it"
			end
			found = entry
		end
	end
	if not found or found.invalid or found.duplicate then
		return nil, "Select a valid, unique dependency line"
	end
	return found
end
function M.command(manager, action, name, group, version)
	assert(M.valid_name(name), "Invalid package name")
	assert(vim.tbl_contains({ "npm", "pnpm", "yarn", "bun" }, manager), "Unsupported package manager")
	if action == "delete" then
		return { manager, manager == "npm" and "uninstall" or "remove", name }
	end
	assert(version == "latest" or semver(version), "Invalid package version")
	local flags = {
		npm = { devDependencies = "--save-dev" },
		pnpm = { devDependencies = "-D" },
		yarn = { devDependencies = "-D" },
		bun = { devDependencies = "-d" },
	}
	local argv = { manager, manager == "npm" and "install" or "add", name .. "@" .. version }
	if flags[manager][group] then
		argv[#argv + 1] = flags[manager][group]
	end
	return argv
end
local function editable(ctx)
	if not saved(ctx) then
		notify("Save package.json and resolve external changes before changing packages", vim.log.levels.WARN)
		return false
	end
	if locks[ctx.root] then
		notify("A package operation is already running in this workspace", vim.log.levels.WARN)
		return false
	end
	return true
end
local function mutate(ctx, action, entry, version)
	if not editable(ctx) then
		return
	end
	local ok, argv = pcall(M.command, ctx.manager, action, entry.name, entry.group, version)
	if not ok then
		notify(tostring(argv), vim.log.levels.ERROR)
		return
	end
	locks[ctx.root] = true
	local mutation_state = state(ctx.buf)
	mutation_state.mutating = true
	notify(ctx.manager .. ": " .. action .. " " .. entry.name)
	-- Mutations are independent of read cancellation. Never abandon their cleanup.
	local started, process = pcall(M.spawn, argv, ctx.dir, 120000, function(result)
		vim.schedule(function()
			locks[ctx.root] = nil
			mutation_state.mutating = false
			cache = {}
			if result.code ~= 0 then
				notify(result_error(result), vim.log.levels.ERROR)
			end
			local disk = read(ctx.path)
			if current(ctx) and not vim.bo[ctx.buf].modified and disk and decode(disk) then
				local lines = vim.split(normalized(disk), "\n", { plain = true })
				vim.api.nvim_buf_set_lines(ctx.buf, 0, -1, false, lines)
				vim.bo[ctx.buf].modified = false
				if state(ctx.buf).visible then
					M.show({ buf = ctx.buf, force = true })
				end
			elseif vim.api.nvim_buf_is_valid(ctx.buf) then
				notify(
					"Package command finished; buffer edits were preserved. Review package.json on disk before reloading.",
					vim.log.levels.WARN
				)
			end
		end)
	end)
	if not started then
		mutation_state.mutating = false
		locks[ctx.root] = nil
		notify(tostring(process), vim.log.levels.ERROR)
	end
end
local function action_context(needs_selection)
	local ctx, err = snapshot()
	if not ctx then
		notify(err, vim.log.levels.WARN)
		return
	end
	if not editable(ctx) then
		return
	end
	local entry
	if needs_selection then
		entry, err = selected(ctx)
		if not entry then
			notify(err, vim.log.levels.WARN)
			return
		end
	end
	return ctx, entry
end
local function confirm(action)
	local ctx, entry = action_context(true)
	if not ctx then
		return
	end
	if
		action == "update"
		and (registry_name(entry) ~= entry.name or entry.spec:match("^catalog:") or entry.spec:match("^npm:"))
	then
		notify("Update the workspace/catalog/alias source instead of replacing its reference", vim.log.levels.WARN)
		return
	end
	vim.ui.select(
		{ "Confirm", "Cancel" },
		{ prompt = action .. " " .. entry.name .. " with " .. ctx.manager .. "?" },
		function(choice)
			if choice == "Confirm" then
				mutate(ctx, action, entry, "latest")
			end
		end
	)
end
function M.update()
	confirm("update")
end
function M.delete()
	confirm("delete")
end
function M.install()
	local ctx = action_context(false)
	if not ctx then
		return
	end
	vim.ui.select({ "dependencies", "devDependencies" }, { prompt = "Dependency type" }, function(group)
		if not group then
			return
		end
		vim.ui.input({ prompt = "Package name: " }, function(name)
			if name == nil then
				return
			end
			if not M.valid_name(name) then
				notify("Enter one registry package name (without a version)", vim.log.levels.WARN)
				return
			end
			for _, entry in ipairs(ctx.parsed.entries) do
				if entry.name == name then
					notify("Package already exists; use Update or Change Version", vim.log.levels.WARN)
					return
				end
			end
			mutate(ctx, "install", { name = name, group = group }, "latest")
		end)
	end)
end
function M.change_version()
	local ctx, entry = action_context(true)
	if not ctx then
		return
	end
	local name = registry_name(entry)
	if not name or name ~= entry.name or entry.spec:match("^catalog:") or entry.spec:match("^npm:") then
		notify("Version changes require a registry dependency, without an alias", vim.log.levels.WARN)
		return
	end
	local function choose(versions)
		if not saved(ctx) then
			return
		end
		vim.ui.select(versions, { prompt = "Version for " .. name }, function(version)
			if version then
				mutate(ctx, "change_version", entry, version)
			end
		end)
	end
	local key = ctx.dir .. "\0" .. name
	if cache[key] and os.time() - cache[key].time < M.options.ttl then
		choose(cache[key].versions)
		return
	end
	run(ctx, registry(ctx, name), M.options.timeout, function(result)
		if result.code ~= 0 then
			notify(result_error(result), vim.log.levels.ERROR)
			return
		end
		local versions, err = M.versions(result.stdout)
		if not versions then
			notify(err, vim.log.levels.ERROR)
			return
		end
		cache[key] = { time = os.time(), versions = versions }
		choose(versions)
	end, true)
end
function M.setup(opts)
	M.options = vim.tbl_extend("force", M.options, opts or {})
	local commands = {
		PackageInfoShow = M.show,
		PackageInfoShowForce = function()
			M.show({ force = true })
		end,
		PackageInfoHide = M.hide,
		PackageInfoToggle = M.toggle,
		PackageInfoUpdate = M.update,
		PackageInfoDelete = M.delete,
		PackageInfoInstall = M.install,
		PackageInfoChangeVersion = M.change_version,
	}
	for name, callback in pairs(commands) do
		vim.api.nvim_create_user_command(name, function()
			callback()
		end, { desc = name:gsub("PackageInfo", "Packages: ") })
	end
	local group = vim.api.nvim_create_augroup("FoxPackageInfo", { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
		group = group,
		pattern = "package.json",
		callback = function(event)
			cancel(event.buf)
			clear(event.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			if states[event.buf] then
				cancel(event.buf)
				states[event.buf] = nil
			end
		end,
	})
	local function highlights()
		vim.api.nvim_set_hl(0, "PackageInfoOutdatedVersion", { link = "DiagnosticWarn", default = true })
		vim.api.nvim_set_hl(0, "PackageInfoUpToDateVersion", { link = "Comment", default = true })
		vim.api.nvim_set_hl(0, "PackageInfoInErrorVersion", { link = "DiagnosticError", default = true })
	end
	highlights()
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
end
return M
