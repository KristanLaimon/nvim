-- ============================================================================
-- PLUGIN: neogit -- the full git UI, for what the Git Center does not cover.
-- ============================================================================
-- The FOX Git Center (<C-S-g>) handles the everyday loop: stage, commit, push,
-- diff. Neogit is here for everything else -- rebases, stashes, history, cherry
-- picks -- and opens in a vertical split with diffview and telescope wired in.
-- `:Neogit` or the command palette; it is lazy-loaded until then.
-- ============================================================================

return {
	{
		"NeogitOrg/neogit",
		branch = "master",
		cmd = "Neogit",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"sindrets/diffview.nvim",
			"nvim-telescope/telescope.nvim",
		},
		config = function()
			local neogit = require("neogit")
			neogit.setup({
				kind = "vsplit",
				graph_style = "ascii",
				integrations = {
					diffview = true,
					telescope = true,
				},
			})
		end,
	},
}
