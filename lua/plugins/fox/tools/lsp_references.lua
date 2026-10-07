-- ============================================================================
-- FOX PLUGIN: LSP Function & Class Reference / Symbol Usages Counter
-- ============================================================================
-- WHAT IT DOES
--   Manages LSP symbol usages display (e.g. "󰌹 3 usages", "1 usage") powered by
--   symbol-usage.nvim across all supported languages and theme styles.
--   Suppresses duplicate raw builtin CodeLens overlays ("4 references") to keep
--   the clean "Usages" UI consistent and deduplicated.
--   Provides toggle command `:FoxToggleReferences` (default: ON).
-- ============================================================================

local store = require("fox.core.store")

local M = {}

M.settings = {
	store_file = vim.fn.stdpath("config") .. "/.foxnvim/references.json",
	default_enabled = true,
	keymap = nil,
}

--- Retrieves current toggle state from persistence store.
--- @return boolean enabled
function M.is_enabled()
	local data = store.load(M.settings.store_file, {})
	if data.enabled ~= nil then
		return data.enabled
	end
	return M.settings.default_enabled
end

local function disable_builtin_codelens(bufnr)
	if vim.lsp.codelens then
		if vim.lsp.codelens.enable then
			pcall(vim.lsp.codelens.enable, false, { bufnr = bufnr })
		elseif vim.lsp.codelens.clear then
			pcall(vim.lsp.codelens.clear, nil, bufnr)
		end
	end
end

--- True when symbol-usage already has workers for this buffer.
--- @param bufnr integer
--- @return boolean
local function symbol_usage_attached(bufnr)
	local ok, state = pcall(require, "symbol-usage.state")
	if not ok or not state or not state.get_buf_workers then
		return false
	end
	local workers = state.get_buf_workers(bufnr)
	return workers ~= nil and next(workers) ~= nil
end

--- Refreshes symbol usages in the active buffer.
--- Clears any duplicate raw CodeLens virtual text in favor of symbol-usage.
--- @param bufnr number|nil
function M.refresh(bufnr)
	if not M.is_enabled() then
		return
	end

	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
		return
	end

	-- Clear raw builtin codelens virtual text to prevent duplicate "4 references" above "4 usages"
	disable_builtin_codelens(bufnr)

	-- symbol-usage already refreshes itself (its own LspAttach plus per-buffer
	-- TextChanged/InsertLeave/BufEnter autocmds). Calling a full clear+re-attach
	-- on every event is what duplicated the label: reference requests still in
	-- flight resolve after the clear and `set_extmark` resurrects their deleted
	-- marks, stacking "# usages" many times over. Only attach when the buffer has
	-- no workers yet; otherwise leave the plugin's own lifecycle in charge.
	if symbol_usage_attached(bufnr) then
		return
	end

	local ok_buf, su_buf = pcall(require, "symbol-usage.buf")
	if ok_buf and su_buf.attach_buffer then
		pcall(su_buf.attach_buffer, bufnr)
	end
end

--- Clears all LSP code lenses and symbol usages from active buffer.
--- @param bufnr number|nil
function M.clear(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	disable_builtin_codelens(bufnr)
	local ok_buf, su_buf = pcall(require, "symbol-usage.buf")
	if ok_buf and su_buf.clear_buffer then
		pcall(su_buf.clear_buffer, bufnr)
	end
end

--- Toggles LSP reference / symbol usage counts on or off.
function M.toggle()
	local new_state = not M.is_enabled()
	store.save(M.settings.store_file, { enabled = new_state })

	local ok_su, su = pcall(require, "symbol-usage")
	if ok_su and su.toggle_globally then
		pcall(su.toggle_globally)
	end

	if new_state then
		vim.notify("Symbol Usages: ENABLED", vim.log.levels.INFO, { title = "Symbol Usages" })
		M.refresh(0)
	else
		vim.notify("Symbol Usages: DISABLED", vim.log.levels.WARN, { title = "Symbol Usages" })
		M.clear(0)
	end
end

--- Runs code lens under cursor or opens references list.
function M.run()
	if vim.lsp.codelens then
		pcall(vim.lsp.codelens.run)
	end
end

function M.setup()
	if M._did_setup then
		return
	end
	M._did_setup = true

	local group = vim.api.nvim_create_augroup("FOX_LSP_References", { clear = true })

	vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "BufWritePost", "InsertLeave" }, {
		group = group,
		callback = function(args)
			if M.is_enabled() then
				vim.schedule(function()
					M.refresh(args.buf)
				end)
			else
				vim.schedule(function()
					M.clear(args.buf)
				end)
			end
		end,
	})

	vim.api.nvim_create_user_command("FoxToggleReferences", function()
		M.toggle()
	end, { desc = "Toggle Symbol Usages display" })

	vim.api.nvim_create_user_command("FoxRunCodeLens", function()
		M.run()
	end, { desc = "Run LSP CodeLens / References under cursor" })

	if M.settings.keymap then
		vim.keymap.set("n", M.settings.keymap, M.toggle, { desc = "Toggle Symbol Usages" })
	end
end

-- LAZY.NVIM SPEC
local plugin_spec = {
	name = "fox_lsp_references",
	dir = require("fox.core.lazyspec").for_module(),
	event = { "LspAttach" },
	cmd = { "FoxToggleReferences", "FoxRunCodeLens" },
	keys = {},
	config = M.setup,
}

return setmetatable(plugin_spec, { __index = M })
