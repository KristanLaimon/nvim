local Source = {}
function Source.new()
	return setmetatable({}, { __index = Source })
end
function Source.enabled(_)
	return vim.tbl_contains({ "php", "blade" }, vim.bo.filetype)
end
function Source.get_trigger_characters(_)
	return { ".", "<", ":", "@", "(", "'", '"' }
end
function Source.get_completions(_, ctx, callback)
	local cancelled = false
	vim.schedule(function()
		if cancelled then
			return
		end
		local items = {}
		local ok, err = pcall(function()
			local m = require("fox.langs.php.laravel")
			local buf = ctx.bufnr or vim.api.nvim_get_current_buf()
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
