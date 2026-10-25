for _, plugin in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim", "mini.icons" }) do
	vim.opt.runtimepath:append(vim.fn.stdpath("data") .. "/lazy/" .. plugin)
end
local icons = require("plugins.ui.devicons")[1]
icons.config(nil, vim.deepcopy(icons.opts))
require("neo-tree").setup({ enable_git_status = false, enable_diagnostics = false })
vim.cmd("runtime plugin/neo-tree.lua")
