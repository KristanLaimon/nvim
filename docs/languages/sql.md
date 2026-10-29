# SQL and FoxQuerier

[Back to languages](../languages.md) · [Query workspace guide](../query-mode.md)

FoxQuerier provides read-only SQLite, MySQL, and PostgreSQL consoles, cached table/column completion through blink.cmp, dialect-aware function completion and Shift+K help, and Standard/Visual query layouts. SQL settings and tooling live in `lua/fox/langs/sql/`; database sessions and UI live in `lua/fox/query/`.

FoxQuery uses bundled Go executables under `config/tools/foxquery/` for Windows/Linux amd64. SQLite, the runtime, and all database drivers are compiled in; external database clients are unnecessary at runtime. MariaDB uses the MySQL connection type and dialect (`mysql`), with the bundled go-sql-driver/mysql driver. Source and dependency lockfiles are in `config/tools/repos/foxquery/`; build scripts generate Git-ignored vendor dependencies when missing and reuse them. Only rebuilding requires Go. See [build instructions](../../config/tools/repos/foxquery/README.md). Passwords entered in Query connections are saved locally as plaintext under `.foxnvim/query/private/passwords/` (Git-ignored, owner-only file permissions on Unix); `password_env` remains available.

Select the optional **SQL / FoxQuerier** bundle in `:LanguageManager` for the SQL Treesitter parser and SQLFluff. SQLFluff requires Python for installation; bundled database execution, completion, function help, and dialect warnings do not. The minimal fresh setup stays Lua-only. No optional SQL tools are installed without selection.

Every SQL document has a first-line metadata comment, for example `-- foxquery: dialect=mysql`. New SQL actions ask for MySQL, PostgreSQL, or SQLite. The project's sole connection type comes first; otherwise the last chosen flavor comes first (SQLite initially). This choice persists in `.foxnvim/query/settings.json`. Opening an older file without metadata adds its default header in the buffer; save it with `:write`. The comment travels with the SQL through saves, renames, and workspace restoration. `:FoxQueryDialect [mysql/postgres/sqlite]` changes the current file's flavor; it does not change the connection.

Completion combines the current console's cached schema with a local catalog of common engine functions. It makes no network requests while typing. Shift+K (`K`) on a documented function shows its signature, behavior, example, and official documentation link. For example, MySQL offers `CURDATE()`, PostgreSQL offers `DATE_TRUNC()`, and SQLite offers `STRFTIME()`. The bundled catalog is not an exhaustive reference for all functions or server versions.

In a Query console, `K` also shows cached table and column metadata, including named `WITH` tables and their projected columns. The live diagram labels CTEs as **WITH table (query only)** and names subquery results after their SQL context and sources.

In Query SQL buffers, Shift+K also shows a column's source table and type from cached metadata, resolving aliases and the nearest subquery scope. On a table name or alias it opens the full table inspector. `:FoxQueryHover` and **Query: Inspect SQL Symbol at Cursor** in the palette use the same behavior. UTF-8 identifiers such as `año` stay intact in hover, completion, and parameter labels.

**General syntax checking is off by default.** `gS` in a SQL buffer (normal mode), `:FoxQuerySyntaxCheck`, or **Query: Toggle General SQL Syntax Checking** in the palette toggles it for the project and persists the choice. When enabled, SQLFluff runs asynchronously on buffer contents with the file's selected dialect; it never executes SQL or writes a temporary SQL file. Parse/lexing errors appear as editor diagnostics; formatting/style findings are ignored. Install SQLFluff through the optional SQL bundle first. Checks debounce edits, discard stale results, and stop at 128 KiB.

**Dialect warnings remain on**, independently of the general checker and without SQLFluff. They flag a curated set of known functions belonging to another engine, such as `CURDATE()` in a SQLite file. Strings, comments, qualified custom functions, and unknown function names are excluded. These are warnings about built-ins, since extensions or user-defined functions may supply the same name; they are not a complete grammar or server-version validator.

JOIN insertion is available through `:FoxQueryInsertJoin`, with FK mapping, alias, join-type selection, and a preview. Live diagrams include derived tables, scalar and predicate subqueries, nested subqueries, and correlation links. Complex CTE/UNION structures remain partial.

Start with `:FoxMode query`, then `:FoxQueryConnections`. See the [query guide](../query-mode.md) for profiles, safety, persistence, diagrams, and testing.
