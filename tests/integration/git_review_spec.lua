local t = require("fox.lib.foxnvim.test")
local wrapper = require("plugins.fox.git.review")
local review = getmetatable(wrapper).__index

t.describe("Git review input and virtual annotations", function()
	local root, tab
	local function choose(label)
		for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
			if line:find(label, 1, true) then
				vim.api.nvim_win_set_cursor(0, { index, 0 })
				vim.fn.maparg("<CR>", "n", false, true).callback()
				return
			end
		end
		error("Missing session menu option: " .. label)
	end
	t.beforeEach(function()
		root = vim.fs.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
		vim.cmd("tabnew")
		tab = vim.api.nvim_get_current_tabpage()
		review.new_session(root)
	end)
	t.afterEach(function()
		vim.cmd("stopinsert")
		if vim.api.nvim_tabpage_is_valid(tab) then
			vim.api.nvim_set_current_tabpage(tab)
			vim.cmd("tabclose!")
		end
		review.annotations = {}
		review.active_session = nil
		vim.fn.delete(root, "rf")
	end)

	t.it("anchors below a scrolled line and saves multiline ghost text on unnamed Git panels", function()
		local source = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(source)
		local lines = {}
		for index = 1, 200 do
			lines[index] = "source line " .. index
		end
		vim.api.nvim_buf_set_lines(source, 0, -1, false, lines)
		vim.api.nvim_buf_set_extmark(source, vim.api.nvim_create_namespace("fox_review_test_diff"), 145, 0, {
			virt_lines = { { { "deleted diff line", "Comment" } } },
		})
		vim.bo[source].modified = false
		vim.api.nvim_win_set_cursor(0, { 150, 0 })
		vim.cmd("normal! zz")
		local original_win = vim.api.nvim_get_current_win()
		review.render_annotations(source, "file[1].lua")
		vim.cmd("vsplit")
		local other = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(other)
		vim.api.nvim_buf_set_lines(other, 0, -1, false, lines)
		review.render_annotations(other, "file[1].lua")
		vim.api.nvim_set_current_win(original_win)
		review.add_annotation("file[1].lua", 150, root)
		local input = vim.api.nvim_get_current_buf()
		local config = vim.api.nvim_win_get_config(0)
		t.expect(config.win).toBe(original_win)
		t.expect(config.bufpos).toEqual({ 149, 0 })
		t.expect(config.row).toBe(1)
		vim.cmd("redraw")
		local position = vim.fn.screenpos(original_win, 150, 1)
		t.expect(vim.api.nvim_win_get_position(0)[1]).toBe(position.row)
		-- q must remain typable in annotation text.
		t.expect(vim.fn.maparg("q", "i", false, true)).toEqual({})
		t.expect(config.title[1][1]:find("Add [SUGGESTION] L150", 1, true) ~= nil).toBe(true)
		vim.api.nvim_buf_set_lines(input, 0, -1, false, { "query this", "second line" })
		vim.fn.maparg("<CR>", "n", false, true).callback()
		t.expect(vim.api.nvim_buf_is_valid(input)).toBe(false)
		t.expect(vim.api.nvim_get_current_win()).toBe(original_win)
		for _, buf in ipairs({ source, other }) do
			local marks = vim.api.nvim_buf_get_extmarks(buf, review.namespace, 0, -1, { details = true })
			t.expect(#marks).toBe(1)
			t.expect(marks[1][2]).toBe(149)
			local box = marks[1][4].virt_lines
			t.expect(box[1][1][1]:find("[SUGGESTION] L150", 1, true) ~= nil).toBe(true)
			t.expect(vim.trim(box[3][1][1]:sub(3, -3))).toBe("query this")
			t.expect(vim.trim(box[4][1][1]:sub(3, -3))).toBe("second line")
			for _, row in ipairs(box) do
				t.expect(vim.fn.strdisplaywidth(row[1][1])).toBe(vim.fn.strdisplaywidth(box[1][1][1]))
			end
			t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual(lines)
		end
		t.expect(vim.bo[source].modified).toBe(false)
		local session = review.active_session
		local saved =
			vim.json.decode(table.concat(vim.fn.readfile(root .. "/.foxnvim/review/" .. session .. ".json"), "\n"))
		t.expect(saved.annotations[1].text).toBe("query this\nsecond line")
		review.annotations = {}
		t.expect(review.load_session(session, root)).toBe(true)
		t.expect(review.annotations[1].line).toBe(150)
		review.delete_annotation("file[1].lua", 150, root)
		for _, buf in ipairs({ source, other }) do
			t.expect(#vim.api.nvim_buf_get_extmarks(buf, review.namespace, 0, -1, {})).toBe(0)
		end
	end)

	t.it("cycles the border title without changing text, inserts newlines and cancels with Escape", function()
		review.add_annotation("sample.lua", 1, root)
		local input = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_lines(input, 0, -1, false, { "[NOTE] keep this literal" })
		vim.fn.maparg("<Tab>", "i", false, true).callback()
		t.expect(vim.api.nvim_win_get_config(0).title[1][1]:find("Add [ISSUE] L1", 1, true) ~= nil).toBe(true)
		t.expect(vim.api.nvim_buf_get_lines(input, 0, -1, false)).toEqual({ "[NOTE] keep this literal" })
		vim.fn.maparg("<S-Tab>", "i", false, true).callback()
		t.expect(vim.api.nvim_win_get_config(0).title[1][1]:find("Add [SUGGESTION] L1", 1, true) ~= nil).toBe(true)
		vim.api.nvim_win_set_cursor(0, { 1, 7 })
		vim.fn.maparg("<C-j>", "i", false, true).callback()
		t.expect(vim.api.nvim_buf_get_lines(input, 0, -1, false)).toEqual({ "[NOTE] ", "keep this literal" })
		vim.fn.maparg("<Esc>", "i", false, true).callback()
		t.expect(vim.api.nvim_buf_is_valid(input)).toBe(false)
		t.expect(#review.annotations).toBe(0)
	end)

	t.it("wraps Unicode text in complete rectangles for every annotation type", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
		for index, ann_type in ipairs({ "SUGGESTION", "NOTE", "ISSUE" }) do
			review.annotations[index] =
				{ file = "sample.lua", line = index, type = ann_type, text = string.rep("你好 á", 35) }
		end
		review.render_annotations(buf, "sample.lua")
		local marks = vim.api.nvim_buf_get_extmarks(buf, review.namespace, 0, -1, { details = true })
		t.expect(#marks).toBe(3)
		for index, mark in ipairs(marks) do
			local box = mark[4].virt_lines
			t.expect(box[1][1][1]:find("[" .. review.annotations[index].type .. "] L" .. index, 1, true) ~= nil).toBe(true)
			t.expect(#box > 5).toBe(true)
			local reconstructed = {}
			for row_index, row in ipairs(box) do
				t.expect(vim.fn.strdisplaywidth(row[1][1])).toBe(vim.fn.strdisplaywidth(box[1][1][1]))
				if row_index > 2 and row_index < #box - 1 then
					reconstructed[#reconstructed + 1] = vim.trim(row[1][1]:sub(3, -3))
				end
			end
			t.expect(table.concat(reconstructed):gsub(" ", "")).toBe(review.annotations[index].text:gsub(" ", ""))
		end
	end)

	t.it("creates distinct sessions without overwriting annotations and restores the selected session", function()
		vim.fn.writefile({ "source" }, root .. "/sample.lua")
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		review.session_name = "First Session"
		review.annotations = { { file = "sample.lua", line = 1, type = "NOTE", text = "first session note" } }
		review.save_session(root)
		local first = review.active_session
		review.render_annotations(buf, "sample.lua")
		review.session_menu(root)
		t.expect(vim.bo.filetype).toBe("foxreviewsessions")
		t.expect(vim.api.nvim_win_get_config(0).relative).toBe("editor")
		choose("Create a new session")
		t.expect(review.active_session ~= first).toBe(true)
		t.expect(#review.list_sessions(root)).toBe(2)
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, review.namespace, 0, -1, {})).toBe(0)
		review.session_menu(root)
		choose("Load a saved session")
		choose("First Session")
		t.expect(review.active_session).toBe(first)
		t.expect(review.annotations[1].text).toBe("first session note")
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, review.namespace, 0, -1, {})).toBe(1)
		review.annotations = {}
		review.active_session = nil
		review.ensure_session(root)
		t.expect(review.active_session).toBe(first)
		t.expect(review.annotations[1].text).toBe("first session note")
	end)

	t.it("clears the current session only after confirmation and removes its ghost boxes", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_current_buf(buf)
		review.annotations = { { file = "sample.lua", line = 1, type = "NOTE", text = "clear me" } }
		review.save_session(root)
		local session = review.active_session
		review.render_annotations(buf, "sample.lua")
		review.session_menu(root)
		choose("Clear all annotations")
		choose("Cancel")
		t.expect(#review.annotations).toBe(1)
		review.session_menu(root)
		choose("Clear all annotations")
		choose("Delete")
		t.expect(review.active_session).toBe(session)
		t.expect(#review.annotations).toBe(0)
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, review.namespace, 0, -1, {})).toBe(0)
		t.expect(review.load_session(session, root)).toBe(true)
		t.expect(#review.annotations).toBe(0)
	end)

	t.it("deletes all saved sessions only after confirmation and starts empty without touching other config", function()
		review.annotations = { { file = "sample.lua", line = 1, type = "ISSUE", text = "old note" } }
		review.save_session(root)
		review.new_session(root)
		local old_uuid = review.session_id
		vim.fn.writefile({ "keep" }, root .. "/.foxnvim/tasks.json")
		vim.fn.writefile({ "keep" }, root .. "/.foxnvim/review/README.txt")
		review.session_menu(root)
		choose("Delete ALL saved sessions")
		choose("Cancel")
		t.expect(#review.list_sessions(root)).toBe(2)
		review.session_menu(root)
		choose("Delete ALL saved sessions")
		choose("Delete")
		t.expect(#review.list_sessions(root)).toBe(1)
		t.expect(#review.annotations).toBe(0)
		t.expect(review.session_id ~= old_uuid).toBe(true)
		t.expect(vim.fn.readfile(root .. "/.foxnvim/tasks.json")).toEqual({ "keep" })
		t.expect(vim.fn.readfile(root .. "/.foxnvim/review/README.txt")).toEqual({ "keep" })
		review.ensure_session(root)
		t.expect(#review.annotations).toBe(0)
	end)

	t.it("deletes a selected active session and immediately renders a fresh one", function()
		local first = review.active_session
		review.new_session(root)
		review.session_name = "Session to delete"
		review.annotations = { { file = "sample.lua", line = 1, type = "NOTE", text = "delete me" } }
		review.save_session(root)
		local deleted = review.active_session
		review.session_menu(root)
		choose("Delete a saved session")
		choose("Session to delete")
		choose("Delete")
		t.expect(vim.fn.filereadable(root .. "/.foxnvim/review/" .. deleted .. ".json")).toBe(0)
		t.expect(vim.fn.filereadable(root .. "/.foxnvim/review/" .. first .. ".json")).toBe(1)
		t.expect(#review.annotations).toBe(0)
		t.expect(review.active_session ~= deleted).toBe(true)
	end)
end)
