-- ============================================================================
-- fox.lsp.editorconfig -- IntelliSense data and completion source for
-- `.editorconfig` files.
-- ============================================================================
-- WHY THIS EXISTS
--   `.editorconfig` has no language server. This module supplies the knowledge
--   one would provide: which properties exist, what values they accept, and what
--   each of them means. The plugin spec (lua/plugins/lsp/editorconfig.lua) turns
--   that same table into diagnostics and `K` hover documentation.
--
-- HOW TO EXTEND
--   Add an entry to `M.properties` -- completion, validation and hover all read
--   from it, so nothing else needs touching. `M.sections` holds the section
--   header templates offered at the start of a line.
--
-- BLINK.CMP SOURCE
--   `M.new()` / `M:get_completions()` implement the source interface; the source
--   is registered in the plugin spec.
-- ============================================================================

local M = {}

-- ============================================================================
-- CONFIGURATION -- the EditorConfig knowledge base
-- ============================================================================

--- Known properties: description, and the values each one accepts.
--- @type table<string, { desc: string, values: { label: string, desc: string }[] }>
M.properties = {
	root = {
		desc = "Declared at the top of the file. When true, EditorConfig stops searching parent directories.",
		values = {
			{ label = "true", desc = "Marks this directory as the project root." },
			{ label = "false", desc = "Keep searching parent directories." },
		},
	},
	indent_style = {
		desc = "Whether indentation uses spaces or tabs.",
		values = {
			{ label = "space", desc = "Indent with spaces." },
			{ label = "tab", desc = "Indent with tab characters." },
		},
	},
	indent_size = {
		desc = "Spaces per indentation level, or 'tab' to follow tab_width.",
		values = {
			{ label = "2", desc = "2 spaces per level." },
			{ label = "4", desc = "4 spaces per level." },
			{ label = "8", desc = "8 spaces per level." },
			{ label = "tab", desc = "Use the same value as tab_width." },
		},
	},
	tab_width = {
		desc = "Visual width of a tab character.",
		values = {
			{ label = "2", desc = "2 columns wide." },
			{ label = "4", desc = "4 columns wide." },
			{ label = "8", desc = "8 columns wide." },
		},
	},
	end_of_line = {
		desc = "Line ending style.",
		values = {
			{ label = "lf", desc = "Unix / macOS / Linux line endings (LF)." },
			{ label = "crlf", desc = "Windows line endings (CRLF)." },
			{ label = "cr", desc = "Classic Mac line endings (CR)." },
		},
	},
	charset = {
		desc = "File character encoding.",
		values = {
			{ label = "utf-8", desc = "UTF-8 without BOM (the recommended default)." },
			{ label = "utf-8-bom", desc = "UTF-8 with a byte order mark." },
			{ label = "utf-16be", desc = "UTF-16 big endian." },
			{ label = "utf-16le", desc = "UTF-16 little endian." },
			{ label = "latin1", desc = "ISO-8859-1 encoding." },
		},
	},
	trim_trailing_whitespace = {
		desc = "Remove trailing whitespace on save.",
		values = {
			{ label = "true", desc = "Strip trailing whitespace." },
			{ label = "false", desc = "Keep trailing whitespace." },
		},
	},
	insert_final_newline = {
		desc = "Ensure the file ends with a newline on save.",
		values = {
			{ label = "true", desc = "Add a final newline." },
			{ label = "false", desc = "Do not force a final newline." },
		},
	},
	max_line_length = {
		desc = "Recommended maximum line length.",
		values = {
			{ label = "80", desc = "The classic 80 column limit." },
			{ label = "100", desc = "100 column limit." },
			{ label = "120", desc = "Modern 120 column limit." },
			{ label = "off", desc = "No length limit." },
		},
	},
}

