local Source = {}
local schemas = {}
local server_schemas = {
	apache = "apache/2.4.json",
	nginx = "nginx/directives.json",
}

local function schema_path(bufnr, filetype)
	if filetype == "dosini" then
		return require("fox.langs.php").ini_schema_path(bufnr)
	end
	return server_schemas[filetype]
end

local function load_schema(path)
	if not schemas[path] then
		local full_path = vim.fn.stdpath("config") .. "/config/schemas/" .. path
		local ok, lines = pcall(vim.fn.readfile, full_path)
		if ok then
			schemas[path] = vim.json.decode(table.concat(lines, "\n"))
		end
	end
	return schemas[path]
end

function Source.new()
	return setmetatable({}, { __index = Source })
end

function Source.enabled()
	local bufnr = vim.api.nvim_get_current_buf()
	return schema_path(bufnr, vim.bo[bufnr].filetype) ~= nil
end

function Source.get_trigger_characters(_self)
	local filetype = vim.bo.filetype
	if filetype == "apache" then
		return { "<" }
	elseif filetype == "dosini" then
		return { "." }
	end
	return {}
end

function Source.get_completions(_self, ctx, callback)
	local result = { items = {}, is_incomplete_forward = true, is_incomplete_backward = true }
	local filetype = vim.bo[ctx.bufnr].filetype
	local path = schema_path(ctx.bufnr, filetype)
	if not path then
		return callback(result)
	end

	local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
	local before = ctx.line:sub(1, col)
	local apache_section = filetype == "apache" and before:match("^%s*</?") ~= nil
	local name_chars = filetype == "dosini" and "[%w_.]" or "[%w_-]"
	local prefix_pattern = apache_section and "^%s*</?(" or "^%s*("
	local prefix = before:match(prefix_pattern .. name_chars .. "*)$")
	if not prefix then
		return callback(result)
	end

	local schema = load_schema(path)
	if not schema then
		return callback(result)
	end

	local suffix = ctx.line:sub(col + 1):match("^" .. name_chars .. "*")
	local range = {
		start = { line = row, character = col - #prefix },
		["end"] = { line = row, character = col + #suffix },
	}
	local search = filetype == "apache" and prefix:lower() or prefix
	local kind = require("blink.cmp.types").CompletionItemKind.Property
	local documentation = { kind = "markdown", value = "[Directive reference](" .. schema.reference .. ")" }
	for _, directive in ipairs(schema.directives) do
		local section_name = directive:match("^<(.+)>$")
		if (section_name ~= nil) == apache_section then
			local name = section_name or directive
			local candidate = filetype == "apache" and name:lower() or name
			if vim.startswith(candidate, search) then
				result.items[#result.items + 1] = {
					label = directive,
					filterText = name,
					kind = kind,
					detail = schema.title,
					documentation = documentation,
					textEdit = { range = range, newText = name },
				}
			end
		end
	end
	return callback(result)
end

return Source
