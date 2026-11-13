-- ============================================================================
-- tests/spec/buffer_language_spec.lua -- Buffer Language & Filetype Manager
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local buf_lang = require("plugins.fox.tools.buffer_language")

describe("plugins.fox.tools.buffer_language", function()
	it("registers user commands and setup properly", function()
		buf_lang.setup()
		local cmds = vim.api.nvim_get_commands({})
		expect(cmds["SetBufferLanguage"]).toBeDefined()
		expect(cmds["FoxSetBufferLanguage"]).toBeDefined()
		expect(cmds["ResetBufferLanguage"]).toBeDefined()
		expect(cmds["FoxResetBufferLanguage"]).toBeDefined()
		expect(cmds["ListBufferLanguages"]).toBeDefined()
		expect(cmds["FoxListBufferLanguages"]).toBeDefined()
	end)

	it("has languages list containing Docker, Docker Compose, JS, Python, etc.", function()
		local has_docker = false
		local has_compose = false
		local has_js = false
		local has_py = false

		for _, l in ipairs(buf_lang.languages) do
			if l.filetype == "dockerfile" then
				has_docker = true
			end
			if l.filetype == "yaml.docker-compose" then
				has_compose = true
			end
			if l.filetype == "javascript" then
				has_js = true
			end
			if l.filetype == "python" then
				has_py = true
			end
		end

		expect(has_docker).toBe(true)
		expect(has_compose).toBe(true)
		expect(has_js).toBe(true)
		expect(has_py).toBe(true)
	end)

	it("persists and reads filetype associations to and from filetypes.json", function()
		local temp_root = vim.fs.normalize(vim.fn.tempname() .. "_lang_test")
		vim.fn.mkdir(temp_root .. "/.foxnvim", "p")

		buf_lang.clear_cache(temp_root)

		-- Save association
		local ok = buf_lang.save_association(temp_root, "main.txt", "javascript")
		expect(ok).toBe(true)

		-- Read association
		local loaded = buf_lang.load_associations(temp_root)
		expect(loaded["main.txt"]).toBe("javascript")

		-- Save another association (e.g. docker-compose)
		buf_lang.save_association(temp_root, "services.dev.yml", "yaml.docker-compose")
		local loaded2 = buf_lang.load_associations(temp_root)
		expect(loaded2["services.dev.yml"]).toBe("yaml.docker-compose")

		-- Clear association
		buf_lang.save_association(temp_root, "main.txt", nil)
		local loaded3 = buf_lang.load_associations(temp_root)
		expect(loaded3["main.txt"]).toBe(nil)
		expect(loaded3["services.dev.yml"]).toBe("yaml.docker-compose")

		-- Cleanup
		pcall(vim.fn.delete, temp_root, "rf")
	end)

	it("applies filetype to buffer and sets Treesitter and FileType", function()
		local buf = vim.api.nvim_create_buf(false, true)
		buf_lang.apply_filetype(buf, "javascript", "javascript")
		expect(vim.bo[buf].filetype).toBe("javascript")

		buf_lang.apply_filetype(buf, "yaml.docker-compose", "yaml")
		expect(vim.bo[buf].filetype).toBe("yaml.docker-compose")

		buf_lang.apply_filetype(buf, "dockerfile", "dockerfile")
		expect(vim.bo[buf].filetype).toBe("dockerfile")

		vim.api.nvim_buf_delete(buf, { force = true })
	end)
end)
