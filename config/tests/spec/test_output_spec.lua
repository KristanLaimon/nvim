local t = require("fox.lib.foxnvim.test")
local root = vim.fn.stdpath("config")

t.describe("Test runner failure-only output", function()
	local fixture
	t.beforeEach(function()
		fixture = vim.fn.tempname() .. ".lua"
		vim.fn.writefile(
			vim.split(
				string.format(
					[[
package.path = %q .. '/lua/?.lua;' .. package.path
local t = require('fox.lib.foxnvim.test')
local _, options = t.parse_args(arg)
t.describe('passing suite', function()
 t.it('passing case', function() print('passing diagnostic'); vim.notify('passing notification'); vim.api.nvim_echo({{'passing echo'}},false,{}) end)
end)
if vim.env.FOX_REPORTER_FAIL == '1' then
 t.describe('failing suite', function()
  t.beforeEach(function() print('failure setup diagnostic') end)
  t.it('failing case', function() print('failure diagnostic'); vim.notify('failure notification'); vim.api.nvim_echo({{'failure echo'}},false,{}); error('intentional failure') end)
 end)
end
local old_print, old_notify, old_echo = print, vim.notify, vim.api.nvim_echo
local ok = pcall(t.run, options)
assert(print == old_print and vim.notify == old_notify and vim.api.nvim_echo == old_echo)
os.exit(ok and 0 or 1)
]],
					root
				),
				"\n",
				{ plain = true }
			),
			fixture
		)
	end)
	t.afterEach(function()
		vim.fn.delete(fixture)
	end)
	local function run(args, fail)
		local cmd = { vim.v.progpath, "-l", fixture }
		vim.list_extend(cmd, args or {})
		local result = vim.system(cmd, { text = true, env = { FOX_REPORTER_FAIL = fail and "1" or "0" } }):wait(10000)
		return result.code, (result.stdout or "") .. (result.stderr or "")
	end
	t.it("hides passing cases, passing suites and passing diagnostics but retains totals", function()
		local code, output = run({ "--only-failure" })
		t.expect(code).toBe(0)
		t.expect(output:find("passing case", 1, true)).toBe(nil)
		t.expect(output:find("passing suite", 1, true)).toBe(nil)
		t.expect(output:find("passing diagnostic", 1, true)).toBe(nil)
		t.expect(output:find("passing notification", 1, true)).toBe(nil)
		t.expect(output:find("passing echo", 1, true)).toBe(nil)
		t.expect(output).toContain("1 Passed, 0 Failed")
	end)
	t.it("keeps failed case identity, errors, diagnostics and nonzero exit status", function()
		local code, output = run({ "--only-failure" }, true)
		t.expect(code).toBe(1)
		t.expect(output).toContain("failing suite")
		t.expect(output).toContain("failing case")
		t.expect(output).toContain("intentional failure")
		t.expect(output).toContain("failure diagnostic")
		t.expect(output).toContain("failure setup diagnostic")
		t.expect(output).toContain("failure notification")
		t.expect(output).toContain("failure echo")
		t.expect(output:find("passing diagnostic", 1, true)).toBe(nil)
		t.expect(output).toContain("1 Passed, 1 Failed")
	end)
	t.it("preserves verbose reporting when the flag is omitted", function()
		local code, output = run()
		t.expect(code).toBe(0)
		t.expect(output).toContain("passing case")
		t.expect(output).toContain("passing diagnostic")
	end)
	t.it("accepts a filename filter before or after the flag", function()
		for _, args in ipairs({
			{ "tasks", "--only-failure" },
			{ "--only-failure", "tasks" },
			{ "--", "tasks", "--only-failure" },
		}) do
			local filter, options = t.parse_args(args)
			t.expect(filter).toBe("tasks")
			t.expect(options.only_failure).toBe(true)
		end
		local filter, options = t.parse_args({ "--only-failure" })
		t.expect(filter).toBe(nil)
		t.expect(options.only_failure).toBe(true)
		t.expect(function()
			t.parse_args({ "--only-failur" })
		end).toThrow("Unknown test option")
	end)
end)
