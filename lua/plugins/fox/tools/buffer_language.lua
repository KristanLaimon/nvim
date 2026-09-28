-- ============================================================================
-- FOX PLUGIN: Buffer Language & Filetype Association Manager
-- ============================================================================
-- WHAT IT DOES
--   1. Allows setting a persistent language/filetype override for any buffer,
--      stored in `.foxnvim/filetypes.json` at the project root.
--   2. Enables treating any file (e.g., `main.txt` as JavaScript, `services.dev.yml`
--      as Docker Compose, `docker.txt` as Dockerfile) with full IntelliSense,
--      LSP attachment, Treesitter highlighting, and formatter support.
--   3. Provides a Telescope picker searchable by language name or file extension.
--   4. Automatically restores language overrides across editor restarts.
--
-- EX COMMANDS & PALETTE ACTIONS
--   :SetBufferLanguage   / :FoxSetBufferLanguage   (Telescope language picker)
--   :ResetBufferLanguage / :FoxResetBufferLanguage (Revert to default filetype)
--   :ListBufferLanguages / :FoxListBufferLanguages (View project overrides)
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local store = lazy_req("fox.core.store")
local project = lazy_req("fox.core.project")
local path = lazy_req("fox.core.path")
local lazyspec = lazy_req("fox.core.lazyspec")

local M = {}

M.settings = {
	config_file = "filetypes.json",
	title = "Buffer Language Manager",
}

