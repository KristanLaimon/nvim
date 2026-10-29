-- ============================================================================
-- PLUGIN: telescope.nvim -- the fuzzy finder, plus a folder-opening picker.
-- ============================================================================
-- WHAT THIS FILE ADDS ON TOP OF TELESCOPE
--   1. Two file finders with a sensible search strategy per project:
--        <C-k>           respect .gitignore (git ls-files inside a repo)
--        <C-A-k> / <C-?> ignore it entirely (everything, including hidden)
--      Both are also exported as `_G.FindFilesGitignore` / `_G.FindFilesNoIgnore`,
--      which is what the keymaps in lua/keymaps/search.lua call.
--   2. `:TelescopeOpenFolder` -- browse directories and ADOPT one as the project:
--      close splits, drop the old buffers, cd, record it, reopen the tree.
--   3. `:TelescopeFindFilesSplit{Left,Below,Above,Right}` -- find a file and open
--      it in a split.
--
-- KEY OWNERSHIP
--   The <C-S-h/j/k/l> split keys are bound in lua/keymaps/search.lua, not
--   here, because <C-S-j> has to fall through to the DAP repl during a debug
--   session. This file only provides the commands they drive.
-- ============================================================================

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local settings = {
	--- Find files, honouring .gitignore.
	find_keys = { "<C-k>", "<C-K>" },

	--- Find files, ignoring .gitignore. Several aliases: Alt/Meta combinations
	--- arrive differently depending on terminal and GUI.
	find_all_keys = {
		"<C-A-k>",
		"<C-A-K>",
		"<C-M-k>",
		"<C-M-K>",
		"<A-C-k>",
		"<A-C-K>",
		"<M-C-k>",
		"<M-C-K>",
		"<C-S-/>",
		"<C-?>",
	},
	live_grep_key = "<C-f>",
	help_tags_key = nil,
	desktop_explorer_key = "<C-/>",
	wsl_explorer_key = nil,

	--- Directory scan depth for the folder picker, and what it never descends into.
	folder_scan_depth = 3,
	folder_excludes = { ".git", "node_modules", ".cache" },

	--- Direction -> Ex command and label, for the split finders.
	splits = {
		h = { command = "leftabove vsplit", label = "Left (←)" },
		j = { command = "rightbelow split", label = "Down (↓)" },
		k = { command = "leftabove split", label = "Up (↑)" },
		l = { command = "rightbelow vsplit", label = "Right (→)" },
	},
}

-- ============================================================================
-- LAZY.NVIM SPEC
-- ============================================================================

