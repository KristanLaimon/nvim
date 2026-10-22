local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local go = require("fox.langs.go")

describe("local Go DAP setup", function()
	local dap, stdpath, data_dir, input, utils
	t.beforeEach(function()
		dap = { adapters = {}, configurations = {}, ABORT = {} }
		stdpath, input, utils = vim.fn.stdpath, vim.ui.input, package.loaded["dap.utils"]
		data_dir = vim.fn.tempname()
		vim.fn.stdpath = function(kind)
			return kind == "data" and data_dir or stdpath(kind)
		end
		go.dap_setup(dap)
	end)
	t.afterEach(function()
		vim.fn.stdpath, vim.ui.input, package.loaded["dap.utils"] = stdpath, input, utils
		vim.fn.delete(data_dir, "rf")
	end)

	it("preserves the seven profiles, test modes, launch settings and attach selector", function()
		local configs = dap.configurations.go
		expect(#configs).toBe(7)
		expect(configs[1].program).toBe("${file}")
		expect(configs[4].program).toBe("${fileDirname}")
		expect(configs[5].request).toBe("attach")
		expect(configs[5].mode).toBe("local")
		expect(configs[6].mode).toBe("test")
		expect(configs[7].program).toBe("./${relativeFileDirname}")
		for _, config in ipairs(configs) do
			expect(config.type).toBe("go")
			if config.request == "launch" then
				expect(config.outputMode).toBe("remote")
			end
		end
		package.loaded["dap.utils"] = {
			pick_process = function()
				return 42
			end,
		}
		expect(configs[5].processId()).toBe(42)
		go.dap_setup(dap)
		expect(#dap.configurations.go).toBe(7)
	end)

	it("launches Delve on loopback with the platform's attached-process setting", function()
		local adapter
		dap.adapters.go(function(result)
			adapter = result
		end, {})
		expect(adapter.type).toBe("server")
		expect(adapter.host).toBe("127.0.0.1")
		expect(adapter.port).toBe("${port}")
		expect(adapter.executable.args).toEqual({ "dap", "-l", "127.0.0.1:${port}" })
		expect(adapter.executable.command).toBe("dlv")
		expect(adapter.executable.detached).toBe(vim.fn.has("win32") == 0)
		expect(adapter.options.initialize_timeout_sec).toBe(20)
	end)

	it("uses the native Mason executable instead of a Windows command wrapper", function()
		local binary = data_dir .. "/mason/packages/delve/dlv" .. (vim.fn.has("win32") == 1 and ".exe" or "")
		vim.fn.mkdir(vim.fn.fnamemodify(binary, ":h"), "p")
		vim.fn.writefile({}, binary)
		local adapter
		dap.adapters.go(function(result)
			adapter = result
		end, {})
		expect(adapter.executable.command).toBe(binary)
	end)

	it("keeps custom host/port values isolated from subsequent launches", function()
		local custom, standard
		dap.adapters.go(function(result)
			custom = result
		end, { host = "localhost", port = 4444 })
		dap.adapters.go(function(result)
			standard = result
		end, {})
		expect(custom.port).toBe(4444)
		expect(custom.executable.args).toEqual({ "dap", "-l", "localhost:4444" })
		expect(standard.port).toBe("${port}")
	end)

	it("waits for asynchronous input, delegates argument parsing and aborts on cancellation", function()
		local callback
		vim.ui.input = function(_, cb)
			callback = cb
		end
		package.loaded["dap.utils"] = {
			splitstr = function(text)
				return { "parsed", text }
			end,
		}
		for _, field in ipairs({ "args", "buildFlags" }) do
			local returned
			local co = coroutine.create(function()
				returned = coroutine.yield()
			end)
			assert(coroutine.resume(co))
			local prompt = dap.configurations.go[3][field]()
			assert(coroutine.resume(prompt, co))
			expect(returned).toBe(nil)
			callback('one "two words"')
			expect(returned).toEqual({ "parsed", 'one "two words"' })
		end
		local returned
		local co = coroutine.create(function()
			returned = coroutine.yield()
		end)
		assert(coroutine.resume(co))
		assert(coroutine.resume(dap.configurations.go[2].args(), co))
		callback(nil)
		expect(returned).toBe(dap.ABORT)
	end)
end)
