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
		local original_root, original_system, original_spawn = project.root, vim.system, vim.uv.spawn
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
$native = Add-Type -Name ExplorerVisibility -Namespace Fox -PassThru -MemberDefinition '
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr window);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr window);';
foreach ($window in @($shell.Windows())) { try {
 if ($window.Document.Folder.Self.Path -eq $env:FOX_OPEN_PATH) {
  if ($native::IsWindowVisible($window.HWND) -and -not $native::IsIconic($window.HWND)) { $found++ }
  if ($env:FOX_CLOSE_TEST -eq '1') { $window.Quit() }
 }
} catch {} }; [Console]::Write($found) ]],
			}, { text = true, env = { FOX_OPEN_PATH = dir, FOX_CLOSE_TEST = close and "1" or "0" } }):wait(10000)
		end
		local ok, err = xpcall(function()
			vim.uv.spawn = function(command, options, callback)
				return original_spawn(command, options, function(code, signal)
					if command == "explorer.exe" then
						results[#results + 1] = { code = code }
					end
					if callback then
						callback(code, signal)
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
			require("neo-tree.command").execute({ action = "focus", dir = vim.fs.dirname(dir) })
			local state = require("neo-tree.sources.manager").get_state("filesystem")
			local node_path = require("neo-tree.utils").normalize_path(dir)
			t.expect(vim.wait(3000, function()
				return state.tree and state.tree:get_node(node_path) ~= nil
			end)).toBe(true)
			require("neo-tree.ui.renderer").focus_node(state, node_path)
			t.expect(state.tree:get_node().type).toBe("directory")
			local cursor = vim.api.nvim_win_get_cursor(state.winid)
			for idx, key in ipairs({ "<C-S-CR>" }) do
				vim.api.nvim_set_current_win(state.winid)
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "xt", false)
				verify_open(idx)
				t.expect(vim.api.nvim_win_get_cursor(state.winid)).toEqual(cursor)
				t.expect(vim.api.nvim_get_mode().mode).toBe("n")
			end
			project.root = function()
				return dir
			end
			vim.cmd("OpenRootInExplorer")
			verify_open(2)
		end, debug.traceback)
		project.root, vim.uv.spawn = original_root, original_spawn
		vim.cmd("Neotree close")
		explorer_windows(true)
		vim.fn.delete(dir, "d")
		assert(ok, err)
	end)
end)
