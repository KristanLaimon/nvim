local t = require("fox.lib.foxnvim.test")
local state = require("fox.reader.state")
local workspace = require("fox.reader.workspace")

t.describe("Reader state", function()
	t.it("persists preferences and document positions, and handles corrupt and unwritable files", function()
		local previous = state.path
		local directory = vim.fn.tempname()
		vim.fn.mkdir(directory, "p")
		state.path = directory .. "/state.json"
		local root = assert(workspace.root(vim.fn.getcwd()))
		local preferences =
			{ theme = "dark", font = "Georgia", alignment = "left", size = 20, lineSpacing = 2, width = 900, focus = true }
		t.expect(state.save(root, { kind = "preferences", value = preferences })).toBe(true)
		t.expect(
			state.save(
				root,
				{ kind = "position", path = "README.md", value = { heading = "intro", offset = -24, scroll = 200 } }
			)
		).toBe(true)
		local saved = state.get(root, "README.md")
		t.expect(saved.preferences.width).toBe(900)
		t.expect(saved.position.heading).toBe("intro")
		t.expect(state.get(root, "./README.md").position.heading).toBe("intro")
		t.expect(state.get(root, "AGENTS.md").position).toBe(vim.NIL)
		t.expect(
			state.save(root, { kind = "position", path = "../outside.md", value = { heading = "", offset = 0, scroll = 1 } })
		)
			.toBe(false)
		vim.fn.writefile({ "not json" }, state.path)
		t.expect(type(state.get(root).warning)).toBe("string")
		t.expect(state.save(root, { kind = "preferences", value = preferences })).toBe(true)
		t.expect(state.get(root).preferences.font).toBe("Georgia")
		state.path = directory .. "/missing/../state.json/child"
		t.expect(state.save(root, { kind = "preferences", value = preferences })).toBe(false)
		state.path = previous
		vim.fn.delete(directory, "rf")
	end)
end)
