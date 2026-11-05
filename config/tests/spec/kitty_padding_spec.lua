local t = require("fox.lib.foxnvim.test")
local padding = require("fox.core.kitty_padding")

t.describe("Kitty editor padding", function()
	local original_send, original_uis, original_env, original_neovide, sent
	local env_names = { "KITTY_WINDOW_ID", "TMUX", "STY", "NVIM" }

	t.beforeEach(function()
		original_send, original_uis = vim.api.nvim_ui_send, vim.api.nvim_list_uis
		original_neovide = vim.g.neovide
		original_env = {}
		for _, name in ipairs(env_names) do
			original_env[name] = vim.env[name]
			vim.env[name] = nil
		end
		vim.env.KITTY_WINDOW_ID = "42"
		vim.g.neovide = nil
		sent = {}
		vim.api.nvim_ui_send = function(data)
			assert(data:sub(1, 12) == "\27P@kitty-cmd" and data:sub(-2) == "\27\\")
			sent[#sent + 1] = vim.json.decode(data:sub(13, -3))
		end
		vim.api.nvim_list_uis = function()
			return { { stdout_tty = true } }
		end
		padding.setup()
		sent = {}
	end)

	t.afterEach(function()
		vim.api.nvim_del_augroup_by_name("fox_kitty_padding")
		vim.api.nvim_ui_send, vim.api.nvim_list_uis = original_send, original_uis
		vim.g.neovide = original_neovide
		for _, name in ipairs(env_names) do
			vim.env[name] = original_env[name]
		end
	end)

	t.it("removes padding on entry and resume, restores defaults on suspend and exit", function()
		for _, event in ipairs({ "VimEnter", "UIEnter", "VimSuspend", "VimResume", "VimLeavePre" }) do
			vim.api.nvim_exec_autocmds(event, { group = "fox_kitty_padding" })
		end
		t.expect(#sent).toBe(5)
		for index, command in ipairs(sent) do
			t.expect(command.cmd).toBe("set-spacing")
			t.expect(command.no_response).toBe(true)
			t.expect(command.payload.match_window).toBe("id:42")
			t.expect(command.payload.all).toBe(nil)
			t.expect(command.payload.configured).toBe(nil)
			for _, edge in ipairs({ "top", "right", "bottom", "left" }) do
				local value = command.payload.settings["padding-" .. edge]
				t.expect(value).toBe((index == 3 or index == 5) and vim.NIL or 0)
			end
		end
	end)

	t.it("ignores headless and graphical UIs", function()
		for _, uis in ipairs({ {}, { { stdout_tty = false } } }) do
			vim.api.nvim_list_uis = function()
				return uis
			end
			vim.api.nvim_exec_autocmds("VimEnter", { group = "fox_kitty_padding" })
		end
		t.expect(#sent).toBe(0)
	end)

	t.it("ignores other terminals, multiplexers, embedded editors and Neovide", function()
		vim.env.KITTY_WINDOW_ID = nil
		vim.api.nvim_exec_autocmds("VimEnter", { group = "fox_kitty_padding" })
		vim.env.KITTY_WINDOW_ID = "42"
		for _, name in ipairs({ "TMUX", "STY", "NVIM" }) do
			vim.env[name] = "present"
			vim.api.nvim_exec_autocmds("VimEnter", { group = "fox_kitty_padding" })
			vim.env[name] = nil
		end
		vim.g.neovide = true
		vim.api.nvim_exec_autocmds("VimEnter", { group = "fox_kitty_padding" })
		t.expect(#sent).toBe(0)
	end)

	t.it("does not duplicate hooks when reloaded", function()
		padding.setup()
		sent = {}
		vim.api.nvim_exec_autocmds("VimEnter", { group = "fox_kitty_padding" })
		t.expect(#sent).toBe(1)
	end)
end)
