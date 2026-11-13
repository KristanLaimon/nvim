-- ============================================================================
-- FOX PLUGIN: Git Review Annotation System
-- ============================================================================
-- WHAT IT DOES
--   Place typed notes (annotations) on any line while reviewing diffs in
--   Git Diff Mode or Git Log Diff Mode. Annotations persist per-project in
--   `.foxnvim/review/` as JSON and can be exported as structured Markdown
--   to the clipboard for sharing with AI agents.
--
-- USAGE
--   local review = require("plugins.fox.git.review")
--   review.ensure_session(cwd)          -- load active session or create one
--   review.add_annotation(file, line)   -- prompt for type + text
--   review.export_to_clipboard(cwd)     -- copy Markdown to clipboard
--   review.render_annotations(buf, file) -- draw virtual text badges
--   review.session_menu(cwd)            -- load/new/wipe sessions
--
-- STORAGE
--   `.foxnvim/review/session_<timestamp>.json` per project.
--   Annotations are keyed by file path + line number so they survive
--   git state changes (staging/unstaging the same file keeps annotations).
-- ============================================================================

local lazy_req = require("fox.core.lazy_require")
local path_util = lazy_req("fox.core.path")

local M = {}

-- ---------------------------------------------------------------------------
-- Namespace & state
-- ---------------------------------------------------------------------------

M.namespace = vim.api.nvim_create_namespace("fox_git_review")

--- In-memory annotations for the active session
--- @type table<int, {file:string, line:integer, type:string, text:string, timestamp:integer}>
M.annotations = {}

--- Active session filename (e.g. "session_1719000000") without extension
--- @type string|nil
M.active_session = nil

--- Random session name for export header
--- @type string|nil
M.session_name = nil

--- Random unique identifier for export header
--- @type string|nil
M.session_id = nil

-- ---------------------------------------------------------------------------
-- Adjectives & nouns for random session names
-- ---------------------------------------------------------------------------

local adjectives = {
	"Quick",
	"Silent",
	"Brave",
	"Clever",
	"Swift",
	"Bold",
	"Sharp",
	"Bright",
	"Cool",
	"Calm",
	"Keen",
	"Nimble",
	"Fierce",
	"Grand",
	"Neat",
	"Fine",
}
local nouns = {
	"Falcon",
	"Eagle",
	"Hawk",
	"Wolf",
	"Fox",
	"Owl",
	"Lynx",
	"Raven",
	"Shark",
	"Tiger",
	"Panda",
	"Koala",
	"Dingo",
	"Cobra",
	"Viper",
	"Drake",
}