--- Predefined catalogue of supported languages, filetypes, extensions and Treesitter parsers.
M.languages = {
	{
		name = "JavaScript",
		filetype = "javascript",
		ts = "javascript",
		icon = "🟨",
		extensions = { ".js", ".mjs", ".cjs" },
	},
	{
		name = "TypeScript",
		filetype = "typescript",
		ts = "typescript",
		icon = "🔷",
		extensions = { ".ts", ".mts", ".cts" },
	},
	{
		name = "React / TSX",
		filetype = "typescriptreact",
		ts = "tsx",
		icon = "⚛️",
		extensions = { ".tsx" },
	},
	{
		name = "React / JSX",
		filetype = "javascriptreact",
		ts = "javascript",
		icon = "⚛️",
		extensions = { ".jsx" },
	},
	{
		name = "Python",
		filetype = "python",
		ts = "python",
		icon = "🐍",
		extensions = { ".py", ".pyi", ".pyw" },
	},
	{
		name = "Docker (Dockerfile)",
		filetype = "dockerfile",
		ts = "dockerfile",
		icon = "🐳",
		extensions = { "Dockerfile", "Containerfile", ".dockerfile" },
	},
	{
		name = "Docker Compose",
		filetype = "yaml.docker-compose",
		ts = "yaml",
		icon = "🐙",
		extensions = { "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml", ".yml", ".yaml" },
	},
	{
		name = "HTML",
		filetype = "html",
		ts = "html",
		icon = "🌐",
		extensions = { ".html", ".htm" },
	},
	{
		name = "CSS",
		filetype = "css",
		ts = "css",
		icon = "🎨",
		extensions = { ".css" },
	},
	{
		name = "SCSS / SASS",
		filetype = "scss",
		ts = "scss",
		icon = "💄",
		extensions = { ".scss", ".sass" },
	},
	{
		name = "JSON",
		filetype = "json",
		ts = "json",
		icon = "📦",
		extensions = { ".json" },
	},
	{
		name = "JSON with Comments (JSONC)",
		filetype = "jsonc",
		ts = "jsonc",
		icon = "📦",
		extensions = { ".jsonc" },
	},
	{
		name = "YAML",
		filetype = "yaml",
		ts = "yaml",
		icon = "📄",
		extensions = { ".yaml", ".yml" },
	},
	{
		name = "TOML",
		filetype = "toml",
		ts = "toml",
		icon = "⚙️",
		extensions = { ".toml" },
	},
	{
		name = "XML",
		filetype = "xml",
		ts = "xml",
		icon = "📑",
		extensions = { ".xml", ".xsd", ".props", ".targets", ".csproj" },
	},
	{
		name = "Go",
		filetype = "go",
		ts = "go",
		icon = "🟦",
		extensions = { ".go" },
	},
	{
		name = "Rust",
		filetype = "rust",
		ts = "rust",
		icon = "🦀",
		extensions = { ".rs" },
	},
	{
		name = "C# / .NET",
		filetype = "cs",
		ts = "c_sharp",
		icon = "🎯",
		extensions = { ".cs" },
	},
	{
		name = "C",
		filetype = "c",
		ts = "c",
		icon = "⚡",
		extensions = { ".c", ".h" },
	},
	{
		name = "C++",
		filetype = "cpp",
		ts = "cpp",
		icon = "⚡",
		extensions = { ".cpp", ".cc", ".cxx", ".hpp", ".hxx", ".h" },
	},
	{
		name = "PHP",
		filetype = "php",
		ts = "php",
		icon = "🐘",
		extensions = { ".php" },
	},
	{
		name = "Blade (Laravel)",
		filetype = "blade",
		ts = "php",
		icon = "🗡️",
		extensions = { ".blade.php" },
	},
	{
		name = "Lua",
		filetype = "lua",
		ts = "lua",
		icon = "🌙",
		extensions = { ".lua", ".foxnvim" },
	},
	{
		name = "Shell / Bash",
		filetype = "sh",
		ts = "bash",
		icon = "🐚",
		extensions = { ".sh", ".bash", ".zsh" },
	},
	{
		name = "PowerShell",
		filetype = "ps1",
		ts = "powershell",
		icon = "💻",
		extensions = { ".ps1", ".psm1", ".psd1" },
	},
	{
		name = "Markdown",
		filetype = "markdown",
		ts = "markdown",
		icon = "📝",
		extensions = { ".md", ".markdown" },
	},
	{
		name = "SQL",
		filetype = "sql",
		ts = "sql",
		icon = "🗄️",
		extensions = { ".sql" },
	},
	{
		name = "Ruby",
		filetype = "ruby",
		ts = "ruby",
		icon = "💎",
		extensions = { ".rb", "Gemfile", "Rakefile" },
	},
	{
		name = "Zig",
		filetype = "zig",
		ts = "zig",
		icon = "⚡",
		extensions = { ".zig" },
	},
	{
		name = "Astro",
		filetype = "astro",
		ts = "astro",
		icon = "🪐",
		extensions = { ".astro" },
	},
	{
		name = "Svelte",
		filetype = "svelte",
		ts = "svelte",
		icon = "🔥",
		extensions = { ".svelte" },
	},
	{
		name = "Vue",
		filetype = "vue",
		ts = "vue",
		icon = "💚",
		extensions = { ".vue" },
	},
	{
		name = "Haskell",
		filetype = "haskell",
		ts = "haskell",
		icon = "🔮",
		extensions = { ".hs", ".lhs" },
	},
	{
		name = "Protocol Buffers",
		filetype = "proto",
		ts = "proto",
		icon = "📜",
		extensions = { ".proto" },
	},
	{
		name = "Teal",
		filetype = "teal",
		ts = "teal",
		icon = "🩵",
		extensions = { ".tl" },
	},
	{
		name = "Git Commit / Diff",
		filetype = "gitcommit",
		ts = "gitcommit",
		icon = "🐙",
		extensions = { ".diff", ".patch" },
	},
	{
		name = "Plain Text",
		filetype = "text",
		ts = nil,
		icon = "📄",
		extensions = { ".txt" },
	},
}

--- In-memory cache for per-project filetype overrides: `_cache[root] = { [rel_path] = filetype }`.
local _cache = {}

--- Clears cache for a project or all projects.
--- @param root string|nil
function M.clear_cache(root)
	if root then
		_cache[path.normalize(root)] = nil
	else
		_cache = {}
	end
end

--- Resolves the filetypes.json path for a root directory.
--- @param root string|nil
--- @return string filepath
function M.get_config_path(root)
	root = path.normalize(root or project.root())
	return (project.config_path(M.settings.config_file, root))
end

--- Loads all associations for a project.
--- @param root string|nil
--- @return table<string, string> associations Keyed by relative (or absolute) file path.
function M.load_associations(root)
	root = path.normalize(root or project.root())
	if _cache[root] then
		return _cache[root]
	end

	local filepath = M.get_config_path(root)
	local data = store.load(filepath, {})
	local associations = (type(data) == "table" and type(data.associations) == "table") and data.associations or {}

	_cache[root] = associations
	return associations
