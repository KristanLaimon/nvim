-- Run with: nvim --headless -S config/tests/integration/run.lua kitty_shortcuts
local t = require("fox.lib.foxnvim.test")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")

if vim.fn.executable("kitty") == 0 or vim.fn.executable("bash") == 0 then
	print("Skipping Kitty shortcut integration tests: Kitty and Bash are required.")
	return
end

local maps = {}
for slot = 1, 9 do
	maps[#maps + 1] = "map ctrl+shift+" .. slot .. "\n"
end
maps = table.concat(maps)
local previous = "# >>> FOXVIM KITTY SHORTCUTS >>>\n"
	.. maps
	.. "map ctrl+shift+enter\nmap ctrl+shift+p\n"
	.. "# <<< FOXVIM KITTY SHORTCUTS <<<\n"
local base = "font_size 12\nmap ctrl+shift+x copy_to_clipboard\n"

local function write(path, text)
	local file = assert(io.open(path, "wb"))
	assert(file:write(text))
	assert(file:close())
end

local function read(path)
	local file = assert(io.open(path, "rb"))
	local text = assert(file:read("*a"))
	assert(file:close())
	return text
end

local function run(command, options)
	local result = vim.system(command, vim.tbl_extend("force", { text = true }, options or {})):wait(10000)
	assert(result.code == 0, (result.stdout or "") .. (result.stderr or ""))
end

t.describe("Kitty shortcut setup and undo", function()
	local temporary, config, environment

	t.beforeEach(function()
		temporary = vim.fn.tempname()
		config = temporary .. "/kitty/kitty.conf"
		vim.fn.mkdir(temporary .. "/kitty", "p")
		vim.fn.mkdir(temporary .. "/bin", "p")
		-- Exercise setup/undo without reloading the user's running terminals.
		write(temporary .. "/bin/pkill", "#!/bin/sh\nexit 1\n")
		assert(vim.uv.fs_chmod(temporary .. "/bin/pkill", 493))
		environment = { XDG_CONFIG_HOME = temporary, PATH = temporary .. "/bin:" .. vim.env.PATH }
	end)

	t.afterEach(function()
		vim.fn.delete(temporary, "rf")
	end)

	local function run_script(name)
		run({ "bash", root .. "/config/scripts/" .. name }, { env = environment })
	end

	local function assert_passthrough(enabled)
		-- Kitty exposes its real parser and key selection through its Python runtime.
		local check = string.format(
			[[
from kitty.config import load_config
from kitty.keys import Mappings
from kitty.options.utils import parse_shortcut
errors = []
config = load_config(%s, accumulate_bad_lines=errors)
assert not errors, errors
mappings = Mappings.__new__(Mappings)
mappings.get_active_window = lambda: None
keymap = config.keyboard_modes[''].keymap
selected = mappings.matching_key_actions(keymap[parse_shortcut('ctrl+shift+p')])
assert selected, 'Missing Ctrl+Shift+P mapping'
assert all(not item.is_sequence and not item.definition for item in selected) == %s, selected
for key in ('a', 'q', 'h', 'l'):
    actions = mappings.matching_key_actions(keymap.get(parse_shortcut('ctrl+shift+' + key), []))
    if %s:
        assert actions and all(not item.is_sequence and not item.definition for item in actions), (key, actions)
unrelated = mappings.matching_key_actions(keymap[parse_shortcut('ctrl+shift+x')])
assert unrelated[-1].definition == 'copy_to_clipboard', unrelated
]],
			vim.json.encode(config),
			enabled and "True" or "False",
			enabled and "True" or "False"
		)
		run({ "kitty", "+runpy", check })
	end

	for name, block in pairs({
		shortcuts = previous,
		prefix = previous:gsub("map ctrl%+shift%+p\n", "map ctrl+shift+p no_op\n"),
		letters = previous:gsub(
			"map ctrl%+shift%+p\n",
			"map ctrl+shift+p no_op\nmap ctrl+shift+a no_op\nmap ctrl+shift+q no_op\n"
		),
		environments = "# >>> FOXVIM KITTY ENVIRONMENTS >>>\n" .. maps .. "# <<< FOXVIM KITTY ENVIRONMENTS <<<\n",
		legacy = "# Pass environment shortcuts through to Neovim instead of focusing Kitty windows.\n" .. maps,
	}) do
		t.it("upgrades the " .. name .. " block and preserves other settings on undo", function()
			write(config, base .. block)
			run_script("setup-kitty.sh")
			local configured = read(config)
			local _, blocks = configured:gsub("# >>> FOXVIM KITTY", "")
			t.expect(blocks).toBe(1)
			assert_passthrough(true)
			run_script("setup-kitty.sh")
			t.expect(read(config)).toBe(configured)
			write(config, configured .. "background_opacity 0.95\n")
			run_script("unsetup-kitty.sh")
			t.expect(read(config)).toBe(base .. "background_opacity 0.95\n")
			assert_passthrough(false)
		end)
	end

	t.it("also removes the previous shortcut block on undo", function()
		write(config, base .. previous)
		run_script("unsetup-kitty.sh")
		t.expect(read(config)).toBe(base)
		assert_passthrough(false)
	end)

	t.it("updates the user include without changing the main config", function()
		write(config, "include user.conf\n")
		local user = temporary .. "/kitty/user.conf"
		write(user, base)
		run_script("setup-kitty.sh")
		t.expect(read(config)).toBe("include user.conf\n")
		assert_passthrough(true)
		run_script("unsetup-kitty.sh")
		t.expect(read(user)).toBe(base)
		assert_passthrough(false)
	end)
end)
