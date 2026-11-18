local t = require("fox.lib.foxnvim.test")

local function open_config(filename)
	vim.cmd.edit({ args = { vim.fn.tempname() .. "/" .. filename }, bang = true })
	return vim.api.nvim_get_current_buf()
end

local function completions(bufnr, line, cursor)
	local items
	require("fox.lsp.config_directives")
		.new()
		:get_completions({ bufnr = bufnr, line = line, cursor = { 1, cursor or #line } }, function(result)
			items = result.items
		end)
	return items
end

t.describe("Config directive completion", function()
	t.it("registers with Blink and completes a dotted PHP 8.5.12 key in place", function()
		local bufnr = open_config("php.ini-production")
		require("lazy").load({ plugins = { "blink.cmp" } })
		local providers = require("blink.cmp.sources.lib").get_enabled_providers("default")
		t.expect(providers.config_directives ~= nil).toBe(true)
		local line = "  opcache.enable_cli = 1"
		local items = completions(bufnr, line, #"  opcache.ena")
		local item = vim.iter(items):find(function(candidate)
			return candidate.label == "opcache.enable_cli"
		end)
		t.expect(item.detail).toBe("PHP 8.5.12")
		t.expect(item.textEdit.newText).toBe("opcache.enable_cli")
		t.expect(item.textEdit.range.start.character).toBe(2)
		t.expect(item.textEdit.range["end"].character).toBe(#"  opcache.enable_cli")
		t.expect(completions(bufnr, "memory_hard_limit_per")[1].label).toBe("memory_hard_limit_percent")
		t.expect(#completions(bufnr, "disable_classes")).toBe(0)
		t.expect(#completions(bufnr, ";memory")).toBe(0)
		t.expect(#completions(bufnr, "memory_limit = 12")).toBe(0)
		vim.b[bufnr].fox_php_ini_version = "0.0.0"
		t.expect(#completions(bufnr, "memory")).toBe(0)
	end)

	t.it("completes Apache directives and sections using case-insensitive prefixes", function()
		local bufnr = open_config(".htaccess")
		t.expect(vim.bo[bufnr].filetype).toBe("apache")
		t.expect(completions(bufnr, "rewriteR")[1].textEdit.newText).toBe("RewriteRule")
		local section = completions(bufnr, "  </directo>")[1]
		t.expect(section).toBe(nil)
		section = completions(bufnr, "  </directo>", #"  </directo")[1]
		t.expect(section.textEdit.newText).toBe("Directory")
		t.expect(section.textEdit.range.start.character).toBe(#"  </")
	end)

	t.it("completes Nginx directives and leaves other INI files alone", function()
		local bufnr = open_config("nginx.conf")
		t.expect(vim.bo[bufnr].filetype).toBe("nginx")
		t.expect(completions(bufnr, "  try_f")[1].textEdit.newText).toBe("try_files")
		t.expect(#completions(bufnr, "  proxy_pass http")).toBe(0)
		t.expect(#completions(bufnr, "# try_f")).toBe(0)
		bufnr = open_config("settings.ini")
		t.expect(vim.bo[bufnr].filetype).toBe("dosini")
		t.expect(#completions(bufnr, "memory")).toBe(0)
	end)
end)
