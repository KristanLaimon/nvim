return {
	dir = require("fox.core.lazyspec").for_module(),
	name = "fox_installer",
	cmd = {
		"LanguageManager",
		"FoxLanguageManager",
		"LanguageTooling",
		"FoxInstallDependencies",
		"FoxInstaller",
		"FoxSetup",
		"FoxSystemSetup",
		"FoxInstallSystemDependencies",
		"FoxInstallAgy",
		"AgyInstall",
		"InstallAgy",
		"FoxInstallClaude",
		"ClaudeInstall",
		"InstallClaude",
		"FoxInstallAll",
		"MasonInstallAll",
		"FoxSetupStatus",
		"FoxHealthCheck",
		"FoxSetupReset",
	},
	config = function()
		require("fox.core.installer").init()
	end,
}
