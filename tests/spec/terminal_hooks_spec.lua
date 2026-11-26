local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local installer = require("fox.terminal.hook_installer")
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

local function isolated(test)
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p")
	local ok, err = pcall(test, directory)
	vim.fn.delete(directory, "rf")
	assert(ok, err)
end

local function json(path)
	return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end

describe("terminal session hooks", function()
	it("preserves existing settings and installs each agent idempotently", function()
		isolated(function(home)
			vim.fn.mkdir(home .. "/.claude", "p")
			vim.fn.writefile(
				{ '{"theme":"dark","hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"existing"}]}]}}' },
				home .. "/.claude/settings.json"
			)
			for _, agent in ipairs({ "codex", "claude", "opencode", "agy" }) do
				installer.install(agent, { home = home })
				installer.install(agent, { home = home })
			end
			local claude = json(home .. "/.claude/settings.json")
			expect(claude.theme).toBe("dark")
			expect(#claude.hooks.SessionStart).toBe(2)
			expect(claude.hooks.SessionStart[1].hooks[1].command).toBe("existing")
			expect(#json(home .. "/.config/opencode/tui.json").plugin).toBe(1)
			expect(#json(home .. "/.config/opencode/cli.json").plugins).toBe(1)
			expect(vim.fn.filereadable(home .. "/.claude/settings.json.foxvim-backup")).toBe(1)
			expect(json(home .. "/.gemini/config/hooks.json").foxvim.PreInvocation[1].type).toBe("command")
		end)
	end)

	it("refuses malformed settings and leaves JSONC untouched", function()
		isolated(function(home)
			vim.fn.mkdir(home .. "/.claude", "p")
			vim.fn.writefile({ "{broken" }, home .. "/.claude/settings.json")
			expect(pcall(installer.install, "claude", { home = home })).toBe(false)
			expect(vim.fn.readfile(home .. "/.claude/settings.json")[1]).toBe("{broken")
			vim.fn.mkdir(home .. "/.config/opencode", "p")
			vim.fn.writefile({ "// retained", "{}" }, home .. "/.config/opencode/tui.jsonc")
			expect(pcall(installer.install, "opencode", { home = home })).toBe(false)
			expect(vim.fn.filereadable(home .. "/.config/opencode/foxvim-session.js")).toBe(0)
		end)
	end)

	it("keeps Codex features and profile configuration", function()
		isolated(function(home)
			vim.fn.mkdir(home .. "/.codex", "p")
			vim.fn.writefile(
				{ "[features]", "other = true", "hooks = true", "[profiles.work]", 'model = "test"' },
				home .. "/.codex/config.toml"
			)
			installer.install("codex", { home = home })
			local content = table.concat(vim.fn.readfile(home .. "/.codex/config.toml"), "\n")
			expect(content:find("hooks = true", 1, true) ~= nil).toBe(true)
			expect(content:find('model = "test"', 1, true) ~= nil).toBe(true)
		end)
	end)

	it("preserves an explicit Codex hooks opt-out before any write", function()
		isolated(function(home)
			vim.fn.mkdir(home .. "/.codex", "p")
			vim.fn.writefile({ "[features]", "hooks = false" }, home .. "/.codex/config.toml")
			expect(pcall(installer.install, "codex", { home = home })).toBe(false)
			expect(vim.fn.readfile(home .. "/.codex/config.toml")[2]).toBe("hooks = false")
			expect(vim.fn.filereadable(home .. "/.codex/hooks.json")).toBe(0)
		end)
	end)

	it("preserves pending OpenCode preference migration", function()
		isolated(function(home)
			vim.fn.mkdir(home .. "/.config/opencode", "p")
			vim.fn.writefile({ '{"theme":"existing"}' }, home .. "/.config/opencode/tui.json")
			expect(pcall(installer.install, "opencode", { home = home })).toBe(false)
			expect(json(home .. "/.config/opencode/tui.json").theme).toBe("existing")
			expect(vim.fn.filereadable(home .. "/.config/opencode/cli.json")).toBe(0)
		end)
	end)

	it("encodes Windows hook commands without shell expansion", function()
		isolated(function(home)
			installer.install("claude", { home = home, windows = true, nvim = [[C:\My Editor\nvim.exe]] })
			local command = json(home .. "/.claude/settings.json").hooks.SessionStart[1].hooks[1].command
			local encoded = command:match("%-EncodedCommand (%S+)$")
			expect(type(encoded)).toBe("string")
			local decoded = vim.iconv(vim.base64.decode(encoded), "utf-16le", "utf-8")
			expect(decoded:find([[& 'C:\My Editor\nvim.exe']], 1, true) ~= nil).toBe(true)
		end)
	end)

	it("reports only the terminal's root sessions without transcripts", function()
		isolated(function(directory)
			local function run(agent, payload, terminal)
				return vim
					.system({ vim.v.progpath, "--headless", "-u", "NONE", "-l", root .. "/lua/fox/terminal/session_hook.lua", agent }, {
						stdin = vim.json.encode(payload),
						env = { FOXVIM_AGENT_EVENT_DIR = directory, FOXVIM_TERMINAL_ID = terminal or "token-1" },
						text = true,
					})
					:wait()
			end
			expect(run("claude", { hook_event_name = "SessionStart", session_id = "root", transcript_path = "secret" }).code).toBe(
				0
			)
			local event = json(directory .. "/token-1.json")
			expect(event.id).toBe("root")
			expect(event.agent).toBe("claude")
			expect(event.transcript_path).toBe(nil)
			run("claude", { hook_event_name = "SessionStart", session_id = "child", agent_id = "subagent" })
			expect(json(directory .. "/token-1.json").id).toBe("root")
			run("claude", { hook_event_name = "SessionEnd", session_id = "root" })
			expect(json(directory .. "/token-1.json").event).toBe("end")
			expect(run("agy", { conversationId = "conversation" }, "token-2").stdout).toBe("{}\n")
			expect(json(directory .. "/token-2.json").id).toBe("conversation")
			run("claude", { hook_event_name = "SessionStart", session_id = "escape" }, "../escape")
			expect(vim.fn.filereadable(directory .. "/escape.json")).toBe(0)
		end)
	end)
end)