end

--- Saves an association into `.foxnvim/filetypes.json`.
--- @param root string
--- @param rel_path string
--- @param filetype string|nil If nil, removes association.
--- @return boolean ok
--- @return string|nil err
function M.save_association(root, rel_path, filetype)
	root = path.normalize(root or project.root())
	local filepath = M.get_config_path(root)
	local data = store.load(filepath, { version = 1, associations = {} })

	data.version = data.version or 1
	data.associations = type(data.associations) == "table" and data.associations or {}

	if filetype and filetype ~= "" then
		data.associations[rel_path] = filetype
	else
		data.associations[rel_path] = nil
	end

	local ok, err = store.save(filepath, data)
	if ok then
		_cache[root] = data.associations
	end
	return ok, err
end

--- Computes the storage key for a buffer path relative to the project root.
--- @param buf_name string
--- @param root string
--- @return string key
local function get_buffer_key(buf_name, root)
	local norm_buf = path.normalize(vim.fs.normalize(buf_name))
	local norm_root = path.normalize(vim.fs.normalize(root))
	local rel = path.relative_to(norm_buf, norm_root)
	return (rel and rel ~= "") and rel or norm_buf
end

--- Finds if the current buffer has a registered filetype override.
--- @param bufnr integer|nil
--- @return string|nil filetype
--- @return string|nil root
--- @return string|nil rel_path
function M.get_buffer_override(bufnr)
	bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return nil
	end

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if not buf_name or buf_name == "" then
		return nil
	end

	local root = path.normalize(project.root(bufnr))
	local key = get_buffer_key(buf_name, root)
	local associations = M.load_associations(root)

	local ft = associations[key]
	if ft then
		return ft, root, key
	end

	-- Also check lowercase/normalized fallback on Windows
	if path.is_windows then
		local key_lower = key:lower()
		for k, v in pairs(associations) do
			if k:lower() == key_lower then
				return v, root, k
			end
		end
	end

	return nil, root, key
end

--- Applies a filetype override to a buffer and re-triggers LSP & Treesitter.
--- @param bufnr integer
--- @param target_ft string
--- @param ts_lang string|nil Optional Treesitter parser name.
function M.apply_filetype(bufnr, target_ft, ts_lang)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- 1. Apply buffer filetype
	vim.bo[bufnr].filetype = target_ft

	-- 2. Attach Treesitter parser if specified or derivable
	local parser_lang = ts_lang
	if not parser_lang then
		for _, entry in ipairs(M.languages) do
			if entry.filetype == target_ft then
				parser_lang = entry.ts
				break
			end
		end
	end

	if parser_lang and parser_lang ~= "" then
		pcall(vim.treesitter.start, bufnr, parser_lang)
	end

	-- 3. Trigger FileType autocmd so all configured LSPs & formatters attach
	pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = bufnr })
end

--- Checks and applies any configured filetype override to a buffer.
--- @param bufnr integer|nil
--- @return boolean applied
function M.apply_override(bufnr)
	bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
	local ft = M.get_buffer_override(bufnr)
	if ft and ft ~= "" and vim.bo[bufnr].filetype ~= ft then
		M.apply_filetype(bufnr, ft)
		return true
	end
	return false
end

