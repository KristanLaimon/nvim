local t = require("fox.lib.foxnvim.test")
local media = require("fox.media.kitty")
local function with_file(ext, content, callback)
	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir, "p")
	local path = dir .. "/asset." .. ext
	local f = assert(io.open(path, "wb"))
	f:write(content)
	f:close()
	local ok, err = pcall(callback, path)
	vim.fn.delete(dir, "rf")
	if not ok then
		error(err)
	end
end

t.describe("Kitty media preview", function()
	t.it("swaps a ready image before retiring the previous frame in one synchronized update", function()
		local content = "new-image-payload"
		local swap = media.frame_update(content, 123)
		t.expect(swap:sub(1, 8)).toBe("\27[?2026h")
		t.expect(swap:sub(-8)).toBe("\27[?2026l")
		local new_pos = assert(swap:find(content, 1, true))
		local delete_pos = assert(swap:find("\27_Ga=d,d=I,i=123", 1, true))
		t.expect(new_pos < delete_pos).toBe(true)
	end)
	t.it("keeps the displayed frame while a replacement render is pending", function()
		local original_system, original_send = vim.system, vim.api.nvim_ui_send
		local original_buf = vim.api.nvim_get_current_buf()
		local preview = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(preview)
		local sends, killed = {}, false
		vim.api.nvim_ui_send = function(data)
			sends[#sends + 1] = data
		end
		vim.system = function()
			return {
				kill = function()
					killed = true
				end,
			}
		end
		local state = { preview = preview, kind = "image", path = "unused.png", id = 123, generation = 0 }
		local ok, err = pcall(function()
			media.render(state)
			media.render(state)
			t.expect(killed).toBe(true)
			t.expect(#sends).toBe(0)
		end)
		-- Clear the pending fake render before restoring the real process runner.
		local other = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(other)
		media.render({ preview = other, kind = "binary", id = 124, generation = 0 })
		vim.system, vim.api.nvim_ui_send = original_system, original_send
		if not vim.api.nvim_buf_is_valid(original_buf) then
			original_buf = vim.api.nvim_create_buf(true, false)
		end
		vim.api.nvim_set_current_buf(original_buf)
		vim.api.nvim_buf_delete(preview, { force = true })
		vim.api.nvim_buf_delete(other, { force = true })
		if not ok then
			error(err)
		end
	end)

	t.it("crops zoomed images within the viewport and pans to either edge", function()
		local w, h, cw, ch, x, y = media.crop_geometry(1600, 900, 800, 600, 2, 0, 0)
		t.expect(w).toBe(1600)
		t.expect(h).toBe(900)
		t.expect(cw).toBe(800)
		t.expect(ch).toBe(600)
		t.expect(x).toBe(400)
		t.expect(y).toBe(150)
		local _, _, _, _, left, top = media.crop_geometry(1600, 900, 800, 600, 2, -1, -1)
		t.expect(left).toBe(0)
		t.expect(top).toBe(0)
		local _, _, _, _, right, bottom = media.crop_geometry(1600, 900, 800, 600, 2, 1, 1)
		t.expect(right).toBe(800)
		t.expect(bottom).toBe(300)
	end)
	t.it("keeps reported terminal pixel dimensions", function()
		local size = media.resolve_window_size("[120,40,1440,960]")
		t.expect(size[3]).toBe(1440)
		t.expect(size[4]).toBe(960)
	end)
	t.it("renders when ioctl omits pixel dimensions", function()
		local size = media.resolve_window_size("[120,40,0,0]")
		t.expect(size[1]).toBe(120)
		t.expect(size[2]).toBe(40)
		t.expect(size[3]).toBe(1200)
		t.expect(size[4]).toBe(800)
	end)
	t.it("uses editor geometry when the TTY helper fails or returns malformed data", function()
		for _, output in ipairs({ "", "null", "{}", "invalid", "[0,0,0,0]" }) do
			local size = media.resolve_window_size(output)
			t.expect(size[1]).toBe(vim.o.columns)
			t.expect(size[2]).toBe(vim.o.lines)
			t.expect(size[3]).toBe(vim.o.columns * 10)
			t.expect(size[4]).toBe(vim.o.lines * 20)
		end
	end)

	t.it("distinguishes images, video, PDF, generic binaries and ordinary text", function()
		with_file("PNG", "image", function(p)
			t.expect(media.classify(p)).toBe("image")
		end)
		with_file("mp4", "video", function(p)
			t.expect(media.classify(p)).toBe("video")
		end)
		with_file("pdf", "%PDF", function(p)
			t.expect(media.classify(p)).toBe("pdf")
		end)
		with_file("dat", "A\0B", function(p)
			t.expect(media.classify(p)).toBe("binary")
		end)
		with_file("dat", "\137PNG\r\n\26\n", function(p)
			t.expect(media.classify(p)).toBe("image")
		end)
		with_file("lua", "return {}", function(p)
			t.expect(media.classify(p)).toBe(nil)
		end)
	end)
	t.it("renders byte offsets, hex values and printable text without executing the file", function()
		local result = media.hex_lines("A\0B\255")
		t.expect(result[1]).toBe("00000000  41 00 42 ff                                      |A.B.|")
	end)
	t.it("opens a preview by default and F4 restores complete original bytes and window options", function()
		local available, render, setup = media.is_available, media.render, media._setup
		local win = vim.api.nvim_get_current_win()
		local original_buf = vim.api.nvim_get_current_buf()
		local old_number, old_relative = vim.wo.number, vim.wo.relativenumber
		local source, preview, source2, preview2
		local last_render, last_state, toast
		local old_notify = vim.notify
		vim.notify = function(message, _, opts)
			toast = { message = message, opts = opts }
		end
		media.is_available = function()
			return true
		end
		media.render = function(state)
			last_render = state.preview
			last_state = state
		end -- Graphics need a real Kitty TUI.
		media._setup = false
		media.setup()
		local ok, err = pcall(function()
			with_file("png", "A\0B\255", function(path)
				vim.wo.number, vim.wo.relativenumber = false, false
				vim.cmd.edit(vim.fn.fnameescape(path))
				source = vim.api.nvim_get_current_buf()
				vim.wait(50, function()
					return vim.bo.filetype == "foxmedia"
				end)
				preview = vim.api.nvim_get_current_buf()
				t.expect(preview ~= source).toBe(true)
				t.expect(vim.bo[preview].modifiable).toBe(false)
				t.expect(media.current_path()).toBe(path)
				t.expect(vim.bo[preview].buflisted).toBe(true)
				t.expect(vim.bo[source].buflisted).toBe(false)
				t.expect(vim.api.nvim_buf_get_lines(preview, 0, -1, false)[1]).toBe("")
				t.expect(toast.opts.timeout).toBe(900)
				media.toggle()
				t.expect(vim.api.nvim_get_current_buf()).toBe(source)
				t.expect(vim.bo.binary).toBe(true)
				t.expect(vim.api.nvim_buf_get_lines(source, 0, -1, false)[1]).toBe("A\0B\255")
				t.expect(vim.wo.number).toBe(false)
				t.expect(vim.wo.relativenumber).toBe(false)
				media.toggle()
				t.expect(vim.api.nvim_get_current_buf()).toBe(preview)
				t.expect(vim.bo[preview].modified).toBe(false)
				with_file("png", "second", function(path2)
					vim.cmd.edit(vim.fn.fnameescape(path2))
					source2 = vim.api.nvim_get_current_buf()
					vim.wait(50, function()
						return vim.bo.filetype == "foxmedia"
					end)
					preview2 = vim.api.nvim_get_current_buf()
					t.expect(last_render).toBe(preview2)
					vim.api.nvim_set_current_buf(preview)
					vim.wait(50, function()
						return last_render == preview
					end)
					t.expect(last_render).toBe(preview)
					vim.api.nvim_set_current_buf(preview2)
					vim.wait(50, function()
						return last_render == preview2
					end)
					t.expect(last_render).toBe(preview2)
					local image_win = vim.api.nvim_get_current_win()
					vim.cmd("leftabove vnew")
					local explorer_win, explorer_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
					vim.bo.filetype = "neo-tree"
					vim.wait(20)
					t.expect(vim.api.nvim_win_get_buf(image_win)).toBe(preview2)
					t.expect(vim.wo[image_win].number).toBe(false)
					vim.api.nvim_set_current_win(image_win)
					vim.api.nvim_win_close(explorer_win, true)
					vim.api.nvim_buf_delete(explorer_buf, { force = true })
					if vim.fn.executable("magick") == 1 then
						media.zoom(2)
						vim.wait(100, function()
							return last_state.zoom == 2
						end)
						t.expect(last_state.zoom).toBe(2)
						media.pan(10, -10)
						t.expect(last_state.pan_x).toBe(1)
						t.expect(last_state.pan_y).toBe(-1)
						media.zoom(0)
						t.expect(last_state.zoom).toBe(1)
						t.expect(last_state.pan_x).toBe(0)
						t.expect(last_state.pan_y).toBe(0)
					end
					-- Reopening the real filename also returns to its preview.
					vim.api.nvim_set_current_buf(source)
					vim.wait(50, function()
						return vim.api.nvim_get_current_buf() == preview
					end)
					t.expect(vim.api.nvim_get_current_buf()).toBe(preview)
				end)
			end)
		end)
		if source2 and vim.api.nvim_buf_is_valid(source2) then
			vim.api.nvim_buf_delete(source2, { force = true })
		end
		if preview2 and vim.api.nvim_buf_is_valid(preview2) then
			vim.api.nvim_buf_delete(preview2, { force = true })
		end
		if source and vim.api.nvim_buf_is_valid(source) then
			vim.api.nvim_buf_delete(source, { force = true })
		end
		vim.wait(20)
		if preview and vim.api.nvim_buf_is_valid(preview) then
			vim.api.nvim_buf_delete(preview, { force = true })
		end
		if not vim.api.nvim_buf_is_valid(original_buf) then
			original_buf = vim.api.nvim_create_buf(true, false)
		end
		vim.api.nvim_win_set_buf(win, original_buf)
		vim.wo.number, vim.wo.relativenumber = old_number, old_relative
		vim.api.nvim_del_augroup_by_name("fox_kitty_media")
		vim.notify = old_notify
		media.is_available, media.render = available, render
		media._setup = false
		media.setup()
		media._setup = setup or media._setup
		if not ok then
			error(err)
		end
	end)
end)
