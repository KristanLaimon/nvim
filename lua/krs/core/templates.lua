-- ============================================================================
-- KRS CORE: Generic File Creation Template System
-- ============================================================================
-- WHAT IT DOES
--   Discovers and presents file creation templates per programming language.
--   Templates live as Markdown files with YAML frontmatter in:
--     `templates/<filetype>/*.md`
--   inside the Neovim config directory (`stdpath("config")`), or locally in
--   workspace roots (`.krsnvim/templates/<filetype>/*.md`).
--
-- TEMPLATE FORMAT
--   ---
--   name: Class
--   description: Standard class template
--   index: 0
--   ---
--   namespace <%csharp_namespace%>;
--
--   internal class <%filename%>
--   {
--      $0
--   }
-- ============================================================================

local M = {}

--- Registry of custom variable providers per filetype.
---@type table<string, fun(filename: string, ctx: table): table>
M.variable_providers = {}

--- Generic identifier sanitizer for general programming languages.
--- @param name string
--- @return string
function M.identifier(name)
	name = name:gsub("[^%w_]", "_")
	if name:match("^%d") then
		name = "_" .. name
	end
	return name
end

--- Compatibility helpers delegate C# rules to the owning language module.
function M.csharp_identifier(name)
	return require("krs.langs.csharp").identifier(name)
end

function M.csharp_namespace(filename)
	return require("krs.langs.csharp").file_namespace(filename)
end