return {
	"nvim-telescope/telescope.nvim",
	branch = "master",
	cmd = {
		"Telescope",
		"TelescopeOpenFolder",
		"TelescopeFileBrowserDesktop",
		"TelescopeFindFilesSplitLeft",
		"TelescopeFindFilesSplitBelow",
		"TelescopeFindFilesSplitAbove",
		"TelescopeFindFilesSplitRight",
		"TelescopeFindFilesGitignore",
		"TelescopeFindFilesNoIgnore",
	},
	keys = {
		{
			"<C-k>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					vim.cmd("TelescopeFindFilesGitignore")
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-K>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					vim.cmd("TelescopeFindFilesGitignore")
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-/>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					vim.cmd("TelescopeFindFilesGitignore")
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-_>",
			function()
				if _G.FindFilesGitignore then
					_G.FindFilesGitignore()
				else
					vim.cmd("TelescopeFindFilesGitignore")
				end
			end,
			mode = { "n", "i" },
			desc = "Telescope find files (excludes .gitignore)",
		},
		{
			"<C-A-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<C-A-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<C-M-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<C-M-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<A-C-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<A-C-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<M-C-k>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{
			"<M-C-K>",
			"<cmd>TelescopeFindFilesNoIgnore<CR>",
			mode = { "n", "i" },
			desc = "Telescope find files (ignoring .gitignore)",
		},
		{ "<C-f>", "<cmd>Telescope live_grep<CR>", mode = { "n", "i" }, desc = "Telescope live grep" },
		{ "<C-S-y>", "<cmd>TelescopeOpenFolder<CR>", mode = { "n", "i" }, desc = "Telescope open folder" },
		{ "<C-/>", "<cmd>TelescopeFileBrowserDesktop<CR>", mode = { "n", "i", "v" }, desc = "Open Desktop File Explorer" },
	},
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-file-browser.nvim",
	},
	config = function()
		local telescope = require("telescope")
		local builtin = require("telescope.builtin")
		local actions = require("telescope.actions")
		local action_state = require("telescope.actions.state")

		local default_ignore_patterns = {
			"node_modules[/\\]",
			"node_modules$",
			"%.git[/\\]",
			"%.git$",
		}

		telescope.setup({
			defaults = {
				file_ignore_patterns = default_ignore_patterns,
				vimgrep_arguments = {
					"rg",
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--smart-case",
					"--hidden",
					"--no-require-git",
					"--glob",
					"!**/.git/*",
				},
				mappings = {
					n = {
						-- `?` shows the context help for whatever picker is open.
						["?"] = function()
							require("plugins.fox.context_help").show_help()
						end,
					},
				},
			},
		})

		-- ------------------------------------------------------------------
		-- File finders
		-- ------------------------------------------------------------------

		--- True when the working directory is inside a git repository.
		--- @return boolean
		local function in_git_repo()
			local cwd = vim.fn.getcwd()
			if vim.fn.isdirectory(cwd .. "/.git") == 1 then
				return true
			end

			local result = vim.system({ "git", "-C", cwd, "rev-parse", "--is-inside-work-tree" }, { text = true }):wait()
			return result and result.code == 0 and result.stdout ~= nil and result.stdout:match("true") ~= nil
		end

		--- Ensures focus is in a main code buffer window before launching a picker,
		--- preventing files from accidentally opening inside Neo-tree or terminal splits.
		local function ensure_code_window()
			local ok, dock = pcall(require, "fox.core.dock")
			if not ok then
				return
			end
			local cur_win = vim.api.nvim_get_current_win()
			if not dock.is_code_win(cur_win) then
				local target = dock.find_code_win()
				if target and vim.api.nvim_win_is_valid(target) then
					vim.api.nvim_set_current_win(target)
				else
					pcall(vim.cmd, "wincmd l")
					local new_win = vim.api.nvim_get_current_win()
					if not dock.is_code_win(new_win) then
						pcall(vim.cmd, "vsplit")
						pcall(vim.cmd, "enew")
					end
				end
			end
		end

		--- Finds files, respecting .gitignore.
		--- Uses rg/fd with --no-require-git so ignore rules are strictly honored
		--- in git repos, non-git repos, subfolders, and WSL workspaces alike.
		local function find_files_gitignore(opts)
			ensure_code_window()
			opts = opts or {}
			if vim.fn.executable("rg") == 1 then
				builtin.find_files(vim.tbl_extend("force", {
					find_command = { "rg", "--files", "--color=never", "--hidden", "--no-require-git", "--glob", "!**/.git/*" },
					file_ignore_patterns = default_ignore_patterns,
				}, opts))
			elseif vim.fn.executable("fd") == 1 then
				builtin.find_files(vim.tbl_extend("force", {
					find_command = { "fd", "--type", "f", "--hidden", "--no-require-git", "--exclude", ".git" },
					file_ignore_patterns = default_ignore_patterns,
				}, opts))
			elseif in_git_repo() then
				builtin.git_files(vim.tbl_extend("force", {
					recurse_submodules = true,
					file_ignore_patterns = default_ignore_patterns,
				}, opts))
			else
				builtin.find_files(vim.tbl_extend("force", {
					no_ignore = false,
					hidden = true,
					file_ignore_patterns = default_ignore_patterns,
				}, opts))
			end
		end

		--- Finds every file, ignore rules included -- for build output and vendored
		--- code you deliberately want to open.
		local function find_files_no_ignore()
			ensure_code_window()
			if vim.fn.executable("rg") == 1 then
				builtin.find_files({
					find_command = { "rg", "--files", "--color=never", "--no-ignore", "--hidden", "--glob", "!**/.git/*" },
					file_ignore_patterns = {},
				})
			elseif vim.fn.executable("fd") == 1 then
				builtin.find_files({
					find_command = { "fd", "--type", "f", "--no-ignore", "--hidden", "--exclude", ".git" },
					file_ignore_patterns = {},
				})
			else
				builtin.find_files({ no_ignore = true, hidden = true, file_ignore_patterns = {} })
			end
		end

		-- Exported for lua/keymaps/search.lua, which binds these before
		-- telescope has loaded.
		_G.FindFilesGitignore = find_files_gitignore
		_G.FindFilesNoIgnore = find_files_no_ignore

		vim.api.nvim_create_user_command("TelescopeFindFilesGitignore", function()
			find_files_gitignore()
		end, {
			desc = "Find files respecting .gitignore",
		})

		vim.api.nvim_create_user_command("TelescopeFindFilesNoIgnore", find_files_no_ignore, {
			desc = "Find files ignoring .gitignore",
		})

		for _, key in ipairs(settings.find_keys) do
			vim.keymap.set({ "n", "i" }, key, find_files_gitignore, {
				noremap = true,
				silent = true,
				desc = "Telescope find files (excludes .gitignore)",
			})
		end
		for _, key in ipairs(settings.find_all_keys) do
			vim.keymap.set({ "n", "i" }, key, find_files_no_ignore, {
				noremap = true,
				silent = true,
				desc = "Telescope find files (ignoring .gitignore)",
			})
		end

		if settings.live_grep_key then
			vim.keymap.set({ "n", "i" }, settings.live_grep_key, builtin.live_grep, { desc = "Telescope live grep" })
		end
		if settings.help_tags_key then
			vim.keymap.set("n", settings.help_tags_key, builtin.help_tags, { desc = "Telescope help tags" })
		end

		-- ------------------------------------------------------------------
		-- Folder picker
		-- ------------------------------------------------------------------

		local open_folder_picker

		--- Browses directories; <CR> adopts one (or calls on_select), <C-l> descends, <C-h> goes up.
		--- @param opts table|nil `{ cwd = string }` Directory to browse.
		--- @param on_select function|nil `function(dir)` Optional callback when selected.
		open_folder_picker = function(opts, on_select)
			opts = opts or {}
			return require("plugins.fox.tools.file_explorer").open_folder_picker(opts, on_select)
		end

		_G.OpenFolderPicker = open_folder_picker

		pcall(telescope.load_extension, "file_browser")

		vim.api.nvim_create_user_command("TelescopeOpenFolder", function()
			open_folder_picker()
		end, { desc = "Browse folders and open one as the active project" })

		vim.api.nvim_create_user_command("TelescopeFileBrowserDesktop", function()
			require("plugins.fox.tools.file_explorer").open_desktop_explorer()
		end, { desc = "Open the floating desktop file explorer" })
		if settings.desktop_explorer_key then
			vim.keymap.set({ "n", "i" }, settings.desktop_explorer_key, function()
				require("plugins.fox.tools.file_explorer").open_desktop_explorer()
			end, { desc = "Open Desktop File Explorer" })
		end

		-- ------------------------------------------------------------------
		-- Split finders
		-- ------------------------------------------------------------------

		--- Finds a file and opens it in a split in `direction`.
		--- @param direction "h"|"j"|"k"|"l"
		local function open_find_files_split(direction)
			ensure_code_window()
			local split = settings.splits[direction]

			local find_opts = {
				prompt_title = " 🔍 Find & Open File " .. (split and split.label or direction) .. " ",
				file_ignore_patterns = default_ignore_patterns,
				attach_mappings = function(prompt_bufnr)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						actions.close(prompt_bufnr)

						local filepath = selection and (selection.value or selection[1])
						if filepath and split then
							vim.cmd(split.command .. " " .. vim.fn.fnameescape(filepath))
						end
					end)
					return true
				end,
			}
			if vim.fn.executable("rg") == 1 then
				find_opts.find_command =
					{ "rg", "--files", "--color=never", "--hidden", "--no-require-git", "--glob", "!**/.git/*" }
			elseif vim.fn.executable("fd") == 1 then
				find_opts.find_command = { "fd", "--type", "f", "--hidden", "--no-require-git", "--exclude", ".git" }
			end

			builtin.find_files(find_opts)
		end

		-- Keys for these live in lua/keymaps/search.lua (see the header).
		local split_commands = {
			TelescopeFindFilesSplitLeft = "h",
			TelescopeFindFilesSplitBelow = "j",
			TelescopeFindFilesSplitAbove = "k",
			TelescopeFindFilesSplitRight = "l",
		}
		for name, direction in pairs(split_commands) do
			vim.api.nvim_create_user_command(name, function()
				open_find_files_split(direction)
			end, { desc = "Find a file and open it in a split (" .. direction .. ")" })
		end
	end,
}
