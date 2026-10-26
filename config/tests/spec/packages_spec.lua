local t = require("fox.lib.foxnvim.test")
local packages = require("fox.langs.typescript.packages")
local function json(data)
	return vim.json.encode(data)
end
local function marks(buf)
	return vim.api.nvim_buf_get_extmarks(buf, packages.namespace, 0, -1, { details = true })
end
local function wait(fn)
	assert(vim.wait(500, fn, 1), "Callback did not finish")
end
t.describe("package manager actions and registry state", function()
	local dir, buf, old, original, requests, notices
	local function write(text)
		vim.fn.writefile(vim.split(text, "\n", { plain = true }), dir .. "/package.json")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
		vim.bo[buf].modified = false
	end
	local function answer(index, stdout, code, stderr)
		requests[index].callback({ stdout = stdout or "", code = code or 0, stderr = stderr or "" })
	end
	t.beforeEach(function()
		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		old = vim.api.nvim_get_current_buf()
		buf = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_set_current_buf(buf)
		vim.api.nvim_buf_set_name(buf, dir .. "/package.json")
		original = {
			spawn = packages.spawn,
			options = vim.deepcopy(packages.options),
			notify = vim.notify,
			select = vim.ui.select,
			input = vim.ui.input,
		}
		requests, notices = {}, {}
		packages.spawn = function(argv, cwd, timeout, callback)
			local request = { argv = argv, cwd = cwd, timeout = timeout, callback = callback }
			requests[#requests + 1] = request
			return {
				kill = function()
					request.killed = true
				end,
			}
		end
		vim.notify = function(message)
			notices[#notices + 1] = message
		end
		packages.setup({ package_manager = "npm", hide_unstable_versions = true, hide_up_to_date = true })
		write('{\n  "dependencies": {\n    "test-dep": "^1.0.0"\n  }\n}')
		vim.api.nvim_win_set_cursor(0, { 3, 0 })
	end)
	t.afterEach(function()
		packages.hide(buf)
		packages.spawn, packages.options = original.spawn, original.options
		vim.notify, vim.ui.select, vim.ui.input = original.notify, original.select, original.input
		vim.api.nvim_set_current_buf(old)
		vim.api.nvim_buf_delete(buf, { force = true })
		vim.fn.delete(dir, "rf")
	end)
	t.it("parses exact dependency rows without mistaking scripts or nested objects", function()
		local parsed = assert(
			packages.parse(
				[[{"scripts":{"dependencies":{"bad":"1"}},"dependencies":{"@scope/pkg":"^1.0.0"},"devDependencies":{"dev":"2.0.0"}}]]
			)
		)
		t.expect(#parsed.entries).toBe(2)
		t.expect(parsed.entries[1].name).toBe("@scope/pkg")
		t.expect(parsed.entries[2].group).toBe("devDependencies")
		t.expect(packages.parse("{")).toBe(nil)
		parsed = assert(packages.parse([[{"dependencies":{"x":null},"devDependencies":{"x":"1.0.0"}}]]))
		t.expect(parsed.entries[1].invalid).toBe(true)
		t.expect(parsed.entries[2].duplicate).toBe(true)
	end)
	t.it("detects managers per project, including ancestor monorepos and packageManager", function()
		vim.fn.writefile({ "" }, dir .. "/pnpm-lock.yaml")
		vim.fn.mkdir(dir .. "/packages/one", "p")
		local manager, root = packages.detect(dir .. "/packages/one", {})
		t.expect(manager).toBe("pnpm")
		t.expect(root).toBe(dir)
		vim.fn.writefile({ "" }, dir .. "/packages/one/bun.lockb")
		t.expect(packages.detect(dir .. "/packages/one", {})).toBe("bun")
		t.expect(packages.detect(dir, { packageManager = "yarn@4.0.0" })).toBe("yarn")
	end)
	t.it("sorts versions numerically, filters prereleases, honors dist-tags and validates responses", function()
		local versions, _, latest = packages.versions(
			json({ { ["dist-tags"] = { latest = "1.9.0" }, versions = { "1.9.0", "1.10.0", "2.0.0-next.1" } } })
		)
		t.expect(versions).toEqual({ "1.10.0", "1.9.0" })
		t.expect(latest).toBe("1.9.0")
		t.expect(packages.versions('{"error":"offline"}')).toBe(nil)
		t.expect(packages.versions("not json")).toBe(nil)
		t.expect(packages.versions('["1.0.0-beta"]')).toBe(nil)
	end)
	t.it("builds manager argv preserving dependency types and rejects option/shell input", function()
		for _, manager in ipairs({ "npm", "pnpm", "yarn", "bun" }) do
			local argv = packages.command(manager, "update", "@scope/pkg", "devDependencies", "latest")
			t.expect(argv[1]).toBe(manager)
			t.expect(argv[3]).toBe("@scope/pkg@latest")
			t.expect(#argv).toBe(4)
			t.expect(packages.command(manager, "delete", "test-dep", "dependencies")[3]).toBe("test-dep")
		end
		for _, name in ipairs({ "--help", "a;touch pwned", "a b", "$(id)", "../x" }) do
			t.expect(packages.valid_name(name)).toBe(false)
		end
		t.expect(pcall(packages.command, "npm", "install", "valid", "dependencies", "1;exit")).toBe(false)
	end)
	t.it("resolves Windows shims without shell interpolation and preserves WSL paths", function()
		local has, exepath, wsl = vim.fn.has, vim.fn.exepath, package.loaded["plugins.fox.tools.wsl"]
		local ok, err = pcall(function()
			vim.fn.mkdir(dir .. "/node_modules/npm/bin", "p")
			vim.fn.writefile({ "" }, dir .. "/node_modules/npm/bin/npm-cli.js")
			vim.fn.has = function(feature)
				if feature == "win32" then
					return 1
				end
				return has(feature)
			end
			vim.fn.exepath = function()
				return dir .. "/npm.cmd"
			end
			package.loaded["plugins.fox.tools.wsl"] = {
				parse_wsl_path = function(path)
					if path:find("wsl.localhost", 1, true) then
						return "Ubuntu", "/home/user/a b"
					end
				end,
			}
			local argv, cwd = packages.executable({ "npm", "view", "@scope/pkg" }, dir)
			t.expect(argv).toEqual({ "node", dir .. "/node_modules/npm/bin/npm-cli.js", "view", "@scope/pkg" })
			t.expect(cwd).toBe(dir)
			argv, cwd = packages.executable({ "npm", "view", "a" }, "//wsl.localhost/Ubuntu/home/user/a b")
			t.expect(argv).toEqual({ "wsl.exe", "-d", "Ubuntu", "--cd", "/home/user/a b", "--", "env", "npm", "view", "a" })
			t.expect(cwd).toBe(nil)
		end)
		vim.fn.has, vim.fn.exepath, package.loaded["plugins.fox.tools.wsl"] = has, exepath, wsl
		assert(ok, err)
	end)

	t.it("renders versions from registry results, caches by project, force-refreshes and hides", function()
		packages.show()
		t.expect(requests[1].cwd).toBe(dir)
		t.expect(requests[1].argv)
			.toEqual({ "npm", "--loglevel=error", "view", "test-dep", "dist-tags", "versions", "--json" })
		answer(1, '["1.0.0", "2.0.0"]')
		wait(function()
			return #marks(buf) == 1
		end)
		t.expect(marks(buf)[1][4].virt_text[1][1]).toContain("2.0.0")
		packages.show()
		t.expect(#requests).toBe(1)
		packages.show({ force = true })
		t.expect(#requests).toBe(2)
		packages.hide()
		t.expect(requests[2].killed).toBe(true)
		answer(2, '["3.0.0"]')
		wait(function()
			return packages.get_status() == ""
		end)
		t.expect(#marks(buf)).toBe(0)
	end)
	t.it("limits concurrent reads and does not cross project caches", function()
		local dependencies = {}
		for i = 1, 7 do
			dependencies["dep" .. i] = "1.0.0"
		end
		write(json({ dependencies = dependencies }))
		packages.show()
		t.expect(#requests).toBe(4)
		answer(1, '["2.0.0"]')
		wait(function()
			return #requests == 5
		end)
		packages.hide()
		vim.api.nvim_buf_set_name(buf, dir .. "/other/package.json")
		packages.show()
		t.expect(#requests).toBe(9)
	end)
	t.it("ignores stale results after edits and reports network, JSON and launch errors", function()
		packages.show()
		vim.api.nvim_buf_set_lines(buf, 2, 3, false, { '    "different": "1.0.0"' })
		answer(1, '["2.0.0"]')
		wait(function()
			return packages.get_status() == ""
		end)
		t.expect(#marks(buf)).toBe(0)
		write('{"dependencies":{"test-dep":"1.0.0"}}')
		packages.show({ force = true })
		answer(2, "", 124)
		wait(function()
			return #notices > 0
		end)
		t.expect(notices[#notices]).toContain("timed out")
		packages.show({ force = true })
		answer(3, "{bad")
		wait(function()
			return #notices > 1
		end)
		t.expect(notices[#notices]).toContain("Invalid registry JSON")
		packages.spawn = function()
			error("missing executable")
		end
		packages.show({ force = true })
		t.expect(notices[#notices]).toContain("missing executable")
	end)
	t.it("cancels prompts without spawning commands and rejects unsaved/external edits", function()
		vim.ui.select = function(_, _, callback)
			callback(nil)
		end
		packages.update()
		t.expect(#requests).toBe(0)
		vim.ui.select = function(_, _, callback)
			callback("Confirm")
		end
		vim.bo.modified = true
		packages.update()
		t.expect(#requests).toBe(0)
		vim.bo.modified = false
		vim.fn.writefile({ "{}" }, dir .. "/package.json")
		packages.delete()
		t.expect(#requests).toBe(0)
	end)
	t.it("rechecks delayed prompts, protects local refs and rejects ambiguous single-line selection", function()
		local confirm
		vim.ui.select = function(_, _, callback)
			confirm = callback
		end
		packages.update()
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, { " " })
		confirm("Confirm")
		t.expect(#requests).toBe(0)
		write('{"dependencies":{"a":"1.0.0","b":"1.0.0"}}')
		vim.api.nvim_win_set_cursor(0, { 1, 0 })
		packages.update()
		t.expect(#requests).toBe(0)
		write('{"dependencies":{"a":"workspace:*"}}')
		packages.update()
		t.expect(notices[#notices]).toContain("workspace/catalog/alias")
	end)
	t.it("reloads successful manager changes and invalidates cached registry data", function()
		vim.ui.select = function(_, _, callback)
			callback("Confirm")
		end
		packages.update()
		t.expect(requests[1].argv).toEqual({ "npm", "install", "test-dep@latest" })
		vim.fn.writefile({ '{"dependencies":{"test-dep":"^2.0.0"}}' }, dir .. "/package.json")
		answer(1)
		wait(function()
			return vim.api.nvim_get_current_line():find("2.0.0", 1, true) ~= nil
		end)
		t.expect(vim.bo.modified).toBe(false)
		packages.show()
		t.expect(#requests).toBe(2)
	end)
	t.it("serializes workspace mutations and preserves edits made during a manager process", function()
		vim.ui.select = function(_, _, callback)
			callback("Confirm")
		end
		packages.update()
		packages.delete()
		t.expect(#requests).toBe(1)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{"myUnsavedEdit":true}' })
		vim.fn.writefile({ '{"managerResult":true}' }, dir .. "/package.json")
		answer(1)
		wait(function()
			return #notices >= 3
		end)
		t.expect(vim.api.nvim_get_current_line()).toBe('{"myUnsavedEdit":true}')
		t.expect(vim.bo.modified).toBe(true)
	end)
	t.it("installs development dependencies and offers only published stable versions", function()
		vim.ui.select = function(_, _, callback)
			callback("devDependencies")
		end
		vim.ui.input = function(_, callback)
			callback("new-package")
		end
		packages.install()
		t.expect(requests[1].argv).toEqual({ "npm", "install", "new-package@latest", "--save-dev" })
		answer(1, "", 1, "install failed")
		wait(function()
			return #notices > 1
		end)
		vim.api.nvim_win_set_cursor(0, { 3, 0 })
		local offered
		vim.ui.select = function(values, _, callback)
			offered = values
			callback(nil)
		end
		packages.change_version()
		answer(2, '["1.0.0", "2.0.0-beta.1", "1.1.0"]')
		wait(function()
			return offered ~= nil
		end)
		t.expect(offered).toEqual({ "1.1.0", "1.0.0" })
		t.expect(#requests).toBe(2)
	end)
end)
