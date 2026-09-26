-- ============================================================================
-- LAZY REQUIRE -- Defer module loading until property access or function call.
-- ============================================================================
-- Eliminates startup overhead from top-level `require()` calls inside plugin specs.
-- ============================================================================

local M = {}

--- Creates a transparent lazy proxy table for a Lua module.
--- The target module is only required when a field is accessed or invoked.
---
--- @param modname string Module name to pass to `require()`
--- @return table proxy
function M.require(modname)
	local loaded = nil
	return setmetatable({}, {
		__index = function(_, key)
			if not loaded then
				loaded = require(modname)
			end
			return loaded[key]
		end,
		__newindex = function(_, key, val)
			if not loaded then
				loaded = require(modname)
			end
			loaded[key] = val
		end,
		__call = function(_, ...)
			if not loaded then
				loaded = require(modname)
			end
			return loaded(...)
		end,
	})
end

return setmetatable(M, {
	__call = function(_, modname)
		return M.require(modname)
	end,
})
