---@type FoxLangModule
local M = {}

M.lsp_server = { "mdx_analyzer" }
M.lsp_config = {
	mdx_analyzer = {},
}

M.mason = {
	mdx_analyzer = { mason = "mdx-analyzer", lang = "MDX", type = "lsp", cmd = "mdx-language-server" },
	prettier = require("fox.langs.typescript").mason.prettier,
}
M.mason_order = { "mdx_analyzer", "prettier" }
M.bundle_name = "📝 MDX"
M.requires = {
	{ cmd = "node", name = "Node.js", hint = "https://nodejs.org" },
}
M.treesitter = { "markdown", "markdown_inline" }
M.formatters_by_ft = {
	mdx = { "prettier" },
}

function M.setup()
	vim.filetype.add({ extension = { mdx = "mdx" } })
	-- shortcut: Markdown highlighting omits MDX expressions; use a dedicated parser when supported upstream.
	vim.treesitter.language.register("markdown", "mdx")
end

return M
