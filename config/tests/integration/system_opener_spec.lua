local t = require("fox.lib.foxnvim.test")

t.describe("Windows folder shell associations", function()
	t.it("opens a literal folder through Neo-tree and the project-root command in real Explorer", function()
		if vim.fn.has("win32") ~= 1 then
			return
		end
		require("lazy").load({ plugins = { "neo-tree.nvim", "image_viewer" } })
		local dir = vim.fn.tempname() .. " folder & quote' %"
		vim.fn.mkdir(dir, "p")
		local project = require("fox.core.project")
		local original_root, original_system = project.root, vim.system
		local results = {}
		local function explorer_windows(close)
			return original_system({
				"powershell.exe",
				"-NoProfile",
				"-NonInteractive",
				"-WindowStyle",
				"Hidden",
				"-Command",
				[[ $found = 0; $shell = New-Object -ComObject Shell.Application;
foreach ($window in @($shell.Windows())) { try {
 if ($window.Document.Folder.Self.Path -eq $env:FOX_OPEN_PATH) {
  $found++; if ($env:FOX_CLOSE_TEST -eq '1') { $window.Quit() }
 }
} catch {} }; [Console]::Write($found) ]],
			}, { text = true, env = { FOX_OPEN_PATH = dir, FOX_CLOSE_TEST = close and "1" or "0" } }):wait(10000)
		end
		local ok, err = xpcall(function()
			vim.system = function(command, options, callback)
				return original_system(command, options, function(result)
					if command[1] == "explorer.exe" then
						results[#results + 1] = result
					end
					if callback then
						callback(result)
					end
				end)
			end
			local function verify_open(count)
				t.expect(vim.wait(15000, function()
					return #results == count
				end)).toBe(true)
				assert(results[count].code == 0 or results[count].code == 1, results[count].stderr)
				t.expect(vim.wait(10000, function()
					local result = explorer_windows(false)
					assert(result.code == 0, result.stderr)
					return (tonumber(result.stdout) or 0) > 0
				end, 200)).toBe(true)
				explorer_windows(true)
			end
			local open = require("neo-tree").peek_config().commands.open_with_system_app
			open({ tree = {
				get_node = function()
					return { type = "directory", path = dir }
				end,
			} })
			verify_open(1)
			project.root = function()
				return dir
			end
			vim.cmd("OpenRootInExplorer")
			verify_open(2)
		end, debug.traceback)
		project.root, vim.system = original_root, original_system
		explorer_windows(true)
		vim.fn.delete(dir, "d")
		assert(ok, err)
	end)
end)
