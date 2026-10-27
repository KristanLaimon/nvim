local M = {}

local tags = {}
for name in
	("p div span strong em b i s del code pre br hr img a video source details summary ul ol li table thead tbody tr th td h1 h2 h3 h4 h5 h6 blockquote"):gmatch(
		"%S+"
	)
do
	tags[name] = true
end
local void = { img = true, br = true, hr = true, source = true }
local blocks = { p = true, div = true, video = true, table = true, pre = true, ul = true, ol = true, blockquote = true }

local function escape(text)
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#39;"))
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

local function style(text)
	local values = {}
	for declaration in text:gmatch("[^;]+") do
		local key, value = declaration:match("^%s*([%a-]+)%s*:%s*(.-)%s*$")
		if key and value then
			key, value = key:lower(), value:lower()
			local size, unit = value:match("^(%d*%.?%d+)([%a%%]+)$")
			if
				(key == "display" and vim.tbl_contains({ "block", "inline", "inline-block" }, value))
				or (key == "text-align" and vim.tbl_contains({ "left", "center", "right", "justify" }, value))
				or (
					key == "font-size"
					and size
					and tonumber(size) > 0
					and tonumber(size) <= 96
					and vim.tbl_contains({ "px", "em", "rem", "%" }, unit)
				)
			then
				values[#values + 1] = key .. ":" .. value
			end
		end
	end
	return #values > 0 and table.concat(values, ";") or nil
end

local function attribute(tag, name, value)
	value = decode(value)
	if name == "title" or (tag == "img" and name == "alt") then
		return value
	elseif name == "align" and vim.tbl_contains({ "left", "right", "center", "justify" }, value:lower()) then
		return value:lower()
	elseif (name == "width" or name == "height") and (tag == "img" or tag == "video") and value:match("^%d+$") then
		return value
	elseif name == "style" then
		return style(value)
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
		local first = text:find("<", start, true)
		if not first then
			break
		end
		local last = ending(text, first)
		if not last then
			break
		end
		output[#output + 1] = text:sub(start, first - 1)
		local sanitized = tag(text:sub(first, last))
		output[#output + 1] = sanitized and hold(sanitized) or text:sub(first, last)
		start = last + 1
	end
	output[#output + 1] = text:sub(start)
	return table.concat(output)
end

function M.block(line)
	local first = line:find("^%s*<")
	if not first then
		return nil
	end
	local start = line:find("<", 1, true)
	local last = ending(line, start)
	if not last then
		return nil
	end
	local sanitized, name, closing = tag(line:sub(start, last))
	return sanitized and not closing and blocks[name] and name or nil
end

function M.render(text, first_line)
	local output, start, line = {}, 1, first_line
	local function plain(value)
		for content, newline in value:gmatch("([^\n]*)(\n?)") do
			if content:match("%S") then
				output[#output + 1] = '<span data-source-line="' .. line .. '">' .. escape(decode(content)) .. "</span>"
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
		local first = text:find("<", start, true)
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

return M
