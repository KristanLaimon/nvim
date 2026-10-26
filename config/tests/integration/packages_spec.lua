local t = require("fox.lib.foxnvim.test")
local packages = require("fox.langs.typescript.packages")
local root = vim.fn.stdpath("config")
local function wait(fn)
	assert(vim.wait(20000, fn, 10), "Package manager did not finish: " .. debug.traceback())
end
local function disk(path)
	local file = io.open(path, "rb")
	if not file then
		return {}
	end
	local text = file:read("*a")
	file:close()
	local ok, value = pcall(vim.json.decode, text)
	return ok and value or {}
end
t.describe("packages with real managers and an offline registry", function()
	local old, buf, dir, server, port, original, notices
	t.beforeEach(function()
		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		server = vim.fn.jobstart({ "python", root .. "/config/tests/fixtures/package_registry.py" }, {
			on_stdout = function(_, lines)
				for _, line in ipairs(lines) do
					if tonumber(line) then
						port = tonumber(line)
					end
				end
			end,
		})
		wait(function()
			return port ~= nil
		end)
		vim.fn.writefile({
			"registry=http://127.0.0.1:" .. port .. "/",
			"ignore-scripts=true",
			"audit=false",
			"fund=false",
			"fetch-retries=0",
			"fetch-timeout=4000",
		}, dir .. "/.npmrc")
		vim.fn.writefile({
			"{",
			'  "name": "fox-test-project",',
			'  "private": true,',
			'  "packageManager": "npm@11.0.0",',
			'  "dependencies": {',
			'    "fox-package-fixture": "1.0.0"',
			"  }",
			"}",
		}, dir .. "/package.json")
		old = vim.api.nvim_get_current_buf()
		vim.cmd("noautocmd edit " .. vim.fn.fnameescape(dir .. "/package.json"))
		buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_win_set_cursor(0, { 6, 0 })
		original = {
			options = vim.deepcopy(packages.options),
			spawn = packages.spawn,
			notify = vim.notify,
			select = vim.ui.select,
			input = vim.ui.input,
		}
		notices = {}
		vim.notify = function(message)
			notices[#notices + 1] = message
		end
		require("lazy").load({ plugins = { "fox_packages" } })
	end)
	t.afterEach(function()
		packages.hide(buf)
		packages.options, packages.spawn = original.options, original.spawn
		vim.notify, vim.ui.select, vim.ui.input = original.notify, original.select, original.input
		vim.api.nvim_set_current_buf(old)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.jobstop(server)
		port = nil
		vim.fn.delete(dir, "rf")
	end)
	local function dependency_row()
		for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			if line:find('"fox-package-fixture"', 1, true) then
				vim.api.nvim_win_set_cursor(0, { i, 0 })
				return
			end
		end
		error("Missing dependency line")
	end
	t.it("registers retained Ex commands, palette entries and the compatibility API without autostart", function()
		t.expect(require("lazy.core.config").plugins["package-info.nvim"]).toBe(nil)
		t.expect(require("package-info")).toBe(packages)
		t.expect(packages.get_status()).toBe("")
		local palette = require("plugins.fox.tools.command_palette").commands
		for _, name in ipairs({
			"PackageInfoShow",
			"PackageInfoShowForce",
			"PackageInfoHide",
			"PackageInfoToggle",
			"PackageInfoUpdate",
			"PackageInfoDelete",
			"PackageInfoInstall",
			"PackageInfoChangeVersion",
		}) do
			t.expect(vim.fn.exists(":" .. name)).toBe(2)
			local found = false
			for _, command in ipairs(palette) do
				if command.cmd == name then
					found = true
				end
			end
			t.expect(found).toBe(true)
		end
	end)
	t.it("queries real npm asynchronously, renders latest, reuses cache and hides", function()
		local calls = 0
		packages.spawn = function(...)
			calls = calls + 1
			return original.spawn(...)
		end
		vim.cmd.PackageInfoShow()
		wait(function()
			return packages.get_status() == ""
		end)
		local marks = vim.api.nvim_buf_get_extmarks(buf, packages.namespace, 0, -1, { details = true })
		t.expect(#marks).toBe(1)
		t.expect(marks[1][4].virt_text[1][1]).toContain("1.0.0 → 2.0.0")
		vim.cmd.PackageInfoShow()
		t.expect(calls).toBe(1)
		vim.cmd.PackageInfoHide()
		t.expect(#vim.api.nvim_buf_get_extmarks(buf, packages.namespace, 0, -1, {})).toBe(0)
	end)
	t.it("updates, selects a stable version and removes through real npm while preserving lockfiles", function()
		vim.ui.select = function(_, _, callback)
			callback("Confirm")
		end
		vim.cmd.PackageInfoUpdate()
		wait(function()
			return (disk(dir .. "/package.json").dependencies or {})["fox-package-fixture"] ~= "1.0.0"
		end)
		wait(function()
			return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find("2.0.0", 1, true) ~= nil
		end)
		t.expect(disk(dir .. "/package-lock.json").packages["node_modules/fox-package-fixture"].version).toBe("2.0.0")
		t.expect(disk(dir .. "/node_modules/fox-package-fixture/package.json").version).toBe("2.0.0")
		dependency_row()
		local versions
		vim.ui.select = function(values, _, callback)
			versions = values
			callback("1.0.0")
		end
		vim.cmd.PackageInfoChangeVersion()
		wait(function()
			return disk(dir .. "/node_modules/fox-package-fixture/package.json").version == "1.0.0"
		end)
		wait(function()
			return packages.get_status() == ""
				and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find("1.0.0", 1, true) ~= nil
		end)
		t.expect(versions).toEqual({ "2.0.0", "1.0.0" })
		dependency_row()
		vim.ui.select = function(_, _, callback)
			callback("Confirm")
		end
		vim.cmd.PackageInfoDelete()
		wait(function()
			return not (disk(dir .. "/package.json").dependencies or {})["fox-package-fixture"]
		end)
		wait(function()
			return not table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find('"fox-package-fixture"', 1, true)
		end)
		t.expect(vim.bo[buf].modified).toBe(false)
		t.expect(disk(dir .. "/package-lock.json").packages["node_modules/fox-package-fixture"]).toBe(nil)
	end)
	t.it("installs a development dependency through real Bun", function()
		assert(vim.fn.executable("bun") == 1, "Bun is required for this integration")
		vim.api.nvim_buf_set_lines(
			buf,
			0,
			-1,
			false,
			{ '{"name":"fox-bun-test","private":true,"packageManager":"bun@1.0.0"}' }
		)
		vim.cmd("noautocmd write")
		vim.ui.select = function(_, _, callback)
			callback("devDependencies")
		end
		vim.ui.input = function(_, callback)
			callback("fox-package-fixture")
		end
		vim.cmd.PackageInfoInstall()
		wait(function()
			return disk(dir .. "/node_modules/fox-package-fixture/package.json").version == "2.0.0"
		end)
		wait(function()
			return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find("devDependencies", 1, true) ~= nil
		end)
		t.expect(disk(dir .. "/package.json").devDependencies["fox-package-fixture"]).toBeTruthy()
		t.expect(vim.fn.filereadable(dir .. "/bun.lock")).toBe(1)
	end)
end)
