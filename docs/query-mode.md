# FoxQuerier

[Back to wiki](index.md) · [SQL tooling](languages/sql.md) · [Design plan](../PLAN-FOXQUERYGRIP.md)

FoxQuerier adds a read-only database workspace to the current project. **Standard** keeps SQL on the left, a database explorer on the right, and results/activity below. **Visual** places the SQL beside an ASCII diagram that follows the statement being edited. A compact terminal uses panel toggles instead of squeezing all panes onto the screen.

## Start

1. Open the project directory in FoxVim.
2. Run `:FoxMode query` or press **Ctrl+Alt+O** to choose a mode.
3. Run `:FoxQueryConnections` and add a profile. SQLite needs an existing file. MySQL/PostgreSQL need host, port, database, and user. Passwords are prompted privately in RAM or resolved from `password_env`.
4. For MySQL/PostgreSQL, run `:FoxQueryInstallDrivers` once in that project if drivers are missing. Python 3 and pip are prerequisites; installation is explicit and project-local.
5. Search/inspect the explorer, create SQL with `:FoxQueryNew`, and save with `:write`.
6. Run `:FoxQueryRun statement`, then inspect results. `:FoxMode editor` restores the editor without closing SQL sessions.

For PowerShell in Windows Terminal, run `./scripts/setup-powershell.ps1` and restart Windows Terminal to forward Ctrl+Alt+O to Neovim. `./scripts/unsetup-powershell.ps1` removes that forwarding. Other terminals/operating systems may intercept it; the Ex command and palette remain available. No new leader shortcuts are added.

## Profiles and local files

Profiles live in `.foxnvim/query/connections.json`:

```json
{
  "profiles": [
    { "id": "local-sqlite", "engine": "sqlite", "path": "data/app.db" },
    { "id": "local-mysql", "engine": "mysql", "host": "127.0.0.1", "port": 3307, "database": "app_db", "user": "readonly", "password_env": "APP_DB_PASSWORD" },
    { "id": "local-postgres", "engine": "postgres", "host": "127.0.0.1", "port": 5432, "database": "app_db", "schema": "public", "user": "readonly", "password_env": "APP_DB_PASSWORD" }
  ]
}
```

Use the connection UI to create profiles or edit this file through **Edit connection profiles**. Literal `password` fields are rejected. For PostgreSQL, `schemas` may contain multiple schema names; the selected schemas become the session search path, and qualified completion makes schema choice explicit. Optional PostgreSQL `sslmode`/`sslrootcert` and MySQL `ssl_ca` settings pass to the driver; MySQL CA configuration enables certificate/hostname verification.

SQLite paths are relative to the project root unless absolute; missing files are rejected rather than created. Docker is not queried or controlled by the app: use its exposed host/port like any other database.

SQL, notes, profiles, metadata cache, explicit workspace data, installed drivers, and exports stay under `.foxnvim/query/`. Private/cache/export directories receive local ignore rules. Project/team policy determines whether saved queries and notes are committed. Existing SQLite databases remain at their configured paths.

## Commands

| Command | Behavior |
|---|---|
| `:FoxMode [editor/query]` | Choose/switch project workflow. FoxAI remains unimplemented. |
| `:FoxQueryView [standard/visual]` | Choose/toggle query layout. |
| `:FoxQueryConnections` | Add/edit/connect/disconnect profiles for this console. |
| `:FoxQueryInstallDrivers` | Explicitly install project-local MySQL/PostgreSQL drivers. |
| `:FoxQueryNew [name.sql]`, `:FoxQueryOpen` | Create/open saved and in-memory SQL tabs. |
| `:FoxQueryRun statement` | Execute the statement under the SQL cursor. |
| `:FoxQueryRun selection` | Execute the last character/line selection; block selections are rejected. |
| `:FoxQueryRun section`, `:FoxQueryRun file` | Execute an explicit section or file, in order, stopping on error. |
| `:FoxQueryCancel` | Request cancellation; an uncertain session must reconnect. |
| `:FoxQueryExplorer`, `:FoxQueryInspect` | Search metadata or inspect the selected table. |
| `:FoxQueryGraph all`, `:FoxQueryGraph neighborhood` | Whole-database overview or selected table neighborhood, initially depth 3. |
| `:FoxQueryNotes` | Open local table Markdown notes. |
| `:FoxQueryInsertJoin` | Review a foreign-key mapping and insert an undoable JOIN edit. |
| `:FoxQueryPin` | Pin/unpin the current statement's location for the live diagram. |
| `:FoxQueryResults`, `:FoxQueryActivity` | Show results or submitted SQL/activity. |
| `:FoxQueryExport` | Explicit JSON export of loaded rows only. |
| `:FoxQueryRefresh` | Refresh current connection metadata. |
| `:FoxQueryClearParameters`, `:FoxQueryClearCache` | Clear RAM values or disposable metadata files; preserve user documents. |
| `:FoxQueryHelp` | Context help, also available with F1 in SQL buffers and `?` in panels. |
| `:FoxQueryErrorDetails` | Explicitly reveal the last server diagnostic in a temporary buffer; values may appear, and details are never saved automatically. |

All commands are in the Command Palette's **Query** category. The default Run scope is statement; an unresolved statement never falls back to running the whole file.

Section example:

```sql
-- @section Customer overview
SELECT c.id, c.name FROM customers c;

-- @section Orders for one customer
SELECT o.id, o.total FROM orders o WHERE o.customer_id = ?;
```

