local t = require("fox.lib.foxnvim.test")

t.describe("dashboard initial startup", function()
	local function startup(args, check)
		local command = { vim.v.progpath, "--headless", "-i", "NONE" }
		vim.list_extend(command, args)
		vim.list_extend(command, { "-c", "lua " .. check, "-c", "qa!" })
		local result = vim.system(command, { text = true, timeout = 15000 }):wait()
		assert(result.code == 0, (result.stdout or "") .. (result.stderr or ""))
	end

	t.it("renders the banner and menu before VimEnter or scheduled work", function()
		startup(
			{},
			[[
			assert(vim.v.vim_did_enter == 0)
			assert(vim.bo.filetype == "alpha", "dashboard was deferred")
			local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
			assert(text:find("Foxes can be coders too!", 1, true), "missing banner")
			assert(text:find("Recent projects", 1, true), "missing menu")
		]]
		)
	end)

	t.it("preserves files supplied on the command line", function()
		startup(
			{ vim.fn.stdpath("config") .. "/init.lua" },
			[[
			assert(vim.bo.filetype ~= "alpha")
			assert(vim.api.nvim_buf_get_name(0):match("init%.lua$"))
		]]
		)
	end)
end)
