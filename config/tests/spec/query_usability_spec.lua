local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local query = require("fox.query")

describe("FoxQuerier usability", function()
	it("keeps explorer objects above a padded footer", function()
		local render = require("fox.query.render")
		local item = { key = "Player", name = "Player" }
		local lines, objects = render.explorer({ tables = { item } }, "", "Player", {}, 12)
		expect(#lines).toBe(12)
		expect(objects[1]).toBe(item)
		expect(lines[9]).toBe("──────")
		expect(lines[10]).toBe("DATABASE EXPLORER")
		expect(lines[11]).toContain("/: filter")
		expect(lines[12]).toBe("Filter: ")
	end)

	it("centers the focused schema card and connects incoming and outgoing neighbors at both widths", function()
		local render = require("fox.query.render")
		local schema = { tables = { { key = "Main", columns = { { name = "id", pk = true } } } }, relations = {} }
		for index = 1, 6 do
			local key = "Neighbor" .. index
			schema.tables[#schema.tables + 1] = { key = key, columns = { { name = "id" } } }
			schema.relations[#schema.relations + 1] = {
				source = index % 2 == 0 and "Main" or key,
				target = index % 2 == 0 and key or "Main",
				columns = { { source = "id", target = "id" } },
			}
		end
		for _, width in ipairs({ 180, 65 }) do
			local lines, objects = render.map(schema, "Main", 1, width)
			local positions = {}
			for row, object in pairs(objects) do
				for _, region in ipairs(object.regions or {}) do
					positions[region.item.key] = positions[region.item.key] or { row = row, x = region.first }
				end
			end
			local text = table.concat(lines, "\n")
			expect(text).toContain("> Main")
			expect(positions.Neighbor1.x < positions.Main.x).toBeTruthy()
			expect(positions.Neighbor2.x > positions.Main.x).toBeTruthy()
			for index = 1, 6 do
				expect(text).toContain("Neighbor" .. index)
			end
			local arrows = 0
			for row, line in ipairs(lines) do
				if not line:match("^%[") then
					arrows = arrows + select(2, line:gsub("[<>%^]", ""))
				end
				if row > 3 and row < #lines - 8 then
					expect(line:find("Main", 1, true) == nil or line:find("> Main", 1, true) ~= nil).toBeTruthy()
				end
			end
			expect(arrows >= 4).toBeTruthy()
		end
	end)
	it("uses compact query popups and calls back once on selection or cancellation", function()
		local item, values, popup = { id = "test" }, {}, nil
		local function open()
			query.select({ item, { id = "second" } }, {
				prompt = "Queries",
				format_item = function(value)
					return value.id
				end,
			}, function(value)
				values[#values + 1] = value or false
			end)
			popup = vim.api.nvim_get_current_win()
		end
		local ok, err = pcall(function()
			open()
			local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
			expect(lines[3]).toBe("test")
			expect(lines[4]).toBe("second")
			expect(vim.api.nvim_win_get_config(popup).relative).toBe("editor")
			expect(vim.bo.filetype == "TelescopePrompt").toBeFalsy()
			vim.fn.maparg("j", "n", false, true).callback()
			expect(vim.api.nvim_win_get_cursor(popup)[1]).toBe(4)
			vim.fn.maparg("k", "n", false, true).callback()
			vim.fn.maparg("<CR>", "n", false, true).callback()
			expect(values[1]).toBe(item)
			open()
			vim.fn.maparg("<Esc>", "n", false, true).callback()
			expect(values[2]).toBe(false)
			open()
			vim.api.nvim_win_close(popup, true)
			expect(vim.wait(1000, function()
				return #values == 3
			end, 10)).toBeTruthy()
			expect(values[3]).toBe(false)
		end)
		if popup and vim.api.nvim_win_is_valid(popup) then
			vim.api.nvim_win_close(popup, true)
		end
		if not ok then
			error(err)
		end
	end)

	it("keeps file selection through explorer folder navigation without changing project root", function()
		local names =
			{ "telescope.pickers", "telescope.finders", "telescope.config", "telescope.actions", "telescope.actions.state" }
		local saved, selected, choose, received = {}, nil, nil, nil
		for _, name in ipairs(names) do
			saved[name] = package.loaded[name]
		end
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		vim.fn.mkdir(root .. "/nested", "p")
		vim.fn.writefile({}, root .. "/nested/test.db")
		local function restore()
			for _, name in ipairs(names) do
				package.loaded[name] = saved[name]
			end
			vim.fn.delete(root, "rf")
		end
		local ok, err = pcall(function()
			package.loaded["telescope.actions"] = {
				close = function() end,
				select_default = {
					replace = function(_, callback)
						choose = callback
					end,
				},
			}
			package.loaded["telescope.actions.state"] = {
				get_selected_entry = function()
					return { value = selected }
				end,
			}
			package.loaded["telescope.finders"] = {
				new_table = function(opts)
					return opts
				end,
			}
			package.loaded["telescope.config"] = { values = { generic_sorter = function() end } }
			local opened = 0
			package.loaded["telescope.pickers"] = {
				new = function(opts)
					opened = opened + 1
					return {
						find = function()
							opts.attach_mappings(0, function() end)
						end,
					}
				end,
			}
			require("plugins.fox.tools.file_explorer").open_desktop_explorer({
				path = root,
				on_select_file = function(filename)
					received = filename
				end,
			})
			selected = { path = root .. "/nested", is_dir = true }
			choose()
			expect(vim.wait(1000, function()
				return opened == 2
			end, 10)).toBeTruthy()
			expect(received).toBeNil()
			selected = { path = root .. "/nested/test.db", is_dir = false }
			choose()
			expect(received).toBe(root .. "/nested/test.db")
			expect(vim.fn.getcwd()).toBe(cwd)
		end)
		restore()
		if not ok then
			error(err)
		end
	end)

	it("completes bare columns in the current statement and qualifies ambiguous columns", function()
		local buf = vim.api.nvim_create_buf(false, true)
		local previous = vim.api.nvim_get_current_buf()
		local key = "query-completion-test"
		local metadata = {
			tables = {
				{ key = "Match", name = "Match", columns = { { name = "id" }, { name = "date_played_id" } } },
				{ key = "other", name = "other", columns = { { name = "id" } } },
			},
			relations = {},
		}
		query.states[key] = { metadata = metadata, consoles = {} }
		vim.b[buf].fox_query_root = key
		vim.api.nvim_set_current_buf(buf)
		local ok, err = pcall(function()
			local function labels(text, column)
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
				vim.api.nvim_win_set_cursor(0, { 1, column })
				local result = {}
				require("fox.query.completion")
					.new()
					:get_completions({ bufnr = buf, cursor = { 1, column } }, function(response)
						for _, item in ipairs(response.items) do
							result[item.label] = true
						end
					end)
				return result
			end
			expect(labels("SELECT date FROM Match;", 11).date_played_id).toBeTruthy()
			expect(labels("SELECT M.da FROM Match m;", 11).date_played_id).toBeTruthy()
			local ambiguous = labels("SELECT id FROM Match m JOIN other o ON m.id = o.id;", 9)
			expect(ambiguous.id).toBeNil()
			expect(ambiguous["m.id"]).toBeTruthy()
			expect(ambiguous["o.id"]).toBeTruthy()
			expect(labels("SELECT id FROM other; SELECT date FROM Match;", 33).date_played_id).toBeTruthy()
		end)
		query.states[key] = nil
		vim.api.nvim_set_current_buf(previous)
		vim.api.nvim_buf_delete(buf, { force = true })
		if not ok then
			error(err)
		end
	end)

	it("renders aligned, unwrapped inspector rows with colored sections", function()
		local item = {
			key = "Long表Name",
			name = "Long表Name",
			columns = {
				{ name = "id", type = "BIGINT", pk = true, nullable = false },
				{ name = "parent", type = "TEXT", nullable = true },
				{ name = "表名", type = "BOOLEAN", pk = true, nullable = false },
			},
			indexes = { { name = string.rep("index", 15), unique = true } },
		}
		local lines, highlights = require("fox.query.render").inspect(item, {
			relations = {
				{
					source = item.key,
					target = "parents",
					columns = {
						{ source = "parent", target = "id" },
						{ source = "表名", target = "other_id" },
					},
				},
			},
		}, 44)
		expect(lines[1]:sub(1, #"┌")).toBe("┌")
		for _, line in ipairs(lines) do
			expect(vim.fn.strdisplaywidth(line)).toBe(vim.fn.strdisplaywidth(lines[1]))
		end
		local text = table.concat(lines, "\n")
		local header, id, parent, wide
		for _, line in ipairs(lines) do
			if line:find("│ NAME", 1, true) then
				header = line
			end
			if line:find("│ id ", 1, true) then
				id = line
			end
			if line:find("│ parent ", 1, true) then
				parent = line
			end
			if line:find("│ 表名 ", 1, true) then
				wide = line
			end
		end
		local function position(line, value)
			return vim.fn.strdisplaywidth(line:sub(1, assert(line:find(value, 1, true)) - 1))
		end
		expect(position(id, "BIGINT")).toBe(position(header, "TYPE"))
		expect(position(parent, "TEXT")).toBe(position(header, "TYPE"))
		expect(position(wide, "BOOLEAN")).toBe(position(header, "TYPE"))
		expect(position(id, "PK")).toBe(position(header, "PK"))
		expect(position(id, "NN")).toBe(position(header, "NN"))
		expect(position(parent, "FK")).toBe(position(header, "FK"))
		for _, flag in ipairs({ "PK", "FK", "NN" }) do
			expect(position(wide, flag)).toBe(position(header, flag))
		end
		expect(parent:find("NN", 1, true)).toBeNil()
		expect(text).toContain(string.rep("index", 15))
		expect(#highlights > #lines).toBeTruthy()
		expect(text).toContain("INDEXES")
		expect(text).toContain("RELATIONSHIPS")
	end)

	it("uses the existing explorer for SQLite paths and leaves cancellation unsaved", function()
		local old_select, old_input, old_connect = query.select, vim.ui.input, query.connect
		local old_lazy, old_explorer = package.loaded.lazy, package.loaded["plugins.fox.tools.file_explorer"]
		local root, cwd = vim.fn.tempname(), vim.fn.getcwd()
		vim.fn.mkdir(root, "p")
		vim.fn.writefile({}, root .. "/selected.db")
		vim.api.nvim_set_current_dir(root)
		local picked, connected
		local ok, err = pcall(function()
			package.loaded.lazy = { load = function() end }
			package.loaded["plugins.fox.tools.file_explorer"] = {
				open_desktop_explorer = function(opts)
					picked = opts
				end,
			}
			query.select = function(_, _, callback)
				callback("sqlite")
			end
			vim.ui.input = function(opts, callback)
				expect(opts.prompt).toBe("id: ")
				callback("test-sqlite")
			end
			query.connect = function(profile)
				connected = profile
			end
			query.add_profile()
			expect(picked.path).toBe(require("fox.query.storage").root(root))
			expect(connected).toBeNil()
			expect(vim.fn.filereadable(root .. "/.foxnvim/query/connections.json")).toBe(0)
			picked.on_select_file(root .. "/selected.db")
			expect(connected.path).toBe(root .. "/selected.db")
		end)
		query.select, vim.ui.input, query.connect = old_select, old_input, old_connect
		package.loaded.lazy, package.loaded["plugins.fox.tools.file_explorer"] = old_lazy, old_explorer
		query.close_root(root)
		vim.api.nvim_set_current_dir(cwd)
		vim.fn.delete(root, "rf")
		if not ok then
			error(err)
		end
	end)
end)
