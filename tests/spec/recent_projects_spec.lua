local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("recent projects ordering", function()
	local saved, originals, options, projects, starred
	local wsl_path = "//wsl.localhost/Ubuntu/home/me/legacy"
	t.beforeEach(function()
		saved, originals, options = {}, {}, nil
		projects = { "/old", "/favorite", "/new" }
		starred = { ["/favorite"] = true }
		local function mock(name, value)
			saved[name] = { package.loaded[name] }
			package.loaded[name] = value
		end
		mock("fox.projects.history", {
			list = function()
				return projects
			end,
		})
		mock("fox.projects.favorites", {
			key = function(p)
				return p
			end,
			load = function()
				return starred
			end,
		})
		mock("plugins.fox.tools.wsl", {
			get_recent_projects = function(check)
				expect(check).toBe(false)
				return { "/old", wsl_path }
			end,
			is_wsl_path = function(p)
				return p == wsl_path
			end,
		})
		mock("telescope.pickers", {
			new = function(opts)
				options = opts
				return { find = function() end }
			end,
		})
		mock("telescope.finders", {
			new_table = function(opts)
				local entries = {}
				for index, value in ipairs(opts.results) do
					entries[index] = opts.entry_maker(value)
					entries[index].index = index
				end
				return entries
			end,
		})
		mock("telescope.config", {
			values = {
				generic_sorter = function()
					return {
						scoring_function = function(_, prompt, line)
							return line:find(prompt, 1, true) and 0 or -1
						end,
					}
				end,
			},
		})
		mock("telescope.actions", {})
		mock("telescope.actions.state", {})
		mock("telescope.themes", {
			get_dropdown = function(opts)
				return opts
			end,
		})
		originals.command, originals.keymap = vim.api.nvim_create_user_command, vim.keymap.set
		originals.isdir, originals.open = vim.fn.isdirectory, _G.OpenRecentProjects
		vim.api.nvim_create_user_command, vim.keymap.set = function() end, function() end
		vim.fn.isdirectory = function(p)
			assert(p ~= wsl_path, "WSL paths must not be probed")
			return 1
		end
		dofile(vim.fn.getcwd() .. "/lua/plugins/editor/project.lua").config()
	end)
	t.afterEach(function()
		for name, value in pairs(saved) do
			package.loaded[name] = value[1]
		end
		vim.api.nvim_create_user_command, vim.keymap.set = originals.command, originals.keymap
		vim.fn.isdirectory, _G.OpenRecentProjects = originals.isdir, originals.open
	end)

	it("pins favorites above newest-first history, appending deduplicated legacy WSL entries", function()
		_G.OpenRecentProjects()
		local paths = vim.tbl_map(function(entry)
			return entry.value.path
		end, options.finder)
		expect(paths).toEqual({ "/favorite", "/new", "/old", wsl_path })
		expect(options.sorting_strategy).toBe("ascending")
	end)

	it("shows newest first without favorites and reflects reopened projects", function()
		starred = {}
		projects = { "/new", "/favorite", "/old" }
		_G.OpenRecentProjects()
		expect(options.finder[1].value.path).toBe("/old")
		expect(options.finder[2].value.path).toBe("/favorite")
		expect(options.finder[3].value.path).toBe("/new")
	end)

	it("filters search matches without changing favorite and recency priority", function()
		_G.OpenRecentProjects()
		local score = options.sorter.scoring_function
		expect(score(options.sorter, "", "/favorite", options.finder[1])).toBe(1)
		expect(score(options.sorter, "/", "/new", options.finder[2])).toBe(2)
		expect(score(options.sorter, "missing", "/new", options.finder[2])).toBe(-1)
	end)
end)
