local t = require("fox.lib.foxnvim.test")
local injector = require("plugins.fox.tools.type_injector_typescript")

t.describe("type injector npm execution", function()
	t.it("runs Windows npm through Node for installation and updates", function()
		local dir = vim.fs.normalize(vim.fn.tempname())
		local cli = dir .. "/node_modules/npm/bin/npm-cli.js"
		vim.fn.mkdir(vim.fs.dirname(cli), "p")
		vim.fn.writefile({ "" }, cli)
		local original = { has = vim.fn.has, exepath = vim.fn.exepath, system = vim.system }
		local calls = {}
		local ok, err = pcall(function()
			vim.fn.has = function(feature)
				return feature == "win32" and 1 or original.has(feature)
			end
			vim.fn.exepath = function(name)
				return name == "node" and dir .. "/node.exe" or dir .. "/npm.cmd"
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
			t.expect(calls[1].argv).toEqual({ dir .. "/node.exe", cli, "install", "--save-dev", "@types/bun" })
			t.expect(calls[2].argv).toEqual({ dir .. "/node.exe", cli, "install", "--save-dev", "@types/bun@latest" })
			t.expect(calls[1].cwd).toBe(dir .. "/types__bun")
		end)
		vim.fn.has, vim.fn.exepath, vim.system = original.has, original.exepath, original.system
		vim.fn.delete(dir, "rf")
		assert(ok, err)
	end)
end)
