local M = rawget(_G, "FOX_PROJECT_SEARCH") or {}
rawset(_G, "FOX_PROJECT_SEARCH", M)
local engine = require("fox.core.project_replace")
local preview = require("fox.core.preview_tab")
local ns = vim.api.nvim_create_namespace("fox_project_search")
local match_ns = vim.api.nvim_create_namespace("fox_project_search_match")

local function notify(message)
	vim.notify(tostring(message), vim.log.levels.ERROR, { title = "Project Search" })
end

local function field(state, index)
	return table.concat(vim.api.nvim_buf_get_lines(state.fields[index].buf, 0, -1, false), "\n")
end

local function clear_match(state)
	if state.marked and vim.api.nvim_buf_is_valid(state.marked) then
		vim.api.nvim_buf_clear_namespace(state.marked, match_ns, 0, -1)
	end
	state.marked = nil
end

function M.close()
	local state = M.state
	if not state then
		return
	end
	M.state = nil
	state.generation = state.generation + 1
	if state.process then
		pcall(state.process.kill, state.process, 15)
	end
	clear_match(state)
	preview.close(state.preview)
	vim.api.nvim_del_augroup_by_id(state.group)
	local live = {}
	for _, item in ipairs(state.fields) do
		if vim.api.nvim_win_is_valid(item.win) then
			live[#live + 1] = item.win
		end
	end
	if #live > 0 and vim.api.nvim_tabpage_is_valid(state.tab) and #vim.api.nvim_tabpage_list_wins(state.tab) == #live then
		-- If the editor was closed, turn the last sidebar pane back into an editor.
		local buf = vim.api.nvim_buf_is_valid(state.preview.original) and state.preview.original
			or vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(live[1], buf)
		vim.wo[live[1]].winbar = ""
		vim.wo[live[1]].winfixwidth, vim.wo[live[1]].winfixheight = false, false
	end
	for _, item in ipairs(state.fields) do
		if vim.api.nvim_win_is_valid(item.win) and vim.api.nvim_win_get_buf(item.win) == item.buf then
			vim.api.nvim_win_close(item.win, true)
		end
		if vim.api.nvim_buf_is_valid(item.buf) then
			vim.api.nvim_buf_delete(item.buf, { force = true })
		end
	end
end

function M.focus(index, insert)
	local state = M.state
	if state and state.fields[index] and vim.api.nvim_win_is_valid(state.fields[index].win) then
		vim.cmd("stopinsert")
		vim.api.nvim_set_current_win(state.fields[index].win)
		if insert and index < 4 then
			vim.cmd("startinsert!")
		end
	end
end

function M.preview_selected(focus)
	local state = M.state
	if not state or not state.plan then
		return
	end
	local row = state.rows[vim.api.nvim_win_get_cursor(state.fields[4].win)[1]]
	if not row then
		return
	end
	if not row.match then
		row = { file = row.file, match = row.file.matches[1], span = row.file.matches[1].spans[1] }
	end
	local editor = state.preview.win
	if not vim.api.nvim_win_is_valid(editor) then
		editor = require("fox.core.dock").find_code_win()
	end
	if not editor then
		return
	end
	clear_match(state)
	local ok, buf = pcall(preview.show, state.preview, row.file.filename, editor)
	if not ok then
		notify(buf)
		return
	end
	state.marked = buf
	local line = math.min(row.match.line, vim.api.nvim_buf_line_count(buf))
	local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
	local first = math.min(row.span[1], #text)
	local last = math.min(math.max(row.span[2], first + 1), #text)
	vim.api.nvim_buf_set_extmark(buf, match_ns, line - 1, first, {
		end_col = last,
		hl_group = "IncSearch",
		line_hl_group = "CursorLine",
		priority = 200,
	})
	vim.api.nvim_win_set_cursor(editor, { line, first })
	vim.api.nvim_win_call(editor, function()
		vim.cmd("normal! zz")
	end)
	if focus then
		vim.api.nvim_set_current_win(editor)
	end
end

local function render(state)
	if M.state ~= state or not state.fields[4] or not vim.api.nvim_buf_is_valid(state.fields[4].buf) then
		return
	end
	local flags = string.format(
		"[gc] Aa:%s  [gr] Regex:%s  [gw] Word:%s",
		state.case_sensitive and "on" or "off",
		state.regex and "on" or "off",
		state.word and "on" or "off"
	)
	local lines = { flags, "[a] Apply  [gR] Replace on/off  [o] Keep file  [q] Close", "" }
	local marks = {}
	state.rows = {}
	if state.plan then
		lines[#lines + 1] =
			string.format("%d results in %d files | %d skipped", state.plan.count, #state.plan.files, state.plan.skipped)
		lines[#lines + 1] = ""
		for _, file in ipairs(state.plan.files) do
			local file_buf = file.buf or vim.fn.bufnr(file.filename)
			local count = 0
			for _, match in ipairs(file.matches) do
				count = count + #match.spans
			end
			local collapsed = state.collapsed[file.filename]
			lines[#lines + 1] = string.format(
				"%s [%s] %s%s%s (%d)",
				collapsed and ">" or "v",
				file.selected and "x" or " ",
				file.relative,
				file_buf > 0 and vim.api.nvim_buf_is_loaded(file_buf) and vim.bo[file_buf].modified and " M" or "",
				file.replacement_error and " [search only]" or "",
				count
			)
			state.rows[#lines] = { file = file }
			marks[#marks + 1] = { #lines - 1, "Directory" }
			if not collapsed then
				for _, match in ipairs(file.matches) do
					for _, span in ipairs(match.spans) do
						local start = math.max(0, vim.fn.charidx(match.before, span[1]) - 16)
						local snippet = (start > 0 and "..." or "")
							.. vim.fn.strcharpart(match.before, start, math.max(10, state.width - 12))
						lines[#lines + 1] = string.format("  |-%d: %s", match.line, snippet)
						state.rows[#lines] = { file = file, match = match, span = span }
						if state.replacing then
							lines[#lines + 1] = "  | + " .. vim.fn.strcharpart(match.after, 0, math.max(10, state.width - 8))
							state.rows[#lines] = { file = file, match = match, span = span }
							marks[#marks + 1] = { #lines - 1, "DiffAdd" }
						end
					end
				end
			end
			lines[#lines + 1] = ""
		end
	else
		lines[#lines + 1] = state.status or "Enter search text in section 1."
	end
	local buf = state.fields[4].buf
	for index, line in ipairs(lines) do
		lines[index] = line:gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("%z", "\\0")
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, mark in ipairs(marks) do
		vim.api.nvim_buf_set_extmark(buf, ns, mark[1], 0, { line_hl_group = mark[2] })
	end
end

function M.refresh(immediate)
	local state = M.state
	if not state then
		return
	end
	for _, item in ipairs(state.fields) do
		if not vim.api.nvim_buf_is_valid(item.buf) then
			return
		end
	end
	state.generation = state.generation + 1
	local generation = state.generation
	if state.process then
		pcall(state.process.kill, state.process, 15)
		state.process = nil
	end
	state.plan = nil
	clear_match(state)
	local search, replacement, glob = field(state, 1), field(state, 2), field(state, 3)
	state.status = search == "" and "Enter search text in section 1." or "Searching..."
	render(state)
	if search == "" then
		return
	end
	local options = {
		case_sensitive = state.case_sensitive,
		regex = state.regex,
		word = state.word,
		include_unsaved = true,
		lazy = true,
		yield = coroutine.yield,
	}
	local work = coroutine.create(function()
		return engine.preview(state.root, search, replacement, glob, options)
	end)
	local function step()
		if M.state ~= state or state.generation ~= generation then
			return
		end
		local ok, result = coroutine.resume(work)
		if not ok then
			state.status = "Search failed: " .. tostring(result)
		elseif coroutine.status(work) ~= "dead" then
			vim.schedule(step)
			return
		else
			state.plan = result
		end
		render(state)
	end
	local function start()
		if M.state ~= state or state.generation ~= generation then
			return
		end
		if vim.fn.executable("rg") ~= 1 then
			step()
			return
		end
		local ok, process = pcall(vim.system, engine.command(search, options), { cwd = state.root }, function(result)
			vim.schedule(function()
				if M.state ~= state or state.generation ~= generation then
					return
				end
				state.process = nil
				if result.code ~= 0 and result.code ~= 1 then
					state.status = "Search failed: " .. (result.stderr or "rg failed")
					render(state)
					return
				end
				options.files = vim.split(result.stdout or "", "\0", { plain = true, trimempty = true })
				step()
			end)
		end)
		if ok then
			state.process = process
		else
			state.status = "Search failed: " .. tostring(process)
			render(state)
		end
	end
	if immediate then
		start()
	else
		vim.defer_fn(start, 180)
	end
end

local function fold(state, expand)
	local row = state.rows[vim.api.nvim_win_get_cursor(state.fields[4].win)[1]]
	if row then
		if expand == nil then
			state.collapsed[row.file.filename] = not state.collapsed[row.file.filename]
		else
			state.collapsed[row.file.filename] = not expand
		end
		render(state)
		for line, item in pairs(state.rows) do
			if item.file == row.file and not item.match then
				vim.api.nvim_win_set_cursor(state.fields[4].win, { line, 0 })
				break
			end
		end
	end
end

function M.open(replacing)
	if M.state then
		if M.state.tab == vim.api.nvim_get_current_tabpage() then
			M.state.replacing = replacing == true or M.state.replacing
			M.focus(replacing and 2 or 1)
			render(M.state)
			return
		end
		M.close()
	end
	local editor = require("fox.core.dock").find_code_win()
	if not editor then
		vim.cmd("aboveleft vnew")
		editor = vim.api.nvim_get_current_win()
	end
	local state = {
		root = vim.fn.getcwd(),
		tab = vim.api.nvim_get_current_tabpage(),
		preview = preview.new("Search", editor),
		fields = {},
		rows = {},
		collapsed = {},
		generation = 0,
		width = math.min(60, math.max(28, math.floor(vim.o.columns * 0.35))),
		replacing = replacing == true,
		case_sensitive = false,
		regex = false,
		word = false,
		group = vim.api.nvim_create_augroup("FoxProjectSearch", { clear = true }),
	}
	M.state = state
	local below
	for index = 4, 1, -1 do
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].filetype = index == 4 and "fox_search_results" or "fox_search_input"
		vim.api.nvim_buf_set_name(buf, "fox-search://" .. buf)
		local win = vim.api.nvim_open_win(
			buf,
			false,
			below and { win = below, split = "above", height = 1 } or { win = -1, split = "right", width = state.width }
		)
		state.fields[index] = { buf = buf, win = win }
		below = win
		vim.wo[win].winfixwidth = true
		vim.wo[win].winfixheight = index ~= 4
		vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].wrap = false, false, false
		vim.wo[win].signcolumn, vim.wo[win].foldcolumn, vim.wo[win].spell = "no", "0", false
		vim.wo[win].winbar = ({ "1 Search", "2 Replace", "3 Files (glob)", "4 Results" })[index]
		vim.wo[win].cursorline = index == 4
		if index == 3 then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "*" })
		end
		local function map(key, callback, description, modes)
			vim.keymap.set(modes or "n", key, callback, { buffer = buf, silent = true, nowait = true, desc = description })
		end
		for section = 1, 4 do
			map(tostring(section), function()
				M.focus(section)
			end, "Focus search section " .. section)
		end
		map("<Tab>", function()
			M.focus(index % 4 + 1, vim.fn.mode():sub(1, 1) == "i")
		end, "Next search section", { "n", "i" })
		map("<S-Tab>", function()
			M.focus((index + 2) % 4 + 1, vim.fn.mode():sub(1, 1) == "i")
		end, "Previous search section", { "n", "i" })
		map("q", M.close, "Close project search")
		map("gc", function()
			state.case_sensitive = not state.case_sensitive
			M.refresh(true)
		end, "Toggle match case")
		map("gr", function()
			state.regex = not state.regex
			M.refresh(true)
		end, "Toggle Vim regex")
		map("gw", function()
			state.word = not state.word
			M.refresh(true)
		end, "Toggle whole word")
		map("gR", function()
			state.replacing = not state.replacing
			render(state)
		end, "Toggle replacement preview")
		if index ~= 4 then
			map("<CR>", function()
				M.refresh(true)
				M.focus(4)
			end, "Search project", { "n", "i" })
			vim.api.nvim_buf_attach(buf, false, {
				on_lines = function()
					vim.schedule(function()
						if M.state == state then
							if index == 2 then
								state.replacing = true
							end
							M.refresh()
						end
					end)
				end,
			})
		else
			map("<CR>", function()
				local row = state.rows[vim.api.nvim_win_get_cursor(win)[1]]
				if row and not row.match then
					fold(state)
				else
					M.preview_selected(true)
				end
			end, "Focus match in editor")
			map("l", function()
				local row = state.rows[vim.api.nvim_win_get_cursor(win)[1]]
				if row and not row.match then
					fold(state, true)
				else
					M.preview_selected(true)
				end
			end, "Expand file or focus match")
			map("h", function()
				fold(state, false)
			end, "Collapse file")
			map("za", function()
				fold(state)
			end, "Toggle file fold")
			map("zM", function()
				for _, file in ipairs(state.plan and state.plan.files or {}) do
					state.collapsed[file.filename] = true
				end
				render(state)
			end, "Collapse all files")
			map("zR", function()
				state.collapsed = {}
				render(state)
			end, "Expand all files")
			map("<Space>", function()
				local row = state.rows[vim.api.nvim_win_get_cursor(win)[1]]
				if row then
					if row.file.replacement_error then
						notify(row.file.replacement_error .. "; this file is searchable but cannot safely be replaced")
						return
					end
					row.file.selected = not row.file.selected
					render(state)
				end
			end, "Select file for replacement")
			map("a", function()
				if not state.replacing or not state.plan then
					notify("Enable replacement preview with gR first")
					return
				end
				local ok, count = pcall(engine.apply, state.plan)
				if ok then
					vim.notify(string.format("Replaced in %d files", count))
					M.refresh(true)
				else
					notify(count)
				end
			end, "Apply selected replacements")
			map("o", function()
				M.preview_selected(true)
				preview.keep(state.preview)
			end, "Keep file as a normal editor tab")
			map("r", function()
				M.refresh(true)
			end, "Refresh project search")
			vim.api.nvim_create_autocmd("CursorMoved", {
				group = state.group,
				buffer = buf,
				callback = function()
					M.preview_selected(false)
				end,
			})
		end
		vim.api.nvim_create_autocmd("WinClosed", {
			group = state.group,
			pattern = tostring(win),
			callback = function()
				vim.schedule(function()
					if M.state == state then
						M.close()
					end
				end)
			end,
		})
	end
	vim.api.nvim_create_autocmd("DirChanged", { group = state.group, callback = M.close })
	render(state)
	M.focus(1)
end

local function open_shortcut()
	vim.cmd("stopinsert")
	vim.cmd("ProjectReplace")
end

return setmetatable({
	name = "fox_project_replace",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = { "ProjectSearch", "ProjectReplace", "ProjectSearchClose" },
	keys = {
		{ "<C-f>", "<Cmd>ProjectSearch<CR>", mode = { "n", "i", "x" }, desc = "Project Search Sidebar" },
		{
			"<C-S-m>",
			open_shortcut,
			mode = { "n", "i", "x", "t" },
			desc = "Project-wide Replace Preview",
		},
		{
			"<F9>",
			open_shortcut,
			mode = { "n", "i", "x", "t" },
			desc = "Project-wide Replace Preview",
		},
		{
			"\x1b[77;6u",
			open_shortcut,
			mode = { "n", "i", "x", "t" },
			desc = "Project-wide Replace Preview",
		},
		{
			"<C-A-r>",
			open_shortcut,
			mode = { "n", "i", "x", "t" },
			desc = "Project-wide Replace Preview",
		},
		{
			"\x1b[114;7u",
			open_shortcut,
			mode = { "n", "i", "x", "t" },
			desc = "Project-wide Replace Preview",
		},
	},
	config = function()
		vim.api.nvim_create_user_command("ProjectReplace", function()
			M.open(true)
		end, { desc = "Project search and replace sidebar" })
		vim.api.nvim_create_user_command("ProjectSearch", function()
			M.open(false)
		end, { desc = "Project search sidebar" })
		vim.api.nvim_create_user_command("ProjectSearchClose", M.close, { desc = "Close project search sidebar" })
	end,
}, { __index = M })
