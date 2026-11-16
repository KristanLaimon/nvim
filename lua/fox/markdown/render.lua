local M = {}
local markup = require("fox.markdown.html")

function M.escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;"))
end

local function inline(text)
	local saved = {}
	local function hold(html)
		saved[#saved + 1] = html
		return "\1" .. #saved .. "\2"
	end
	text = text:gsub("[%z\1\2]", "")
	text = markup.protect(text, hold)
	text = text:gsub("(!?)%[([^%]]*)%]%(([^%s%)]+)%)", function(image, label, url)
		url = markup.url(url, image == "!")
		if not url then
			return hold(markup.escape_text(label))
		end
		if image == "!" then
			return hold('<img alt="' .. M.escape(label) .. '" src="' .. M.escape(url) .. '">')
		end
		return hold('<a href="' .. M.escape(url) .. '">' .. markup.escape_text(label) .. "</a>")
	end)
	text = text:gsub("<?(https?://[^%s<>]+)>?", function(url)
		local clean, tail = url:match("^(.-)([.,;!?:]*)$")
		return hold('<a href="' .. M.escape(clean) .. '">' .. M.escape(clean) .. "</a>" .. tail)
	end)
	text = text:gsub("<?([%w._%%+-]+@[%w.-]+%.[%a]+)>?", function(email)
		return hold('<a href="mailto:' .. M.escape(email) .. '">' .. M.escape(email) .. "</a>")
	end)
	text = markup.escape_text(text)
	text = text:gsub("%*%*%*(%S.-)%*%*%*", "<strong><em>%1</em></strong>")
	text = text:gsub("___(%S.-)___", "<strong><em>%1</em></strong>")
	for _, rule in ipairs({
		{ "%*%*(.-)%*%*", "strong" },
		{ "__(.-)__", "strong" },
		{ "~~(.-)~~", "s" },
		{ "%*(%S.-)%*", "em" },
	}) do
		text = text:gsub(rule[1], "<" .. rule[2] .. ">%1</" .. rule[2] .. ">")
	end
	return (text:gsub("\1(%d+)\2", function(index)
		return saved[tonumber(index)]
	end))
end

local function cells(line)
	line = vim.trim(line):gsub("^|", ""):gsub("|$", "")
	local result, current, escaped = {}, "", false
	for i = 1, #line do
		local char = line:sub(i, i)
		if char == "|" and not escaped then
			result[#result + 1], current = vim.trim(current), ""
		else
			current = current .. char
		end
		escaped = char == "\\" and not escaped
	end
	result[#result + 1] = vim.trim(current)
	return result
end

local function table_separator(line)
	if not line or not line:find("|", 1, true) then
		return false
	end
	for _, cell in ipairs(cells(line)) do
		if not cell:match("^:?-+:?$") then
			return false
		end
	end
	return true
end

local function list_item(line)
	local indent, marker, value = line:match("^( *)([-+*])%s+(.*)$")
	if not indent then
		indent, marker, value = line:match("^( *)(%d+[.)])%s+(.*)$")
	end
	if indent then
		local prefix = line:match("^ *[^ ]+%s+")
		return #indent, marker:match("^%d") and "ol" or "ul", value, #prefix, marker
	end
end

function M.render(lines, source_offset)
	-- shortcut: focused Markdown subset, extend with fixtures when documents need more CommonMark constructs.
	local output, paragraph, fence, code = {}, {}, nil, {}
	local paragraph_start
	local function emit(html, first, last)
		if first then
			html =
				html:gsub("^(<[%w]+)", '%1 data-source-line="' .. first .. '" data-source-end="' .. (last or first) .. '"', 1)
		end
		output[#output + 1] = html
	end
	local function flush()
		if #paragraph > 0 then
			emit("<p>" .. table.concat(paragraph, "\n") .. "</p>", paragraph_start, paragraph_start + #paragraph - 1)
			paragraph = {}
		end
	end
	local function close_code(last)
		local content = M.escape(table.concat(code, "\n"))
		if fence.lang ~= "mermaid" then
			local spans = {}
			for number, line in ipairs(code) do
				spans[#spans + 1] = '<span data-source-line="' .. (fence.first + number) .. '">' .. M.escape(line) .. "</span>"
			end
			content = table.concat(spans, "\n")
		end
		emit(
			fence.lang == "mermaid" and ('<pre class="mermaid">' .. content .. "</pre>")
				or ("<pre><code>" .. content .. "</code></pre>"),
			fence.first,
			last
		)
		fence, code = nil, {}
	end
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local marker, lang = line:match("^%s*([`~]+)%s*([%w_-]*)%s*$")
		local html_block, block_end
		if not fence then
			html_block, block_end = markup.render_block(lines, i)
		end
		if fence then
			if marker and marker:sub(1, 1) == fence.char and #marker >= fence.size and lang == "" then
				close_code(i)
			else
				code[#code + 1] = line
			end
		elseif marker and #marker >= 3 then
			flush()
			fence = { char = marker:sub(1, 1), size = #marker, lang = lang, first = i }
		elseif html_block then
			flush()
			emit(html_block)
			i = block_end
		elseif table_separator(lines[i + 1]) and line:find("|", 1, true) then
			flush()
			local alignment = cells(lines[i + 1])
			local function row(value, tag, number)
				local html = { '<tr data-source-line="' .. number .. '">' }
				for column, cell in ipairs(cells(value)) do
					local align = alignment[column] or ""
					local style = align:match("^:.*:$") and "center" or (align:match(":$") and "right" or "left")
					html[#html + 1] = "<" .. tag .. ' style="text-align:' .. style .. '">' .. inline(cell) .. "</" .. tag .. ">"
				end
				return table.concat(html) .. "</tr>"
			end
			emit("<table><thead>" .. row(line, "th", i) .. "</thead><tbody>")
			i = i + 2
			while lines[i] and lines[i]:find("|", 1, true) and vim.trim(lines[i]) ~= "" do
				emit(row(lines[i], "td", i))
				i = i + 1
			end
			emit("</tbody></table>")
			i = i - 1
		else
			local heading, title = line:match("^(#+)%s+(.+)$")
			local indent, kind, item, content_indent, bullet = list_item(line)
			local attachment = vim.trim(line):match("^https://github%.com/user%-attachments/assets/[%w-]+$")
			if attachment then
				flush()
				emit(
					'<video controls preload="metadata" src="'
						.. M.escape(attachment)
						.. '">'
						.. '<a href="'
						.. M.escape(attachment)
						.. '">Open video</a></video>',
					i
				)
			elseif heading and #heading <= 6 then
				flush()
				emit("<h" .. #heading .. ">" .. inline(title:gsub("%s+#+%s*$", "")) .. "</h" .. #heading .. ">", i)
			elseif vim.trim(line) == "" then
				flush()
			elseif line:match("^%s*>%s?") then
				flush()
				local first, quoted = i, {}
				while lines[i] and lines[i]:match("^%s*>") do
					quoted[#quoted + 1] = lines[i]:gsub("^%s*>%s?", "", 1)
					i = i + 1
				end
				emit("<blockquote>" .. M.render(quoted, first - 1) .. "</blockquote>", first, i - 1)
				i = i - 1
			elseif item then
				flush()
				local start = kind == "ol" and (' start="' .. bullet:match("%d+") .. '"') or ""
				emit("<" .. kind .. start .. ">")
				while item do
					local first, contents = i, { item }
					i = i + 1
					while lines[i] do
						local next_indent = list_item(lines[i])
						if next_indent and next_indent <= indent then
							break
						end
						if vim.trim(lines[i]) == "" then
							local next_line = i + 1
							while lines[next_line] and vim.trim(lines[next_line]) == "" do
								next_line = next_line + 1
							end
							if not lines[next_line] or #(lines[next_line]:match("^ *")) < content_indent then
								break
							end
						elseif #(lines[i]:match("^ *")) < content_indent then
							break
						end
						contents[#contents + 1] = lines[i]:sub(content_indent + 1)
						i = i + 1
					end
					local checked, label = contents[1]:match("^%[([ xX])%]%s+(.*)$")
					if checked then
						contents[1] = label
					end
					local body = M.render(contents, first - 1)
					if checked then
						local checkbox = '<input type="checkbox" disabled' .. (checked ~= " " and " checked" or "") .. "> "
						body = body:gsub("(<p[^>]*>)", "%1" .. checkbox, 1)
					end
					if not vim.tbl_contains(contents, "") then
						body = body:gsub("^<p[^>]*>(.-)</p>", "%1", 1)
					end
					emit((checked and '<li class="task-list-item">' or "<li>") .. body .. "</li>", first, i - 1)
					local next_line = i
					while lines[next_line] and vim.trim(lines[next_line]) == "" do
						next_line = next_line + 1
					end
					local sibling_indent, sibling_kind = list_item(lines[next_line] or "")
					if sibling_indent == indent and sibling_kind == kind then
						i = next_line
					end
					local next_indent, next_kind, next_item, next_content_indent = list_item(lines[i] or "")
					item = next_indent == indent and next_kind == kind and next_item or nil
					content_indent = next_content_indent
				end
				emit("</" .. kind .. ">")
				i = i - 1
			elseif line:match("^%s*<[/]?[%a][%w]*[%s>/]") then
				flush()
				emit(inline(line), i)
			elseif line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") then
				flush()
				emit("<hr>", i)
			else
				if #paragraph == 0 then
					paragraph_start = i
				end
				paragraph[#paragraph + 1] = '<span data-source-line="' .. i .. '">' .. inline(line) .. "</span>"
			end
		end
		i = i + 1
	end
	flush()
	if fence then
		close_code(#lines)
	end
	local html = table.concat(output, "\n")
	return (
		html:gsub('(data%-source%-[%w]+=")(%d+)', function(attribute, number)
			return attribute .. (tonumber(number) + (source_offset or 0))
		end)
	)
end

return M
