-- Native insert-mode editing. Returned keys go through Neovim's normal undo and
-- indent machinery; no scheduled buffer writes can race completion/snippets.
local M = { config = { check_ts = true, disable_filetype = { "TelescopePrompt", "vim" } } }
local brackets = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local quotes = { ["'"] = true, ['"'] = true, ["`"] = true }
local fences = {
	markdown = true,
	vimwiki = true,
	rmarkdown = true,
	rmd = true,
	pandoc = true,
	quarto = true,
	typst = true,
	gitcommit = true,
}
local triples = { python = true, elixir = true, julia = true, kotlin = true, scala = true, sbt = true, toml = true }
local tags = {
	html = true,
	htmlangular = true,
	htmldjango = true,
	heex = true,
	eruby = true,
	php = true,
	blade = true,
	typescript = true,
	typescriptreact = true,
	javascript = true,
	javascriptreact = true,
	svelte = true,
	vue = true,
	xml = true,
	rescript = true,
	astro = true,
}
local function keys(value)
	return vim.api.nvim_replace_termcodes(value, true, false, true)
end
local function active()
	return vim.bo.modifiable
		and vim.bo.buftype ~= "terminal"
		and not vim.tbl_contains(M.config.disable_filetype, vim.bo.filetype)
		and vim.fn.reg_recording() == ""
		and vim.fn.reg_executing() == ""
		and vim.api.nvim_get_mode().mode:sub(1, 1) ~= "R"
		and vim.v.count == 0
		and not (vim.bo.filetype == "" and vim.api.nvim_win_get_config(0).relative ~= "")
end
local function context()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_get_current_line()
	return line:sub(1, cursor[2]), line:sub(cursor[2] + 1), cursor[1] - 1, cursor[2]
end
local function escaped(text)
	return #(text:match("\\+$") or "") % 2 == 1
