local M = {}

local common = {
	{
		"COUNT",
		"expression | *",
		"Counts rows, or non-NULL expression values. Returns an integer.",
		"SELECT COUNT(*) FROM orders;",
	},
	{
		"SUM",
		"expression",
		"Adds non-NULL values. An empty input normally returns NULL.",
		"SELECT SUM(total) FROM orders;",
	},
	{ "AVG", "expression", "Computes the mean of non-NULL numeric values.", "SELECT AVG(total) FROM orders;" },
	{ "MIN", "expression", "Returns the smallest non-NULL value.", "SELECT MIN(total) FROM orders;" },
	{ "MAX", "expression", "Returns the largest non-NULL value.", "SELECT MAX(total) FROM orders;" },
	{
		"COALESCE",
		"value, ...",
		"Returns the first argument that is not NULL. Returns NULL when every argument is NULL.",
		"SELECT COALESCE(NULL, 'fallback');",
	},
	{ "NULLIF", "a, b", "Returns NULL if a equals b; otherwise returns a.", "SELECT NULLIF(0, 0);" },
	{ "ABS", "number", "Returns the absolute numeric value.", "SELECT ABS(-42);" },
	{
		"ROUND",
		"number [, digits]",
		"Rounds a number to the requested number of decimal places. Numeric types and tie handling depend on the engine.",
		"SELECT ROUND(12.345, 2);",
	},
	{
		"LOWER",
		"text",
		"Converts text to lowercase. Unicode and collation behavior depend on the engine.",
		"SELECT LOWER('FOX');",
	},
	{
		"UPPER",
		"text",
		"Converts text to uppercase. Unicode and collation behavior depend on the engine.",
		"SELECT UPPER('fox');",
	},
	{
		"REPLACE",
		"text, search, replacement",
		"Replaces occurrences of search in text.",
		"SELECT REPLACE('foxvim', 'vim', 'sql');",
	},
	{
		"TRIM",
		"text",
		"Removes spaces at both ends. Additional arguments use dialect-specific syntax.",
		"SELECT TRIM(' fox ');",
	},
	{
		"ROW_NUMBER",
		"",
		"Assigns sequential row numbers within each window partition. Use an OVER clause.",
		"SELECT ROW_NUMBER() OVER (ORDER BY id) FROM orders;",
	},
	{
		"RANK",
		"",
		"Assigns a window rank with gaps after ties. Use an OVER clause.",
		"SELECT RANK() OVER (ORDER BY total) FROM orders;",
	},
	{
		"DENSE_RANK",
		"",
		"Assigns a window rank without gaps after ties. Use an OVER clause.",
		"SELECT DENSE_RANK() OVER (ORDER BY total) FROM orders;",
	},
	{
		"LAG",
		"expression [, offset [, default]]",
		"Reads an expression from a preceding row in the window. Use an OVER clause.",
		"SELECT LAG(total) OVER (ORDER BY id) FROM orders;",
	},
	{
		"LEAD",
		"expression [, offset [, default]]",
		"Reads an expression from a following row in the window. Use an OVER clause.",
		"SELECT LEAD(total) OVER (ORDER BY id) FROM orders;",
	},
}

