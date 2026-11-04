local t = require("fox.lib.foxnvim.test")
local engine = require("fox.core.project_replace")

t.describe("native project replacement", function()
	local root
	local function write(name, data)
		local filename = root .. "/" .. name
		vim.fn.mkdir(vim.fs.dirname(filename), "p")
		local file = assert(io.open(filename, "wb"))
		assert(file:write(data))
		file:close()
	end
	local function read(name)
		local file = assert(io.open(root .. "/" .. name, "rb"))
		local data = file:read("*a")
		file:close()
		return data
	end
	t.beforeEach(function()
		root = vim.fn.tempname():gsub("\\", "/")
		vim.fn.mkdir(root, "p")
	end)
	t.afterEach(function()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf):gsub("\\", "/"):sub(1, #root) == root then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.fn.delete(root, "rf")
	end)

	t.it("previews literal matches without writes, filters files and skips binaries/dependencies", function()
		write("src/one.lua", "a.b a.b\n")
		write("two.txt", "a.b\n")
		write("node_modules/dep.lua", "a.b\n")
		write(".git/config", "a.b\n")
		write("binary.lua", "a.b\0data")
		local plan = engine.preview(root, "a.b", "%1\\x", "*.lua")
		t.expect(#plan.files).toBe(1)
		t.expect(plan.count).toBe(2)
		t.expect(plan.skipped).toBe(1)
		t.expect(plan.files[1].matches[1].after).toBe("%1\\x %1\\x")
		t.expect(read("src/one.lua")).toBe("a.b a.b\n")
		t.expect(engine.apply(plan)).toBe(1)
		t.expect(read("src/one.lua")).toBe("%1\\x %1\\x\n")
		t.expect(read("two.txt")).toBe("a.b\n")
		t.expect(pcall(engine.apply, plan)).toBe(false)
	end)

	t.it("applies selected files, preserves CRLF/no final newline, and supports deletion and undo", function()
		write("one.txt", "foo\r\nfoo")
		write("two.txt", "foo\n")
		local plan = engine.preview(root, "foo", "", "*")
		plan.files[2].selected = false
		t.expect(engine.apply(plan)).toBe(1)
		t.expect(read("one.txt")).toBe("\r\n")
		t.expect(read("two.txt")).toBe("foo\n")
		vim.api.nvim_buf_call(plan.files[1].buf, function()
			vim.cmd("silent undo")
		end)
		t.expect(vim.api.nvim_buf_get_lines(plan.files[1].buf, 0, -1, false)).toEqual({ "foo", "foo" })
	end)

	t.it("rejects disk changes across the whole selection before writing anything", function()
		write("one.txt", "foo\n")
		write("two.txt", "foo\n")
		local plan = engine.preview(root, "foo", "bar", "*")
		write("two.txt", "external edit\n")
		t.expect(pcall(engine.apply, plan)).toBe(false)
		t.expect(read("one.txt")).toBe("foo\n")
		t.expect(read("two.txt")).toBe("external edit\n")
	end)

	t.it("searches mixed line endings while protecting their bytes from replacement", function()
		local mixed = "foo\r\nfoo\nfoo\r\n"
		write("mixed.txt", mixed)
		write("normal.txt", "foo\n")
		local buf = vim.fn.bufadd(root .. "/mixed.txt")
		vim.api.nvim_buf_call(buf, function()
			vim.cmd("silent edit ++ff=dos " .. vim.fn.fnameescape(root .. "/mixed.txt"))
		end)
		local plan = engine.preview(root, "foo", "bar", "*", { include_unsaved = true })
		t.expect(plan.count).toBe(4)
		t.expect(plan.files[1].replacement_error ~= nil).toBe(true)
		t.expect(plan.files[1].selected).toBe(false)
		t.expect(engine.apply(plan)).toBe(1)
		t.expect(read("mixed.txt")).toBe(mixed)
		t.expect(read("normal.txt")).toBe("bar\n")
		plan = engine.preview(root, "foo", "bar", "mixed.txt", { include_unsaved = true })
		plan.files[1].selected = true
		t.expect(pcall(engine.apply, plan)).toBe(false)
		t.expect(read("mixed.txt")).toBe(mixed)

		write("raw.txt", "foo\nfoo\r\n")
		vim.api.nvim_buf_call(vim.fn.bufadd(root .. "/raw.txt"), function()
			vim.cmd("silent edit ++ff=unix " .. vim.fn.fnameescape(root .. "/raw.txt"))
		end)
		plan = engine.preview(root, "foo", "bar", "raw.txt", { include_unsaved = true })
		t.expect(engine.apply(plan)).toBe(1)
		t.expect(read("raw.txt")).toBe("bar\nbar\r\n")
		write("control.txt", "foo\n")
		t.expect(pcall(engine.preview, root, "foo", "\\r", "control.txt", { regex = true })).toBe(false)
	end)

	t.it("rejects unsaved buffers and edits made after preview", function()
		write("one.txt", "foo\n")
		local plan = engine.preview(root, "foo", "bar", "*")
		vim.api.nvim_buf_set_lines(plan.files[1].buf, 0, -1, false, { "unsaved" })
		t.expect(pcall(engine.apply, plan)).toBe(false)
		t.expect(pcall(engine.preview, root, "foo", "bar", "*")).toBe(false)
		t.expect(read("one.txt")).toBe("foo\n")
	end)

	t.it("rejects empty and multiline search and handles repeated/unicode matches", function()
		t.expect(pcall(engine.preview, root, "", "x")).toBe(false)
		t.expect(pcall(engine.preview, root, "a\nb", "x")).toBe(false)
		local text, count = engine.replace("ééé", "é", "hello")
		t.expect(text).toBe("hellohellohello")
		t.expect(count).toBe(3)
	end)

	t.it("builds lazy search snapshots without opening files and loads only selected replacements", function()
		write("one.txt", "foo\r\nfoo")
		write("two.txt", "foo\n")
		local plan = engine.preview(root, "foo", "bar", "*", { lazy = true, include_unsaved = true })
		t.expect(plan.count).toBe(3)
		for _, file in ipairs(plan.files) do
			t.expect(file.buf).toBe(nil)
			t.expect(vim.fn.bufnr(file.filename)).toBe(-1)
		end
		plan.files[2].selected = false
		t.expect(engine.apply(plan)).toBe(1)
		t.expect(read("one.txt")).toBe("bar\r\nbar")
		t.expect(read("two.txt")).toBe("foo\n")
		t.expect(vim.fn.bufnr(root .. "/two.txt")).toBe(-1)
	end)

	t.it("guards disk changes and unsaved edits after a lazy search", function()
		write("one.txt", "foo\n")
		local plan = engine.preview(root, "foo", "bar", "*", { lazy = true })
		write("one.txt", "external\n")
		t.expect(pcall(engine.apply, plan)).toBe(false)
		write("one.txt", "foo\n")
		plan = engine.preview(root, "foo", "bar", "*", { lazy = true })
		local buf = vim.fn.bufadd(root .. "/one.txt")
		vim.fn.bufload(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
		t.expect(pcall(engine.apply, plan)).toBe(false)
		t.expect(read("one.txt")).toBe("foo\n")
	end)
end)

local sidebar = require("plugins.fox.tools.project_replace")
local preview = require("fox.core.preview_tab")

t.describe("project search sidebar", function()
	local root, cwd, editor, original, tab
	local function write(name, text)
		vim.fn.writefile({ text }, root .. "/" .. name)
	end
	local function press(index, key)
		local item = sidebar.state.fields[index]
		vim.api.nvim_set_current_win(item.win)
		for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(item.buf, "n")) do
			if mapping.lhs == key or mapping.lhs == vim.keycode(key) then
				mapping.callback()
				return
			end
		end
		error("Missing sidebar mapping: " .. key)
	end
	local function search(text, replacement)
		local state = sidebar.state
		vim.api.nvim_buf_set_lines(state.fields[1].buf, 0, -1, false, { text })
		vim.api.nvim_buf_set_lines(state.fields[2].buf, 0, -1, false, { replacement or "" })
		sidebar.refresh(true)
		assert(
			vim.wait(2000, function()
				return state.plan ~= nil
			end),
			state.status
		)
		return state
	end
	local function select_match(state, filename)
		vim.api.nvim_set_current_win(state.fields[4].win)
		for row, item in pairs(state.rows) do
			if item.match and item.file.relative == filename then
				vim.api.nvim_win_set_cursor(state.fields[4].win, { row, 0 })
				sidebar.preview_selected(false)
				return
			end
		end
		error("Missing match: " .. filename)
	end
	t.beforeEach(function()
		root, cwd = vim.fn.tempname():gsub("\\", "/"), vim.fn.getcwd()
		vim.fn.mkdir(root, "p")
		vim.api.nvim_set_current_dir(root)
		vim.cmd("tabnew")
		tab = vim.api.nvim_get_current_tabpage()
		editor, original = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
		write("one.txt", "Docker docker")
		write("two.txt", "docker compose")
	end)
	t.afterEach(function()
		sidebar.close()
		if vim.api.nvim_tabpage_is_valid(tab) then
			vim.api.nvim_set_current_tabpage(tab)
			vim.cmd("tabclose!")
		end
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_get_name(buf):gsub("\\", "/"):sub(1, #root) == root then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		vim.api.nvim_set_current_dir(cwd)
		vim.fn.delete(root, "rf")
	end)

	t.it("docks on the right, follows entries in one preview tab, and removes it on close", function()
		sidebar.open(false)
		local state = search("docker")
		t.expect(state.plan.count).toBe(3)
		t.expect(#state.fields).toBe(4)
		t.expect(vim.api.nvim_win_get_position(state.fields[4].win)[2] > vim.api.nvim_win_get_position(editor)[2])
			.toBe(true)
		select_match(state, "one.txt")
		local first = vim.api.nvim_win_get_buf(editor)
		t.expect(vim.b[first].fox_preview_owner).toBe("Search")
		t.expect(vim.api.nvim_get_current_win()).toBe(state.fields[4].win)
		t.expect(
			#vim.api.nvim_buf_get_extmarks(first, vim.api.nvim_create_namespace("fox_project_search_match"), 0, -1, {})
		)
			.toBe(1)
		select_match(state, "two.txt")
		local second = vim.api.nvim_win_get_buf(editor)
		t.expect(first ~= second).toBe(true)
		t.expect(vim.bo[first].buflisted).toBe(false)
		t.expect(vim.bo[second].buflisted).toBe(true)
		t.expect(
			#vim.api.nvim_buf_get_extmarks(first, vim.api.nvim_create_namespace("fox_project_search_match"), 0, -1, {})
		)
			.toBe(0)
		sidebar.close()
		t.expect(vim.bo[second].buflisted).toBe(false)
		t.expect(vim.api.nvim_win_get_buf(editor)).toBe(original)
	end)

	t.it("supports numbered sections, Vim file folds, selection and explicit replacement", function()
		sidebar.open(true)
		local state = search("docker", "container")
		press(1, "2")
		t.expect(vim.api.nvim_get_current_win()).toBe(state.fields[2].win)
		select_match(state, "one.txt")
		press(4, "za")
		t.expect(state.collapsed[state.plan.files[1].filename]).toBe(true)
		press(4, "za")
		t.expect(state.collapsed[state.plan.files[1].filename]).toBe(false)
		select_match(state, "two.txt")
		press(4, "<Space>")
		t.expect(state.plan.files[2].selected).toBe(false)
		press(4, "a")
		t.expect(vim.fn.readfile(root .. "/one.txt")[1]).toBe("container container")
		t.expect(vim.fn.readfile(root .. "/two.txt")[1]).toBe("docker compose")
	end)

	t.it("keeps already-open and edited preview files as normal tabs", function()
		local existing = vim.fn.bufadd(root .. "/one.txt")
		vim.fn.bufload(existing)
		vim.bo[existing].buflisted = true
		local session = preview.new("Diff", editor)
		preview.show(session, root .. "/one.txt")
		local temporary = preview.show(session, root .. "/two.txt")
		t.expect(vim.bo[existing].buflisted).toBe(true)
		vim.api.nvim_buf_set_lines(temporary, 0, -1, false, { "unsaved edits" })
		preview.show(session, root .. "/one.txt")
		t.expect(vim.bo[temporary].buflisted).toBe(true)
		t.expect(vim.b[temporary].fox_preview_owner).toBe(nil)
		preview.close(session)
		t.expect(vim.api.nvim_buf_get_lines(temporary, 0, -1, false)[1]).toBe("unsaved edits")
	end)

	t.it("supports case, whole-word and Vim regex matching with capture replacements", function()
		local plan = engine.preview(root, "docker", "box", "*", { case_sensitive = true })
		t.expect(plan.count).toBe(2)
		write("word.txt", "docker dockers Docker")
		plan = engine.preview(root, "docker", "box", "word.txt", { case_sensitive = false, word = true })
		t.expect(plan.count).toBe(2)
		t.expect(plan.files[1].after[1]).toBe("box dockers box")
		plan = engine.preview(root, "\\(docker\\) compose", "\\1 up", "two.txt", { regex = true })
		t.expect(plan.count).toBe(1)
		t.expect(plan.files[1].after[1]).toBe("docker up")
		write("regex.txt", "aa b")
		for _, expression in ipairs({ ".*", "^", "a*", "\\>" }) do
			local count = 0
			vim.fn.substitute("aa b", expression, function()
				count = count + 1
				return "x"
			end, "g")
			local result = engine.preview(root, expression, "x", "regex.txt", { regex = true })
			assert(result.count == count, expression .. ": " .. result.count .. " matches, expected " .. count)
		end
	end)

	t.it("searches unsaved text but refuses to overwrite it with replacements", function()
		sidebar.open(true)
		local buf = vim.fn.bufadd(root .. "/one.txt")
		vim.fn.bufload(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved unique" })
		local state = search("unique", "saved")
		t.expect(state.plan.count).toBe(1)
		t.expect(pcall(engine.apply, state.plan)).toBe(false)
		t.expect(vim.fn.readfile(root .. "/one.txt")[1]).toBe("Docker docker")
	end)

	t.it("cancels stale live searches and closes cleanly while a scan is pending", function()
		for index = 1, 30 do
			write("extra" .. index .. ".txt", "docker")
		end
		sidebar.open(false)
		local state = sidebar.state
		vim.api.nvim_buf_set_lines(state.fields[1].buf, 0, -1, false, { "docker" })
		sidebar.refresh(true)
		t.expect(state.plan).toBe(nil)
		vim.api.nvim_buf_set_lines(state.fields[1].buf, 0, -1, false, { "compose" })
		sidebar.refresh(true)
		t.expect(vim.wait(2000, function()
			return state.plan ~= nil
		end)).toBe(true)
		t.expect(state.plan.count).toBe(1)
		vim.api.nvim_buf_set_lines(state.fields[1].buf, 0, -1, false, { "docker" })
		sidebar.refresh(true)
		sidebar.close()
		vim.wait(30, function()
			return false
		end)
		t.expect(sidebar.state).toBe(nil)
	end)

	t.it("restores an editor when its original editor window was closed", function()
		sidebar.open(false)
		vim.api.nvim_win_close(editor, true)
		sidebar.close()
		t.expect(sidebar.state).toBe(nil)
		t.expect(#vim.api.nvim_tabpage_list_wins(tab)).toBe(1)
		t.expect(vim.api.nvim_get_current_buf()).toBe(original)
	end)

	t.it("renders multiline errors and completes searches with no matches", function()
		sidebar.open(false)
		local saved = engine.preview
		local ok, err = pcall(function()
			engine.preview = function()
				error("first error line\nsecond error line")
			end
			local state = sidebar.state
			vim.api.nvim_buf_set_lines(state.fields[1].buf, 0, -1, false, { "docker" })
			sidebar.refresh(true)
			assert(vim.wait(2000, function()
				return state.status and state.status:find("Search failed", 1, true) ~= nil
			end))
			local lines = vim.api.nvim_buf_get_lines(state.fields[4].buf, 0, -1, false)
			t.expect(table.concat(lines, "\n")).toContain("first error line\\nsecond error line")
		end)
		engine.preview = saved
		assert(ok, err)
		local state = search("no_such_text_in_this_fixture")
		t.expect(state.plan.count).toBe(0)
		t.expect(table.concat(vim.api.nvim_buf_get_lines(state.fields[4].buf, 0, -1, false), "\n"))
			.toContain("0 results in 0 files")
	end)

	t.it("searches without ripgrep through the built-in fallback", function()
		local executable = vim.fn.executable
		local ok, err = pcall(function()
			vim.fn.executable = function(name)
				return name == "rg" and 0 or executable(name)
			end
			sidebar.open(false)
			local state = search("docker")
			t.expect(state.plan.count).toBe(3)
		end)
		vim.fn.executable = executable
		assert(ok, err)
	end)

	t.it("uses rg candidate files and respects ignore rules without losing unsaved matches", function()
		if vim.fn.executable("rg") ~= 1 then
			return
		end
		write(".ignore", "ignored.txt")
		write("ignored.txt", "docker")
		sidebar.open(false)
		local state = search("docker")
		t.expect(#state.plan.files).toBe(2)
		local buf = vim.fn.bufadd(root .. "/two.txt")
		vim.fn.bufload(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "fresh unsaved search term" })
		state = search("unsaved")
		t.expect(state.plan.count).toBe(1)
		t.expect(state.plan.files[1].relative).toBe("two.txt")
		state.regex = true
		state = search("Docker\\|compose")
		t.expect(state.plan.count).toBe(2)
	end)
end)
