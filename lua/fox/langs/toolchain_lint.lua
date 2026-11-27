local M = {}
local toolchain = require("fox.langs.toolchain")
local namespaces = {}
local pending = {}

function M.run(buf)
	if vim.bo[buf].buftype ~= "" or vim.bo[buf].modified then
		return
	end
	local filename = vim.api.nvim_buf_get_name(buf)
	if filename == "" or vim.fn.filereadable(filename) ~= 1 then
		return
	end
	local ctx = toolchain.context(buf)
	local state = toolchain.read(ctx)
	local definitions = toolchain.linters(ctx.ft)
	local names = toolchain.selection(state, "linters", {})
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local generation = {}
	pending[buf] = generation
	for _, ns in pairs(namespaces) do
		vim.diagnostic.reset(ns, buf)
	end
	for _, name in ipairs(names) do
		local spec = definitions[name]
		local markers = toolchain.markers(state, "linters", name)
		local config = toolchain.find_config(ctx, markers)
		if spec and (not markers or #markers == 0 or config) then
			toolchain.missing_tool("Linter", name, vim.fn.executable(spec.command or name) ~= 1)
		end
		if spec and (not markers or #markers == 0 or config) and vim.fn.executable(spec.command or name) == 1 then
			local command = { spec.command or name }
			vim.list_extend(command, spec.args or {})
			if config and spec.config_args then
				for _, arg in ipairs(spec.config_args) do
					command[#command + 1] = arg == "$CONFIG" and config or arg
				end
			end
			command[#command + 1] = filename
			namespaces[name] = namespaces[name] or vim.api.nvim_create_namespace("FoxLint:" .. name)
			local ok, err = pcall(
				vim.system,
				command,
				{ cwd = ctx.root, text = true },
				vim.schedule_wrap(function(result)
					if
						pending[buf] ~= generation
						or not vim.api.nvim_buf_is_valid(buf)
						or vim.api.nvim_buf_get_changedtick(buf) ~= tick
					then
						return
					end
					local output = (result.stdout or "") .. "\n" .. (result.stderr or "")
					local items = vim.fn.getqflist({ lines = vim.split(output, "\n", { plain = true }), efm = spec.efm }).items
					local diagnostics = {}
					for _, item in ipairs(items) do
						if item.valid == 1 and item.lnum > 0 and (item.bufnr == 0 or item.bufnr == buf) then
							diagnostics[#diagnostics + 1] = {
								lnum = item.lnum - 1,
								col = math.max(0, item.col - 1),
								severity = item.type == "E" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
								message = item.text,
								source = name,
							}
						end
					end
					vim.diagnostic.set(namespaces[name], buf, diagnostics)
					if #diagnostics == 0 and result.code ~= 0 and vim.trim(output) ~= "" then
						vim.notify(name .. ": " .. vim.trim(output):sub(1, 500), vim.log.levels.WARN)
					end
				end)
			)
			if not ok then
				vim.notify(name .. ": " .. tostring(err), vim.log.levels.WARN)
			end
		end
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("FoxToolchainLint", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function(event)
			M.run(event.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(event)
			pending[event.buf] = nil
		end,
	})
end

return M
