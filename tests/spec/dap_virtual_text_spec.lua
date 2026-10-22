local t = require("fox.lib.foxnvim.test")
local describe, it, expect = t.describe, t.it, t.expect
local virtual_text = require("fox.dap.virtual_text")
local namespace = vim.api.nvim_create_namespace("fox_dap_virtual_text")
local key = "fox_dap_virtual_text"

describe("local DAP virtual text", function()
	local buf, debugger, active, session, frame
	local function marks()
		return vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
	end
	local function fire(when, event, s, ...)
		debugger.listeners[when][event][key](s or session, ...)
	end
	local function variables(value)
		return { { presentationHint = "locals", variables = { { name = "x", value = value } } } }
	end

	t.beforeEach(function()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".lua")
		vim.bo[buf].filetype = "lua"
		vim.bo[buf].commentstring = "-- %s"
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			"local x = 1",
			"print(x, x)",
			"do",
			"  local x = 2",
			"  print(x)",
			"end",
			'print("x")',
			"-- x",
		})
		vim.treesitter.query.set(
			"lua",
			"locals",
			[[
			(chunk) @local.scope
			(do_statement) @local.scope
			(identifier) @local.definition.var
			(identifier) @local.reference
		]]
		)
		local function listener_table()
			return setmetatable({}, {
				__index = function(self, event)
					local callbacks = {}
					rawset(self, event, callbacks)
					return callbacks
				end,
			})
		end
		active = nil
		debugger = {
			listeners = { before = listener_table(), after = listener_table(), on_session = {} },
			session = function()
				return active
			end,
		}
		frame =
			{ id = 1, line = 2, column = 1, source = { path = vim.api.nvim_buf_get_name(buf) }, scopes = variables("1") }
		session = { current_frame = frame, stopped_thread_id = 1 }
		virtual_text.setup(debugger)
		virtual_text.enable()
		active = session
		debugger.listeners.on_session[key](nil, session)
	end)
	t.afterEach(function()
		virtual_text.disable()
		vim.treesitter.query.set("lua", "locals", nil)
		vim.api.nvim_buf_delete(buf, { force = true })
		for _, command in ipairs({ "Enable", "Disable", "Toggle", "ForceRefresh" }) do
			vim.api.nvim_del_user_command("DapVirtualText" .. command)
		end
	end)

	it("annotates definitions and references once per line, excluding inactive scopes and text", function()
		local result = marks()
		expect(#result).toBe(2)
		expect(result[1][2]).toBe(0)
		expect(result[2][2]).toBe(1)
		for _, mark in ipairs(result) do
			expect(#mark[4].virt_text).toBe(1)
			expect(mark[4].virt_text[1][1]).toBe("  -- x = 1")
			expect(mark[4].virt_text[1][2]).toBe("NvimDapVirtualText")
			expect(mark[4].virt_text_pos ~= "inline").toBe(true)
			expect(mark[4].virt_text_win_col).toBe(80)
		end
	end)

	it("prefers local scope values and keeps annotations beyond long source lines", function()
		frame.scopes = { { variables = { { name = "x", value = "global" } } }, unpack(variables("local")) }
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "local x = 1 -- " .. string.rep("a", 100) })
		fire("after", "variables")
		local mark = marks()[1]
		expect(mark[4].virt_text[1][1]).toBe("  -- x = local")
		expect(mark[4].virt_text_win_col > 110).toBe(true)
	end)

	it("collapses whitespace and truncates values without splitting Unicode characters", function()
		frame.scopes = variables("a\nb\tc")
		fire("after", "variables")
		expect(marks()[1][4].virt_text[1][1]).toBe("  -- x = a b c")
		frame.scopes = variables(string.rep("é", 70))
		fire("after", "variables")
		expect(marks()[1][4].virt_text[1][1]).toBe("  -- x = " .. string.rep("é", 59) .. "…")
	end)

	it("highlights changed values across stops and keeps that highlight during refresh", function()
		fire("before", "event_stopped", nil, { reason = "step" })
		frame.scopes = variables("2")
		fire("after", "variables")
		expect(marks()[1][4].virt_text[1][2]).toBe("NvimDapVirtualTextChanged")
		fire("after", "variables")
		expect(marks()[1][4].virt_text[1][2]).toBe("NvimDapVirtualTextChanged")
	end)

	it("clears on continue and ignores late variable responses until the next stop", function()
		for _, event in ipairs({ "continue", "next", "stepIn", "stepOut", "stepBack", "reverseContinue", "event_continued" }) do
			fire("before", event)
			expect(#marks()).toBe(0)
			fire("after", "variables")
			expect(#marks()).toBe(0)
			fire("before", "event_stopped")
			fire("after", "variables")
			expect(#marks()).toBe(2)
		end
	end)

	it("clears on exit, termination and disconnect without accepting late results", function()
		for _, event in ipairs({ "event_exited", "event_terminated", "disconnect" }) do
			fire("after", event)
			expect(#marks()).toBe(0)
			fire("after", "variables")
			expect(#marks()).toBe(0)
			debugger.listeners.on_session[key](nil, session)
		end
	end)

	it("updates when switching stack frames and rejects responses from inactive sessions", function()
		local other = { current_frame = frame, stopped_thread_id = 1 }
		active = other
		debugger.listeners.on_session[key](session, other)
		frame.scopes = variables("new session")
		fire("after", "variables", other)
		expect(marks()[1][4].virt_text[1][1]).toBe("  -- x = new session")
		fire("after", "event_exited", session)
		expect(#marks()).toBe(2)
		other.current_frame = { id = 2, line = 5, source = frame.source, scopes = variables("inner") }
		fire("after", "scopes", other)
		expect(#marks()).toBe(4)
		other.current_frame = nil
		fire("after", "stackTrace", other)
		expect(#marks()).toBe(0)
	end)

	it("keeps enable, disable, toggle and refresh commands working", function()
		vim.cmd("DapVirtualTextDisable")
		fire("after", "variables")
		expect(#marks()).toBe(0)
		vim.cmd("DapVirtualTextEnable")
		expect(#marks()).toBe(2)
		vim.cmd("DapVirtualTextToggle")
		expect(#marks()).toBe(0)
		vim.cmd("DapVirtualTextToggle")
		vim.cmd("DapVirtualTextForceRefresh")
		expect(#marks()).toBe(2)
	end)

	it("shows exception details and data breakpoint reasons", function()
		fire("before", "event_stopped", nil, { reason = "exception" })
		fire("after", "variables")
		expect(#marks()).toBe(3)
		fire("after", "exceptionInfo", nil, nil, { description = "Bad\nvalue" })
		local found = false
		for _, mark in ipairs(marks()) do
			if mark[4].virt_text[1][1] == "-- Bad value" then
				found = mark[4].virt_text[1][2] == "NvimDapVirtualTextError"
			end
		end
		expect(found).toBe(true)
		fire("before", "event_stopped", nil, { reason = "data breakpoint" })
		fire("after", "variables")
		found = false
		for _, mark in ipairs(marks()) do
			found = found or mark[4].virt_text[1][2] == "NvimDapVirtualTextInfo"
		end
		expect(found).toBe(true)
	end)

	it("handles missing source buffers, unloaded variables and unsupported parsers", function()
		frame.scopes = nil
		fire("after", "variables")
		expect(#marks()).toBe(0)
		frame.scopes = variables("1")
		vim.bo[buf].filetype = "fox_no_parser"
		fire("after", "variables")
		expect(#marks()).toBe(0)
		frame.source = { path = vim.fn.tempname() }
		fire("after", "variables")
		expect(#marks()).toBe(0)
		frame.source = nil
		virtual_text.refresh()
		expect(#marks()).toBe(0)
	end)
end)
