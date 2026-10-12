-- Native Kitty graphics live in the host TUI, never inside a :terminal PTY.
local M = {}
local uv = vim.uv or vim.loop
local states = {}
local visible
local serial = 10000
local images = {
	png = true,
	jpg = true,
	jpeg = true,
	gif = true,
	webp = true,
	bmp = true,
	ico = true,
	svg = true,
	tiff = true,
	tif = true,
	avif = true,
	heic = true,
	jxl = true,
}
local videos = {
	mp4 = true,
	mkv = true,
	avi = true,
	mov = true,
	wmv = true,
	flv = true,
	webm = true,
	m4v = true,
	["3gp"] = true,
	ogv = true,
}

function M.is_available()
	if vim.g.neovide or vim.env.TMUX or not vim.api.nvim_ui_send then
		return false
	end
	if not (vim.env.KITTY_WINDOW_ID or vim.env.TERM == "xterm-kitty") then
		return false
	end
	if vim.fn.executable("kitten") ~= 1 and vim.fn.executable("kitty") ~= 1 then
		return false
	end
	for _, ui in ipairs(vim.api.nvim_list_uis()) do
		if ui.stdout_tty then
			return true
		end
	end
	return false
end

function M.classify(filepath)
	local stat = uv.fs_stat(filepath)
	if not stat or stat.type ~= "file" then
		return nil
	end
	local ext = vim.fn.fnamemodify(filepath, ":e"):lower()
	if images[ext] then
		return "image"
	end
	if videos[ext] then
		return "video"
	end
	if ext == "pdf" then
		return "pdf"
	end
	local f = io.open(filepath, "rb")
	if not f then
		return nil
	end
	local sample = f:read(8192) or ""
	f:close()
	-- Extensionless assets still get their native visual preview.
	if
		sample:sub(1, 8) == "\137PNG\r\n\26\n"
		or sample:sub(1, 3) == "\255\216\255"
		or sample:sub(1, 6) == "GIF87a"
		or sample:sub(1, 6) == "GIF89a"
		or (sample:sub(1, 4) == "RIFF" and sample:sub(9, 12) == "WEBP")
	then
		return "image"
	end
	if sample:sub(1, 5) == "%PDF-" then
		return "pdf"
	end
	if sample:find("\0", 1, true) then
		return "binary"
	end
	return nil
end