--- Section headers offered when a line starts with `[`.
--- @type { label: string, desc: string }[]
M.sections = {
	{ label = "[*]", desc = "Applies to every file in the project." },
	{ label = "[*.{js,ts,jsx,tsx}]", desc = "Applies to JavaScript and TypeScript files." },
	{ label = "[*.py]", desc = "Applies to Python files." },
	{ label = "[*.lua]", desc = "Applies to Lua files." },
	{ label = "[*.json]", desc = "Applies to JSON files." },
	{ label = "[*.md]", desc = "Applies to Markdown files." },
	{ label = "[*.css]", desc = "Applies to CSS files." },
	{ label = "[*.html]", desc = "Applies to HTML files." },
	{ label = "[Makefile]", desc = "Applies to the Makefile." },
}

--- Properties whose value may be any number, beyond the suggested ones.
M.numeric_properties = { indent_size = true, tab_width = true, max_line_length = true }

--- Kept as the previous field names, for anything still reading them.
M.PROPERTIES = M.properties
M.SECTION_TEMPLATES = M.sections

-- ============================================================================
-- COMPLETION ITEMS
-- ============================================================================

local KIND = vim.lsp.protocol.CompletionItemKind

--- Builds one completion item.
--- @param label string Inserted text and displayed label.
--- @param kind integer LSP CompletionItemKind.
--- @param detail string Short right-hand label.
--- @param documentation string Markdown documentation.
--- @param insert_text string|nil Overrides `label` on insert.
--- @return table item
local function item(label, kind, detail, documentation, insert_text)
	return {
		label = label,
		kind = kind,
		detail = detail,
		documentation = { kind = "markdown", value = documentation },
		insertText = insert_text or label,
	}
end

--- Section header completions.
--- @return table[] items
local function section_items()
	local items = {}
	for _, section in ipairs(M.sections) do
		table.insert(items, item(section.label, KIND.Struct, "EditorConfig section", section.desc))
	end
	return items
end

--- Value completions for a property.
--- @param key string Property name.
--- @return table[] items
local function value_items(key)
	local property = M.properties[key]
	if not property or not property.values then
		return {}
	end

	local items = {}
	for _, value in ipairs(property.values) do
		table.insert(
			items,
			item(value.label, KIND.Value, "EditorConfig value", value.desc .. "\n\n*Property:* `" .. key .. "`")
		)
	end
	return items
end

--- Property name completions, inserting `name = ` ready for a value.
--- @return table[] items
local function property_items()
	local items = {}
	for key, property in pairs(M.properties) do
		table.insert(items, item(key, KIND.Property, "EditorConfig property", property.desc, key .. " = "))
	end
	return items
end

-- ============================================================================
-- VALIDATION -- shared with the diagnostics in the plugin spec
-- ============================================================================

--- Checks one `key = value` pair.
--- @param key string Property name.
--- @param value string Assigned value.
--- @return boolean known_property
--- @return boolean valid_value True when the value is accepted (or unchecked).
--- @return string[] allowed Accepted values, for the error message.
function M.validate(key, value)
	local property = M.properties[key]
	if not property then
		return false, false, {}
	end
	if not property.values or value == "" then
		return true, true, {}
	end

	local allowed = {}
	for _, candidate in ipairs(property.values) do
		table.insert(allowed, candidate.label)
		if candidate.label == value then
			return true, true, allowed
		end
	end

	-- Numeric properties accept any number, not only the suggested ones.
	if M.numeric_properties[key] and tonumber(value) then
		return true, true, allowed
	end
	return true, false, allowed
end

-- ============================================================================
-- BLINK.CMP SOURCE INTERFACE
-- ============================================================================

--- Constructs a source instance. Required by blink.cmp.
--- @return table source
function M.new()
	return setmetatable({}, { __index = M })
end

--- Completions for the cursor position: values after `=`, sections after `[`,
--- property names otherwise.
---
--- @param context table blink.cmp context.
--- @param callback fun(result: table)
function M:get_completions(context, callback)
	local line = context.line or ""
	local before_cursor = line:sub(1, context.cursor[2])

	local items
	local key = before_cursor:match("^%s*([%w_]+)%s*=")

	if key then
		items = value_items(vim.trim(key))
	elseif before_cursor:match("^%s*%[") then
		items = section_items()
	else
		items = property_items()
		-- On an empty line a section header is just as likely as a property.
		if #vim.trim(before_cursor) == 0 then
			vim.list_extend(items, section_items())
		end
	end

	callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
