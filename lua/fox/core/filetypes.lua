local M = {}
local markdown_guard_installed = false

function M.setup()
	-- Neovim's Markdown ftplugin starts Treesitter before core parsers may be installed.
	if not markdown_guard_installed then
		local start = vim.treesitter.start
		vim.treesitter.start = function(buf, lang)
			buf = buf or 0
			if (lang or vim.treesitter.language.get_lang(vim.bo[buf].filetype)) == "markdown" then
				local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
				if not ok or not parser then
					return
				end
			end
			return start(buf, lang)
		end
		markdown_guard_installed = true
	end

	vim.filetype.add({
		pattern = {
			[".*%.blade%.php"] = "blade",
		},
	})
end

return M