local function random_session_name()
	return adjectives[math.random(#adjectives)] .. " " .. nouns[math.random(#nouns)]
end

local function random_uuid()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
		return string.format("%x", v)
	end)
end

-- ---------------------------------------------------------------------------
-- Review directory helpers
-- ---------------------------------------------------------------------------

--- Returns the full path to the .foxnvim/review/ directory, creating it if needed
--- @param cwd string
--- @return string
local function review_dir(cwd)
	local dir = path_util.join(cwd, ".foxnvim", "review")
	return path_util.ensure_dir(dir)
end

--- Returns the full path to a session JSON file
--- @param session_id string
--- @param cwd string
--- @return string
local function session_file_path(session_id, cwd)
	return path_util.join(review_dir(cwd), session_id .. ".json")
end

-- ---------------------------------------------------------------------------
-- Session persistence
-- ---------------------------------------------------------------------------

--- Loads annotations from a session JSON file into M.annotations
--- @param session_id string
--- @param cwd string
--- @return boolean success
function M.load_session(session_id, cwd)
	local fpath = session_file_path(session_id, cwd)
	if vim.fn.filereadable(fpath) ~= 1 then
		return false
	end

	local ok, content = pcall(vim.fn.readfile, fpath)
	if not ok or #content == 0 then
		return false
	end

	-- Join lines and parse JSON
	local json_text = table.concat(content, "\n")
	local parse_ok, data = pcall(vim.json.decode, json_text)
	if not parse_ok or not data or not data.annotations then
		return false
	end

	M.annotations = data.annotations
	M.active_session = session_id
	M.session_name = data.session_name or random_session_name()
	M.session_id = data.session_id or random_uuid()
	return true
end

--- Saves current annotations to the active session JSON file
--- @param cwd string
function M.save_session(cwd)
	if not M.active_session then
		return
	end

	local data = {
		session_id = M.session_id or random_uuid(),
		session_name = M.session_name or random_session_name(),
		created = os.time(),
		annotations = M.annotations,
	}

	local fpath = session_file_path(M.active_session, cwd)
	local json_text = vim.json.encode(data)
	vim.fn.writefile(vim.split(json_text, "\n"), fpath)
end

--- Creates a new empty session with a timestamp-based name
--- @param cwd string
function M.new_session(cwd)
	local timestamp = tostring(os.time())
	M.active_session = "session_" .. timestamp
	M.annotations = {}
	M.session_name = random_session_name()
	M.session_id = random_uuid()
	M.save_session(cwd)
end

--- Ensures there is an active session: loads last-used or creates a new one
--- @param cwd string
function M.ensure_session(cwd)
	-- Try to load the last-used session from a pointer file
	local rdir = review_dir(cwd)
	local pointer_file = path_util.join(rdir, ".active_session")

	if vim.fn.filereadable(pointer_file) == 1 then
		local lines = vim.fn.readfile(pointer_file)
		if lines and #lines > 0 then
			local last_session = lines[1]
			if M.load_session(last_session, cwd) then
				M.cleanup_stale_annotations(cwd)
				return
			end
		end
	end

	-- No active session found, try to load the most recent session file
	local sessions = M.list_sessions(cwd)
	if #sessions > 0 then
		-- Load the most recently modified session
		local latest = sessions[#sessions] -- sessions are sorted by time
		if M.load_session(latest.id, cwd) then
			M.cleanup_stale_annotations(cwd)
			return
		end
	end

	-- Create a brand new session
	M.new_session(cwd)
end

--- Saves the active session pointer so it can be restored on next open
--- @param cwd string
local function save_active_pointer(cwd)
	if not M.active_session then
		return
	end
	local rdir = review_dir(cwd)
	local pointer_file = path_util.join(rdir, ".active_session")
	vim.fn.writefile({ M.active_session }, pointer_file)
end

-- Override save_session to also save the pointer
local _orig_save_session = M.save_session
M.save_session = function(cwd)
	_orig_save_session(cwd)
	save_active_pointer(cwd)
end

-- ---------------------------------------------------------------------------
-- Session listing & management
-- ---------------------------------------------------------------------------

--- Lists all session files in the review directory
--- @param cwd string
--- @return table<{id:string, created:integer, annotation_count:integer}>
function M.list_sessions(cwd)
	local rdir = review_dir(cwd)
	local result = {}

	local ok, files = pcall(vim.fn.globpath, rdir, "*.json", false, true)
	if not ok or type(files) ~= "table" or #files == 0 then
		return result
	end

	for _, fpath in ipairs(files) do
		local fname = vim.fn.fnamemodify(fpath, ":t")
		if fname == ".active_session" then
			goto continue
		end
		local id = fname:match("^(.+)%..+$")
		if not id then
			goto continue
		end

		-- Try to read the session to get metadata
		local count = 0
		local created = 0
		if vim.fn.filereadable(fpath) == 1 then
			local lines = vim.fn.readfile(fpath)
			if lines and #lines > 0 then
				local json_text = table.concat(lines, "\n")
				local parse_ok, data = pcall(vim.json.decode, json_text)
				if parse_ok and data then
					count = data.annotations and #data.annotations or 0
					created = data.created or 0
				end
			end
		end

		table.insert(result, { id = id, created = created, annotation_count = count })
		::continue::
	end

	-- Sort by created time ascending
	table.sort(result, function(a, b)
		return a.created < b.created
	end)

	return result
end

--- Deletes a session file permanently
--- @param session_id string
--- @param cwd string
--- @return boolean success
function M.wipe_session(session_id, cwd)
	local fpath = session_file_path(session_id, cwd)
	if vim.fn.filereadable(fpath) == 1 then
		os.remove(fpath)
		return true
	end
	return false
end

--- Opens a floating menu to manage sessions (load, create new, wipe)
--- @param cwd string
function M.session_menu(cwd)
	local sessions = M.list_sessions(cwd)

	local choices = {}
	for _, s in ipairs(sessions) do
		local time_str = ""
		if s.created > 0 then
			time_str = " (" .. os.date("%Y-%m-%d %H:%M", s.created) .. ")"
		end
		table.insert(choices, {
			label = "Load " .. s.id .. time_str .. " (" .. s.annotation_count .. " notes)",
			value = "load:" .. s.id,
		})
		-- Add wipe option after each session
		table.insert(choices, {
			label = "   🗑 Wipe " .. s.id,
			value = "wipe:" .. s.id,
		})
	end

	table.insert(choices, {
		label = "Create New Session",
		value = "new",
	})

	if #choices == 0 then
		table.insert(choices, {
			label = "Create New Session",
			value = "new",
		})
	end

	vim.ui.select(choices, {
		prompt = "📝 Review Sessions",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if not choice then
			return
		end

		if choice.value == "new" then
			M.new_session(cwd)
			vim.notify("New review session created: " .. M.active_session, vim.log.levels.INFO, {
				title = "Git Review",
			})
		elseif choice.value:startswith("load:") then
			local session_id = choice.value:sub(6)
			if M.load_session(session_id, cwd) then
				M.cleanup_stale_annotations(cwd)
				vim.notify("Loaded session: " .. session_id, vim.log.levels.INFO, {
					title = "Git Review",
				})
				-- Re-render annotations in current buffer
				M._on_session_loaded()
			else
				vim.notify("Failed to load session: " .. session_id, vim.log.levels.WARN, {
					title = "Git Review",
				})
			end
		elseif choice.value:startswith("wipe:") then
			local session_id = choice.value:sub(6)
			vim.ui.select({ "Yes, delete", "Cancel" }, {
				prompt = "Confirm wipe: " .. session_id,
			}, function(confirm)
				if confirm == "Yes, delete" then
					if M.wipe_session(session_id, cwd) then
						-- If wiping the active session, reset state
						if M.active_session == session_id then
							M.annotations = {}
							M.active_session = nil
							M.session_name = nil
							M.session_id = nil
						end
						vim.notify("Deleted session: " .. session_id, vim.log.levels.INFO, {
							title = "Git Review",
						})
					else
						vim.notify("Session not found: " .. session_id, vim.log.levels.WARN, {
							title = "Git Review",
						})
					end
				end
			end)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Annotation CRUD
-- ---------------------------------------------------------------------------

--- Adds an annotation at the cursor position using inline input.
--- @param file_path string Relative file path
--- @param line_nr integer Line number (1-based)
--- @param cwd string Working directory
function M.add_annotation(file_path, line_nr, cwd)
	M.open_inline_annotation_input(file_path, line_nr, cwd)
end

--- Deletes the annotation at the cursor position
--- @param file_path string Relative file path
--- @param line_nr integer Line number (1-based)
--- @param cwd string Working directory
function M.delete_annotation(file_path, line_nr, cwd)
	for i, ann in ipairs(M.annotations) do
		if ann.file == file_path and ann.line == line_nr then
			table.remove(M.annotations, i)
			M.save_session(cwd)
			M.render_annotations_for_file(file_path)
			vim.notify("Annotation deleted at " .. file_path .. ":" .. line_nr, vim.log.levels.INFO, { title = "Git Review" })
			return
		end
	end

	vim.notify("No annotation found at this line", vim.log.levels.WARN, { title = "Git Review" })
end

--- Checks if there is an annotation at the given file:line
--- @param file_path string
--- @param line_nr integer
--- @return table|nil
function M.get_annotation(file_path, line_nr)
	for _, ann in ipairs(M.annotations) do
		if ann.file == file_path and ann.line == line_nr then
			return ann
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Visual markers (virtual text badges)
-- ---------------------------------------------------------------------------

--- Color map for annotation types
local type_colors = {
	SUGGESTION = "#FFCB6B", -- yellow
	ISSUE = "#F47067", -- red
	NOTE = "#73D5FF", -- blue
}

--- Ordered list of annotation types for cycling
local ANNOTATION_TYPES = { "SUGGESTION", "ISSUE", "NOTE" }

local function annotation_highlight(ann_type)
	local group = "FoxReview" .. ann_type
	vim.api.nvim_set_hl(0, group, { fg = type_colors[ann_type] or "#808080", bold = true })
	return group
end

-- ---------------------------------------------------------------------------
-- Inline annotation input (replaces the two-step select + modal)
-- ---------------------------------------------------------------------------

--- Opens an inline input at the cursor line for adding a review annotation.
--- The input appears below the current line with its type in the border title.
--- Tab/S-Tab cycles types, Enter saves, Ctrl-J inserts newline, Esc cancels.
--- @param file_path string Relative file path
--- @param line_nr integer Line number (1-based)
--- @param cwd string Working directory
function M.open_inline_annotation_input(file_path, line_nr, cwd)
	-- Ensure session exists
	if not M.active_session then
		M.ensure_session(cwd)
	end

	-- Check if there's already an annotation at this line
	for _, ann in ipairs(M.annotations) do
		if ann.file == file_path and ann.line == line_nr then
			vim.notify(
				"Annotation already exists at " .. file_path .. ":" .. line_nr,
				vim.log.levels.WARN,
				{ title = "Git Review" }
			)
			return
		end
	end

	local orig_win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(orig_win)

	-- Create the input buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "acwrite"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "foxreviewinput"
	vim.api.nvim_buf_set_name(buf, "Review Annotation Input")

	-- State for the inline input
	local current_type_idx = 1 -- Start with SUGGESTION
	local finished = false
	local win = nil -- Forward declare for use in finish()

	--- Creates custom highlight groups for annotation types
	local function setup_highlights()
		for _, ann_type in ipairs(ANNOTATION_TYPES) do
			annotation_highlight(ann_type)
		end
		vim.api.nvim_set_hl(0, "FoxReviewInputBg", { blend = 20 })
	end

	setup_highlights()

	--- Keeps the type in the border, separate from editable annotation text.
	local function update_type_highlight()
		if not win or not vim.api.nvim_win_is_valid(win) then
			return
		end
		local ann_type = ANNOTATION_TYPES[current_type_idx]
		vim.api.nvim_win_set_config(win, {
			title = string.format(" Add [%s] L%d (Tab/S-Tab:type Enter:save Ctrl-J:newline Esc:cancel) ", ann_type, line_nr),
			title_pos = "left",
		})
		vim.wo[win].winhighlight = "FloatBorder:FoxReview" .. ann_type .. ",FloatTitle:FoxReview" .. ann_type
	end

	--- Cycles to the next annotation type and updates the buffer
	local function cycle_type(forward)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		if forward then
			current_type_idx = current_type_idx >= #ANNOTATION_TYPES and 1 or current_type_idx + 1
		else
			current_type_idx = current_type_idx <= 1 and #ANNOTATION_TYPES or current_type_idx - 1
		end

		update_type_highlight()
	end

	--- Inserts a newline at the cursor position
	local function insert_newline()
		if not (vim.api.nvim_win_is_valid(orig_win) and vim.api.nvim_buf_is_valid(buf)) then
			return
		end
		local input_win = vim.api.nvim_get_current_win()
		local cur = vim.api.nvim_win_get_cursor(input_win)
		local cur_row, cur_col = cur[1], cur[2]
		local line = vim.api.nvim_buf_get_lines(buf, cur_row - 1, cur_row, false)[1] or ""
		vim.api.nvim_buf_set_lines(buf, cur_row - 1, cur_row, false, {
			line:sub(1, cur_col),
			line:sub(cur_col + 1),
		})
		vim.api.nvim_win_set_cursor(input_win, { cur_row + 1, 0 })
	end

	--- Finishes the input and saves the annotation
	local function finish(ok)
		if finished then
			return
		end
		finished = true

		-- Read the text BEFORE closing the buffer
		local text = ""
		local ann_type = ANNOTATION_TYPES[current_type_idx]
		if ok and vim.api.nvim_buf_is_valid(buf) then
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			text = table.concat(lines, "\n")
		end

		-- Stop insert mode and close the float window
		if vim.api.nvim_win_is_valid(win) then
			vim.cmd("stopinsert")
			pcall(vim.api.nvim_win_close, win, true)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(function()
				vim.bo[buf].modified = false
			end)
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
		if vim.api.nvim_win_is_valid(orig_win) then
			pcall(vim.api.nvim_set_current_win, orig_win)
		end

		if not ok then
			return
		end

		if not text or text:match("^%s*$") then
			return
		end

		-- Add annotation
		local annotation = {
			file = file_path,
			line = line_nr,
			type = ann_type,
			text = text,
			timestamp = os.time(),
		}
		table.insert(M.annotations, annotation)
		M.save_session(cwd)

		-- Re-render annotations on all open buffers that match this file
		M.render_annotations_for_file(file_path)

		vim.notify(
			"Annotation added: [" .. ann_type .. "] at " .. file_path .. ":" .. line_nr,
			vim.log.levels.INFO,
			{ title = "Git Review" }
		)
	end

	local width = math.max(1, math.min(110, vim.o.columns - 4))
	local height = 3
	-- Buffer anchoring accounts for scrolling, folds, wrapping and diff virtual lines.
	win = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		win = orig_win,
		bufpos = { cursor[1] - 1, 0 },
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = { "+", "-", "+", "|", "+", "-", "+", "|" },
		zindex = math.max(50, (vim.api.nvim_win_get_config(orig_win).zindex or 0) + 1),
	})

	-- Set window options for inline appearance
	for option, value in pairs({
		wrap = true,
		linebreak = true,
		scrolloff = 0,
		cursorline = true,
		signcolumn = "no",
		number = false,
		relativenumber = false,
	}) do
		pcall(vim.api.nvim_set_option_value, option, value, { win = win })
	end

	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	vim.cmd("startinsert!")

	-- Set up keymaps
	local kopts = { buffer = buf, noremap = true, silent = true, nowait = true }

	-- Enter to save
	vim.keymap.set({ "n", "i" }, "<CR>", function()
		finish(true)
	end, kopts)

	-- Ctrl-J works in terminals that cannot distinguish Shift+Enter.
	vim.keymap.set({ "n", "i" }, "<C-j>", insert_newline, kopts)
	vim.keymap.set({ "n", "i" }, "<S-CR>", insert_newline, kopts)
	vim.keymap.set({ "n", "i" }, "<S-Enter>", insert_newline, kopts)

	-- Tab to cycle forward
	vim.keymap.set({ "n", "i" }, "<Tab>", function()
		cycle_type(true)
	end, kopts)

	-- Shift+Tab to cycle backward
	vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
		cycle_type(false)
	end, kopts)

	-- q or Esc to cancel
	vim.keymap.set("n", "q", function()
		finish(false)
	end, kopts)
	vim.keymap.set({ "n", "i" }, "<Esc>", function()
		finish(false)
	end, kopts)

	-- BufWriteCmd confirms
	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = buf,
		callback = function()
			finish(true)
		end,
	})

	-- WinClosed cancels
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if finished then
				return
			end
			finished = true
			if vim.api.nvim_buf_is_valid(buf) then
				pcall(function()
					vim.bo[buf].modified = false
				end)
				pcall(vim.api.nvim_buf_delete, buf, { force = true })
			end
			if vim.api.nvim_win_is_valid(orig_win) then
				pcall(vim.api.nvim_set_current_win, orig_win)
			end
		end,
	})

	-- Initial highlight
	update_type_highlight()
