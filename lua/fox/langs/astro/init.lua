-- ============================================================================
-- FOX ASTRO: Web Framework Language Configuration
-- ============================================================================

---@type FoxLangModule
local M = {}

M.lsp_server = { "astro" }

M.lsp_config = {
	astro = {
		init_options = { typescript = {} },
		before_init = function(_, config)
			config.init_options = config.init_options or {}
			config.init_options.typescript = config.init_options.typescript or {}
			local typescript = config.init_options.typescript
			if typescript.tsdk and typescript.tsdk ~= "" then
				return
			end
			local candidates = {}
			if config.root_dir then
				for _, modules in
					ipairs(vim.fs.find("node_modules", {
						path = config.root_dir,
						upward = true,
						limit = math.huge,
						type = "directory",
					}))
				do
					candidates[#candidates + 1] = modules .. "/typescript/lib"
				end
			end
			local mason = vim.fs.normalize(vim.fn.stdpath("data") .. "/mason/packages")
			for _, package in ipairs({
				"astro-language-server",
				require("fox.langs.typescript").lsp_server[1],
				"typescript-language-server",
			}) do
				candidates[#candidates + 1] = mason .. "/" .. package .. "/node_modules/typescript/lib"
			end
			for _, candidate in ipairs(candidates) do
				if
					vim.fn.filereadable(candidate .. "/typescript.js") == 1
					or vim.fn.filereadable(candidate .. "/tsserverlibrary.js") == 1
				then
					typescript.tsdk = candidate
					return
				end
			end
		end,
	},
}

M.mason = {
	astro = { mason = "astro-language-server", lang = "Astro", type = "lsp", cmd = "astro-ls" },
}

M.mason_order = { "astro" }
M.bundle_extra_mason_pkgs = { "biome" }
M.bundle_name = "🪐 Astro"
M.requires = {
	{ cmd = "node", name = "Node.js", hint = "https://nodejs.org" },
}
M.treesitter = { "astro" }

M.formatters_by_ft = {
	astro = { "prettier_astro", "biome_astro", stop_after_first = true },
}

M.conform_formatters = {
	prettier_astro = {
		inherit = "prettier",
		condition = function(_, ctx)
			for _, modules in ipairs(vim.fs.find("node_modules", { path = ctx.dirname, upward = true, limit = math.huge })) do
				if
					vim.fn.filereadable(modules .. "/prettier/package.json") == 1
					and vim.fn.filereadable(modules .. "/prettier-plugin-astro/package.json") == 1
				then
					return true
				end
			end
			return false
		end,
		cwd = function(_, ctx)
			return vim.fs.root(ctx.dirname, { "package.json" }) or ctx.dirname
		end,
		args = function(_, ctx)
			local args = { "--stdin-filepath", "$FILENAME", "--plugin", "prettier-plugin-astro" }
			local config = vim.fs.find({ ".prettierrc.astro.json" }, { path = ctx.dirname, upward = true })[1]
			if config then
				vim.list_extend(args, { "--config", config })
			end
			return args
		end,
	},
	biome_astro = {
		inherit = "biome",
		append_args = function(self, ctx)
			if self:cwd(ctx) then
				return {}
			end
			return { "--config-path", vim.fn.stdpath("config") .. "/config/formatters/biome-astro.json" }
		end,
	},
}

M.formatter_configs = {}

local function build_formatter_configs()
	local ts = require("fox.langs.typescript")
	vim.list_extend(M.formatter_configs, ts.PRETTIER_CONFIG_FILES)
	vim.list_extend(M.formatter_configs, ts.BIOME_CONFIG_FILES)
end

M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_project_config(buf, M.formatter_configs) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

function M.setup()
	build_formatter_configs()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = "astro",
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
