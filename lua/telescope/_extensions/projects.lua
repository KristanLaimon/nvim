-- Keep :Telescope projects and the environment picker on the FOX project UI.
require("lazy").load({ plugins = { "fox_recent_projects" } })
return require("telescope").register_extension({
	exports = {
		projects = function(opts)
			return _G.OpenRecentProjects(opts)
		end,
	},
})
