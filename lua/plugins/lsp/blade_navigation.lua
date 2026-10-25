-- Local spec glue; language behavior belongs to fox.langs.php.
return {
	name = "fox_laravel",
	dir = require("fox.core.lazyspec").for_module(),
	ft = { "blade", "php" },
	cmd = { "BladeNavClearCache", "BladeNavToggleShowValues", "BladeNavInstallArtisanCommand", "BladeNavGoToFile" },
	config = function()
		require("fox.langs.php.laravel").setup()
	end,
}
