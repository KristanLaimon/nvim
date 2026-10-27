local M = {}

function M.escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;"))
end

local function safe_url(url)
	local scheme = url:match("^([%w+.-]+):")
	return not url:find("[%c]") and (not scheme or vim.tbl_contains({ "http", "https", "mailto" }, scheme:lower()))
end

local function inline(text)
	local saved = {}
	local function hold(html)
		saved[#saved + 1] = html
		return "\1" .. #saved .. "\2"
	end
	text = text:gsub("[%z\1\2]", "")
	text = text:gsub("(`+)(.-)%1", function(_, code)
		return hold("<code>" .. M.escape(code) .. "</code>")
	end)
	text = text:gsub("\\([%p])", function(char)
		return hold(M.escape(char))
	end)
	text = text:gsub("(!?)%[([^%]]*)%]%(([^%s%)]+)%)", function(image, label, url)
		if not safe_url(url) then
			return hold(M.escape(label))
		end
		if image == "!" then
			return hold('<img alt="' .. M.escape(label) .. '" src="' .. M.escape(url) .. '">')
		end
		return hold('<a href="' .. M.escape(url) .. '">' .. M.escape(label) .. "</a>")
	end)
	text = text:gsub("<?(https?://[^%s<>]+)>?", function(url)
		local clean, tail = url:match("^(.-)([.,;!?:]*)$")
		return hold('<a href="' .. M.escape(clean) .. '">' .. M.escape(clean) .. "</a>" .. tail)
	end)
	text = text:gsub("<?([%w._%%+-]+@[%w.-]+%.[%a]+)>?", function(email)
		return hold('<a href="mailto:' .. M.escape(email) .. '">' .. M.escape(email) .. "</a>")
	end)
	text = M.escape(text)
	for _, rule in ipairs({
		{ "%*%*(.-)%*%*", "strong" },
		{ "__(.-)__", "strong" },
		{ "~~(.-)~~", "s" },
		{ "%*(.-)%*", "em" },
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

function M.render(lines)
	-- shortcut: focused Markdown subset, extend with fixtures when documents need more CommonMark constructs.
	local output, paragraph, list, fence, code = {}, {}, nil, nil, {}
	local function emit(html)
		output[#output + 1] = html
	end
	local function flush()
		if #paragraph > 0 then
			emit("<p>" .. inline(table.concat(paragraph, "\n")) .. "</p>")
			paragraph = {}
		end
	end
	local function close_list()
		if list then
			emit("</" .. list .. ">")
			list = nil
		end
	end
	local function close_code()
		local content = M.escape(table.concat(code, "\n"))
		emit(
			fence.lang == "mermaid" and ('<pre class="mermaid">' .. content .. "</pre>")
				or ("<pre><code>" .. content .. "</code></pre>")
		)
		fence, code = nil, {}
	end
	local i = 1
	while i <= #lines do
		local line = lines[i]
		local marker, lang = line:match("^%s*([`~]+)%s*([%w_-]*)%s*$")
		if fence then
			if marker and marker:sub(1, 1) == fence.char and #marker >= fence.size and lang == "" then
				close_code()
			else
				code[#code + 1] = line
			end
		elseif marker and #marker >= 3 then
			flush()
			close_list()
			fence = { char = marker:sub(1, 1), size = #marker, lang = lang }
		elseif table_separator(lines[i + 1]) and line:find("|", 1, true) then
			flush()
			close_list()
			local alignment = cells(lines[i + 1])
			local function row(value, tag)
				local html = { "<tr>" }
				for column, cell in ipairs(cells(value)) do
					local align = alignment[column] or ""
					local style = align:match("^:.*:$") and "center" or (align:match(":$") and "right" or "left")
					html[#html + 1] = "<" .. tag .. ' style="text-align:' .. style .. '">' .. inline(cell) .. "</" .. tag .. ">"
				end
				return table.concat(html) .. "</tr>"
			end
			emit("<table><thead>" .. row(line, "th") .. "</thead><tbody>")
			i = i + 2
			while lines[i] and lines[i]:find("|", 1, true) and vim.trim(lines[i]) ~= "" do
				emit(row(lines[i], "td"))
				i = i + 1
			end
			emit("</tbody></table>")
			i = i - 1
		else
			local heading, title = line:match("^(#+)%s+(.+)$")
			local item = line:match("^%s*[-+*]%s+(.+)$")
			local numbered = line:match("^%s*%d+[.)]%s+(.+)$")
			if not item and not numbered then
				close_list()
			end
			if heading and #heading <= 6 then
				flush()
				emit("<h" .. #heading .. ">" .. inline(title:gsub("%s+#+%s*$", "")) .. "</h" .. #heading .. ">")
			elseif vim.trim(line) == "" then
				flush()
			elseif line:match("^%s*>%s?") then
				flush()
				emit("<blockquote>" .. inline((line:gsub("^%s*>%s?", ""))) .. "</blockquote>")
			elseif item or numbered then
				flush()
				local kind = numbered and "ol" or "ul"
				if list ~= kind then
					close_list()
					list = kind
					emit("<" .. kind .. ">")
				end
				local value = item or numbered
				local checked, label = value:match("^%[([ xX])%]%s+(.*)$")
				local checkbox = checked
						and ('<input type="checkbox" disabled' .. (checked ~= " " and " checked" or "") .. "> ")
					or ""
				emit("<li>" .. checkbox .. inline(label or value) .. "</li>")
			elseif line:match("^%s*<details>%s*$") or line:match("^%s*</details>%s*$") then
				flush()
				emit(vim.trim(line))
			elseif line:match("^%s*<summary>.*</summary>%s*$") then
				flush()
				emit("<summary>" .. inline(line:match("<summary>(.*)</summary>")) .. "</summary>")
			elseif line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") then
				flush()
				emit("<hr>")
			else
				paragraph[#paragraph + 1] = line
			end
		end
		i = i + 1
	end
	flush()
	close_list()
	if fence then
		close_code()
	end
	return table.concat(output, "\n")
end

return M