--- Interactively sets the language / filetype for the current buffer.
--- Saves to `.foxnvim/filetypes.json` and updates the active buffer immediately.
function M.open_picker()
	local bufnr = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if not buf_name or buf_name == "" then
		vim.notify("Cannot set language for an unnamed buffer. Save the file first.", vim.log.levels.WARN, {
			title = M.settings.title,
		})
		return
	end

	local root = path.normalize(project.root(bufnr))
	local rel_path = get_buffer_key(buf_name, root)
	local current_override = M.get_buffer_override(bufnr)
	local current_ft = vim.bo[bufnr].filetype

	-- Build picker options list
	local items = {}

	-- Option 1: Reset / Revert to auto-detected default
	table.insert(items, {
		type = "reset",
		display = string.format("🔄 Reset to Default / Auto-Detected (Current: %s)", current_ft),
		ordinal = "reset clear default remove auto",
		desc = "Remove persistent override and revert to Neovim's auto-detected filetype",
	})

	-- Option 2: Predefined languages catalog
	for _, lang in ipairs(M.languages) do
		local exts = table.concat(lang.extensions, ", ")
		local is_current = (lang.filetype == current_override) or (lang.filetype == current_ft)
		local mark = is_current and " (active)" or ""

		local display_str = string.format("%s %-24s [%s] (%s)%s", lang.icon, lang.name, lang.filetype, exts, mark)

		local search_terms = string.format(
			"%s %s %s %s",
			lang.name:lower(),
			lang.filetype:lower(),
			table.concat(lang.extensions, " "):lower(),
			(lang.ts or ""):lower()
		)

		table.insert(items, {
			type = "language",
			item = lang,
			display = display_str,
			ordinal = search_terms,
		})
	end

	-- Option 3: Custom filetype
	table.insert(items, {
		type = "custom",
		display = "✍️ Custom Language / Filetype Name...",
		ordinal = "custom other manual",
		desc = "Type a custom Neovim filetype string manually",
	})

	local function on_select(selection)
		if not selection then
			return
		end

		if selection.type == "reset" then
			M.save_association(root, rel_path, nil)
			-- Re-detect filetype
			vim.bo[bufnr].filetype = ""
			local detected = vim.filetype.match({ buf = bufnr, filename = buf_name })
			if detected and detected ~= "" then
				M.apply_filetype(bufnr, detected)
			else
				pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = bufnr })
			end
			vim.notify(
				string.format("✓ Removed language override for '%s'. Reverted to '%s'.", rel_path, vim.bo[bufnr].filetype),
				vim.log.levels.INFO,
				{ title = M.settings.title }
			)
			return
		end

		if selection.type == "custom" then
			vim.ui.input({
				prompt = "Enter Neovim filetype name (e.g. 'yaml.docker-compose', 'javascript', 'python'): ",
			}, function(input)
				if not input or input == "" then
					return
				end
				local target_ft = vim.trim(input)
				M.save_association(root, rel_path, target_ft)
				M.apply_filetype(bufnr, target_ft)
				vim.notify(
					string.format(
						"✓ Buffer '%s' persistently treated as '%s'.\nSaved in .foxnvim/filetypes.json.",
						rel_path,
						target_ft
					),
					vim.log.levels.INFO,
					{ title = M.settings.title }
				)
			end)
			return
		end

		if selection.type == "language" and selection.item then
			local lang = selection.item
			M.save_association(root, rel_path, lang.filetype)
			M.apply_filetype(bufnr, lang.filetype, lang.ts)
			vim.notify(
				string.format(
					"✓ %s %s activated for '%s'.\nPersistent setting saved to .foxnvim/filetypes.json.",
					lang.icon,
					lang.name,
					rel_path
				),
				vim.log.levels.INFO,
				{ title = M.settings.title }
			)
		end
	end

	-- Telescope picker with vim.ui.select fallback
	local has_telescope, pickers = pcall(require, "telescope.pickers")
	if not has_telescope then
		local labels, by_label = {}, {}
		for _, item in ipairs(items) do
			table.insert(labels, item.display)
			by_label[item.display] = item
		end
		vim.ui.select(labels, { prompt = "Select Language / Filetype for Current Buffer: " }, function(choice)
			if choice then
				on_select(by_label[choice])
			end
		end)
		return
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	pickers
		.new({}, {
			prompt_title = " 🌐 Select Buffer Language / Filetype (Search name or .ext) ",
			finder = finders.new_table({
				results = items,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.ordinal,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					local selected = action_state.get_selected_entry()
					actions.close(prompt_bufnr)
					if selected and selected.value then
						on_select(selected.value)
					end
				end)
				return true
			end,
		})
		:find()
end

--- Resets the current buffer's language override.
function M.reset_current_buffer()
	local bufnr = vim.api.nvim_get_current_buf()
	local buf_name = vim.api.nvim_buf_get_name(bufnr)
	if not buf_name or buf_name == "" then
		return
	end

	local root = path.normalize(project.root(bufnr))
	local rel_path = get_buffer_key(buf_name, root)

	M.save_association(root, rel_path, nil)
	vim.bo[bufnr].filetype = ""
	local detected = vim.filetype.match({ buf = bufnr, filename = buf_name })
	if detected and detected ~= "" then
		M.apply_filetype(bufnr, detected)
	else
		pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = bufnr })
	end

	vim.notify(
		string.format("✓ Reset language override for '%s'. Now using: '%s'.", rel_path, vim.bo[bufnr].filetype),
		vim.log.levels.INFO,
		{ title = M.settings.title }
	)
