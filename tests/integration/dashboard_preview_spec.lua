local t = require("fox.lib.foxnvim.test")
local root = vim.fn.stdpath("config")
local preview_dir = root .. "/tests/temp"

local sizes = {
	{ 180, 45 },
	{ 150, 45 },
	{ 149, 45 },
	{ 139, 45 },
	{ 140, 45 },
	{ 110, 30 },
	{ 100, 22 },
	{ 80, 24 },
	{ 50, 35 },
	{ 40, 20 },
}

t.describe("dashboard terminal previews", function()
	for _, size in ipairs(sizes) do
		local width, height = size[1], size[2]
		t.it(("renders %dx%d without clipping the menu or quote"):format(width, height), function()
			assert(vim.fn.mkdir(preview_dir, "p") == 1 or vim.fn.isdirectory(preview_dir) == 1)
			local filename = ("dashboard-%dx%d-%s-%s.preview"):format(
				width,
				height,
				tostring(vim.uv.hrtime()),
				vim.fn.fnamemodify(vim.fn.tempname(), ":t")
			)
			local path = preview_dir .. "/" .. filename
			local channel = vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE" }, {
				rpc = true,
			})
			assert(channel > 0, "could not start Neovim for dashboard preview")
			local function call(method, ...)
				return vim.rpcrequest(channel, method, ...)
			end
			local ok, err = xpcall(function()
				call("nvim_ui_attach", width, height, { rgb = true })
				local lines = call(
					"nvim_exec_lua",
					[[
					local root = ...
					vim.opt.rtp:prepend(root)
					local art = require('fox.ui.dashboard_art')
					art.quotes = { 'May the fox be with you.' }
					art.authors = { 'Obi-Wan Kenfoxi' }
					art.foxes = { art.foxes[2] }
					require('plugins.ui.dashboard').config()
					vim.cmd('redraw')
					local screen = {}
					for y = 1, vim.o.lines do
						local cells = {}
						for x = 1, vim.o.columns do cells[#cells + 1] = vim.fn.screenstring(y, x) end
						screen[#screen + 1] = table.concat(cells)
					end
					return screen
				]],
					{ root }
				)
				assert(vim.fn.writefile(lines, path) == 0, "could not write " .. path)
				local screen = table.concat(vim.fn.readfile(path), "\n")
				assert(screen:find("May the fox be with you.", 1, true), "quote is missing from " .. path)
				assert(screen:find("- Obi-Wan Kenfoxi", 1, true), "attribution is missing from " .. path)
				assert(not screen:find("Environment:", 1, true), "environment appears below the quote in " .. path)
				assert(screen:find("Recent projects", 1, true), "first menu entry is missing from " .. path)
				assert(screen:find("Vim motions:", 1, true), "last menu entry is missing from " .. path)
				if width >= 110 and height >= 30 then
					assert(screen:find("⢀⣆", 1, true), "fox artwork is missing from " .. path)
					if width >= 140 and height >= 32 then
						assert(screen:find("/::|", 1, true), "large logo is missing from " .. path)
					else
						assert(screen:find("_____", 1, true), "logo is missing from " .. path)
					end
				end
				local resized_width, resized_height = width >= 100 and 80 or 140, width >= 100 and 24 or 45
				call("nvim_ui_try_resize", resized_width, resized_height)
				local resized = call(
					"nvim_exec_lua",
					[[
					local width, height = ...
					assert(vim.wait(2000, function() return vim.o.columns == width and vim.o.lines == height end))
					vim.wait(100)
					vim.cmd('redraw')
					local screen = {}
					for y = 1, vim.o.lines do
						local cells = {}
						for x = 1, vim.o.columns do cells[#cells + 1] = vim.fn.screenstring(y, x) end
						screen[#screen + 1] = table.concat(cells)
					end
					return screen
				]],
					{ resized_width, resized_height }
				)
				assert(vim.fn.writefile(resized, path) == 0, "could not write resized preview " .. path)
				local resized_screen = table.concat(resized, "\n")
				assert(resized_screen:find("May the fox be with you.", 1, true), "quote missing after resize")
				assert(resized_screen:find("- Obi-Wan Kenfoxi", 1, true), "attribution missing after resize")
				assert(resized_screen:find("Vim motions:", 1, true), "menu missing after resize")
				if resized_width == 140 then
					assert(resized_screen:find("/::|", 1, true), "large logo missing after resize")
					local quote_row
					for row, line in ipairs(resized) do
						if line:find("May the fox be with you.", 1, true) then
							quote_row = row
						end
					end
					assert(quote_row and quote_row > 5, "quote is not vertically centered after resize")
				end
			end, debug.traceback)
			pcall(call, "nvim_command", "qa!")
			if not ok then
				error(err .. "\nPreview retained at " .. path)
			end
			if vim.env.FOX_KEEP_DASHBOARD_PREVIEWS ~= "1" then
				assert(vim.fn.delete(path) == 0, "could not remove " .. path)
			else
				print("Dashboard preview: " .. path)
			end
		end)
	end
end)
