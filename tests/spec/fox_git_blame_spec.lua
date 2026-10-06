-- ============================================================================
-- tests/spec/fox_git_blame_spec.lua -- Per-line authorship parsing (git blame)
-- ============================================================================

local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local blame = require("fox.git.blame")

describe("fox.git.blame", function()
	it("maps every final line to the author that last touched it", function()
		local sample = {
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 1 1 2",
			"author Alice",
			"author-mail <alice@example.com>",
			"author-time 1700000000",
			"	line one",
			"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 2 2",
			"	line two",
			"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 3 3 1",
			"author Bob",
			"	line three",
			"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 4 4",
			"	line four",
		}
		local authors = blame.parse_porcelain(sample)

		expect(authors[1]).toBe("Alice")
		expect(authors[2]).toBe("Alice")
		expect(authors[3]).toBe("Bob")
		expect(authors[4]).toBe("Bob")
	end)

	it("keeps the author name when it contains spaces", function()
		local sample = {
			"cccccccccccccccccccccccccccccccccccccccc 7 7 1",
			"author Kristan Ruiz Limon",
			"	code",
		}
		local authors = blame.parse_porcelain(sample)
		expect(authors[7]).toBe("Kristan Ruiz Limon")
	end)

	it("queries a real file without error", function()
		local authors = blame.query("lua/fox/git/blame.lua", nil, vim.fn.stdpath("config"))
		expect(type(authors)).toBe("table")
	end)
end)
