-- Explicit package.json actions; opening JSON never starts a package manager.
local commands = {
	"PackageInfoShow",
	"PackageInfoShowForce",
	"PackageInfoHide",
	"PackageInfoToggle",
	"PackageInfoUpdate",
	"PackageInfoDelete",
	"PackageInfoInstall",
	"PackageInfoChangeVersion",
}
return {
	name = "fox_packages",
	dir = require("fox.core.lazyspec").for_module(),
	ft = "json",
	cmd = commands,
	config = function()
		require("fox.langs.typescript.packages").setup(require("fox.langs.typescript").package_info)
	end,
}
