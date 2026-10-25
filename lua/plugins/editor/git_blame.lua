-- ============================================================================
-- PLUGIN: git-blame.nvim -- VS Code GitLens-style inline blame virtual text.
-- ============================================================================
-- Displays inline git blame info as subtle virtual text at the end of the line:
-- "  <author>, <date> • <summary>"
--
-- Ex commands:
--   :GitBlameToggle         -- Toggle inline virtual text
--   :GitBlameEnable         -- Turn inline virtual text on
--   :GitBlameDisable        -- Turn inline virtual text off
--   :GitBlameOpenCommitURL  -- Open commit in browser
--   :GitBlameCopyCommitURL  -- Copy commit URL to clipboard
--   :GitBlameCopySHA        -- Copy commit SHA to clipboard
--   :GitBlameOpenFileURL    -- Open file at commit in browser
--   :GitBlameCopyFileURL    -- Copy file URL to clipboard
-- ============================================================================

return {
	name = "fox_inline_blame",
	dir = require("fox.core.lazyspec").for_module(),
	event = { "BufReadPost" },
	cmd = {
		"GitBlameToggle",
		"GitBlameEnable",
		"GitBlameDisable",
		"GitBlameOpenCommitURL",
		"GitBlameCopyCommitURL",
		"GitBlameCopySHA",
		"GitBlameOpenFileURL",
		"GitBlameCopyFileURL",
	},
	opts = {
		enabled = true,
		message_template = "  <author>, <date> • <summary>",
		date_format = "%r",
		message_when_not_committed = "  Not Committed Yet",
		highlight_group = "GitBlame",
		delay = 150,
		ignored_filetypes = {
			"neo-tree",
			"TelescopePrompt",
			"alpha",
			"dashboard",
			"help",
			"gitcommit",
			"lazy",
			"mason",
		},
	},
	config = function(_, opts)
		require("fox.git.inline_blame").setup(opts)
	end,
}
