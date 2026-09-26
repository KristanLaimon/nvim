-- ============================================================================
-- PLUGIN: nvim-autopairs -- closes brackets, quotes and tags as you type.
-- ============================================================================
-- `check_ts` uses Treesitter to decide whether a pair really should close, so it
-- does not add a quote inside a string or a comment. Disabled in the telescope
-- prompt, where a stray closing bracket breaks the search pattern.
--
-- The completion menu is deliberately suppressed inside a freshly inserted empty
-- pair -- see the blink.cmp `auto_show` rule in lua/plugins/lsp/lsp.lua.
-- ============================================================================

return {
	"windwp/nvim-autopairs",
	event = "InsertEnter",
	config = function()
		local is_native_termux = false
		local env_ok, env_mod = pcall(require, "fox.core.environment")
		if env_ok then
			local env = env_mod.detect()
			-- proot Ubuntu is a full Linux container — TS-aware pairs work fine there.
			-- Only disable check_ts on bare native Termux (no proot overlay).
			is_native_termux = env.is_termux and not env.is_proot
		else
			is_native_termux = vim.env.TERMUX_VERSION ~= nil
				and vim.fn.isdirectory("/data/data/com.termux") == 1
				and vim.fn.filereadable("/etc/os-release") == 0
		end

		require("nvim-autopairs").setup({
			check_ts = not is_native_termux,
			disable_filetype = { "TelescopePrompt", "vim" },
		})
	end,
}
