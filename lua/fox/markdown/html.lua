local M = {}

local tags = {}
local blocks = {}
for name in
	("article aside blockquote div dl figure footer h1 h2 h3 h4 h5 h6 header nav ol p pre section table ul video"):gmatch(
		"%S+"
	)
do
	blocks[name] = true
	tags[name] = true
end
for name in
	("a b br caption code col colgroup dd del details dt em figcaption hr i img kbd li mark picture s samp small source span strong sub summary sup tbody td tfoot th thead tr u var wbr"):gmatch(
		"%S+"
	)
do
	tags[name] = true
end
local void = { br = true, col = true, hr = true, img = true, source = true, wbr = true }

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;"))
end

function M.escape_text(text)
	-- The browser decodes character references as text without reinterpreting them as tags.
	return (escape(text):gsub("&amp;(#?[%w]+;)", "&%1"))
end

local function decode(text)
	local named = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
	return (
		text:gsub("&([#%w]+);", function(entity)
			local code = entity:match("^#[xX](%x+)$")
			local number = code and tonumber(code, 16) or tonumber(entity:match("^#(%d+)$"))
			if number and number > 0 and number <= 0x10ffff and not (number >= 0xd800 and number <= 0xdfff) then
				return vim.fn.nr2char(number)
			end
			return named[entity] or ("&" .. entity .. ";")
		end)
	)
end

function M.url(text, media)
	text = vim.trim(decode(text))
	local scheme = text:match("^([^/#?]+):")
	if
		text:find("[%c\\]")
		or (scheme and not vim.tbl_contains(media and { "http", "https" } or { "http", "https", "mailto" }, scheme:lower()))
	then
		return nil
	end
	return text
end

local dimensions = { col = true, colgroup = true, img = true, table = true, td = true, th = true, video = true }
local table_cells = { td = true, th = true }
local table_rows = { tr = true, tbody = true, tfoot = true, thead = true }

local function attribute(tag, name, value)
	value = decode(value)
	if name == "style" or name == "title" or (tag == "img" and name == "alt") then
		return value
	elseif name == "align" or (name == "valign" and (table_cells[tag] or table_rows[tag])) then
		return vim.trim(value):lower()
	elseif (name == "width" or name == "height") and dimensions[tag] then
		return vim.trim(value):lower()
	elseif table_cells[tag] and (name == "colspan" or name == "rowspan") then
		return value:match("^%d+$")
	elseif (tag == "col" or tag == "colgroup") and name == "span" then
		return value:match("^%d+$")
	elseif
		(name == "href" and tag == "a")
		or (name == "src" and (tag == "img" or tag == "video" or tag == "source"))
		or (name == "poster" and tag == "video")
	then
		return M.url(value, name ~= "href")
	elseif name == "type" and tag == "source" and value:match("^video/[%w.+-]+$") then
		return value
	elseif name == "open" and tag == "details" then
		return ""
	end
end