end
-- Scan only the prefix, respecting escapes. Treesitter handles multiline strings.
local function in_quote(text)
	local quote
	local slash = false
	local substitutions = {}
	local shell = vim.bo.filetype == "bash" or vim.bo.filetype == "sh"
	for i = 1, #text do
		local ch = text:sub(i, i)
		if shell and not slash and (ch == "(" or ch == "{") and text:sub(i - 1, i - 1) == "$" then
			substitutions[#substitutions + 1] = { close = ch == "(" and ")" or "}", quote = quote }
			quote = nil
		elseif not slash and not quote and substitutions[#substitutions] and ch == substitutions[#substitutions].close then
			quote = table.remove(substitutions).quote
		elseif not slash and quotes[ch] then
			if quote == ch then
				quote = nil
			elseif not quote then
				quote = ch
			end
		end
		if ch == "\\" then
			slash = not slash
		else
			slash = false
		end
	end
	return quote
end
local function syntax_blocked(row, col)
	if not M.config.check_ts or col == 0 then
		return false
	end
	local ok, blocked = pcall(function()
		local parser = vim.treesitter.get_parser(0, nil, { error = false })
		if not parser then
			return false
		end
		parser:parse()
		local node = vim.treesitter.get_node({ pos = { row, col - 1 }, ignore_injections = false })
		while node do
			local kind = node:type()
			if kind:find("comment") or kind:find("string") then
				local _, _, er, ec = node:range()
				-- A cursor just after a complete string is outside it.
				return er > row or ec > col or kind:find("comment") ~= nil
			end
			node = node:parent()
		end
		return false
	end)
	return ok and blocked or false
end
local function sequences()
	local ft = vim.bo.filetype
	local result = {}
	if ft == "html" or ft == "markdown" then
		result[#result + 1] = { "<!--", "-->" }
	end
	if fences[ft] then
		result[#result + 1] = { "```", "```" }
	end
	if triples[ft] then
		result[#result + 1] = { '"""', '"""' }
	end
	if ft == "python" or ft == "toml" then
		result[#result + 1] = { "'''", "'''" }
	end
	if ft == "nix" then
		result[#result + 1] = { "''", "''" }
	end
	return result
end
local function balanced(line, open, close)
	local count = 0
	for i = 1, #line do
		local ch = line:sub(i, i)
		if ch == open then
			count = count + 1
		elseif ch == close then
			count = count - 1
		end
	end
	return count == 0
end
local function insert_pair(ch, close)
	return keys("<C-g>u") .. ch .. close .. keys(string.rep("<C-g>U<Left>", #close) .. "<C-g>u")
end
function M.type(ch)
	if not active() then
		return ch
	end
	local before, after, row, col = context()
	local next_char = after:sub(1, 1)
	for _, pair in ipairs(sequences()) do
		local open, close = pair[1], pair[2]
		if (before .. ch):sub(-#open) == open and before:sub(-#open) ~= open then
			return insert_pair(ch, close)
		end
	end
	if escaped(before) then
		return ch
	end
	local quote = in_quote(before)
	if next_char == ch and (quotes[ch] and (quote == ch or #after == 1)) then
		return keys("<C-g>U<Right>")
	end
	for open, close in pairs(brackets) do
		if ch == close and next_char == close and balanced(before .. after, open, close) then
			return keys("<C-g>U<Right>")
		end
	end
	local close = brackets[ch] or (quotes[ch] and ch)
	if not close then
		return ch
	end
	if quotes[ch] then
		if quote or syntax_blocked(row, col) then
			return ch
		end
		if ch == "'" then
			local python_prefix = vim.bo.filetype == "python" and before:match("[frbuFRBU]$")
			if before:match("%w$") and not python_prefix then
				return ch
			end
			if vim.bo.filetype == "rust" and (before:match("[<&]$") or next_char == ">") then
				return ch
			end
			if vim.bo.filetype == "nix" then
				return ch
			end
		end
	elseif not (quote and next_char == quote) then
		if syntax_blocked(row, col) then
			return ch
		end
	end
	if next_char:match("[%w%%'%[%\"%.%`%$]") and not (brackets[ch] and next_char == quote) then
		-- Wrapping an existing quoted argument is useful: (|"argument")
		if brackets[ch] and quotes[next_char] and not quote then
			local finish
			for i = 2, #after do
				if after:sub(i, i) == next_char and not escaped(after:sub(1, i - 1)) then
					finish = i
					break
				end
			end
			if finish then
				return keys("<C-g>u")
					.. ch
					.. keys(string.rep("<C-g>U<Right>", vim.fn.strchars(after:sub(1, finish))))
					.. close
					.. keys(string.rep("<C-g>U<Left>", vim.fn.strchars(after:sub(1, finish)) + 1) .. "<C-g>u")
			end
		end
		return ch
	end
	if brackets[ch] and (next_char == close or next_char == ch) and not balanced(before .. after, ch, close) then
		return ch
	end
	return insert_pair(ch, close)
end
function M.backspace()
	if active() then
		local before, after = context()
		local pairs_list = sequences()
		for open, close in pairs(brackets) do
			pairs_list[#pairs_list + 1] = { open, close }
		end
		for quote in pairs(quotes) do
			pairs_list[#pairs_list + 1] = { quote, quote }
		end
		for _, pair in ipairs(pairs_list) do
			if before:sub(-#pair[1]) == pair[1] and after:sub(1, #pair[2]) == pair[2] then
				return keys(string.rep("<BS>", #pair[1]) .. string.rep("<Del>", #pair[2]))
			end
		end
	end
	return keys("<BS>")
end
function M.enter()
	if not active() or vim.fn.pumvisible() ~= 0 then
		return keys("<CR>")
	end
	local before, after = context()
	local expand = brackets[before:sub(-1)] == after:sub(1, 1) and after ~= ""
		or quotes[before:sub(-1)] and before:sub(-1) == after:sub(1, 1)
	for _, pair in ipairs(sequences()) do
		if pair[1] ~= "<!--" and before:sub(-#pair[1]) == pair[1] and after:sub(1, #pair[2]) == pair[2] then
			expand = true
		end
	end
	if fences[vim.bo.filetype] and before:match("^%s*```[^`]*$") and after:match("^```") then
		expand = true
	end
	if tags[vim.bo.filetype] and before:match(">[%w%s]*$") and after:match("^%s*</") then
		expand = true
	end
	if expand then
		return keys("<C-g>u<CR><Cmd>normal! ==<CR><C-g>U<Up><End><CR>")
	end
	return keys("<CR>")
end
function M.setup(opts)
	M.config = vim.tbl_extend("force", M.config, opts or {})
	local options = { expr = true, replace_keycodes = false, desc = "FOX auto pairs" }
	for _, ch in ipairs({ "(", ")", "[", "]", "{", "}", "'", '"', "`", "-" }) do
		vim.keymap.set("i", ch, function()
			return M.type(ch)
		end, options)
	end
	vim.keymap.set("i", "<BS>", M.backspace, options)
	vim.keymap.set("i", "<CR>", M.enter, options)
end
return M
