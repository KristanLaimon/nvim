local M = {}
local ns = vim.api.nvim_create_namespace("fox_sql_syntax")
local dialect_ns = vim.api.nvim_create_namespace("fox_sql_dialect")
local pending = {}
local revisions = {}
local dialect = require("fox.langs.sql.dialect")

function M.dialect_checks(text, name)
	local diagnostics = {}
	local exclusive = {
		CURDATE = { mysql = true },
		CURTIME = { mysql = true },
		DATE_FORMAT = { mysql = true },
		STR_TO_DATE = { mysql = true },
		DATEDIFF = { mysql = true },
		TIMESTAMPDIFF = { mysql = true },
		DATE_ADD = { mysql = true, postgres = true },
		DATE_SUB = { mysql = true },
		DATE_TRUNC = { postgres = true },
		DATE_PART = { postgres = true },
		JSONB_BUILD_OBJECT = { postgres = true },
		GENERATE_SERIES = { postgres = true },
		SQLITE_VERSION = { sqlite = true },
		JULIANDAY = { sqlite = true },
		STRFTIME = { sqlite = true },
		TOTAL = { sqlite = true },
		NOW = { mysql = true, postgres = true },
	}
	local tokens = require("fox.query.sql").tokens(text, name)
	for index, token in ipairs(tokens) do
		local supported = token.kind == "word" and exclusive[token.upper]
		if
			supported
			and not supported[name]
			and tokens[index + 1]
			and tokens[index + 1].value == "("
			and not (tokens[index - 1] and tokens[index - 1].value == ".")
		then
			local before = text:sub(1, token.first - 1)
			local _, row = before:gsub("\n", "")
			local column = #(before:match("[^\n]*$") or "")
			diagnostics[#diagnostics + 1] = {
				lnum = row,
				col = column,
				end_col = column + #token.value,
				message = token.upper
					.. "() is not a built-in "
					.. dialect.names[name]
					.. " function (available in "
					.. table.concat(vim.tbl_keys(supported), ", ")
					.. ").",
				severity = vim.diagnostic.severity.WARN,
				source = "SQL dialect",
			}
		end
	end
	return diagnostics
end

function M.parse(output, lines)
	local ok, files = pcall(vim.json.decode, output)
	if not ok or type(files) ~= "table" then
		return nil
	end
	local diagnostics = {}
	for _, file in ipairs(files) do
		for _, violation in ipairs(file.violations or {}) do
			if violation.code == "PRS" or violation.code == "LXR" or violation.code == "TMP" then
				local row = math.max(0, math.min(#lines - 1, (violation.start_line_no or violation.line_no or 1) - 1))
				local char = math.max(0, (violation.start_line_pos or violation.line_pos or 1) - 1)
				local column = vim.fn.byteidx(lines[row + 1] or "", char)
				diagnostics[#diagnostics + 1] = {
					lnum = row,
					col = column < 0 and #(lines[row + 1] or "") or column,
					message = violation.description or "Invalid SQL",
					code = violation.code,
					severity = vim.diagnostic.severity.ERROR,
					source = "SQLFluff",
				}
			end
		end
	end
	return diagnostics
end

function M.check(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local name = dialect.read(buf) or vim.b[buf].fox_sql_dialect
	if not name then
		return
	end
	revisions[buf] = (revisions[buf] or 0) + 1
	local revision = revisions[buf]
	if pending[buf] then
		pending[buf]:kill(15)
		pending[buf] = nil
	end
	vim.diagnostic.reset(ns, buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local text = table.concat(lines, "\n")
	if #text > 128 * 1024 then
		vim.diagnostic.reset(dialect_ns, buf)
		vim.b[buf].fox_sql_syntax_status = "SQL checks limited to 128 KiB"
		return
	end
	vim.diagnostic.set(
		dialect_ns,
		buf,
		M.dialect_checks(text, name),
		{ underline = true, signs = true, virtual_text = true }
	)
	local root = vim.b[buf].fox_sql_root or vim.b[buf].fox_query_root or require("fox.query.storage").root()
	local settings = require("fox.query.storage").load(root, "settings.json", {})
	if not settings or settings.sql_syntax_check ~= true then
		vim.b[buf].fox_sql_syntax_status = "general syntax off; dialect checks on"
		return
	end
	if vim.fn.executable("sqlfluff") ~= 1 then
		vim.b[buf].fox_sql_syntax_status = "Install SQLFluff via :LanguageManager for syntax diagnostics"
		return
	end
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	vim.b[buf].fox_sql_syntax_status = "checking " .. name
	local executable = vim.fn.exepath("sqlfluff")
	if vim.fn.has("win32") == 1 and executable:lower():match("%.cmd$") then
		local mason = vim.fn.stdpath("data") .. "/mason"
		local ok, mason_settings = pcall(require, "mason.settings")
		if ok then
			mason = mason_settings.current.install_root_dir
		end
		local native = mason .. "/packages/sqlfluff/venv/Scripts/sqlfluff.exe"
		if vim.fn.executable(native) == 1 then
			executable = native
		end
	end
	local started, process = pcall(vim.system, {
		executable,
		"lint",
		"--dialect",
		name,
		"--format",
		"json",
		"--templater",
		"raw",
		"--ignore-local-config",
		"--disable-progress-bar",
		"--nocolor",
		"-",
	}, { stdin = text, text = true, timeout = 15000 }, function(result)
		vim.schedule(function()
			if
				not vim.api.nvim_buf_is_valid(buf)
				or vim.api.nvim_buf_get_changedtick(buf) ~= tick
				or (dialect.read(buf) or vim.b[buf].fox_sql_dialect) ~= name
				or revisions[buf] ~= revision
			then
				return
			end
			pending[buf] = nil
			local diagnostics = M.parse(result.stdout or "", lines)
			if not diagnostics or result.code > 1 then
				vim.b[buf].fox_sql_syntax_status = "SQLFluff failed: " .. (result.stderr or "invalid output")
				return
			end
			vim.b[buf].fox_sql_syntax_status = "checked " .. name
			vim.diagnostic.set(ns, buf, diagnostics, { underline = true, signs = true, virtual_text = true })
		end)
	end)
	if started then
		pending[buf] = process
	else
		vim.b[buf].fox_sql_syntax_status = "SQLFluff failed to start: " .. tostring(process)
	end
end

function M.attach(buf)
	if vim.b[buf].fox_sql_diagnostics then
		return
	end
	vim.b[buf].fox_sql_diagnostics = true
	local revision = 0
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
		buffer = buf,
		callback = function()
			revision = revision + 1
			local current = revision
			vim.defer_fn(function()
				if current == revision then
					M.check(buf)
				end
			end, 650)
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			revision = revision + 1
			revisions[buf] = nil
			if pending[buf] then
				pending[buf]:kill(15)
				pending[buf] = nil
			end
		end,
	})
	M.check(buf)
end

return M