function M.hex_lines(data)
	local lines = {}
	for offset = 1, #data, 16 do
		local bytes, chars = {}, {}
		for i = offset, math.min(offset + 15, #data) do
			local b = data:byte(i)
			bytes[#bytes + 1] = string.format("%02x", b)
			chars[#chars + 1] = b >= 32 and b <= 126 and string.char(b) or "."
		end
		lines[#lines + 1] = string.format("%08x  %-47s  |%s|", offset - 1, table.concat(bytes, " "), table.concat(chars))
	end
	return lines
end

local function send(data)
	vim.api.nvim_ui_send(data)
end

local function delete_image(state)
	if state then
		send("\27_Ga=d,d=I,i=" .. state.id .. ",q=2\27\\")
	end
end

function M.frame_update(content, previous_id)
	local retire = previous_id and ("\27_Ga=d,d=I,i=" .. previous_id .. ",q=2\27\\") or ""
	return "\27[?2026h\27" .. "7" .. content .. retire .. "\27" .. "8\27[?2026l"
end

local function cancel_pending(state)
	state.generation = state.generation + 1
	if state.job then
		state.job:kill(15)
		state.job = nil
	end
end

local function stop(state)
	cancel_pending(state)
	delete_image(state)
	if visible == state then
		visible = nil
	end
end

local function lines(state, content)
	if not vim.api.nvim_buf_is_valid(state.preview) then
		return
	end
	vim.bo[state.preview].modifiable = true
	vim.api.nvim_buf_set_lines(state.preview, 0, -1, false, content)
	vim.bo[state.preview].modifiable = false
	vim.bo[state.preview].modified = false
end

local function icat()
	return vim.fn.executable("kitten") == 1 and { "kitten", "icat" } or { "kitty", "+kitten", "icat" }
end

-- Only ioctl: no terminal queries or reads competing with Neovim input.
local winsize_script = [[import os,fcntl,termios,struct,json
fd=os.open('/dev/tty',os.O_RDONLY|os.O_NOCTTY)
r,c,x,y=struct.unpack('HHHH',fcntl.ioctl(fd,termios.TIOCGWINSZ,b'\0'*8))
os.close(fd)
print(json.dumps([c,r,x,y]))]]

-- Some Kitty launches expose rows/columns but omit the ioctl pixel fields.
-- icat still needs a complete geometry: estimate cell pixels in that case.
-- Placement stays constrained to the real Neovim window in character cells.
function M.resolve_window_size(output)
	local ok, size = pcall(vim.json.decode, output or "")
	if not ok or type(size) ~= "table" then
		size = {}
	end
	local function positive(value, fallback)
		return type(value) == "number" and value > 0 and math.floor(value) or fallback
	end
	local columns = positive(size[1], math.max(1, vim.o.columns))
	local rows = positive(size[2], math.max(1, vim.o.lines))
	return { columns, rows, positive(size[3], columns * 10), positive(size[4], rows * 20) }
end

local function run(state, argv, callback)
	local generation = state.generation
	local ok, job = pcall(vim.system, argv, { text = false }, function(result)
		vim.schedule(function()
			if generation ~= state.generation or not vim.api.nvim_buf_is_valid(state.preview) then
				return
			end
			state.job = nil
			callback(result)
		end)
	end)
	if ok then
		state.job = job
	else
		lines(state, { "Preview could not start: " .. tostring(job), "F4: inspect file bytes" })
	end
end

-- Fit the image first, then zoom and crop a movable viewport from it.
function M.crop_geometry(image_width, image_height, view_width, view_height, zoom, pan_x, pan_y)
	local fit = math.min(view_width / image_width, view_height / image_height)
	local width = math.max(1, math.floor(image_width * fit * zoom))
	local height = math.max(1, math.floor(image_height * fit * zoom))
	local crop_width, crop_height = math.min(width, view_width), math.min(height, view_height)
	local x = math.floor((width - crop_width) * (pan_x + 1) / 2)
	local y = math.floor((height - crop_height) * (pan_y + 1) / 2)
	return width, height, crop_width, crop_height, x, y
end

local function prepare_view(state, image, size, width, height, callback)
	if (state.zoom or 1) == 1 then
		callback(image)
		return
	end
	local magick = vim.fn.exepath("magick")
	if magick == "" then
		vim.notify("Image zoom and pan need ImageMagick (magick).", vim.log.levels.WARN, { timeout = 900 })
		callback(image)
		return
	end
	local function crop(dimensions)
		local w, h, cw, ch, x, y = M.crop_geometry(
			dimensions[1],
			dimensions[2],
			math.max(1, math.floor(width * size[3] / size[1])),
			math.max(1, math.floor(height * size[4] / size[2])),
			state.zoom,
			state.pan_x or 0,
			state.pan_y or 0
		)
		state.view_temp = state.view_temp or vim.fn.tempname() .. ".png"
		run(state, {
			magick,
			image .. "[0]",
			"-resize",
			w .. "x" .. h .. "!",
			"-crop",
			cw .. "x" .. ch .. "+" .. x .. "+" .. y,
			"+repage",
			state.view_temp,
		}, function(result)
			if result.code == 0 then
				callback(state.view_temp)
			else
				callback(image)
			end
		end)
	end
	if state.dimensions then
		crop(state.dimensions)
		return
	end
	run(state, { magick, "identify", "-format", "%w %h", image .. "[0]" }, function(result)
		local w, h = (result.stdout or ""):match("^(%d+) (%d+)")
		if result.code ~= 0 or not w or not h then
			callback(image)
			return
		end
		state.dimensions = { tonumber(w), tonumber(h) }
		crop(state.dimensions)
	end)
end

local function preview_window(state)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(win) == state.preview then
			return win
		end
	end
end

function M.render(state)
	local win = preview_window(state)
	if not win then
		return
	end
	if visible == state then
		-- Keep the displayed frame while its replacement is prepared.
		cancel_pending(state)
	elseif visible then
		stop(visible)
	end
	visible = state
	state.generation = state.generation + 1
	serial = serial + 1
	local next_image_id = serial
	if state.kind == "binary" then
		return
	end
	local function display(image)
		local function with_size(geometry_output)
			local size = M.resolve_window_size(geometry_output)
			if
				not vim.api.nvim_win_is_valid(win)
				or vim.api.nvim_win_get_buf(win) ~= state.preview
				or vim.api.nvim_win_get_tabpage(win) ~= vim.api.nvim_get_current_tabpage()
			then
				return
			end
			local pos = vim.api.nvim_win_get_position(win)
			local width = vim.api.nvim_win_get_width(win)
			local height = math.max(1, vim.api.nvim_win_get_height(win))
			prepare_view(state, image, size, width, height, function(view_image)
				local cmd = icat()
				vim.list_extend(cmd, {
					"--stdin=no",
					"--transfer-mode=stream",
					"--passthrough=none",
					"--z-index=-1",
					"--use-window-size=" .. table.concat(size, ","),
					"--image-id=" .. next_image_id,
					"--place=" .. width .. "x" .. height .. "@" .. pos[2] .. "x" .. pos[1],
					"--loop=-1",
					view_image,
				})
				run(state, cmd, function(output)
					if output.code ~= 0 then
						lines(state, {
							"Kitty could not decode this file.",
							(output.stderr or ""):gsub("[\r\n]+", " "),
							"F4: inspect bytes; Ctrl+Shift+Enter: external app",
						})
						return
					end
					-- Upload a separate image, then retire the old one in the same
					-- synchronized terminal update. No blank frame between views.
					send(M.frame_update(output.stdout, state.id))
					state.id = next_image_id
				end)
			end)
		end
		if vim.fn.executable("python3") == 1 then
			run(state, { "python3", "-c", winsize_script }, function(result)
				with_size(result.code == 0 and result.stdout or nil)
			end)
		else
			with_size(nil)
		end
	end
	if state.kind == "image" then
		display(state.path)
		return
	end
	local converter = state.kind == "video" and "ffmpeg" or "pdftoppm"
	if vim.fn.executable(converter) ~= 1 then
		lines(state, { "Preview requires " .. converter .. ".", "F4: inspect bytes; Ctrl+Shift+Enter: external app" })
		return
	end
	if state.converted then
		display(state.converted)
		return
	end
	state.temp = state.temp or vim.fn.tempname() .. ".png"
	local cmd = state.kind == "video"
			and { "ffmpeg", "-nostdin", "-v", "error", "-y", "-i", state.path, "-frames:v", "1", state.temp }
		or { "pdftoppm", "-f", "1", "-singlefile", "-scale-to", "1600", "-png", state.path, state.temp:sub(1, -5) }
	run(state, cmd, function(result)
		if result.code == 0 then
			state.converted = state.temp
			display(state.temp)
		else
			lines(state, { "Could not create media preview.", "F4: inspect file bytes" })
		end
	end)
end

function M.preview()
	local buf = vim.api.nvim_get_current_buf()
	local state = states[buf]
	if state then
		if buf == state.source then
			M.toggle()
		else
			M.render(state)
		end
	else
		M.open(buf)
	end
end

local window_keys = { "number", "relativenumber", "signcolumn", "cursorline", "wrap" }
local function enter_preview(state, win)
	state.windows = state.windows or {}
	if not state.windows[win] then
		local saved = {}
		for _, key in ipairs(window_keys) do
			saved[key] = vim.wo[win][key]
		end
		state.windows[win] = saved
	end
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].cursorline = false
	vim.wo[win].wrap = false
end
local function leave_preview(state, win)
	local saved = state.windows and state.windows[win]
	if saved and vim.api.nvim_win_is_valid(win) then
		for key, value in pairs(saved) do
			vim.wo[win][key] = value
		end
		state.windows[win] = nil
	end
end

local function queue_view(state)
	if state.view_pending then
		return
	end
	state.view_pending = true
	vim.defer_fn(function()
		state.view_pending = false
		if vim.api.nvim_buf_is_valid(state.preview) and preview_window(state) then
			M.render(state)
		end
	end, 50)
end

function M.zoom(factor)
	local state = states[vim.api.nvim_get_current_buf()]
	if not state or state.kind == "binary" or vim.api.nvim_get_current_buf() ~= state.preview then
		return
	end
	if factor ~= 0 and vim.fn.executable("magick") ~= 1 then
		vim.notify("Image zoom and pan need ImageMagick (magick).", vim.log.levels.WARN, { timeout = 900 })
		return
	end
	state.zoom = factor == 0 and 1 or math.max(1, math.min(16, (state.zoom or 1) * factor))
	if state.zoom == 1 then
		state.pan_x, state.pan_y = 0, 0
	end
	queue_view(state)
end

function M.pan(dx, dy)
	local state = states[vim.api.nvim_get_current_buf()]
	if not state or (state.zoom or 1) == 1 or vim.api.nvim_get_current_buf() ~= state.preview then
		return
	end
	state.pan_x = math.max(-1, math.min(1, (state.pan_x or 0) + dx))
	state.pan_y = math.max(-1, math.min(1, (state.pan_y or 0) + dy))
	queue_view(state)
end

local function bind_controls(buf)
	local opts = { buffer = buf, silent = true }
	for _, key in ipairs({ "+", "=", "<ScrollWheelUp>", "<C-ScrollWheelUp>" }) do
		vim.keymap.set("n", key, function()
			M.zoom(1.25)
		end, vim.tbl_extend("force", opts, { desc = "Zoom image in" }))
	end
	for _, key in ipairs({ "-", "<ScrollWheelDown>", "<C-ScrollWheelDown>" }) do
		vim.keymap.set("n", key, function()
			M.zoom(0.8)
		end, vim.tbl_extend("force", opts, { desc = "Zoom image out" }))
	end
	vim.keymap.set("n", "0", function()
		M.zoom(0)
	end, vim.tbl_extend("force", opts, { desc = "Reset image to fit" }))
	for key, delta in pairs({
		h = { -0.15, 0 },
		l = { 0.15, 0 },
		k = { 0, -0.15 },
		j = { 0, 0.15 },
		["<Left>"] = { -0.15, 0 },
		["<Right>"] = { 0.15, 0 },
		["<Up>"] = { 0, -0.15 },
		["<Down>"] = { 0, 0.15 },
	}) do
		vim.keymap.set("n", key, function()
			M.pan(delta[1], delta[2])
		end, vim.tbl_extend("force", opts, { desc = "Pan image" }))
	end
	local drag
	vim.keymap.set("n", "<LeftMouse>", function()
		drag = vim.fn.getmousepos()
	end, opts)
	vim.keymap.set("n", "<LeftDrag>", function()
		local mouse = vim.fn.getmousepos()
		if drag and mouse.winid == drag.winid and vim.api.nvim_win_is_valid(mouse.winid) then
			M.pan(
				(drag.wincol - mouse.wincol) * 2 / vim.api.nvim_win_get_width(mouse.winid),
				(drag.winrow - mouse.winrow) * 2 / vim.api.nvim_win_get_height(mouse.winid)
			)
		end
		drag = mouse
	end, opts)
end

local function bind(buf)
	vim.keymap.set("n", "<F4>", M.toggle, { buffer = buf, desc = "Toggle media preview / file bytes", silent = true })
end

function M.open(source, kind)
	if states[source] then
		return
	end
	local filepath = vim.api.nvim_buf_get_name(source)
	kind = kind or M.classify(filepath)
	if not kind then
		return
	end
	serial = serial + 1
	local stat = uv.fs_stat(filepath)
	if not stat or stat.type ~= "file" then
		return
	end
	local preview = vim.api.nvim_create_buf(false, true)
	local state = { source = source, preview = preview, path = filepath, kind = kind, id = serial, generation = 0 }
	states[source], states[preview] = state, state
	vim.api.nvim_buf_set_name(preview, "fox-media://" .. source .. "/" .. vim.fn.fnamemodify(filepath, ":t"))
	vim.bo[preview].bufhidden = "hide"
	vim.bo[preview].filetype = "foxmedia"
	vim.b[preview].fox_media_source = source
	vim.bo[source].buflisted = false
	vim.bo[preview].buflisted = true
	local info = {
		vim.fn.fnamemodify(filepath, ":t") .. " (" .. kind .. ", " .. stat.size .. " bytes)",
		"F4: preview / bytes | Ctrl+Shift+Enter: external app"
			.. (kind == "video" and " | :MediaPlay: play video (q returns)" or ""),
	}
	local content = {}
	if kind == "binary" then
		local f = io.open(filepath, "rb")
		local sample = f and f:read(4096) or ""
		if f then
			f:close()
		end
		vim.list_extend(content, M.hex_lines(sample))
		info[#info + 1] = "Hex preview: first 4096 bytes. F4 opens full file content."
	end
	if kind ~= "binary" then
		info[#info + 1] = "Wheel / +/-: zoom | hjkl / drag: pan | 0: fit"
		bind_controls(preview)
	end
	lines(state, content)
	vim.notify(table.concat(info, "\n"), vim.log.levels.INFO, { title = "Media Preview", timeout = 900 })
	bind(source)
	bind(preview)
	enter_preview(state, vim.api.nvim_get_current_win())
	vim.api.nvim_win_set_buf(0, preview)
	M.render(state)
end

function M.toggle()
	local state = states[vim.api.nvim_get_current_buf()]
	if not state then
		if M.is_available() then
			M.open(vim.api.nvim_get_current_buf())
		end
		return
	end
	stop(state)
	if vim.api.nvim_get_current_buf() == state.preview then
		if not vim.api.nvim_buf_is_valid(state.source) then
			return
		end
		state.show_bytes = true
		vim.bo[state.preview].buflisted = false
		vim.bo[state.source].buflisted = true
		vim.api.nvim_win_set_buf(0, state.source)
		if vim.b[state.source].fox_media_unloaded then
			-- BufReadCmd kept the binary off-screen until bytes were requested.
			vim.cmd("noautocmd edit ++bin " .. vim.fn.fnameescape(state.path))
			vim.b[state.source].fox_media_unloaded = nil
		end
		leave_preview(state, vim.api.nvim_get_current_win())
	else
		state.show_bytes = false
		vim.bo[state.source].buflisted = false
		vim.bo[state.preview].buflisted = true
		enter_preview(state, vim.api.nvim_get_current_win())
		vim.api.nvim_win_set_buf(0, state.preview)
		M.render(state)
	end
end

function M.current_path()
	local state = states[vim.api.nvim_get_current_buf()]
	return state and state.path or nil
end

function M.play()
	local filepath = M.current_path() or vim.api.nvim_buf_get_name(0)
	if M.classify(filepath) ~= "video" or vim.fn.executable("mpv") ~= 1 or not M.is_available() then
		vim.notify("Kitty video playback requires a video file and mpv with its kitty output.", vim.log.levels.WARN)
		return
	end
	if visible then
		stop(visible)
	end
	-- Suspend the TUI so mpv owns terminal input and video output. q returns.
	vim.cmd("!mpv --vo=kitty --vo-kitty-use-shm=no --really-quiet -- " .. vim.fn.shellescape(filepath))
	vim.cmd.redraw()
	local state = states[vim.api.nvim_get_current_buf()]
	if state and vim.api.nvim_get_current_buf() == state.preview then
		M.render(state)
	end
end

function M.setup()
	if M._setup then
		return
	end
	M._setup = true
	local group = vim.api.nvim_create_augroup("fox_kitty_media", { clear = true })
	vim.api.nvim_create_user_command(
		"MediaPreviewToggle",
		M.toggle,
		{ desc = "Toggle native media preview / file bytes" }
	)
	vim.api.nvim_create_user_command(
		"MediaPlay",
		M.play,
		{ desc = "Play video with mpv Kitty graphics output (q returns)" }
	)
	if not M.is_available() then
		return
	end
	-- Eager interception also covers files supplied on Neovim's command line.
	local patterns = { "*.pdf", "*.PDF" }
	for ext in pairs(images) do
		patterns[#patterns + 1] = "*." .. ext
		patterns[#patterns + 1] = "*." .. ext:upper()
	end
	for ext in pairs(videos) do
		patterns[#patterns + 1] = "*." .. ext
		patterns[#patterns + 1] = "*." .. ext:upper()
	end
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = group,
		pattern = patterns,
		callback = function(ev)
			if not M.is_available() then
				vim.api.nvim_buf_call(ev.buf, function()
					vim.cmd("noautocmd read " .. vim.fn.fnameescape(ev.file))
				end)
				-- :read inserts below the initial empty line.
				vim.api.nvim_buf_set_lines(ev.buf, 0, 1, false, {})
				vim.bo[ev.buf].modified = false
				return
			end
			vim.b[ev.buf].fox_media_unloaded = true
			vim.bo[ev.buf].modified = false
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(ev.buf) and vim.api.nvim_get_current_buf() == ev.buf then
					M.open(ev.buf)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufReadPre", {
		group = group,
		callback = function(ev)
			if M.classify(ev.file) == "binary" then
				vim.bo[ev.buf].binary = true
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		callback = function(ev)
			if not M.is_available() or states[ev.buf] then
				return
			end
			local filepath = vim.api.nvim_buf_get_name(ev.buf)
			local kind = M.classify(filepath)
			if not kind then
				return
			end
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(ev.buf) and vim.api.nvim_get_current_buf() == ev.buf then
					M.open(ev.buf, kind)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "TabLeave" }, {
		group = group,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			local state = states[vim.api.nvim_get_current_buf()]
			-- These events also fire when focusing the explorer. Wait until the
			-- transition finishes, then check whether the image is still on screen.
			vim.schedule(function()
				if state and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) ~= state.preview then
					leave_preview(state, win)
				end
				if visible and not preview_window(visible) then
					stop(visible)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TabEnter", "VimResized", "WinResized" }, {
		group = group,
		callback = function(ev)
			vim.schedule(function()
				local state = states[vim.api.nvim_get_current_buf()]
				if state and state.source == vim.api.nvim_get_current_buf() and not state.show_bytes then
					vim.bo[state.source].buflisted = false
					vim.bo[state.preview].buflisted = true
					vim.api.nvim_win_set_buf(0, state.preview)
				end
				if state and state.preview == vim.api.nvim_get_current_buf() then
					enter_preview(state, vim.api.nvim_get_current_win())
					M.render(state)
				elseif visible and preview_window(visible) and visible.windows then
					local image_win = preview_window(visible)
					-- Reposition on layout changes even while the explorer has focus.
					if vim.api.nvim_win_is_valid(image_win) then
						enter_preview(visible, image_win)
						if ev.event == "WinResized" or ev.event == "VimResized" then
							M.render(visible)
						end
					end
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(ev)
			local state = states[ev.buf]
			if not state then
				return
			end
			stop(state)
			states[state.source], states[state.preview] = nil, nil
			if state.temp then
				vim.fn.delete(state.temp)
			end
			if state.view_temp then
				vim.fn.delete(state.view_temp)
			end
			if ev.buf == state.preview and vim.api.nvim_buf_is_valid(state.source) then
				vim.bo[state.source].buflisted = true
				if not vim.bo[state.source].modified then
					vim.schedule(function()
						pcall(vim.api.nvim_buf_delete, state.source, { force = false })
					end)
				end
			end
			if ev.buf == state.source and vim.api.nvim_buf_is_valid(state.preview) then
				vim.schedule(function()
					pcall(vim.api.nvim_buf_delete, state.preview, { force = true })
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if visible then
				stop(visible)
			end
			for buf, state in pairs(states) do
				if buf == state.source then
					if state.temp then
						vim.fn.delete(state.temp)
					end
					if state.view_temp then
						vim.fn.delete(state.view_temp)
					end
				end
			end
		end,
	})
end

return M
