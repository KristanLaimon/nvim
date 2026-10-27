-- Explicit LSP package actions. Language metadata remains in fox.langs.
local M = {}
function M.packages()
	local packages = {}
	for name, tool in pairs(require("fox.core.installer").tools) do
		if tool.type == "lsp" then
			packages[name] = tool.mason
		end
	end
	return packages
end
function M.install(args, servers)
	local packages = M.packages()
	if #args == 0 then
		local candidates = {}
		for name in pairs(packages) do
			local cfg = (servers or {})[name] or vim.lsp.config[name]
			if cfg and vim.tbl_contains(cfg.filetypes or {}, vim.bo.filetype) then
				candidates[#candidates + 1] = name
			end
		end
		table.sort(candidates)
		if #candidates == 0 then
			vim.notify("No managed LSP for " .. vim.bo.filetype, vim.log.levels.WARN)
			return
		end
		vim.ui.select(candidates, { prompt = "Install language server:" }, function(choice)
			if choice then
				M.install({ choice }, servers)
			end
		end)
		return
	end
	local targets = {}
	for _, arg in ipairs(args) do
		local name, version = arg:match("^([^@]+)(.*)$")
		if not packages[name] then
			vim.notify("Unknown managed LSP: " .. arg, vim.log.levels.ERROR)
			return
		end
		targets[#targets + 1] = packages[name] .. version
	end
	vim.api.nvim_cmd({ cmd = "MasonInstall", args = targets }, {})
end
function M.setup(servers)
	vim.api.nvim_create_user_command("LspInstall", function(a)
		M.install(a.fargs, servers)
	end, {
		nargs = "*",
		desc = "Install selected LSPs through Mason",
		complete = function(prefix)
			return vim.tbl_filter(function(name)
				return name:sub(1, #prefix) == prefix
			end, vim.tbl_keys(M.packages()))
		end,
	})
	vim.api.nvim_create_user_command("LspUninstall", function(a)
		local packages = M.packages()
		local targets = {}
		for _, name in ipairs(a.fargs) do
			if not packages[name] then
				error("Unknown managed LSP: " .. name)
			end
			targets[#targets + 1] = packages[name]
		end
		vim.api.nvim_cmd({ cmd = "MasonUninstall", args = targets }, {})
	end, { nargs = "+", desc = "Uninstall selected LSPs through Mason" })
end
return M
