-- ============================================================================
-- FOX DOCKER: Centralized Dockerfile Language Configuration
-- ============================================================================
-- WHAT IT DOES
--   Sets standard 2-space indentation defaults for Dockerfile buffers when no
--   .editorconfig file specifies buffer settings. Also owns the dockerls LSP server
--   and dockerfmt formatter.
-- ============================================================================

---@type FoxLangModule
local M = {}

--- The lspconfig/mason server name(s) this language owns.
M.lsp_server = { "dockerls", "docker_compose_language_service" }

--- lspconfig server settings, keyed by server name (see M.lsp_server).
---@type table<string, vim.lsp.Config>
M.lsp_config = {
	dockerls = {},
	docker_compose_language_service = {},
}

--- Mason package metadata, keyed by lspconfig/formatter name.
M.mason = {
	dockerls = { mason = "dockerfile-language-server", lang = "Docker", type = "lsp", cmd = "docker-langserver" },
	docker_compose_language_service = {
		mason = "docker-compose-language-service",
		lang = "Docker Compose",
		type = "lsp",
		cmd = "docker-compose-langserver",
	},
}

--- Mason packages to auto-install for Docker files.
M.mason_order = { "dockerls", "docker_compose_language_service" }

--- Language Tooling Manager bundle metadata (see lua/fox/core/installer.lua).
M.bundle_name = "🐳 Docker"
M.requires = {} -- standalone Mason binaries
M.treesitter = { "dockerfile", "yaml" }

--- conform.nvim formatter list per filetype.
M.formatters_by_ft = {
	dockerfile = { "dockerfmt" },
	["yaml.docker-compose"] = { "prettier" },
}

--- Standard defaults for Dockerfile & Compose (2 spaces).
M.defaults = {
	expandtab = true,
	shiftwidth = 2,
	tabstop = 2,
	softtabstop = 2,
	autoindent = true,
}

--- Apply Docker language defaults if no .editorconfig is present.
--- @param buf integer Buffer handle.
function M.apply_defaults(buf)
	local ok, langs = pcall(require, "fox.langs")
	if ok and not langs.has_editorconfig(buf) then
		for option, val in pairs(M.defaults) do
			vim.bo[buf][option] = val
		end
	end
end

--- Initialize Dockerfile & Docker Compose language configuration autocmds.
function M.setup()
	vim.filetype.add({
		filename = {
			["docker-compose.yml"] = "yaml.docker-compose",
			["docker-compose.yaml"] = "yaml.docker-compose",
			["compose.yml"] = "yaml.docker-compose",
			["compose.yaml"] = "yaml.docker-compose",
			["docker-compose.dev.yml"] = "yaml.docker-compose",
			["docker-compose.prod.yml"] = "yaml.docker-compose",
			["docker-compose.override.yml"] = "yaml.docker-compose",
			["docker-compose.local.yml"] = "yaml.docker-compose",
			["compose.dev.yml"] = "yaml.docker-compose",
			["compose.prod.yml"] = "yaml.docker-compose",
			["compose.override.yml"] = "yaml.docker-compose",
			["compose.local.yml"] = "yaml.docker-compose",
		},
		pattern = {
			["[dD]ocker%-compose.*%.ya?ml"] = "yaml.docker-compose",
			["compose.*%.ya?ml"] = "yaml.docker-compose",
		},
	})

	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "dockerfile", "yaml.docker-compose" },
		callback = function(args)
			M.apply_defaults(args.buf)
		end,
	})
end

return M
