local t = require("fox.lib.foxnvim.test")
local templates = require("fox.core.templates")
local cli = require("fox.lib.foxnvim.cli")

local tmp_dir

t.describe("generic file creation template system", function()
	t.beforeEach(function()
		tmp_dir = vim.fn.tempname()
		vim.fn.mkdir(tmp_dir, "p")
	end)

	t.afterEach(function()
		if tmp_dir and vim.fn.isdirectory(tmp_dir) == 1 then
			vim.fn.delete(tmp_dir, "rf")
		end
	end)

	t.it("discovers and orders templates by frontmatter index", function()
		local cs_tmpls = templates.get_templates("cs")
		t.expect(#cs_tmpls > 0).toBe(true)

		-- Verify Class is index 0 and first
		t.expect(cs_tmpls[1].name).toBe("Class")
		t.expect(cs_tmpls[1].index).toBe(0)

		-- Verify ascending order of indices
		for i = 2, #cs_tmpls do
			t.expect(cs_tmpls[i].index >= cs_tmpls[i - 1].index).toBe(true)
		end
	end)

	t.it("discovers and parses typescriptreact component templates", function()
		local tsx_tmpls = templates.get_templates("typescriptreact")
		t.expect(#tsx_tmpls).toBe(7)

		local names = {}
		for _, tmpl in ipairs(tsx_tmpls) do
			names[#names + 1] = tmpl.name
		end

		t.expect(names).toContain("Function Component with Props")
		t.expect(names).toContain("Function Component (Hooks, no props)")
		t.expect(names).toContain("Arrow Function with Props")
		t.expect(names).toContain("Arrow Function (Hooks, no props)")
		t.expect(names).toContain("Class Component")
		t.expect(names).toContain("Server Component (Async)")
		t.expect(names).toContain("Custom Hook")
	end)

	t.it("returns empty list for languages without template folder or 0 templates", function()
		t.expect(templates.get_templates("nonexistent_lang")).toEqual({})
		t.expect(templates.get_templates("")).toEqual({})
		t.expect(templates.get_templates(nil)).toEqual({})
	end)

	t.it("parses YAML frontmatter and body cleanly", function()
		local sample =
			"---\nname: Special Component\ndescription: Custom widget\nindex: 3\n---\nexport const <%filename%> = () => {};\n"
		local meta, body = templates.parse_frontmatter(sample, "Fallback")
		t.expect(meta.name).toBe("Special Component")
		t.expect(meta.description).toBe("Custom widget")
		t.expect(meta.index).toBe(3)
		t.expect(body).toBe("export const <%filename%> = () => {};\n")
	end)

	t.it("substitutes universal variables in template body", function()
		local body = "// File: <%filename%>\n// Ext: <%filename_ext%>\n// Date: <%year%>\nexport default <%classname%>;"
		local vars = templates.resolve_variables("/path/to/my_cool_component.tsx", "typescriptreact")
		local rendered = templates.render(body, vars)
		t.expect(rendered).toContain("// File: my_cool_component")
		t.expect(rendered).toContain("// Ext: my_cool_component.tsx")
		t.expect(rendered).toContain("// Date: " .. os.date("%Y"))
		t.expect(rendered).toContain("export default my_cool_component;")
	end)

	t.it("cleans up lines with nil namespace when no namespace is present", function()
		local body = "namespace <%csharp_namespace%>\n\ninternal class <%filename%>\n{\n   $0\n}"
		local vars = templates.resolve_variables("/standalone/Customer.cs", "cs")
		local rendered = templates.render(body, vars)
		-- Standalone with no .csproj and no Program.cs has nil namespace
		t.expect(rendered:find("namespace")).toBeNil()
		t.expect(rendered).toContain("internal class Customer")
		t.expect(rendered).toContain("   $0")
	end)

	t.it("infers namespace from .csproj with RootNamespace and relative folder", function()
		vim.fn.mkdir(tmp_dir .. "/src/Services/Auth", "p")
		vim.fn.writefile(
			{ "<Project><PropertyGroup><RootNamespace>MyCompany.Core</RootNamespace></PropertyGroup></Project>" },
			tmp_dir .. "/src/MyProject.csproj"
		)
		local file = tmp_dir .. "/src/Services/Auth/TokenProvider.cs"
		local ns = templates.csharp_namespace(file)
		t.expect(ns).toBe("MyCompany.Core.Services.Auth")
	end)

	t.it("infers namespace from .csproj project name when RootNamespace is omitted", function()
		vim.fn.mkdir(tmp_dir .. "/Controllers", "p")
		vim.fn.writefile({ "<Project />" }, tmp_dir .. "/ShopApp.csproj")
		local file = tmp_dir .. "/Controllers/OrderController.cs"
		local ns = templates.csharp_namespace(file)
		t.expect(ns).toBe("ShopApp.Controllers")
	end)

	t.it("infers namespace from root Program.cs when no .csproj exists", function()
		vim.fn.mkdir(tmp_dir .. "/Models", "p")
		vim.fn.writefile({ "namespace CoolStore.Server;\npublic class Program {}" }, tmp_dir .. "/Program.cs")
		local file = tmp_dir .. "/Models/Item.cs"
		local ns = templates.csharp_namespace(file)
		t.expect(ns).toBe("CoolStore.Server.Models")
	end)

	t.it("infers namespace from root Program.cs for files in root", function()
		vim.fn.writefile({ "namespace CoolStore.Server;\npublic class Program {}" }, tmp_dir .. "/Program.cs")
		local file = tmp_dir .. "/Startup.cs"
		local ns = templates.csharp_namespace(file)
		t.expect(ns).toBe("CoolStore.Server")
	end)

	t.it("sanitizes C# keywords and invalid identifiers in namespace", function()
		vim.fn.mkdir(tmp_dir .. "/class/123-bad", "p")
		vim.fn.writefile({ "<Project />" }, tmp_dir .. "/App.csproj")
		local file = tmp_dir .. "/class/123-bad/Item.cs"
		local ns = templates.csharp_namespace(file)
		t.expect(ns).toBe("App.@class._123_bad")
	end)

	t.it("applies template to buffer with proper $0 cursor positioning", function()
		local buf = vim.api.nvim_create_buf(true, false)
		local file = tmp_dir .. "/User.lua"
		vim.api.nvim_buf_set_name(buf, file)

		local tmpl = {
			name = "Module",
			filetype = "lua",
			body = "local M = {}\n\n$0\n\nreturn M\n",
		}

		templates.apply_template_to_buffer(buf, tmpl, file)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = table.concat(lines, "\n")
		t.expect(lines[1]).toBe("local M = {}")
		t.expect(content).toContain("return M")
		t.expect(content:find("%$0")).toBeNil()

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	t.it("supports linked numbered tabstops and finishes at $0", function()
		local original = vim.api.nvim_get_current_buf()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp_dir .. "/Linked.lua")
		vim.api.nvim_set_current_buf(buf)
		local ok, err = pcall(function()
			templates.apply_template_to_buffer(buf, {
				name = "Linked",
				filetype = "lua",
				body = "${1:Item} = $1\n$2\n$0",
			})
			t.expect(vim.snippet.active()).toBe(true)
			vim.api.nvim_buf_set_text(buf, 0, 0, 0, 4, { "Thing" })
			vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
			t.expect(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]).toBe("Thing = Thing")
			vim.snippet.jump(1)
			t.expect(vim.api.nvim_win_get_cursor(0)).toEqual({ 2, 0 })
			vim.snippet.jump(1)
			t.expect(vim.snippet.active()).toBe(false)
			t.expect(vim.api.nvim_win_get_cursor(0)).toEqual({ 3, 0 })
		end)
		if vim.snippet.active() then
			vim.snippet.stop()
		end
		vim.api.nvim_set_current_buf(original)
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)

	t.it("removes numbered markers when the target buffer is hidden", function()
		local buf = vim.api.nvim_create_buf(true, false)
		local file = tmp_dir .. "/Hidden.lua"
		vim.api.nvim_buf_set_name(buf, file)
		templates.apply_template_to_buffer(buf, {
			name = "Hidden",
			filetype = "lua",
			body = "${1:Item} = $1\n$2\n$0",
		}, file)
		t.expect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)).toEqual({ "Item = Item", "", "" })
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	t.it("offers template menu and closes cleanly when option selected", function()
		local buf = vim.api.nvim_create_buf(true, false)
		local file = tmp_dir .. "/Widget.svelte"
		vim.api.nvim_buf_set_name(buf, file)
		vim.bo[buf].filetype = "svelte"

		local menu_called = false
		local orig_menu = cli.menu
		cli.menu = function(title, options, cb)
			menu_called = true
			t.expect(title.title).toContain("SVELTE")
			t.expect(#options > 0).toBe(true)
			cb(options[1])
		end

		local offered = templates.offer_template(buf, "svelte")
		cli.menu = orig_menu

		t.expect(offered).toBe(true)
		t.expect(menu_called).toBe(true)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		t.expect(lines[1]).toContain("<script")

		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	t.it("does not offer menu for languages without templates", function()
		local buf = vim.api.nvim_create_buf(true, false)
		vim.bo[buf].filetype = "python"
		local offered = templates.offer_template(buf, "python")
		t.expect(offered).toBe(false)
		vim.api.nvim_buf_delete(buf, { force = true })
	end)

	t.it("closes the real floating menu window completely upon selection", function()
		local list_uis = vim.api.nvim_list_uis
		vim.api.nvim_list_uis = function()
			return { {} }
		end

		local buf = vim.api.nvim_create_buf(true, false)
		local file = tmp_dir .. "/Button.svelte"
		vim.api.nvim_buf_set_name(buf, file)
		vim.bo[buf].filetype = "svelte"

		local ok, err = pcall(function()
			local offered = templates.offer_template(buf, "svelte")
			t.expect(offered).toBe(true)

			local popup_win = vim.api.nvim_get_current_win()
			local popup_buf = vim.api.nvim_win_get_buf(popup_win)
			t.expect(vim.bo[popup_buf].filetype).toBe("foxmenu")
			local popup_lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
			local popup_size = vim.api.nvim_win_get_config(popup_win)
			t.expect(popup_lines[1]).toContain("SVELTE Template")
			t.expect(popup_lines[4]).toContain("Component")
			t.expect(popup_size.width).toBe(math.min(96, vim.o.columns - 4))
			t.expect(popup_size.height).toBe(math.min(18, vim.o.lines - 4))

			-- Trigger Enter on the menu
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(popup_buf, "n")) do
				if map.lhs == "<CR>" then
					map.callback()
					break
				end
			end

			-- The floating window must now be closed!
			t.expect(vim.api.nvim_win_is_valid(popup_win)).toBe(false)
			t.expect(vim.b[buf].fox_template_pending).toBeNil()

			local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
			t.expect(content).toContain("<script")
		end)

		vim.api.nvim_list_uis = list_uis
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		assert(ok, err)
	end)

	t.it("automatically discovers newly added template files without lua code changes", function()
		local custom_lang_dir = vim.fs.joinpath(tmp_dir, "customtestlang")
		vim.fn.mkdir(custom_lang_dir, "p")
		local original_dirs = templates.get_template_dirs
		templates.get_template_dirs = function()
			return { tmp_dir }
		end

		-- Initially 0 templates
		t.expect(#templates.get_templates("customtestlang")).toBe(0)

		-- User drops a markdown file into the folder
		local file_content = "---\nname: Custom Snippet\ndescription: Zero Lua required\nindex: 0\n---\nHello <%filename%>!"
		vim.fn.writefile(vim.split(file_content, "\n"), custom_lang_dir .. "/my_snippet.md")

		local found = templates.get_templates("customtestlang")
		t.expect(#found).toBe(1)
		t.expect(found[1].name).toBe("Custom Snippet")
		t.expect(found[1].description).toBe("Zero Lua required")

		-- Cleanup
		vim.fn.delete(custom_lang_dir, "rf")
		t.expect(#templates.get_templates("customtestlang")).toBe(0)
		templates.get_template_dirs = original_dirs
	end)

	t.it("adds a new C# menu choice from a Markdown file", function()
		local lang_dir = vim.fs.joinpath(tmp_dir, "cs")
		vim.fn.mkdir(lang_dir, "p")
		vim.fn.writefile(
			{ "---", "name: Service", "index: 0", "---", "internal class <%filename%> {}" },
			lang_dir .. "/service.md"
		)
		local original_dirs, original_menu = templates.get_template_dirs, cli.menu
		templates.get_template_dirs = function()
			return { tmp_dir }
		end
		local selected
		cli.menu = function(_, options, callback)
			selected = options[1].name
			callback(options[1])
		end
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(buf, tmp_dir .. "/Widget.cs")
		local ok, err = pcall(function()
			require("fox.langs.csharp").new_type(buf)
			t.expect(selected).toBe("Service")
			t.expect(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")).toContain("internal class Widget")
		end)
		cli.menu, templates.get_template_dirs = original_menu, original_dirs
		vim.api.nvim_buf_delete(buf, { force = true })
		assert(ok, err)
	end)
end)
