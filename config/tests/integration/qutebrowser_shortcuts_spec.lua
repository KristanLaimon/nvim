local t = require("fox.lib.foxnvim.test")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")

if vim.fn.executable("bash") == 0 or vim.fn.executable("python3") == 0 then
	print("Skipping qutebrowser script tests: Bash and Python 3 are required.")
	return
end

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

t.describe("qutebrowser setup and undo", function()
	local temporary, config

	t.beforeEach(function()
		temporary = vim.fn.tempname()
		vim.fn.mkdir(temporary .. "/qutebrowser", "p")
		config = temporary .. "/qutebrowser/config.py"
	end)

	t.afterEach(function()
		vim.fn.delete(temporary, "rf")
	end)

	local function run(name, fails)
		local result = vim
			.system({ "bash", root .. "/config/scripts/" .. name .. "-qutebrowser.sh" }, {
				text = true,
				env = { XDG_CONFIG_HOME = temporary },
			})
			:wait(10000)
		assert((result.code ~= 0) == (fails == true), (result.stdout or "") .. (result.stderr or ""))
	end

	t.it("sets up a fresh config once and removes it on undo", function()
		run("unsetup")
		run("setup")
		local installed = read(config)
		assert(installed:find("config.load_autoconfig()", 1, true))
		assert(installed:find("https://www.google.com/search?q={}", 1, true))
		run("setup")
		assert(read(config) == installed)
		run("unsetup")
		assert(vim.fn.filereadable(config) == 0)
		run("unsetup")
	end)

	t.it("preserves existing settings, later edits, autoconfig and backups", function()
		local original = "config.load_autoconfig(False)\nc.tabs.position = 'left'"
		write(config, original)
		write(temporary .. "/qutebrowser/autoconfig.yml", "existing autoconfig")
		run("setup")
		assert(not read(config):find("config.load_autoconfig()", 1, true))
		local backups = vim.fn.glob(config .. ".bak.*", false, true)
		assert(#backups == 1 and read(backups[1]) == original)
		local later = "\nc.tabs.show = 'always'\n"
		write(config, read(config) .. later)
		run("unsetup")
		assert(read(config) == original .. later)
		assert(read(temporary .. "/qutebrowser/autoconfig.yml") == "existing autoconfig")
	end)

	t.it("refuses to modify incomplete managed blocks", function()
		local broken = "\n# >>> FOXVIM QUTEBROWSER >>>\n# missing end\n"
		write(config, broken)
		run("setup", true)
		run("unsetup", true)
		assert(read(config) == broken)
	end)

	t.it("refuses to append to invalid Python", function()
		write(config, "this is not valid Python !!!")
		run("setup", true)
		assert(read(config) == "this is not valid Python !!!")
	end)

	t.it("separates tab/history navigation and preserves native DevTools shortcuts", function()
		run("setup")
		local check = [[
import sys
from types import SimpleNamespace
bindings = {}
config = SimpleNamespace(
    load_autoconfig=lambda: None,
    bind=lambda key, command, mode='normal': bindings.update({(mode, key): command}),
)
c = SimpleNamespace(url=SimpleNamespace(searchengines={}))
source = open(sys.argv[1]).read()
source = source[source.index('# Browser shortcuts'):]
exec(compile(source, sys.argv[1], 'exec'), {'config': config, 'c': c})
for mode in ('normal', 'insert'):
    for key, command in {
        '<Alt-h>': 'tab-prev', '<Alt-l>': 'tab-next',
        '<Alt-Left>': 'tab-prev', '<Alt-Right>': 'tab-next',
        '<Ctrl-h>': 'back', '<Ctrl-l>': 'forward',
        '<Ctrl-k>': 'cmd-set-text -s :buffer',
        '<F12>': 'devtools bottom', '<Ctrl-Shift-i>': 'devtools bottom',
        '<Ctrl-Alt-o>': 'devtools-focus ;; mode-enter passthrough',
    }.items():
        assert bindings[mode, key] == command, (mode, key)
assert bindings['normal', 'a'] == 'open -t'
for mode in ('normal', 'insert', 'passthrough'):
    assert bindings[mode, '<Ctrl-;>'] == 'fox-devtools console ;; mode-enter passthrough'
    assert bindings[mode, '<Ctrl-Shift-f>'] == 'fox-devtools elements ;; mode-enter passthrough'
assert ('insert', 'a') not in bindings
assert bindings['passthrough', '<Ctrl-Alt-o>'] == 'devtools-focus ;; mode-enter normal'
assert bindings['passthrough', '<F12>'] == 'devtools bottom ;; mode-enter normal'
for key in ('<Ctrl-l>', '<Ctrl-h>', '<Ctrl-f>', '<Ctrl-Shift-p>', '<Ctrl-Shift-j>', '<Ctrl-Shift-c>'):
    assert ('passthrough', key) not in bindings, key
]]
		local result = vim.system({ "python3", "-c", check, config }, { text = true }):wait(10000)
		assert(result.code == 0, (result.stdout or "") .. (result.stderr or ""))
	end)
end)
