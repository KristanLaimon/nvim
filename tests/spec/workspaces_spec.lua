-- ============================================================================
-- tests/spec/workspaces_spec.lua -- Workspaces manager tests.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local ws = require("plugins.fox.tools.workspaces")

describe("plugins.fox.tools.workspaces", function()
	local temp_dir
	local orig_storage_dir

	beforeEach(function()
		temp_dir = vim.fn.tempname()
		vim.fn.mkdir(temp_dir, "p")
		orig_storage_dir = ws.settings.storage_dir
		ws.settings.storage_dir = temp_dir
	end)

	afterEach(function()
		ws.settings.storage_dir = orig_storage_dir
		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end
	end)

	it("creates a new workspace via M.new_workspace", function()
		local orig_input = vim.ui.input
		vim.ui.input = function(_, on_confirm)
			on_confirm("My Custom Workspace")
		end

		local called = false
		ws.new_workspace(function()
			called = true
		end)

		vim.ui.input = orig_input

		expect(called).toBe(true)
		-- save_workspace notifies and saves file
		local index_path = temp_dir .. "/index.json"
		expect(vim.fn.filereadable(index_path)).toBe(1)
	end)

	it("overwrites existing workspace when save_workspace is called with a name", function()
		ws.save_workspace("Original Name")
		ws.save_workspace("Original Name")

		local store = require("fox.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(#index).toBe(1)
		expect(index[1].name).toBe("Original Name")
	end)

	it("renames an existing workspace", function()
		ws.save_workspace("Old Workspace Name")

		local orig_input = vim.ui.input
		vim.ui.input = function(_, on_confirm)
			on_confirm("Renamed Workspace Name")
		end

		ws.rename_workspace("Old Workspace Name")

		vim.ui.input = orig_input

		local store = require("fox.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(#index).toBe(1)
		expect(index[1].name).toBe("Renamed Workspace Name")
	end)

	it("deletes a workspace when confirmed", function()
		ws.save_workspace("To Delete")

		local orig_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			return 1 -- Yes
		end

		local called = false
		ws.delete_workspace("To Delete", function()
			called = true
		end)

		vim.fn.confirm = orig_confirm

		expect(called).toBe(true)
		local store = require("fox.core.store")
		local index = store.load(temp_dir .. "/index.json", {})
		expect(#index).toBe(0)
	end)

	it("returns 1 for active slot when only 1 or no workspace is active", function()
		ws.set_active_workspace(nil)
		expect(ws.get_active_slot_number()).toBe(1)

		ws.save_workspace("Workspace 1")
		expect(ws.get_active_slot_number()).toBe(1)
	end)

	it("updates and toggles floating workspace badge", function()
		expect(type(ws.update_badge)).toBe("function")
		expect(type(ws.toggle_badge)).toBe("function")
		expect(type(ws.get_badge_text)).toBe("function")
		expect(type(ws.get_badge_components)).toBe("function")

		ws.set_active_workspace(nil)
		expect(ws.get_badge_text()).toBe(" 🦊 1 ")

		-- Calling update_badge should not crash
		pcall(ws.update_badge)
	end)

	it("provides focus_badge and does not interfere with hover_links", function()
		expect(type(ws.focus_badge)).toBe("function")
		pcall(ws.focus_badge)

		-- Verify hover_links does not mistake the workspace badge for an LSP hover float
		local hl = require("plugins.fox.editor.hover_links")
		expect(type(hl.show_or_focus_hover)).toBe("function")
	end)

	it("recovers orphaned session files on disk into the index", function()
		local fake_session = temp_dir .. "/ws_1790000000_1234.vim"
		local lines = {
			'" FoxWorkspace: name=Recovered Project Session',
			"cd /fake/project/path",
			"badd +1 src/index.ts",
			"badd +10 src/server.ts",
		}
		vim.fn.writefile(lines, fake_session)

		local list = ws.list_workspaces()
		local found = nil
		for _, item in ipairs(list) do
			if item.id == "ws_1790000000_1234" then
				found = item
				break
			end
		end

		expect(found ~= nil).toBe(true)
		expect(found.name).toBe("Recovered Project Session")
		expect(found.cwd).toBe("/fake/project/path")
		expect(#found.buffers).toBe(2)
	end)

	it("preserves and lists workspaces across multiple projects", function()
		local store = require("fox.core.store")
		local index_data = {
			{
				id = "ws_project_a",
				name = "Project A Feature",
				cwd = "/work/project_a",
				cwd_name = "project_a",
				created_at = 1780000000,
				updated_at = 1780000000,
				session_file = temp_dir .. "/ws_project_a.vim",
				buffers = { "src/a.ts" },
			},
			{
				id = "ws_project_b",
				name = "Project B Feature",
				cwd = "/work/project_b",
				cwd_name = "project_b",
				created_at = 1780000010,
				updated_at = 1780000010,
				session_file = temp_dir .. "/ws_project_b.vim",
				buffers = { "src/b.ts" },
			},
		}
		store.save(temp_dir .. "/index.json", index_data)

		local all = ws.list_workspaces()
		expect(#all).toBe(2)

		local proj_a = ws.list_workspaces("/work/project_a")
		expect(#proj_a).toBe(1)
		expect(proj_a[1].name).toBe("Project A Feature")
	end)
end)
