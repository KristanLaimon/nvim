local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect

describe("local Mason DAP registration", function()
	local root, stdpath, has, shared
	t.beforeEach(function()
		root, stdpath, has = vim.fn.tempname(), vim.fn.stdpath, vim.fn.has
		root = root:gsub("\\", "/")
		shared = package.loaded["plugins.fox.debuggers._shared"]
		vim.fn.stdpath = function(kind)
			return kind == "data" and root or stdpath(kind)
		end
		package.loaded["plugins.fox.debuggers._shared"] = {
			js_debug = function() end,
			add = function() end,
			web_filetypes = {},
			js_skip = {},
		}
	end)
	t.afterEach(function()
		vim.fn.stdpath, vim.fn.has = stdpath, has
		package.loaded["plugins.fox.debuggers._shared"] = shared
		vim.fn.delete(root, "rf")
	end)
	local function touch(relative)
		local path = root .. "/mason/packages/" .. relative
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		vim.fn.writefile({}, path)
		return path
	end
	local function adapter(lang, name)
		local dap = { adapters = {}, configurations = {} }
		require("fox.langs." .. lang).dap_setup(dap)
		local result = dap.adapters[name]
		if type(result) == "function" then
			result(function(value)
				result = value
			end, {})
		end
		return result
	end

	for _, windows in ipairs({ false, true }) do
		it("registers Python and C# native executables for " .. (windows and "Windows" or "Unix"), function()
			vim.fn.has = function(feature)
				return feature == "win32" and (windows and 1 or 0) or has(feature)
			end
			local python = touch("debugpy/venv/" .. (windows and "Scripts/python.exe" or "bin/python"))
			local coreclr = touch("netcoredbg/netcoredbg/netcoredbg" .. (windows and ".exe" or ""))
			local py = adapter("python", "python")
			expect(py.command).toBe(python)
			expect(py.args).toEqual({ "-m", "debugpy.adapter" })
			local cs = adapter("csharp", "coreclr")
			expect(cs.command).toBe(coreclr)
			expect(cs.args).toEqual({ "--interpreter=vscode" })
			if windows then
				expect(cs.options.detached).toBe(false)
			else
				expect(cs.options).toBe(nil)
			end
		end)
	end

	it("registers Node entrypoints for PHP, Bash and Firefox without command wrappers", function()
		local php = touch("php-debug-adapter/extension/out/phpDebug.js")
		local bash = touch("bash-debug-adapter/extension/out/bashDebug.js")
		local firefox = touch("firefox-debug-adapter/dist/adapter.bundle.js")
		expect(adapter("php", "php").args).toEqual({ php })
		expect(adapter("php", "php").command).toBe("node")
		expect(adapter("bash", "bashdb").args).toEqual({ bash })
		expect(adapter("bash", "bashdb").command).toBe("node")
		local dap = { adapters = {} }
		dofile(stdpath("config") .. "/lua/plugins/fox/debuggers/browsers.lua")(dap)
		local ff
		dap.adapters.firefox(function(value)
			ff = value
		end)
		expect(ff.command).toBe("node")
		expect(ff.args).toEqual({ firefox })
	end)

	it("registers the native codelldb server and preserves its port argument", function()
		local path = touch("codelldb/extension/adapter/codelldb" .. (has("win32") == 1 and ".exe" or ""))
		local cpp = adapter("cpp", "codelldb")
		expect(cpp.executable.command).toBe(path)
		expect(cpp.executable.args).toEqual({ "--port", "${port}" })
	end)

	it("falls back to PATH when optional packages are absent and resolves later installs", function()
		expect(adapter("python", "python").command).toBe("debugpy-adapter")
		expect(adapter("php", "php").command).toBe("php-debug-adapter")
		expect(adapter("csharp", "coreclr").command).toBe("netcoredbg")
		local dap = { adapters = {} }
		require("fox.langs.php").dap_setup(dap)
		local script = touch("php-debug-adapter/extension/out/phpDebug.js")
		local resolved
		dap.adapters.php(function(value)
			resolved = value
		end)
		expect(resolved.args).toEqual({ script })
	end)
end)