Each `?` input is bound through the driver. Inputs stay in RAM; the same unchanged SQL may reuse values as masked prompt defaults, which must be reviewed/confirmed before execution. `NULL` means SQL null, blank means empty text, and `text:NULL` means the literal text `NULL`. Ctrl-C cancels input; the final parameter confirmation can also cancel. PostgreSQL JSON `?`, `?|`, and `?&` operators are distinguished from ordinary placeholders in the supported syntax. List expansion and native/named placeholders are not implemented.

## Visual diagram and navigation

The graph resolves tables from cached metadata and updates after a 200 ms typing pause. Active table boxes are connected by actual SQL JOIN predicates. FK neighbors are dim, dotted suggestions and do not imply a JOIN exists in the SQL. `*` marks selected/output columns, `k` a join key, and `f` a filter column; a column can have several roles. Aliases/self-JOINs remain separate instances.

The renderer caps active cards at 40, context suggestions at 20, and displayed columns per card at 12. Counts disclose hidden content. Source columns unrelated to the query stay hidden; inspect a table to read its full structure. Incomplete/ambiguous/unsupported SQL is labelled partial; the graph is not an execution plan or validation proof.

Use Enter on a table box to inspect it; the cursor position determines the left/right box. Inspector actions: `J` offers Insert JOIN, `n` opens notes, `b` browses rows, and `g` opens the neighborhood. Joining always requires an explicit reviewed edit; clicking a node does not rewrite or execute SQL.

Explorer: `/` fuzzy-filters cached tables, Enter inspects, `b` browses, `n` opens notes. In Visual view `/` can select/recenter a table through the graph/inspector commands. Full map: `/` chooses any cached table, Enter recenters, `i` inspects, `+`/`-` change neighborhood depth, native scrolling and `zh`/`zl` pan, `q` returns. The graph shows possible bridge-table classifications with the evidence used; missing visible relationships do not prove a table is an orphan.

Results: use arrows/hjkl, native `/` search over loaded rows, Enter to expand a row, `y` to copy, and `e` to export loaded JSON. Grid cells are visually clipped to 32 display cells; expanded rows retain fetched values. Binary fields carry a capped base64 preview with byte length. `gR` follows a verified table-browse result's FK, previewing the generated bound SQL. Arbitrary SQL projections do not get guessed row origins.

## Sessions, workspaces, and limits

Each SQL console has its own session and explicit profile; the project permits up to four open sessions. Switching a profile clears old results and RAM parameters. Switching layouts/projects keeps sessions with their original owner. A busy console cannot reconnect or be closed until its query finishes or is canceled. Closing modified documents offers save/discard/cancel.

`:write` saves queries and notes locally with atomic replacement and external-change detection. WorkspaceSave requires saved query documents. Query workspace state is stored under the project's private directory, and generic/global session files exclude query buffers. Explicit workspace load reopens saved SQL and layout while disconnected, without parameter/result replay or automatic execution. Normal startup does not open query tabs.

ShaDa is suspended while Query is active; registers/input/search histories are restored on returning to Editor, and query file paths are excluded from file-mark persistence. This means a yank intended for later editor use should be deliberately copied to the system clipboard instead of relying on query-local registers. Query buffers disable swap, persistent undo, modelines, and automatic backup writes.

Fetching stops at 1,000 rows or 8 MiB for a run; table browsing requests 200 rows and orders by a known primary key when available. Without a key, row order is not guaranteed. The grid replaces the previous result; submitted SQL/timing belong to that execution, while the diagram follows the editable draft. Client fetch caps do not limit server work, and a single huge field can require more transient driver memory than the display cap.

The worker requests cancellation after 30 seconds. For MySQL, a truncated unbuffered result closes the session instead of draining arbitrary remaining rows; reconnect before another query. If cancellation cannot be verified, the UI disconnects the worker and requires reconnection. Metadata queries are bounded at 20,000 objects per catalog query and report an error rather than silently claiming complete coverage.

Read-only behavior is enforced with SQLite read-only URI/query-only mode, MySQL session transaction read-only mode, and PostgreSQL read-only transactions. Use restricted database credentials too: SELECT functions and external server effects are not comprehensively controlled by statement classification. SQL writes, editable grids, transaction UI, routine execution, native placeholder formats, automatic recovery drafts, full SQL history, and virtual relationships remain outside this first implementation. Session settings/temporary objects cannot be created through the read-only SQL guard.

## Validation and remaining platform checks

Automated tests use disposable SQLite fixtures for binding, batches, metadata, read-only enforcement, row limits, cancellation, and actual Neovim-to-Python transport. Lua tests cover scopes, aliases, composite JOINs, diagram roles, project storage, view switching, and session exclusion.

Implementation validation on Windows: **772 repository tests passed**, **9 Python driver tests passed**, changed Lua files passed StyLua/Luacheck, and **780 Lua files parsed without syntax errors**. Command registration and Standard/Visual switching also passed a headless smoke check.

The authorized production MySQL check confirmed **5.7.44**, read-only session setup, bound constants, and a zero-row catalog query. **No business rows were read and no production files were saved.** PostgreSQL code and Windows driver loading are present, but live PostgreSQL and Linux integration still need an available test environment. Advanced SQL graph analysis remains intentionally partial.

Run:

```text
nvim --headless -u NONE -i NONE -l tests/run.lua query
python -B -m unittest discover -s tests/query -v
```

For an explicitly authorized remote check, `tests/query/remote_check.py` prompts privately for a password and runs only version/bound constants/zero-row metadata SQL. Its connection arguments contain no password.

Driver references: [PyMySQL connection options](https://pymysql.readthedocs.io/en/latest/modules/connections.html), [psycopg connections](https://www.psycopg.org/psycopg3/docs/api/connections.html), [psycopg cursor behavior](https://www.psycopg.org/psycopg3/docs/advanced/cursors.html), [Python SQLite](https://docs.python.org/3/library/sqlite3.html).
