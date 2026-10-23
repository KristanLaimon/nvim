# SQL and FoxQuerier

[Back to languages](../languages.md) · [Query workspace guide](../query-mode.md)

FoxQuerier provides read-only SQLite, MySQL, and PostgreSQL consoles, cached table/column completion through blink.cmp, and Standard/Visual query layouts. SQL settings live in `lua/fox/langs/sql/init.lua`; database sessions and UI live in `lua/fox/query/`.

Python 3 is required for database connections. SQLite uses Python's standard library. For MySQL/PostgreSQL, explicitly run `:FoxQueryInstallDrivers` in the project; it installs PyMySQL and psycopg into `.foxnvim/query/private/drivers/`. Nothing installs on startup.

Select the optional **SQL / FoxQuerier** bundle in `:LanguageManager` for the SQL Treesitter parser. The minimal fresh setup stays Lua-only. This bundle does not install a language server, formatter, database server, or Python automatically.

Completion uses the current console's cached schema: qualified table names, table aliases, and columns. It makes no network requests while typing. JOIN insertion is available through `:FoxQueryInsertJoin`, with FK mapping, alias, join-type selection, and a preview. SQL analysis intentionally supports a subset; complex CTE/subquery/UNION structures are marked partial.

Start with `:FoxMode query`, then `:FoxQueryConnections`. See the [query guide](../query-mode.md) for profiles, safety, persistence, diagrams, and testing.
