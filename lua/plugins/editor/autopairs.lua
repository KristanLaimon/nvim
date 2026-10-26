-- Local pair editing loads before Blink captures fallback insert mappings.
return {
	name = "fox_autopairs",
	dir = require("fox.core.lazyspec").for_module(),
	lazy = false,
	config = function()
		local is_native_termux
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

		require("fox.editor.autopairs").setup({
			check_ts = not is_native_termux,
			disable_filetype = { "TelescopePrompt", "vim" },
		})
	end,
}