local engines = {
	mysql = {
		{
			"CURDATE",
			"",
			"Returns today's date in the session time zone. In a text context the value uses YYYY-MM-DD; numeric context produces YYYYMMDD. It is evaluated consistently within a statement. CURRENT_DATE is a synonym. This function takes no arguments.",
			"SELECT CURDATE(), CURDATE() + INTERVAL 1 DAY;",
			"https://dev.mysql.com/doc/refman/8.4/en/date-and-time-functions.html#function_curdate",
		},
		{
			"NOW",
			"[fractional_seconds_precision]",
			"Returns the current date and time in the session time zone, fixed at statement start. Precision may be 0 through 6.",
			"SELECT NOW(6);",
		},
		{
			"CURTIME",
			"[fractional_seconds_precision]",
			"Returns the current time in the session time zone.",
			"SELECT CURTIME();",
		},
		{
			"DATE_FORMAT",
			"date, format",
			"Formats a date or datetime using MySQL percent directives.",
			"SELECT DATE_FORMAT(CURDATE(), '%Y-%m-%d');",
		},
		{
			"DATE_ADD",
			"date, INTERVAL value unit",
			"Adds a MySQL interval to a date or datetime.",
			"SELECT DATE_ADD(CURDATE(), INTERVAL 7 DAY);",
		},
		{
			"DATE_SUB",
			"date, INTERVAL value unit",
			"Subtracts a MySQL interval from a date or datetime.",
			"SELECT DATE_SUB(CURDATE(), INTERVAL 1 MONTH);",
		},
		{
			"DATEDIFF",
			"date1, date2",
			"Returns the number of days date1 minus date2. Time components are ignored.",
			"SELECT DATEDIFF('2026-10-27', '2026-10-01');",
		},
		{
			"TIMESTAMPDIFF",
			"unit, start, finish",
			"Returns finish minus start as an integer in the requested unit.",
			"SELECT TIMESTAMPDIFF(HOUR, '2026-10-27 00:00:00', NOW());",
		},
		{
			"STR_TO_DATE",
			"text, format",
			"Parses text using MySQL date/time format directives.",
			"SELECT STR_TO_DATE('27/10/2026', '%d/%m/%Y');",
		},
		{
			"IFNULL",
			"value, fallback",
			"Returns fallback when value is NULL; otherwise returns value.",
			"SELECT IFNULL(NULL, 'fox');",
		},
		{
			"IF",
			"condition, true_value, false_value",
			"Chooses true_value when condition is true; otherwise chooses false_value.",
			"SELECT IF(1 = 1, 'yes', 'no');",
		},
		{
			"CONCAT",
			"value, ...",
			"Concatenates arguments. If any argument is NULL, the result is NULL.",
			"SELECT CONCAT('fox', 'vim');",
		},
		{
			"CONCAT_WS",
			"separator, value, ...",
			"Concatenates non-NULL arguments using separator.",
			"SELECT CONCAT_WS(', ', 'fox', NULL, 'sql');",
		},
		{
			"LENGTH",
			"text",
			"Returns the string length in bytes. Use CHAR_LENGTH for character count.",
			"SELECT LENGTH('fox');",
		},
		{ "CHAR_LENGTH", "text", "Returns the string length in characters.", "SELECT CHAR_LENGTH('fox');" },
		{
			"SUBSTRING",
			"text, start [, length]",
			"Extracts text using a one-based start position.",
			"SELECT SUBSTRING('foxvim', 4, 3);",
		},
		{
			"GROUP_CONCAT",
			"[DISTINCT] expression [ORDER BY ...] [SEPARATOR text]",
			"Aggregates non-NULL strings. Output is limited by group_concat_max_len.",
			"SELECT GROUP_CONCAT(name SEPARATOR ', ') FROM customers;",
		},
		{
			"JSON_EXTRACT",
			"document, path, ...",
			"Reads values at MySQL JSON paths.",
			"SELECT JSON_EXTRACT('{\"id\":1}', '$.id');",
		},
		{
			"JSON_UNQUOTE",
			"json_value",
			"Converts a JSON string value into an unquoted SQL string.",
			"SELECT JSON_UNQUOTE(JSON_EXTRACT('{\"name\":\"fox\"}', '$.name'));",
		},
		{ "YEAR", "date", "Extracts the year from a date.", "SELECT YEAR(CURDATE());" },
		{ "MONTH", "date", "Extracts the month number from a date.", "SELECT MONTH(CURDATE());" },
		{ "DAY", "date", "Extracts the day of the month.", "SELECT DAY(CURDATE());" },
	},
	postgres = {
		{ "NOW", "", "Returns a timestamp with time zone fixed at the start of the current transaction.", "SELECT NOW();" },
		{
			"DATE_TRUNC",
			"field, timestamp [, time_zone]",
			"Truncates a timestamp to a boundary such as day or month.",
			"SELECT DATE_TRUNC('month', NOW());",
		},
		{
			"DATE_PART",
			"field, timestamp | interval",
			"Extracts a date/time field as double precision.",
			"SELECT DATE_PART('year', NOW());",
		},
		{
			"AGE",
			"timestamp [, timestamp]",
			"Computes a symbolic interval including years and months. With one argument, compares with current_date.",
			"SELECT AGE(TIMESTAMP '2000-01-01');",
		},
		{
			"EXTRACT",
			"field FROM timestamp | interval",
			"Extracts a date/time field using SQL-standard syntax.",
			"SELECT EXTRACT(YEAR FROM CURRENT_DATE);",
		},
		{
			"CLOCK_TIMESTAMP",
			"",
			"Returns the actual current time; its value can change during a statement.",
			"SELECT CLOCK_TIMESTAMP();",
		},
		{
			"TO_CHAR",
			"value, format",
			"Formats a timestamp, interval, or number using a PostgreSQL template.",
			"SELECT TO_CHAR(NOW(), 'YYYY-MM-DD');",
		},
		{
			"TO_DATE",
			"text, format",
			"Parses text into a date using a PostgreSQL template.",
			"SELECT TO_DATE('27/10/2026', 'DD/MM/YYYY');",
		},
		{
			"TO_TIMESTAMP",
			"text, format",
			"Parses formatted text into timestamp with time zone. A separate numeric overload accepts Unix seconds.",
			"SELECT TO_TIMESTAMP('2026-10-27', 'YYYY-MM-DD');",
		},
		{
			"CONCAT",
			"value, ...",
			"Concatenates arguments, ignoring NULL arguments.",
			"SELECT CONCAT('fox', NULL, 'sql');",
		},
		{ "LENGTH", "text", "Returns the text length in characters.", "SELECT LENGTH('fox');" },
		{
			"SUBSTRING",
			"text FROM start [FOR count]",
			"Extracts text with SQL-standard one-based positions.",
			"SELECT SUBSTRING('foxvim' FROM 4 FOR 3);",
		},
		{
			"STRING_AGG",
			"value, delimiter [ORDER BY ...]",
			"Concatenates non-NULL values within an aggregate.",
			"SELECT STRING_AGG(name, ', ' ORDER BY name) FROM customers;",
		},
		{
			"ARRAY_AGG",
			"expression [ORDER BY ...]",
			"Collects values into an array, retaining NULL values.",
			"SELECT ARRAY_AGG(id ORDER BY id) FROM orders;",
		},
		{
			"JSONB_BUILD_OBJECT",
			"key, value, ...",
			"Builds a jsonb object from alternating keys and values.",
			"SELECT JSONB_BUILD_OBJECT('name', 'fox');",
		},
		{ "JSONB_AGG", "expression", "Aggregates values into a jsonb array.", "SELECT JSONB_AGG(id) FROM orders;" },
		{
			"GENERATE_SERIES",
			"start, stop [, step]",
			"Returns a set of numbers or timestamps. Timestamp series require an interval step.",
			"SELECT * FROM GENERATE_SERIES(1, 5);",
		},
		{
			"GREATEST",
			"value, ...",
			"Returns the largest argument, ignoring NULL arguments unless all are NULL.",
			"SELECT GREATEST(1, 3, 2);",
		},
		{
			"LEAST",
			"value, ...",
			"Returns the smallest argument, ignoring NULL arguments unless all are NULL.",
			"SELECT LEAST(1, 3, 2);",
		},
	},
	sqlite = {
		{
			"DATE",
			"[time_value [, modifier, ...]]",
			"Returns a date string in YYYY-MM-DD form. 'now' uses UTC unless modified with 'localtime'. SQLite has no dedicated date type.",
			"SELECT DATE('now', '+1 day');",
		},
		{ "TIME", "[time_value [, modifier, ...]]", "Returns a time string, normally HH:MM:SS.", "SELECT TIME('now');" },
		{
			"DATETIME",
			"[time_value [, modifier, ...]]",
			"Returns a date/time string, normally YYYY-MM-DD HH:MM:SS. 'now' uses UTC.",
			"SELECT DATETIME('now', 'localtime');",
		},
		{
			"STRFTIME",
			"format [, time_value [, modifier, ...]]",
			"Formats a SQLite date/time value using percent directives.",
			"SELECT STRFTIME('%Y-%m-%d', 'now');",
		},
		{
			"JULIANDAY",
			"[time_value [, modifier, ...]]",
			"Returns a Julian day number as a real value.",
			"SELECT JULIANDAY('now');",
		},
		{
			"UNIXEPOCH",
			"[time_value [, modifier, ...]]",
			"Returns Unix seconds for a date/time value.",
			"SELECT UNIXEPOCH('now');",
		},
		{
			"TIMEDIFF",
			"time_value1, time_value2",
			"Returns a readable calendar-aware difference. Available since SQLite 3.43; use julianday subtraction for elapsed days.",
			"SELECT TIMEDIFF('2026-10-27', '2026-10-01');",
		},
		{ "IFNULL", "value, fallback", "Returns fallback when value is NULL.", "SELECT IFNULL(NULL, 'fox');" },
		{
			"IIF",
			"condition, true_value, false_value",
			"Chooses a value using the condition. Supported argument counts depend on SQLite version.",
			"SELECT IIF(1 = 1, 'yes', 'no');",
		},
		{
			"LENGTH",
			"value",
			"Counts Unicode code points for text before its first NUL, or bytes for a blob.",
			"SELECT LENGTH('fox');",
		},
		{
			"SUBSTR",
			"text, start [, length]",
			"Extracts text with one-based positions; negative start counts from the end.",
			"SELECT SUBSTR('foxvim', 4, 3);",
		},
		{
			"INSTR",
			"text, search",
			"Returns the one-based position of the first match, or zero when absent.",
			"SELECT INSTR('foxvim', 'vim');",
		},
		{
			"GROUP_CONCAT",
			"expression [, separator]",
			"Concatenates non-NULL values. Without an explicit order, input order is not guaranteed.",
			"SELECT GROUP_CONCAT(name, ', ') FROM customers;",
		},
		{
			"TOTAL",
			"expression",
			"Adds numeric values as a floating-point result. Returns 0.0 for empty input.",
			"SELECT TOTAL(total) FROM orders;",
		},
		{
			"TYPEOF",
			"value",
			"Returns the SQLite storage class: null, integer, real, text, or blob.",
			"SELECT TYPEOF(42);",
		},
		{
			"JSON_EXTRACT",
			"document, path, ...",
			"Reads SQLite JSON paths. A single scalar path returns an SQL value rather than JSON text.",
			"SELECT JSON_EXTRACT('{\"id\":1}', '$.id');",
		},
		{
			"JSON_OBJECT",
			"key, value, ...",
			"Builds a JSON object from alternating text keys and values.",
			"SELECT JSON_OBJECT('name', 'fox');",
		},
		{
			"JSON_GROUP_ARRAY",
			"expression",
			"Collects aggregate values into a JSON array.",
			"SELECT JSON_GROUP_ARRAY(id) FROM orders;",
		},
		{ "SQLITE_VERSION", "", "Returns the version of the connected SQLite library.", "SELECT SQLITE_VERSION();" },
	},
}