end

--- Lists all current project filetype associations in a floating window.
function M.list_associations()
	local root = path.normalize(project.root())
	local associations = M.load_associations(root)
	local lines = {
		" 🌐 FOX Project Filetype Associations (.foxnvim/filetypes.json)",
		" " .. string.rep("─", 68),
		string.format(" Project Root: %s", root),
		"",
	}

	local count = 0
	for file_key, ft in pairs(associations) do
		count = count + 1
		local icon = "📄"
		for _, l in ipairs(M.languages) do
			if l.filetype == ft then
				icon = l.icon
				break
			end
		end
		table.insert(lines, string.format("  %s %-35s -> %s", icon, file_key, ft))
	end

	if count == 0 then
		table.insert(lines, "  (No custom filetype associations saved for this project)")
		table.insert(lines, "")
		table.insert(lines, "  Use :SetBufferLanguage to treat any file as another language.")
	end

	table.insert(lines, "")
	table.insert(lines, " [q/Esc] Close   |   Use :SetBufferLanguage to add or change")

	local ui = require("fox.core.ui")
	local buf, win = ui.float({
		width = math.min(74, vim.o.columns - 4),
		height = math.min(#lines + 2, vim.o.lines - 4),
		title = " 🌐 Filetype Associations ",
		focusable = true,
		modifiable = false,
	})

	ui.close_on_keys(buf, win)
	pcall(function()
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
	end)
end

--- Initializes autocmds and user commands.
function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	-- Register pattern with Neovim's native filetype detector so overrides are
	-- applied as early as possible during file load.
	pcall(vim.filetype.add, {
		pattern = {
			[".*"] = {
				function(filepath, bufnr)
					if not filepath or filepath == "" then
						return nil
					end
					local root = path.normalize(project.root(bufnr))
					local key = get_buffer_key(filepath, root)
					local associations = M.load_associations(root)
					local match_ft = associations[key]
					if match_ft then
						return match_ft
					end
					if path.is_windows then
						local key_lower = key:lower()
						for k, v in pairs(associations) do
							if k:lower() == key_lower then
								return v
							end
						end
					end
					return nil
				end,
				{ priority = 1000000 },
			},
		},
	})

	-- Buffer event listener for newly read, opened, or entered files
	local group = vim.api.nvim_create_augroup("FoxBufferLanguage", { clear = true })
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter" }, {
		group = group,
		callback = function(args)
			M.apply_override(args.buf)
		end,
	})

	-- User commands
	local user_commands = {
		SetBufferLanguage = {
			fn = M.open_picker,
			desc = "Set persistent language/filetype for current buffer (Telescope)",
		},
		FoxSetBufferLanguage = {
			fn = M.open_picker,
			desc = "Set persistent language/filetype for current buffer (Telescope)",
		},
		ResetBufferLanguage = {
			fn = M.reset_current_buffer,
			desc = "Reset language override for current buffer to default",
		},
		FoxResetBufferLanguage = {
			fn = M.reset_current_buffer,
			desc = "Reset language override for current buffer to default",
		},
		ListBufferLanguages = {
			fn = M.list_associations,
			desc = "List all persistent language associations in .foxnvim/filetypes.json",
		},
		FoxListBufferLanguages = {
			fn = M.list_associations,
			desc = "List all persistent language associations in .foxnvim/filetypes.json",
		},
	}

	for cmd_name, spec in pairs(user_commands) do
		if vim.fn.exists(":" .. cmd_name) == 0 then
			vim.api.nvim_create_user_command(cmd_name, spec.fn, { desc = spec.desc })
		end
	end
end

return setmetatable({
	name = "fox_buffer_language",
	dir = lazyspec.for_module(),
	event = { "BufReadPost", "BufNewFile" },
	cmd = {
		"SetBufferLanguage",
		"FoxSetBufferLanguage",
		"ResetBufferLanguage",
		"FoxResetBufferLanguage",
		"ListBufferLanguages",
		"FoxListBufferLanguages",
	},
	config = M.setup,
}, { __index = M })
