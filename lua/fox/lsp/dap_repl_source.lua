-- ============================================================================
-- FOX: blink.cmp source for the DAP repl (the "immediate window").
-- ============================================================================
-- WHY IT EXISTS
--   The repl is an ordinary buffer, so blink's default sources (lsp/buffer/
--   snippets) offered string methods and words scraped from the file -- useless
--   while stopped at a breakpoint. This source asks the DEBUG ADAPTER instead, so
--   the menu only holds what actually exists in the current frame.
--
-- TWO STRATEGIES
--   1. Adapters advertising `supportsCompletionsRequest` answer directly.
--   2. Everything else: list the variables of the frame's scopes, which is the
--      best approximation available.
--
-- WIRING
--   Registered as a blink.cmp source in lua/plugins/lsp/lsp.lua.
-- ============================================================================

local M = {}

--- Constructs a source instance. Required by blink.cmp.
--- @return table source
function M.new()
	return setmetatable({}, { __index = M })
end

--- The live debug session, or nil.
--- @return table|nil session
local function session()
	local ok, dap = pcall(require, "dap")
	return ok and dap.session() or nil
end

--- blink.cmp only queries this source while a session is live.
--- @return boolean
function M:enabled()
	return session() ~= nil
end

--- Characters that open the menu without typing a word first.
--- @return string[]
function M:get_trigger_characters()
	return { ".", "[", '"', "'" }
end

--- Asks the adapter what is in scope at the cursor.
--- @param ctx table blink.cmp context.
--- @param callback fun(result: table|nil)
function M:get_completions(ctx, callback)
	callback = vim.schedule_wrap(callback)
	local s = session()
	local frame = s and s.current_frame
	if not frame then
		return callback()
	end

	local kind = require("blink.cmp.types").CompletionItemKind
	local function done(items)
		callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
	end

	-- nvim-dap prefixes repl lines with "dap> "; the adapter must not see it.
	local line = ctx.line:sub(1, ctx.cursor[2])
	local offset = vim.startswith(line, "dap> ") and 5 or 0
	local text = line:sub(offset + 1)

	if (s.capabilities or {}).supportsCompletionsRequest then
		s:request("completions", { frameId = frame.id, text = text, column = #text + 1 }, function(err, resp)
			if err or not resp then
				return done({})
			end
			local items = {}
			for _, t in ipairs(resp.targets or {}) do
				items[#items + 1] = {
					label = t.label,
					insertText = t.text or t.label,
					kind = kind.Variable,
					detail = t.detail,
				}
			end
			done(items)
		end)
		return
	end

	-- Adapters without a `completions` request: list the frame's scope variables.
	s:request("scopes", { frameId = frame.id }, function(err, resp)
		local scopes = (not err and resp and resp.scopes) or {}
		local pending, items = #scopes, {}
		if pending == 0 then
			return done({})
		end
		for _, scope in ipairs(scopes) do
			s:request("variables", { variablesReference = scope.variablesReference }, function(verr, vresp)
				for _, v in ipairs((not verr and vresp and vresp.variables) or {}) do
					items[#items + 1] = {
						label = v.name,
						kind = kind.Variable,
						detail = (v.value or ""):gsub("%s+", " "),
					}
				end
				pending = pending - 1
				if pending == 0 then
					done(items)
				end
			end)
		end
	end)
end

return M
