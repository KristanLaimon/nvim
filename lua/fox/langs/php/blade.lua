-- Blade syntax and indentation, owned by the PHP language module.
local M = {}
local pairs_ = {
	if_ = "endif",
	unless = "endunless",
	foreach = "endforeach",
	forelse = "endforelse",
	for_ = "endfor",
	while_ = "endwhile",
	switch = "endswitch",
	section = "endsection",
	push = "endpush",
	prepend = "endprepend",
	component = "endcomponent",
	slot = "endslot",
	auth = "endauth",
	guest = "endguest",
	can = "endcan",
	cannot = "endcannot",
	canany = "endcanany",
	isset = "endisset",
	empty = "endempty",
	hasSection = "endif",
	session = "endsession",
	error = "enderror",
	once = "endonce",
	pushOnce = "endPushOnce",
	prependOnce = "endPrependOnce",
	php = "endphp",
	verbatim = "endverbatim",
	script = "endscript",
	assets = "endassets",
	fragment = "endfragment",
	production = "endproduction",
	env = "endenv",
}
pairs_["if"], pairs_["for"], pairs_["while"] = pairs_.if_, pairs_.for_, pairs_.while_
pairs_.if_, pairs_.for_, pairs_.while_ = nil, nil, nil
local branches = { ["else"] = true, ["elseif"] = true, elsecan = true, elsecannot = true, elsecanany = true }
local ends = { stop = true, show = true, append = true, overwrite = true }
local void = {
	area = true,
	base = true,
	br = true,
	col = true,
	embed = true,
	hr = true,
	img = true,
	input = true,
	link = true,
	meta = true,
	param = true,
	source = true,
	track = true,
	wbr = true,
}
local function directives()
	local starts = vim.tbl_extend("force", pairs_, vim.g.blade_custom_directives_pairs or {})
	local closes = vim.tbl_extend("force", {}, ends)
	for _, close in pairs(starts) do
		closes[close] = true
	end
	return starts, closes
end
function M.syntax()
	-- PHP's built-in syntax already includes HTML, JS and CSS.
	vim.cmd("runtime! syntax/php.vim")
	vim.cmd("unlet! b:current_syntax")
	vim.cmd(
		[[syntax region FoxBladeEcho matchgroup=FoxBladeDelimiter start=/\%(@\)\@<!{{/ end=/}}/ contains=@phpClTop containedin=ALLBUT,FoxBladeComment,FoxBladeVerbatim keepend]]
	)
	vim.cmd(
		[[syntax region FoxBladeRawEcho matchgroup=FoxBladeDelimiter start=/{!!/ end=/!!}/ contains=@phpClTop containedin=ALLBUT,FoxBladeComment,FoxBladeVerbatim keepend]]
	)
	vim.cmd(
		[[syntax region FoxBladePHP matchgroup=FoxBladeDirective start=/@php\>\s*(\@!/ end=/@endphp\>/ contains=@phpClTop containedin=ALLBUT,FoxBladeComment,FoxBladeVerbatim keepend]]
	)
	vim.cmd(
		[[syntax match FoxBladeDirective /\%(@\)\@<!@[a-zA-Z][a-zA-Z0-9_]*/ containedin=ALLBUT,FoxBladeComment,FoxBladeVerbatim,FoxBladeEcho,FoxBladeRawEcho]]
	)
	vim.cmd([[syntax region FoxBladeVerbatim start=/@verbatim\>/ end=/@endverbatim\>/ keepend]])
	vim.cmd([[syntax region FoxBladeComment start=/{{--/ end=/--}}/ containedin=ALLBUT,FoxBladeVerbatim keepend]])
	for group, target in pairs({
		FoxBladeEcho = "Normal",
		FoxBladeRawEcho = "Normal",
		FoxBladePHP = "Normal",
		FoxBladeDirective = "Statement",
		FoxBladeDelimiter = "PreProc",
		FoxBladeComment = "Comment",
	}) do
		vim.api.nvim_set_hl(0, group, { default = true, link = target })
	end
	vim.b.current_syntax = "blade"
end
local function strip(line, state)
	if state.comment then
		local stop = line:find("--}}", 1, true)
		if not stop then
			return ""
		end
		line = line:sub(stop + 4)
		state.comment = false
	end
	line = line:gsub("{{--.-%-%-}}", ""):gsub("<!%-%-.-%-%->", "")
	local start = line:find("{{--", 1, true)
	if start then
		state.comment = true
		line = line:sub(1, start - 1)
	end
	-- Strings cannot open directives, tags or PHP blocks. Keep their delimiters
	-- so a comma in section('title', 'value') is still visible to the parser.
	line = line:gsub([['[^']*']], "''"):gsub('"[^"]*"', '""'):gsub("@@[%w_]+", "")
	return line
end
local function delta(line, state, starts, closes)
	local depth = 0
	for directive, pos in line:gmatch("@([%w_]+)()") do
		if closes[directive] then
			depth = depth - 1
		elseif starts[directive] and not (directive == "empty" and not line:sub(pos):match("^%s*%(")) then
			local rest = line:sub(pos)
			local inline = (directive == "section" or directive == "slot") and rest:match("^%s*%([^)]*,")
			if not inline and not (directive == "php" and rest:match("^%s*%(")) then
				depth = depth + 1
			end
		end
	end
	for slash, tag, rest in line:gmatch("<(/?)([%w:_-]+)([^>]*)>") do
		if slash == "/" then
			depth = depth - 1
		elseif not void[tag:lower()] and not rest:match("/%s*$") then
			depth = depth + 1
		end
	end
	if line:find("<?", 1, true) or line:match("@php%s*$") then
		state.php = true
	end
	if state.php then
		local _, opens = line:gsub("{", "")
		local _, closed = line:gsub("}", "")
		depth = depth + opens - closed
		if line:find("?>", 1, true) or line:match("@endphp") then
			state.php = false
		end
	end
	return depth
end
function M.indent(lnum)
	local starts, closes = directives()
	local state, depth = {}, 0
	for row = 1, lnum - 1 do
		local line = strip(vim.fn.getline(row), state)
		if state.verbatim then
			if line:match("@endverbatim") then
				state.verbatim = false
				depth = math.max(0, depth - 1)
			end
		else
			depth = math.max(0, depth + delta(line, state, starts, closes))
			if line:match("@verbatim") and not line:match("@endverbatim") then
				state.verbatim = true
			end
		end
	end
	local current = vim.trim(strip(vim.fn.getline(lnum), state))
	if state.verbatim and not current:match("^@endverbatim") then
		return -1
	end
	local directive = current:match("^@([%w_]+)")
	if
		directive
		and (closes[directive] or branches[directive] or (directive == "empty" and not current:match("^@empty%s*%(")))
	then
		depth = depth - 1
	end
	if current:match("^</") or (state.php and current:match("^}")) then
		depth = depth - 1
	end
	return math.max(0, depth) * vim.fn.shiftwidth()
end
return M
