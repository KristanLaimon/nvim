-- ============================================================================
-- tests/spec/environments_spec.lua -- Environments manager unit tests.
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect, beforeEach, afterEach = t.describe, t.it, t.expect, t.beforeEach, t.afterEach
local envs = require("plugins.fox.tools.environments")

describe("plugins.fox.tools.environments", function()
	local temp_dir
	local orig_envs
	local orig_active_slot

	beforeEach(function()
		temp_dir = vim.fn.tempname()

		orig_envs = vim.deepcopy(_G._fox_environments or {})
		orig_active_slot = _G._fox_active_env_slot or 1

		_G._fox_environments = {}
		_G._fox_active_env_slot = 1
	end)

	afterEach(function()
		_G._fox_environments = orig_envs
		_G._fox_active_env_slot = orig_active_slot

		if temp_dir and vim.fn.isdirectory(temp_dir) == 1 then
			vim.fn.delete(temp_dir, "rf")
		end
	end)

	it("manages slot creation and retrieval up to 9 slots", function()
		local slot1_dir = vim.fn.stdpath("config")
		local env1 = envs.create_environment(1, slot1_dir, "MyConfig", false)
		expect(env1 ~= nil).toBe(true)
		expect(env1.slot).toBe(1)
		expect(env1.name).toBe("MyConfig")
		expect(env1.neotree_open).toBe(false)

		local fetched = envs.get_environment(1)
		expect(fetched ~= nil).toBe(true)
		expect(fetched.name).toBe("MyConfig")
		expect(envs.get_active_count()).toBe(1)
		expect(envs.has_multiple_environments()).toBe(false)
		-- Indicator is empty when <= 1 environment
		expect(envs.indicator_status()).toBe("")
	end)

	it("shows statusline indicator only when > 1 environments are active", function()
		local dir1 = vim.fn.stdpath("config")
		local dir2 = vim.fn.stdpath("data")

		envs.create_environment(1, dir1, "Project1", false)
		envs.create_environment(2, dir2, "Project2", false)

		expect(envs.get_active_count()).toBe(2)
		expect(envs.has_multiple_environments()).toBe(true)

		_G._fox_active_env_slot = 1
		local ind1 = envs.indicator_status()
		expect(ind1:find("Project1") ~= nil).toBe(true)
		expect(ind1:find("%[1:") ~= nil).toBe(true)

		_G._fox_active_env_slot = 2
		local ind2 = envs.indicator_status()
		expect(ind2:find("Project2") ~= nil).toBe(true)
		expect(ind2:find("%[2:") ~= nil).toBe(true)
	end)

	it("renames an environment", function()
		local dir = vim.fn.stdpath("config")
		envs.create_environment(1, dir, "InitialName", false)

		envs.rename_environment(1, "UpdatedName")
		local env = envs.get_environment(1)
		expect(env.name).toBe("UpdatedName")
	end)

	it("filters buffers based on active environment slot", function()
		local dir1 = vim.fn.stdpath("config")
		local dir2 = vim.fn.stdpath("data")

		envs.create_environment(1, dir1, "SlotOne", false)
		envs.create_environment(2, dir2, "SlotTwo", false)

		local buf1 = vim.api.nvim_create_buf(true, false)
		vim.b[buf1].fox_env_slot = 1

		local buf2 = vim.api.nvim_create_buf(true, false)
		vim.b[buf2].fox_env_slot = 2

		_G._fox_active_env_slot = 1
		expect(envs.is_buffer_in_current_environment(buf1)).toBe(true)
		expect(envs.is_buffer_in_current_environment(buf2)).toBe(false)

		_G._fox_active_env_slot = 2
		expect(envs.is_buffer_in_current_environment(buf1)).toBe(false)
		expect(envs.is_buffer_in_current_environment(buf2)).toBe(true)

		pcall(vim.api.nvim_buf_delete, buf1, { force = true })
		pcall(vim.api.nvim_buf_delete, buf2, { force = true })
	end)

	it("closes an environment and cleans up its buffers and terminals", function()
		local dir = vim.fn.stdpath("config")
		local env = envs.create_environment(1, dir, "ToClose", false)

		local buf = vim.api.nvim_create_buf(true, false)
		vim.b[buf].fox_env_slot = 1

		local term_buf = vim.api.nvim_create_buf(true, false)
		env.terminals = { [1] = { buf = term_buf, win = nil } }

		local orig_confirm = vim.fn.confirm
		vim.fn.confirm = function()
			return 1 -- Yes
		end

		envs.close_environment(1)
		vim.fn.confirm = orig_confirm

		expect(envs.get_environment(1)).toBe(nil)
		expect(envs.get_active_count()).toBe(0)
		expect(vim.api.nvim_buf_is_valid(buf)).toBe(false)
		expect(vim.api.nvim_buf_is_valid(term_buf)).toBe(false)
	end)

	it("keeps environment slots in RAM without creating storage", function()
		envs.create_environment(1, vim.fn.stdpath("config"), "Memory", false)
		envs.rename_environment(1, "Renamed")
		expect(vim.fn.isdirectory(temp_dir)).toBe(0)
		expect(envs.get_environment(1).session_file).toBe(nil)
		expect(envs.save_index).toBe(nil)
		expect(envs.restore_all).toBe(nil)
	end)

	it("remembers a changed project when switching away and back", function()
		local cwd = vim.fn.getcwd()
		vim.fn.mkdir(temp_dir .. "/one", "p")
		vim.fn.mkdir(temp_dir .. "/two", "p")
		vim.fn.mkdir(temp_dir .. "/recent", "p")
		local ok, err = pcall(function()
			vim.api.nvim_set_current_dir(temp_dir .. "/one")
			envs.create_environment(1, temp_dir .. "/one", nil, false)
			envs.create_environment(2, temp_dir .. "/two", "Custom", false)
			vim.api.nvim_set_current_dir(temp_dir .. "/recent")
			envs.update_current_directory()
			expect(envs.get_environment(1).cwd_name).toBe("recent")
			expect(envs.get_environment(1).name).toBe("recent")
			envs.switch_environment(2)
			expect(envs.get_environment(2).name).toBe("Custom")
			envs.switch_environment(1)
			expect(require("fox.core.path").normalize(vim.fn.getcwd())).toBe(
				require("fox.core.path").normalize(temp_dir .. "/recent")
			)
			expect(vim.fn.isdirectory(temp_dir .. "/recent/.foxnvim/environments")).toBe(0)
		end)
		vim.api.nvim_set_current_dir(cwd)
		assert(ok, err)
	end)

	it("provides select_project_for_slot to configure environment slots", function()
		expect(type(envs.select_project_for_slot)).toBe("function")
	end)

	it("keeps hidden preview buffers unlisted when returning to an environment", function()
		local cwd = vim.fn.getcwd()
		vim.fn.mkdir(temp_dir .. "/one", "p")
		vim.fn.mkdir(temp_dir .. "/two", "p")
		local hidden = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(hidden, temp_dir .. "/one/preview.txt")
		vim.b[hidden].fox_env_slot = 1
		local ok, err = pcall(function()
			vim.api.nvim_set_current_dir(temp_dir .. "/one")
			envs.create_environment(1, temp_dir .. "/one", nil, false)
			envs.create_environment(2, temp_dir .. "/two", nil, false)
			envs.switch_environment(2)
			envs.switch_environment(1)
			expect(vim.bo[hidden].buflisted).toBe(false)
		end)
		vim.api.nvim_buf_delete(hidden, { force = true })
		vim.api.nvim_set_current_dir(cwd)
		assert(ok, err)
	end)

	it("changes directory when assigning a new project to the active slot", function()
		local cwd = vim.fn.getcwd()
		vim.fn.mkdir(temp_dir, "p")
		local ok, err = pcall(function()
			envs.create_environment(1, temp_dir, nil, true)
			expect(require("fox.core.path").equals(vim.fn.getcwd(), temp_dir)).toBe(true)
		end)
		vim.api.nvim_set_current_dir(cwd)
		assert(ok, err)
	end)
end)