local references = {
	mysql = "https://dev.mysql.com/doc/refman/8.4/en/functions.html",
	postgres = "https://www.postgresql.org/docs/current/functions.html",
	sqlite = "https://www.sqlite.org/lang_corefunc.html",
}

function M.items(engine)
	local result = {}
	for _, list in ipairs({ common, engines[engine] or {} }) do
		for _, entry in ipairs(list) do
			local signature = entry[1] .. "(" .. entry[2] .. ")"
			result[#result + 1] = {
				label = entry[1],
				insertText = entry[1] .. "($0)",
				insertTextFormat = 2,
				kind = 3,
				detail = engine .. " | " .. signature,
				documentation = {
					kind = "markdown",
					value = "```sql\n"
						.. signature
						.. "\n```\n\n"
						.. entry[3]
						.. "\n\nExample:\n```sql\n"
						.. entry[4]
						.. "\n```\n\n[Engine documentation]("
						.. (entry[5] or references[engine])
						.. ")",
				},
			}
		end
	end
	return result
end

function M.hover(buf)
	local query = package.loaded["fox.query"]
	local state = query and query.states[vim.b[buf].fox_query_root or vim.b[buf].fox_sql_root or ""]
	if state then
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local cursor = vim.api.nvim_win_get_cursor(0)
		local offset = cursor[2] + 1
		for row = 1, cursor[1] - 1 do
			offset = offset + #lines[row] + 1
		end
		local item, column = require("fox.query.sql").object_at(table.concat(lines, "\n"), offset, state.metadata)
		if item and (item.cte or not state.consoles[buf]) then
			local content = { "# " .. item.name, item.cte and "WITH table (query only)" or "Table: " .. item.key, "" }
			for _, entry in ipairs(column and { column } or item.columns) do
				content[#content + 1] = "- " .. entry.name .. (entry.type and (" : " .. entry.type) or "")
			end
			vim.lsp.util.open_floating_preview(content, "markdown", { border = "rounded", focus_id = "fox_sql_hover" })
			return
		end
	end
	if vim.b[buf].fox_query_root and require("fox.query").hover(buf) then
		return
	end
	local engine = require("fox.langs.sql.dialect").read(buf) or vim.b[buf].fox_sql_dialect
	local word = vim.fn.expand("<cword>"):upper()
	for _, item in ipairs(M.items(engine or "sqlite")) do
		if item.label == word then
			vim.lsp.util.open_floating_preview(
				vim.split(item.documentation.value, "\n", { plain = true }),
				"markdown",
				{ border = "rounded", focus_id = "fox_sql_hover" }
			)
			return
		end
	end
	vim.lsp.buf.hover()
end

return M
