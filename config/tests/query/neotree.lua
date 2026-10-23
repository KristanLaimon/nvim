for _, plugin in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim", "nvim-web-devicons" }) do
	vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
require("neo-tree").setup({ enable_git_status = false, enable_diagnostics = false })
vim.cmd("runtime plugin/neo-tree.lua")
