-- Keep the Fastfetch compatibility wrapper local to this Neovim process.
local M = {}

function M.setup()
	if vim.fn.has("unix") ~= 1 then
		return
	end

	local bin = vim.fn.stdpath("config") .. "/config/scripts/terminal-bin"
	if vim.fn.executable(bin .. "/fastfetch") ~= 1 then
		return
	end

	-- Reloading config or launching nested Neovim must not duplicate PATH entries.
	local paths = { bin }
	for _, entry in ipairs(vim.split(vim.env.PATH or "", ":", { plain = true })) do
		if entry ~= bin then
			paths[#paths + 1] = entry
		end
	end
	vim.env.PATH = table.concat(paths, ":")
end

return M