local function tag(source)
	local closing, name, rest = source:match("^<(/?)([%a][%w]*)(.-)>$")
	if not name then
		return nil
	end
	name = name:lower()
	if not tags[name] then
		return nil
	end
	if closing == "/" then
		if not rest:match("^%s*$") then
			return nil
		end
		return void[name] and "" or ("</" .. name .. ">"), name, true
	end
	if rest ~= "" and not rest:match("^%s") and rest ~= "/" then
		return nil
	end
	rest = rest:gsub("/%s*$", "")
	local attributes = {}
	while rest:match("%S") do
		local key, tail = rest:match("^%s*([%a][%w_:-]*)(.*)$")
		if not key then
			return nil
		end
		rest = tail
		local value = ""
		if rest:match("^%s*=") then
			rest = rest:gsub("^%s*=%s*", "", 1)
			local quote = rest:sub(1, 1)
			if quote == '"' or quote == "'" then
				local last = rest:find(quote, 2, true)
				if not last then
					return nil
				end
				value, rest = rest:sub(2, last - 1), rest:sub(last + 1)
			else
				value, rest = rest:match("^([^%s\"'`=<>]+)(.*)$")
				if not value then
					return nil
				end
			end
		end
		key = key:lower()
		attributes[key] = attribute(name, key, value)
	end
	if name == "video" then
		attributes.controls, attributes.preload = "", "metadata"
	end
	local output = { "<" .. name }
	for _, key in ipairs(vim.tbl_keys(attributes)) do
		output[#output + 1] = " " .. key .. '="' .. escape(attributes[key]) .. '"'
	end
	return table.concat(output) .. ">", name, false
end

-- Scan to the closing angle outside quotes; a '>' in an attribute is not a tag boundary.
local function ending(text, first)
	local quote
	for i = first + 1, #text do
		local char = text:sub(i, i)
		if quote then
			if char == quote then
				quote = nil
			end
		elseif char == '"' or char == "'" then
			quote = char
		elseif char == ">" then
			return i
		end
	end
end

function M.protect(text, hold)
	local output, start = {}, 1
	while start <= #text do
		local first = text:find("[<`\\]", start)
		if not first then
			break
		end
		output[#output + 1] = text:sub(start, first - 1)
		local marker = text:sub(first, first)
		local last, sanitized
		if marker == "<" and text:find("^</?%a", first) then
			last = ending(text, first)
			sanitized = last and tag(text:sub(first, last))
		elseif marker == "`" then
			local _, finish, _, code = text:find("^(`+)(.-)%1", first)
			last, sanitized = finish, code and ("<code>" .. escape(code) .. "</code>")
		elseif marker == "\\" and text:sub(first + 1, first + 1):match("%p") then
			last, sanitized = first + 1, escape(text:sub(first + 1, first + 1))
		end
		output[#output + 1] = sanitized and hold(sanitized) or marker
		start = (sanitized and last or first) + 1
	end
	output[#output + 1] = text:sub(start)
	return table.concat(output)
end

local function render(text, first_line)
	local output, start, line = {}, 1, first_line
	local function plain(value)
		for content, newline in value:gmatch("([^\n]*)(\n?)") do
			if content:match("%S") then
				output[#output + 1] = '<span data-source-line="' .. line .. '">' .. M.escape_text(content) .. "</span>"
			else
				output[#output + 1] = content
			end
			output[#output + 1] = newline
			if newline ~= "" then
				line = line + 1
			end
		end
	end
	while start <= #text do
		local first = text:find("</?%a", start)
		if not first then
			break
		end
		local last = ending(text, first)
		if not last then
			break
		end
		plain(text:sub(start, first - 1))
		local raw = text:sub(first, last)
		local sanitized, _, closing = tag(raw)
		if sanitized then
			if not closing then
				sanitized = sanitized:gsub("^(<[%w]+)", '%1 data-source-line="' .. line .. '"', 1)
			end
			output[#output + 1] = sanitized
			local _, count = raw:gsub("\n", "")
			line = line + count
		else
			plain(raw)
		end
		start = last + 1
	end
	plain(text:sub(start))
	return table.concat(output)
end

function M.render_block(lines, first_line)
	local name, boundary = lines[first_line]:match("^%s*<([%a][%w]*)(.?)")
	name = name and name:lower()
	if not blocks[name] or (boundary ~= "" and not boundary:match("[%s>/]")) then
		return nil
	end
	local depth, pending = 0, nil
	for i = first_line, #lines do
		local text = pending and (pending .. "\n" .. lines[i]) or lines[i]
		local start = 1
		pending = nil
		while true do
			local first = text:find("</?%a", start)
			if not first then
				break
			end
			local last = ending(text, first)
			if not last then
				pending = text:sub(first)
				break
			end
			local _, tag_name, closing = tag(text:sub(first, last))
			if depth == 0 and (tag_name ~= name or closing) then
				return nil
			end
			if tag_name == name then
				depth = depth + (closing and -1 or 1)
				if depth == 0 then
					return render(table.concat(lines, "\n", first_line, i), first_line), i
				end
			end
			start = last + 1
		end
	end
	if depth > 0 then
		return render(table.concat(lines, "\n", first_line), first_line), #lines
	end
end

return M