--- Get candidate base template directories in lookup priority.
--- @return string[]
function M.get_template_dirs()
	local dirs = {}
	local seen = {}

	local function add_dir(dir)
		if dir and dir ~= "" then
			local norm = vim.fs.normalize(dir)
			if not seen[norm] and vim.fn.isdirectory(norm) == 1 then
				seen[norm] = true
				dirs[#dirs + 1] = norm
			end
		end
	end

	-- 1. Workspace local .krsnvim/templates/
	local cwd = vim.fn.getcwd()
	add_dir(vim.fs.joinpath(cwd, ".krsnvim", "templates"))

	-- 2. Workspace local templates/
	add_dir(vim.fs.joinpath(cwd, "templates"))

	-- 3. Neovim configuration directory templates/
	local config_templates = vim.fs.joinpath(vim.fn.stdpath("config"), "templates")
	add_dir(config_templates)

	return dirs
end

--- Parse Markdown YAML frontmatter and template body.
--- @param content string
--- @param fallback_name string
--- @return table meta, string body
function M.parse_frontmatter(content, fallback_name)
	local meta = {
		name = fallback_name,
		description = nil,
		index = 9999,
	}

	-- Normalize CRLF to LF
	content = content:gsub("\r\n", "\n")

	-- Check for YAML frontmatter between `---` markers
	local fm_text, body = content:match("^%-%-%-[ \t]*\n(.-)\n%-%-%-[ \t]*\n?(.*)$")
	if not fm_text then
		return meta, content
	end

	for line in fm_text:gmatch("([^\n]+)") do
		local key, val = line:match("^%s*([%w_]+)%s*:%s*(.-)%s*$")
		if key and val then
			-- Strip optional enclosing quotes
			val = val:gsub("^[\"'](.-)[\"']$", "%1")
			if key == "name" then
				meta.name = val
			elseif key == "description" or key == "desc" then
				meta.description = val
			elseif key == "index" or key == "order" then
				meta.index = tonumber(val) or meta.index
			elseif key == "filetype" or key == "ft" then
				meta.filetype = val
			end
		end
	end

	return meta, body or ""
end

--- Get all available templates for a specific Neovim filetype.
--- Returns an empty list if no subfolder or 0 .md files exist.
--- @param filetype string
--- @return table[]
function M.get_templates(filetype)
	if not filetype or filetype == "" then
		return {}
	end

	local templates = {}
	local seen_names = {}
	local base_dirs = M.get_template_dirs()

	for _, base_dir in ipairs(base_dirs) do
		local lang_dir = vim.fs.joinpath(base_dir, filetype)
		if vim.fn.isdirectory(lang_dir) == 1 then
			local md_files = vim.fn.glob(lang_dir .. "/*.md", false, true)
			for _, file_path in ipairs(md_files) do
				local raw_filename = vim.fn.fnamemodify(file_path, ":t:r")
				local default_name = raw_filename:gsub("^%l", string.upper):gsub("_", " ")

				local ok, lines = pcall(vim.fn.readfile, file_path)
				if ok then
					local raw_content = table.concat(lines, "\n")
					local meta, body = M.parse_frontmatter(raw_content, default_name)
					local tmpl_name = meta.name or default_name

					if not seen_names[tmpl_name:lower()] then
						seen_names[tmpl_name:lower()] = true
						templates[#templates + 1] = {
							name = tmpl_name,
							description = meta.description,
							index = meta.index or 9999,
							body = body,
							path = file_path,
							filetype = filetype,
						}
					end
				end
			end
		end
	end

	-- Sort primarily by index, secondarily by name
	table.sort(templates, function(a, b)
		if a.index ~= b.index then
			return a.index < b.index
		end
		return a.name:lower() < b.name:lower()
	end)

	return templates
end

--- Register a custom variable provider callback for a filetype.
--- @param filetype string
--- @param provider fun(filename: string, ctx: table): table
function M.register_variables(filetype, provider)
	M.variable_providers[filetype] = provider
end

--- Collect all template variable substitutions for a given file and filetype.
--- @param filename string
--- @param filetype string
--- @param ctx? table
--- @return table<string, string>
function M.resolve_variables(filename, filetype, ctx)
	ctx = ctx or {}
	local raw_name = vim.fn.fnamemodify(filename, ":t:r")
	local ext = vim.fn.fnamemodify(filename, ":e")
	local fullname = vim.fn.fnamemodify(filename, ":t")

	local user = vim.env.USER or vim.env.USERNAME or "user"
	local ok_git, git_user = pcall(vim.fn.system, "git config user.name")
	if ok_git and git_user and git_user ~= "" then
		user = vim.trim(git_user)
	end

	local vars = {
		filename = raw_name,
		name = raw_name,
		file_name = raw_name,
		filename_ext = fullname,
		ext = ext,
		classname = M.identifier(raw_name),
		filetype = filetype,
		filepath = filename,
		date = os.date("%Y-%m-%d"),
		year = os.date("%Y"),
		month = os.date("%m"),
		day = os.date("%d"),
		time = os.date("%H:%M:%S"),
		author = user,
		user = user,
	}

	-- C# special cases
	if filetype == "cs" then
		local cs_ns = M.csharp_namespace(filename)
		local cs_id = M.csharp_identifier(raw_name)
		vars.csharp_namespace = cs_ns
		vars.csharp_identifier = cs_id
		vars.namespace = cs_ns
		vars.classname = cs_id
		vars.filename = cs_id
	end

	-- Query per-language module in lua/krs/langs/<lang>/init.lua if available
	local ok_lang, lang_mod = pcall(require, "krs.langs." .. filetype)
	if ok_lang and type(lang_mod) == "table" and type(lang_mod.template_variables) == "function" then
		local lang_vars = lang_mod.template_variables(filename, ctx)
		if type(lang_vars) == "table" then
			for k, v in pairs(lang_vars) do
				vars[k] = v
			end
		end
	end

	-- Query dynamically registered variable providers
	if M.variable_providers[filetype] then
		local prov_vars = M.variable_providers[filetype](filename, ctx)
		if type(prov_vars) == "table" then
			for k, v in pairs(prov_vars) do
				vars[k] = v
			end
		end
	end

	-- Context overrides
	if ctx.vars then
		for k, v in pairs(ctx.vars) do
			vars[k] = v
		end
	end

	return vars
end

--- Render a template body by substituting `<%var%>`, `<% var %>`, `{{var}}`, `{{ var }}`.
--- Cleans up standalone namespace or nil-variable lines if evaluated to empty/nil.
--- @param body string
--- @param vars table<string, any>
--- @return string
function M.render(body, vars)
	body = body:gsub("\r\n", "\n")

	-- Replace placeholders with values or a placeholder nil marker
	local function replacer(var_name)
		local val = vars[var_name]
		if val ~= nil and val ~= "" then
			return tostring(val)
		end
		return "__KRS_NIL_VAR__"
	end

	local rendered = body:gsub("<%%%s*([%w_]+)%s*%%>", replacer)
	rendered = rendered:gsub("{{%s*([%w_]+)%s*}}", replacer)

	-- Clean up lines that contain nil variables
	local clean_lines = {}
	for line in (rendered .. "\n"):gmatch("([^\n]*)\n") do
		if line:find("__KRS_NIL_VAR__") then
			-- If the line is an optional namespace declaration or empty wrapper, discard it
			if not (line:match("^%s*namespace%s+__KRS_NIL_VAR__%s*;?%s*$") or line:match("^%s*__KRS_NIL_VAR__%s*$")) then
				-- Replace inline occurrence with empty string
				clean_lines[#clean_lines + 1] = line:gsub("__KRS_NIL_VAR__", "")
			end
		else
			clean_lines[#clean_lines + 1] = line
		end
	end

	-- Remove excessive leading/trailing blank lines
	while #clean_lines > 0 and clean_lines[1] == "" do
		table.remove(clean_lines, 1)
	end

	return table.concat(clean_lines, "\n")
end

--- Checks whether a buffer is valid, loaded, modifiable, and completely empty.
--- @param buf integer
--- @return boolean
function M.is_empty_buffer(buf)
	return vim.api.nvim_buf_is_valid(buf)
		and vim.api.nvim_buf_is_loaded(buf)
		and vim.bo[buf].buftype == ""
		and vim.bo[buf].modifiable
		and vim.api.nvim_buf_line_count(buf) == 1
		and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

--- Apply a template directly to a target buffer, handling $0 cursor positioning.
--- @param buf integer
--- @param template table
--- @param filename? string
function M.apply_template_to_buffer(buf, template, filename)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	filename = filename or vim.api.nvim_buf_get_name(buf)
	local ft = template.filetype or vim.bo[buf].filetype
	if ft == "" then
		ft = vim.filetype.match({ buf = buf, filename = filename }) or ""
	end

	if template.name == "Empty file" or template.body == "" or not template.body then
		return
	end

	local vars = M.resolve_variables(filename, ft)
	local rendered = M.render(template.body, vars)

	local current_buf = vim.api.nvim_get_current_buf()
	local is_current = (current_buf == buf)

	-- If $0 is present and buffer is current, attempt native vim.snippet.expand
	if rendered:find("%$0") and is_current and vim.snippet and vim.snippet.expand then
		local ok_snip = pcall(vim.snippet.expand, rendered)
		if ok_snip then
			return
		end
	end

	-- Manual line splitting and cursor placement
	local lines = {}
	local cursor_line = 1
	local cursor_col = 0
	local found_cursor = false

	for line in (rendered .. "\n"):gmatch("([^\n]*)\n") do
		if not found_cursor then
			local s, e = line:find("%$0")
			if s then
				cursor_line = #lines + 1
				cursor_col = s - 1
				line = line:sub(1, s - 1) .. line:sub(e + 1)
				found_cursor = true
			end
		else
			line = line:gsub("%$0", "")
		end
		lines[#lines + 1] = line
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	if found_cursor then
		local win = vim.fn.bufwinid(buf)
		if win ~= -1 and vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_set_cursor, win, {
				math.min(cursor_line, #lines),
				math.max(0, cursor_col),
			})
		end
	end
end

--- Present the interactive template picker menu for an empty buffer.
--- Returns false if no templates exist or buffer is not empty.
--- @param buf? integer
--- @param filetype? string
--- @return boolean
function M.offer_template(buf, filetype)
	buf = buf or vim.api.nvim_get_current_buf()
	if not M.is_empty_buffer(buf) or vim.b[buf].krs_template_pending then
		return false
	end

	local filename = vim.api.nvim_buf_get_name(buf)
	filetype = filetype or vim.bo[buf].filetype
	if not filetype or filetype == "" or filetype == "krsmenu" then
		filetype = vim.filetype.match({ buf = buf, filename = filename }) or ""
	end

	local templates = M.get_templates(filetype)
	if #templates == 0 then
		return false
	end

	vim.b[buf].krs_template_offered = true
	vim.b[buf].krs_template_pending = true
	local tick = vim.api.nvim_buf_get_changedtick(buf)

	local title = (filetype == "cs" and "C# Type") or (filetype:upper() .. " Template")

	-- Build options table matching cli.menu format
	local options = {}
	for _, tmpl in ipairs(templates) do
		local item = {
			name = tmpl.name,
			label = tmpl.description and (tmpl.name .. "  (" .. tmpl.description .. ")") or tmpl.name,
			template = tmpl,
		}
		setmetatable(item, {
			__tostring = function()
				return tmpl.name
			end,
		})
		options[#options + 1] = item
	end

	local cli = require("krs.lib.krsnvim.cli")
	cli.menu(title, options, function(choice)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		vim.b[buf].krs_template_pending = nil

		if
			choice
			and M.is_empty_buffer(buf)
			and vim.api.nvim_buf_get_name(buf) == filename
			and vim.api.nvim_buf_get_changedtick(buf) == tick
		then
			local selected_tmpl = nil
			if type(choice) == "table" and choice.template then
				selected_tmpl = choice.template
			elseif type(choice) == "string" or (type(choice) == "table" and choice.name) then
				local target_name = (type(choice) == "string" and choice or choice.name):lower()
				for _, t in ipairs(templates) do
					if t.name:lower() == target_name then
						selected_tmpl = t
						break
					end
				end
			end

			if selected_tmpl then
				M.apply_template_to_buffer(buf, selected_tmpl, filename)
			end
		end
	end)

	return true
end

--- Recently handled files cache to deduplicate simultaneous creation events.
local recent_created = {}

--- Initialize editor autocmds and user commands for file templates.
function M.setup()
	local group = vim.api.nvim_create_augroup("KrsTemplates", { clear = true })

	-- Trigger on new buffer creation
	vim.api.nvim_create_autocmd({ "BufNewFile", "BufReadPost" }, {
		group = group,
		pattern = "*",
		callback = function(args)
			if vim.g.krs_testing or _G.krs_testing then
				return
			end
			if vim.fn.exists("#KrsCsharp") == 1 and vim.api.nvim_buf_get_name(args.buf):match("%.cs$") then
				return
			end
			vim.schedule(function()
				if
					M.is_empty_buffer(args.buf)
					and not (vim.b[args.buf].krs_template_offered or vim.b[args.buf].csharp_template_offered)
				then
					M.offer_template(args.buf)
				end
			end)
		end,
	})

	-- Trigger on file creation event from explorer / tree
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "KrsFileCreated",
		callback = function(args)
			if vim.g.krs_testing or _G.krs_testing then
				return
			end
			local filename = args.data and args.data.path
			if not filename or filename == "" then
				return
			end
			if vim.fn.exists("#KrsCsharp") == 1 and filename:match("%.cs$") then
				return
			end

			-- Deduplicate duplicate events within 2 seconds
			if recent_created[filename] then
				return
			end
			recent_created[filename] = true
			vim.defer_fn(function()
				recent_created[filename] = nil
			end, 2000)

			vim.schedule(function()
				if vim.fn.getfsize(filename) ~= 0 then
					return
				end

				local ft = vim.filetype.match({ filename = filename })
				if not ft or #M.get_templates(ft) == 0 then
					return
				end

				-- Check if buffer is already open in editor
				local bufnr = vim.fn.bufnr(filename)
				if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
					-- Find a non-floating window to edit the file
					local current_win = vim.api.nvim_get_current_win()
					if vim.api.nvim_win_get_config(current_win).relative ~= "" then
						for _, w in ipairs(vim.api.nvim_list_wins()) do
							if vim.api.nvim_win_get_config(w).relative == "" then
								vim.api.nvim_set_current_win(w)
								break
							end
						end
					end
					vim.cmd("edit " .. vim.fn.fnameescape(filename))
					bufnr = vim.api.nvim_get_current_buf()
				end

				if not vim.b[bufnr].krs_template_offered then
					M.offer_template(bufnr, ft)
				end
			end)
		end,
	})

	-- User commands
	vim.api.nvim_create_user_command("KrsFileTemplate", function()
		M.offer_template()
	end, { desc = "Choose a file creation template for the current empty buffer" })

	vim.api.nvim_create_user_command("TemplateNew", function()
		M.offer_template()
	end, { desc = "Choose a file creation template for the current empty buffer" })
end

return M
