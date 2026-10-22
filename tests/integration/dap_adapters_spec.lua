-- ============================================================================
-- tests/integration/dap_adapters_spec.lua -- Debug adapter wiring.
-- ============================================================================
-- Fails loudly when lua/plugins/fox/debuggers/ stops registering adapters and
-- configurations the way lua/plugins/editor/dap.lua expects -- in particular when
-- generic defaults sneak back in and duplicate a language.
-- ============================================================================

require("lazy").load({ plugins = { "nvim-dap" } })

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local dap = require("dap")

--- Configuration names registered for a filetype.
--- @param ft string Filetype.
--- @return string[] names
local function names(ft)
	local out = {}
	for _, config in ipairs(dap.configurations[ft] or {}) do
		table.insert(out, config.name)
	end
	return out
end

describe("dap web configurations", function()
	it("offers the full web stack for typescript, in order", function()
		local ts = names("typescript")

		expect(ts).toHaveLength(9)
		expect(ts[1]).toContain("Bun")
		expect(ts[3]).toContain("Node")
		expect(ts[9]).toContain("Firefox")
	end)

	it("gives astro the same web configurations", function()
		expect(names("astro")).toHaveLength(9)
	end)

	it("registers the js-debug and edge adapters", function()
		expect(dap.adapters["pwa-node"]).toBeDefined()
		expect(dap.adapters["pwa-msedge"]).toBeDefined()
	end)
end)

describe("dap single-runtime configurations", function()
	it("registers only the configurations owned by each language", function()
		for ft, lang in pairs({ python = "python", cs = "csharp", php = "php" }) do
			expect(#names(ft)).toBe(#require("fox.langs." .. lang).dap_configs)
		end
	end)

	it("registers the seven local Go configurations", function()
		expect(#(dap.configurations.go or {})).toBe(7)
		expect(names("go")[1]).toBe("Debug")
		expect(names("go")[5]).toBe("Attach")
	end)
end)
