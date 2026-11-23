local t = require("fox.lib.foxnvim.test")
local injector = require("plugins.fox.tools.type_injector_typescript")

t.describe("type injector Bun execution", function()
	t.it("runs Bun for installation and updates", function()
		local dir = vim.fs.normalize(vim.fn.tempname())
		local original = { executable = vim.fn.executable, system = vim.system }
		local calls = {}
		local ok, err = pcall(function()
			vim.fn.executable = function(name)
				return name == "bun" and 1 or 0
			end
			vim.system = function(argv, opts)
				calls[#calls + 1] = { argv = argv, cwd = opts.cwd }
			end
			local core = {
				get_schemas_base_dir = function()
					return dir
				end,
				resolve_schema_dir = function(_, name)
					return dir .. "/" .. name
				end,
				notify = function() end,
			}
			injector.install_npm_types("@types/bun", nil, core)
			vim.fn.writefile({ '{"devDependencies":{"@types/bun":"*"}}' }, dir .. "/types__bun/package.json")
			injector.update_npm_types("types__bun", nil, core)
			t.expect(calls[1].argv).toEqual({ "bun", "add", "--dev", "@types/bun" })
			t.expect(calls[2].argv).toEqual({ "bun", "add", "--dev", "@types/bun@latest" })
			t.expect(calls[1].cwd).toBe(dir .. "/types__bun")
		end)
		vim.fn.executable, vim.system = original.executable, original.system
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
end)
