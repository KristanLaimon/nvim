local Source = {}
local alpine_directives = {
	"x-data",
	"x-init",
	"x-show",
	"x-bind",
	"x-on",
	"x-text",
	"x-html",
	"x-model",
	"x-modelable",
	"x-for",
	"x-transition",
	"x-effect",
	"x-ignore",
	"x-ref",
	"x-cloak",
	"x-teleport",
	"x-if",
	"x-id",
}
function Source.new()
	return setmetatable({}, { __index = Source })
end
function Source.enabled(_)
	return vim.tbl_contains({ "php", "blade", "html" }, vim.bo.filetype)
end
function Source.get_trigger_characters(_)
	return { ".", "<", ":", "@", "(", "'", '"', "-" }
end
function Source.get_completions(_, ctx, callback)
	local buf = ctx.bufnr or vim.api.nvim_get_current_buf()
	if vim.api.nvim_buf_is_valid(buf) and vim.tbl_contains({ "blade", "html" }, vim.bo[buf].filetype) then
		local start, prefix = ctx.line:sub(1, ctx.cursor[2]):match("()x%-([%w%-]*)$")
		if start and (start == 1 or ctx.line:sub(start - 1, start - 1):match("[%s<]")) then
			local suffix = ctx.line:sub(ctx.cursor[2] + 1):match("^[%w%-]*")
			local items = {}
			for _, directive in ipairs(alpine_directives) do
				if vim.startswith(directive, "x-" .. prefix) then
					items[#items + 1] = {
						label = directive,
						kind = vim.lsp.protocol.CompletionItemKind.Property,
						detail = "Alpine.js directive",
						textEdit = {
							range = {
								start = { line = ctx.cursor[1] - 1, character = start - 1 },
								["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] + #suffix },
							},
							newText = directive,
						},
					}
				end
			end
			return callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
		end
	end
	if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "blade" then
		local items = require("fox.langs.php.blade_directives").complete(ctx.line, ctx.cursor[1] - 1, ctx.cursor[2])
		if items then
			return callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
		end
	end

	local cancelled = false
	vim.schedule(function()
		if cancelled then
			return
		end
		local items = {}
		local ok, err = pcall(function()
			local m = require("fox.langs.php.laravel")
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			local root = m.root(buf)
			local context = m.context(ctx.line, ctx.cursor[2])
			if not root or not context then
				return
			end
			for name in pairs(m.index(root)[context.kind] or {}) do
				if name:sub(1, #context.prefix) == context.prefix then
					local inserted = name
					local tail = ctx.line:sub(ctx.cursor[2] + 1)
					if context.kind == "component" or context.kind == "livewire" then
						if not tail:find(">", 1, true) then
							inserted = inserted .. " />"
						end
					elseif not tail:match("^['\"]") then
						local quote = ctx.line:sub(context.start, context.start)
						inserted = inserted .. quote
						if not tail:match("^['\"]?%s*%)") then
							inserted = inserted .. ")"
						end
					end
					items[#items + 1] = {
						label = name,
						kind = 18,
						textEdit = {
							range = {
								start = { line = ctx.cursor[1] - 1, character = context.start },
								["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] },
							},
							newText = inserted,
						},
					}
				end
			end
			table.sort(items, function(a, b)
				return a.label < b.label
			end)
		end)
		if not ok then
			vim.notify("Laravel completion: " .. tostring(err), vim.log.levels.WARN)
		end
		callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
	end)
	return function()
		cancelled = true
	end
end
return Source
