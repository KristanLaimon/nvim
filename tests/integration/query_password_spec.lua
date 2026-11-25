local t = require("fox.lib.foxnvim.test")

t.describe("Query password input", function()
	t.it("shows dots in a centered float and accepts a password without opening the command line", function()
		local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, {
			rpc = true,
		})
		assert(channel > 0)
		local function call(method, ...)
			return vim.rpcrequest(channel, method, ...)
		end
		local ok, err = xpcall(function()
			call("nvim_ui_attach", 100, 40, { rgb = true })
			local result = call(
				"nvim_exec_lua",
				[[
				vim.opt.rtp:prepend(...)
				local modal = require("plugins.fox.ui.input_modal")
				local source = vim.api.nvim_get_current_win()
				local observed = {}
				local paste = vim.paste
				vim.cmd.normal({ "qa", bang = true })
				assert(vim.fn.reg_recording() == "a")
				vim.g.clipboard = {
					name = "Password test clipboard",
					copy = { ["+"] = function() end, ["*"] = function() end },
					paste = { ["+"] = function() return { { "!" }, "v" } end, ["*"] = function() return {{}, "v"} end },
				}
				vim.defer_fn(function()
					local win = vim.api.nvim_get_current_win()
					local config = vim.api.nvim_win_get_config(win)
					observed.centered = config.relative == "editor" and config.row > 0 and config.col > 0
					observed.command_line = vim.fn.getcmdtype()
					vim.api.nvim_input("abé<BS>c<C-v>")
				end, 50)
				vim.defer_fn(function()
					observed.mask = vim.api.nvim_get_current_line()
					vim.api.nvim_input("<CR>")
				end, 100)
				observed.password = modal.secret("Database password")
				observed.closed = vim.api.nvim_get_current_win() == source and vim.paste == paste
				observed.macro_is_private = vim.fn.reg_recording() == "" and not vim.fn.getreg("a"):find("abc", 1, true)
				vim.defer_fn(function()
					vim.api.nvim_input("<Esc>")
				end, 50)
				observed.cancelled = modal.secret("Database password") == nil
				return observed
			]],
				{ vim.fn.stdpath("config") }
			)
			t.expect(result).toEqual({
				centered = true,
				command_line = "",
				mask = "••••",
				password = "abc!",
				closed = true,
				macro_is_private = true,
				cancelled = true,
			})
		end, debug.traceback)
		vim.fn.jobstop(channel)
		assert(ok, err)
	end)
end)
