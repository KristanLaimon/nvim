-- ============================================================================
-- tests/spec/core_project_spec.lua -- Contract tests for fox.core.project.
-- ============================================================================
-- Lookup ORDER is the contract here: `.foxnvim` wins over `.foxlocal`, which wins
-- over the legacy `.nvimfox`. A regression silently loads another directory's
-- settings, so each precedence rule gets its own test.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local project = require("fox.core.project")
local path = require("fox.core.path")

local root

--- Creates `<root>/<dir>/<name>` with placeholder JSON content.
local function touch_config(dir, name)
	local full = path.join(root, dir, name)
	path.ensure_dir(vim.fs.dirname(full))
	vim.fn.writefile({ "{}" }, full)
	return full
end

describe("fox.core.project.config_path", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
	end)

	afterEach(function()
		vim.fn.delete(root, "rf")
	end)

	it("defaults to .foxnvim when nothing exists yet", function()
		local file, exists = project.config_path("tasks.json", root)

		expect(file).toBe(path.join(root, ".foxnvim", "tasks.json"))
		expect(exists).toBeFalsy()
	end)

	it("finds an existing .foxnvim config", function()
		local expected = touch_config(".foxnvim", "launch.json")
		local file, exists = project.config_path("launch.json", root)

		expect(file).toBe(expected)
		expect(exists).toBeTruthy()
	end)

	it("falls back to .foxlocal when .foxnvim has no such file", function()
		local expected = touch_config(".foxlocal", "launch.json")

		expect(project.config_path("launch.json", root)).toBe(expected)
	end)

	it("falls back to the legacy .nvimfox directory last", function()
		local expected = touch_config(".nvimfox", "launch.json")

		expect(project.config_path("launch.json", root)).toBe(expected)
	end)

	it("prefers .foxnvim when several candidates exist", function()
		local expected = touch_config(".foxnvim", "launch.json")
		touch_config(".foxlocal", "launch.json")
		touch_config(".nvimfox", "launch.json")

		expect(project.config_path("launch.json", root)).toBe(expected)
	end)
end)

describe("fox.core.project.config_dir", function()
	beforeEach(function()
		root = path.normalize(vim.fn.tempname())
		vim.fn.mkdir(root, "p")
	end)

	afterEach(function()
		vim.fn.delete(root, "rf")
	end)

	it("creates and returns <root>/.foxnvim", function()
		local dir = project.config_dir(root)

		expect(dir).toBe(path.join(root, ".foxnvim"))
		expect(path.is_dir(dir)).toBeTruthy()
	end)
end)

describe("fox.core.project.root", function()
	it("stops at the nearest marker directory", function()
		local base = path.normalize(vim.fn.tempname())
		local nested = path.join(base, "src", "deep")
		path.ensure_dir(nested)
		vim.fn.writefile({ "{}" }, path.join(base, "package.json"))

		local found = path.normalize(vim.fs.dirname(vim.fs.find(project.root_markers, {
			upward = true,
			path = nested,
		})[1]))

		expect(found).toBe(base)
		vim.fn.delete(base, "rf")
	end)

	it("falls back to the cwd when no marker is found", function()
		local orig = project.root_markers
		project.root_markers = { "this-marker-never-exists-fox" }

		expect(path.normalize(project.root())).toBe(path.normalize(vim.fn.getcwd()))

		project.root_markers = orig
	end)

	it("prefers project root (cwd) over subfolder markers when inside cwd", function()
		local orig_cwd = vim.fn.getcwd()
		local base = path.normalize(vim.fn.tempname())
		local subfolder = path.join(base, "subfolder")
		path.ensure_dir(subfolder)
		vim.fn.writefile({ "{}" }, path.join(base, "go.mod"))
		vim.fn.writefile({ "all:" }, path.join(subfolder, "Makefile"))

		vim.cmd("cd " .. vim.fn.fnameescape(base))

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, path.join(subfolder, "main.go"))

		local resolved = path.normalize(project.root(buf))
		vim.cmd("cd " .. vim.fn.fnameescape(orig_cwd))
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(base, "rf")

		expect(resolved).toBe(base)
	end)
end)
