local t = require("fox.lib.foxnvim.test")
local astro = require("fox.langs.astro")

local function with_workspace(callback)
	local root = vim.fs.normalize(vim.fn.tempname())
	vim.fn.mkdir(root .. "/project/src/pages", "p")
	local original_stdpath = vim.fn.stdpath
	vim.fn.stdpath = function(kind)
		return kind == "data" and root .. "/data" or original_stdpath(kind)
	end
	local ok, err = pcall(callback, root)
	vim.fn.stdpath = original_stdpath
	vim.fn.delete(root, "rf")
	assert(ok, err)
end

local function sdk(directory, filename)
	vim.fn.mkdir(directory, "p")
	vim.fn.writefile({ "// SDK fixture" }, directory .. "/" .. (filename or "typescript.js"))
end

t.describe("Astro language tooling", function()
	t.it("prefers workspace TypeScript over the Mason fallback", function()
		with_workspace(function(root)
			local workspace_sdk = root .. "/node_modules/typescript/lib"
			sdk(workspace_sdk)
			sdk(root .. "/data/mason/packages/astro-language-server/node_modules/typescript/lib")
			local config = { root_dir = root .. "/project" }
			astro.lsp_config.astro.before_init({}, config)
			t.expect(config.init_options.typescript.tsdk).toBe(workspace_sdk)
		end)
	end)

	t.it("uses Astro's bundled SDK when a local TypeScript package lacks JavaScript", function()
		with_workspace(function(root)
			vim.fn.mkdir(root .. "/project/node_modules/typescript/lib", "p")
			local fallback = root .. "/data/mason/packages/astro-language-server/node_modules/typescript/lib"
			sdk(fallback, "tsserverlibrary.js")
			local config = { root_dir = root .. "/project", init_options = { typescript = { tsdk = "" } } }
			astro.lsp_config.astro.before_init({}, config)
			t.expect(config.init_options.typescript.tsdk).toBe(fallback)
		end)
	end)

	t.it("preserves an explicitly configured SDK", function()
		local config = { init_options = { typescript = { tsdk = "/custom/typescript/lib" } } }
		astro.lsp_config.astro.before_init({}, config)
		t.expect(config.init_options.typescript.tsdk).toBe("/custom/typescript/lib")
	end)

	t.it("prefers project Prettier only when its Astro plugin is also installed", function()
		with_workspace(function(root)
			t.expect(astro.formatters_by_ft.astro[1]).toBe("prettier_astro")
			t.expect(astro.formatters_by_ft.astro[2]).toBe("biome_astro")
			t.expect(astro.formatters_by_ft.astro.stop_after_first).toBe(true)
			local formatter = astro.conform_formatters[astro.formatters_by_ft.astro[1]]
			local context = { filename = root .. "/project/src/pages/index.astro", dirname = root .. "/project/src/pages" }
			t.expect(formatter.inherit).toBe("prettier")
			t.expect(formatter.condition({}, context)).toBe(false)
			vim.fn.mkdir(root .. "/node_modules/prettier", "p")
			vim.fn.writefile({ "{}" }, root .. "/node_modules/prettier/package.json")
			t.expect(formatter.condition({}, context)).toBe(false)
			vim.fn.mkdir(root .. "/node_modules/prettier-plugin-astro", "p")
			vim.fn.writefile({ "{}" }, root .. "/node_modules/prettier-plugin-astro/package.json")
			t.expect(formatter.condition({}, context)).toBe(true)
			local args = formatter.args({}, context)
			t.expect(args[3]).toBe("--plugin")
			t.expect(args[4]).toBe("prettier-plugin-astro")
			vim.fn.writefile({ "{}" }, root .. "/project/.prettierrc.astro.json")
			args = formatter.args({}, context)
			t.expect(args[5]).toBe("--config")
			t.expect(args[6]).toBe(root .. "/project/.prettierrc.astro.json")
		end)
	end)

	t.it("enables complete Biome Astro formatting by default and respects project configs", function()
		local formatter = astro.conform_formatters.biome_astro
		t.expect(formatter.inherit).toBe("biome")
		local args = formatter.append_args({ cwd = function() end }, {})
		t.expect(args[1]).toBe("--config-path")
		local config = vim.json.decode(table.concat(vim.fn.readfile(args[2]), "\n"))
		t.expect(config.html.experimentalFullSupportEnabled).toBe(true)
		t.expect(config.html.formatter.enabled).toBe(true)
		args = formatter.append_args({
			cwd = function()
				return "/project"
			end,
		}, {})
		t.expect(#args).toBe(0)
	end)
end)