end

local function annotation_box(ann, width, group)
	local title = string.format(" [%s] L%d ", ann.type, ann.line):sub(1, width - 4)
	local lines = { { { "+--" .. title .. string.rep("-", width - #title - 4) .. "+", group } } }
	local function body(text)
		lines[#lines + 1] = { { "| " .. text .. string.rep(" ", width - 4 - vim.fn.strdisplaywidth(text)) .. " |", group } }
	end
	body("")
	for _, text in ipairs(vim.split(ann.text, "\n", { plain = true })) do
		local wrapped = ""
		for _, char in ipairs(vim.fn.split(text:gsub("\t", "    "), "\\zs")) do
			if vim.fn.strdisplaywidth(wrapped .. char) > width - 4 then
				body(wrapped)
				wrapped = ""
			end
			wrapped = wrapped .. char
		end
		body(wrapped)
	end
	body("")
	lines[#lines + 1] = { { "+" .. string.rep("-", width - 2) .. "+", group } }
	return lines
end

--- Draws virtual annotation boxes below annotated lines for the given buffer
--- @param bufnr integer Buffer number
--- @param file_path string Relative file path
function M.render_annotations(bufnr, file_path)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Clear existing extmarks for this buffer in our namespace
	M.clear_buffer(bufnr)
	vim.b[bufnr].fox_review_file = file_path

	for _, ann in ipairs(M.annotations) do
		if ann.file == file_path then
			local row = math.max(0, ann.line - 1)
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			if row < line_count then
				local group = annotation_highlight(ann.type)
				local width = 80
				for _, win_id in ipairs(vim.fn.win_findbuf(bufnr)) do
					local info = vim.fn.getwininfo(win_id)[1]
					width = math.min(width, info.width - info.textoff)
				end
				local lines = annotation_box(ann, math.max(8, width), group)
				vim.api.nvim_buf_set_extmark(bufnr, M.namespace, row, 0, {
					virt_lines = lines,
					virt_lines_above = false,
					priority = 200,
				})
			end
		end
	end
end

--- Clears all extmarks from a buffer in the review namespace
--- @param bufnr integer
function M.clear_buffer(bufnr)
	if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.api.nvim_buf_clear_namespace, bufnr, M.namespace, 0, -1)
		vim.b[bufnr].fox_review_file = nil
	end
end

--- Re-render annotations on all open buffers that display the given file.
--- Used after adding or deleting an annotation so the badge appears immediately.
--- @param file_path string Relative file path
function M.render_annotations_for_file(file_path)
	if not file_path then
		return
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.b[buf].fox_review_file == file_path then
			M.render_annotations(buf, file_path)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Navigation between annotations
-- ---------------------------------------------------------------------------

--- Jumps to the next annotated line in the current buffer
--- @param file_path string Relative file path
function M.jump_next_annotation(file_path)
	if not file_path then
		return
	end

	local cur_line = vim.api.nvim_win_get_cursor(0)[1]
	local target_line = nil

	-- Find the next annotation after the current line
	for _, ann in ipairs(M.annotations) do
		if ann.file == file_path and ann.line > cur_line then
			if not target_line or ann.line < target_line then
				target_line = ann.line
			end
		end
	end

	-- Wrap around to the first annotation if no next one found
	if not target_line then
		for _, ann in ipairs(M.annotations) do
			if ann.file == file_path then
				if not target_line or ann.line < target_line then
					target_line = ann.line
				end
			end
		end
	end

	if target_line then
		pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
		pcall(vim.cmd, "normal! zz")
	else
		vim.notify("No annotations in this file", vim.log.levels.INFO, { title = "Git Review" })
	end
end

--- Jumps to the previous annotated line in the current buffer
--- @param file_path string Relative file path
function M.jump_prev_annotation(file_path)
	if not file_path then
		return
	end

	local cur_line = vim.api.nvim_win_get_cursor(0)[1]
	local target_line = nil

	-- Find the previous annotation before the current line
	for _, ann in ipairs(M.annotations) do
		if ann.file == file_path and ann.line < cur_line then
			if not target_line or ann.line > target_line then
				target_line = ann.line
			end
		end
	end

	-- Wrap around to the last annotation if no previous one found
	if not target_line then
		for _, ann in ipairs(M.annotations) do
			if ann.file == file_path then
				if not target_line or ann.line > target_line then
					target_line = ann.line
				end
			end
		end
	end

	if target_line then
		pcall(vim.api.nvim_win_set_cursor, 0, { target_line, 0 })
		pcall(vim.cmd, "normal! zz")
	else
		vim.notify("No annotations in this file", vim.log.levels.INFO, { title = "Git Review" })
	end
end

-- ---------------------------------------------------------------------------
-- Git file classification for export grouping
-- ---------------------------------------------------------------------------

--- Runs `git status --porcelain` to classify files as unstaged/staged
--- @param cwd string
--- @return table<string, string> file -> "unstaged" | "staged" | "both"
function M.classify_files(cwd)
	local git = lazy_req("fox.git.cmd")
	local status_lines = git.lines({ "status", "--porcelain" }, cwd)

	local file_states = {}
	for _, line in ipairs(status_lines) do
		if #line >= 2 then
			local x = line:sub(1, 1)
			local y = line:sub(2, 2)
			local file = line:sub(4)

			-- Handle renamed files (file -> new_file format)
			if file:find(" -> ") then
				file = file:match("(.+) -> .+") or file
			end

			-- Normalize path separators on Windows
			file = file:gsub("/", "\\")

			if file_states[file] then
				file_states[file] = "both"
			elseif x == "M" or x == "A" or x == "D" or x == "?" then
				-- Index column
				if y == " " then
					-- Staged only
					file_states[file] = "staged"
				elseif x == " " then
					-- Working tree only (unstaged)
					file_states[file] = "unstaged"
				else
					-- Both staged and unstaged
					file_states[file] = "both"
				end
			else
				file_states[file] = "unstaged"
			end
		end
	end

	return file_states
end

-- ---------------------------------------------------------------------------
-- Export to clipboard
-- ---------------------------------------------------------------------------

--- Exports all annotations as structured Markdown to clipboard
--- @param cwd string Working directory
--- @param extra_header? string Optional extra header line (e.g. commit hash for log_diff)
function M.export_to_clipboard(cwd, extra_header)
	if #M.annotations == 0 then
		vim.notify("No annotations to export", vim.log.levels.WARN, { title = "Git Review" })
		return
	end

	local file_states = M.classify_files(cwd)

	-- Group annotations by git state
	local unstaged = {}
	local staged = {}
	local other = {}

	for _, ann in ipairs(M.annotations) do
		local state = file_states[ann.file] or "other"
		if state == "unstaged" or state == "both" then
			table.insert(unstaged, ann)
		end
		if state == "staged" or state == "both" then
			table.insert(staged, ann)
		end
		if state == "other" then
			table.insert(other, ann)
		end
	end

	-- Build Markdown
	local lines = {}
	local session_label = M.session_name or "Unknown"
	local session_uuid = M.session_id or "no-id"

	table.insert(lines, "## Session: " .. session_label .. " | " .. session_uuid)
	table.insert(lines, "")
	table.insert(lines, "I reviewed your code and have the following comments. Please address them.")

	if extra_header then
		table.insert(lines, extra_header)
	end

	local function format_annotations(anns)
		local result = {}
		for i, ann in ipairs(anns) do
			local text_lines = vim.split(ann.text, "\n")
			local first_line = text_lines[1]
			local remaining = ""
			if #text_lines > 1 then
				remaining = "\n" .. table.concat(vim.list_slice(text_lines, 2, #text_lines), "\n   ")
			end
			table.insert(
				result,
				i .. ". [" .. ann.type .. "] `" .. ann.file .. ":" .. ann.line .. "` - " .. first_line .. remaining
			)
		end
		return result
	end

	if #unstaged > 0 then
		table.insert(lines, "")
		table.insert(lines, "======================================================================")
		table.insert(lines, "Reviewing unstaged changes:")
		for _, line in ipairs(format_annotations(unstaged)) do
			table.insert(lines, line)
		end
		table.insert(lines, "======================================================================")
	end

	if #staged > 0 then
		table.insert(lines, "")
		table.insert(lines, "======================================================================")
		table.insert(lines, "Reviewing staged changes:")
		for _, line in ipairs(format_annotations(staged)) do
			table.insert(lines, line)
		end
		table.insert(lines, "======================================================================")
	end

	if #other > 0 then
		table.insert(lines, "")
		table.insert(lines, "======================================================================")
		table.insert(lines, "Other files:")
		for _, line in ipairs(format_annotations(other)) do
			table.insert(lines, line)
		end
		table.insert(lines, "======================================================================")
	end

	local markdown = table.concat(lines, "\n")

	-- Copy to both + and * registers for cross-platform compatibility
	vim.fn.setreg("+", markdown)
	vim.fn.setreg("*", markdown)

	vim.notify(
		"Exported " .. #M.annotations .. " annotations to clipboard",
		vim.log.levels.INFO,
		{ title = "Git Review" }
	)
end

-- ---------------------------------------------------------------------------
-- Stale annotation cleanup
-- ---------------------------------------------------------------------------

--- Removes annotation entries where the referenced file no longer exists on disk
--- @param cwd string
function M.cleanup_stale_annotations(cwd)
	if #M.annotations == 0 then
		return
	end

	local cleaned = false
	local result = {}
	for _, ann in ipairs(M.annotations) do
		local full_path = path_util.join(cwd, ann.file)
		if vim.fn.filereadable(full_path) == 1 then
			table.insert(result, ann)
		else
			cleaned = true
		end
	end

	if cleaned then
		M.annotations = result
		M.save_session(cwd)
	end
end

-- ---------------------------------------------------------------------------
-- Callback hooks (set by diff_mode.lua / log_diff.lua after requiring this module)
-- ---------------------------------------------------------------------------

--- Called after an annotation is added or deleted to re-render
M._on_annotation_added = function()
	-- Default no-op; overridden by diff_mode.lua / log_diff.lua
end

--- Called after a session is loaded to re-render
M._on_session_loaded = function()
	-- Default no-op; overridden by diff_mode.lua / log_diff.lua
end

return setmetatable({
	name = "fox_git_review",
	dir = require("fox.core.lazyspec").for_module(),
	cmd = {},
	config = function()
		-- No setup needed; review.lua is a library module required by diff_mode and log_diff
	end,
}, { __index = M })
