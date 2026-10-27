# FoxQuerier

[Back to wiki](index.md) · [SQL tooling](languages/sql.md) · [Design plan](../config/plans_notes_md/PLAN-FOXQUERYGRIP.md)

FoxQuerier adds a read-only database workspace to the current project. The default layout has saved SQL files above connections on the far left, SQL in the center, the database explorer on the right, results beneath SQL, and a full-width activity bar at the bottom. **Shift+F3** toggles the live diagram: connections disappear and SQL/diagram use 30% / 70% of the width by default, with results still beneath SQL. A compact terminal uses panel toggles above the activity bar.

## Start

1. Open the project directory in FoxVim.
2. Press **F3** to cycle directly between Editor and Query, or run `:FoxMode query`. `:FoxMode` still offers a picker. First entry reopens the last used saved SQL file (or the first saved SQL file if it is unavailable); a new query is created only when none exist.
3. Press **gC** in Normal mode or run `:FoxQueryConnections` to focus the connection sidebar. **a** adds, **e** edits, **d** deletes a profile, **Enter** opens all connection details; **Enter** again connects. **D** disconnects. SQLite opens the existing file explorer at your project root: Enter opens folders or selects a database file; Esc cancels. MySQL/MariaDB and PostgreSQL need host, port, database, and user. Choose **MySQL / MariaDB** in the engine picker for MariaDB (`engine: "mysql"`); no separate driver installation is needed. Passwords are prompted privately and saved locally under `.foxnvim/query/private/passwords/`, or resolved from `password_env`. Editing a connection lets you replace its saved password; blank keeps the existing one.
4. Database drivers are bundled in `config/tools/foxquery/` for Windows/Linux (amd64). The executables include their runtime and drivers; no external database CLI or separate SQLite library is needed. Clone the configuration with these executables included; no driver installation is required. See [build instructions](../config/tools/repos/foxquery/README.md).
5. Search/inspect the explorer, create SQL with **gN** or `:FoxQueryNew`, and save with `:write`. The **SQL FILES** pane above connections lists saved project SQL and open tabs; Enter opens a file or expands/collapses a folder, **a** creates SQL, **A** creates a folder, **r** renames, and **d** deletes after confirmation. **Alt+h/l** switches SQL tabs. Closing every tab leaves a prompt to open or create one.
6. Queries run manually with **Ctrl+Enter** or **F5** in Normal/Insert mode. **Ctrl+Shift+Enter** runs the same statement in a centered results popup using 90% of the screen width and height; **q** or **Esc** closes it. Typing SQL or moving the cursor does not execute it. **Ctrl+Space** or **Ctrl+X Ctrl+O** opens completion in Insert mode. **F3** restores the editor without closing SQL sessions.

For PowerShell in Windows Terminal, run `./config/scripts/setup-powershell.ps1` and restart Windows Terminal to forward Ctrl+Enter, Ctrl+Shift+Enter, and Ctrl+Space to Neovim. `./config/scripts/unsetup-powershell.ps1` removes that forwarding. Ctrl+Alt+O remains an alternative direct mode switch. Other terminals/operating systems may intercept keys; Ex commands and the palette remain available. No new leader shortcuts are added.

Pin or unpin the current SQL tab with **Ctrl+p**, `:BufferLineTogglePin`, or the palette action **Toggle Pin Current Tab (Editor / Query)**. Query pins form their own group at the left of the Query tab bar and are stored separately in `.foxnvim/query/private/tab-pins.json`. Saved pinned queries reopen on entry; editor pins remain separate. **Alt+h/l** follows the visible tab order, including pins. **Ctrl+h/l** moves focus left/right between panes.

The status bar shows **[Editor | Query]** in every theme: the current workflow uses normal text color and the other is dimmed. F2 retains rename; F3 switches workflows and Shift+F3 toggles the diagram. Query also has a dedicated bottom activity bar: SQL status/timing/submitted SQL on the left and **[Default | Visually]** on the right (the active view has an asterisk). Failed preparation and execution requests show the full diagnostic in an error toast and retain it in the activity bar in RAM. Click the bar from any Query pane, or focus it and press `y`, to copy the full diagnostic to the system clipboard; Enter opens the multiline error popup. Long lines can be scrolled horizontally. Diagnostics may contain query values and are never saved automatically.

The statement at the SQL cursor has accent-colored lines above and below it that follow typing and cursor movement without executing SQL. Table details opened with Enter fit their contents within the available editor area, overriding older saved inspector sizes.

Query panes display connection/view/help hints. **Shift+F3** toggles the diagram in Normal/Insert/Visual mode; **gV** does the same in Normal mode. **gN** creates a query, **gE** focuses the explorer/diagram, **gR** opens results, and **F1** opens help. **Ctrl+h/j/k/l** navigate panes in Normal, Insert, and Visual modes; Ctrl+k does not invoke the file finder in Query panes. Completion uses the current statement's cached tables: unique columns are offered bare as well as qualified; ambiguous column names are offered qualified. Inside a subquery, completion prioritizes its own bare columns, then its qualified columns, then columns from outer queries. Bare names resolve in the nearest scope; outer aliases remain available for correlated references. Native and common CSI terminal sequences are mapped; F5 and Ctrl+X Ctrl+O avoid relying on modified Enter/Space delivery.

Automatic execution is disabled by default. If explicitly enabled with `:FoxQueryAutoRun`, it considers only the statement at the cursor. It never submits UPDATE/DELETE/INSERT, WITH, or EXPLAIN automatically. The worker independently validates SQL and enforces read-only access; SELECT INTO is rejected. Unchanged SQL is not repeatedly submitted, requests are serialized, hidden projects do not auto-run, and bound parameters require a manual run. `:FoxQueryAutoRun` toggles automatic execution for the project in RAM. SELECT can still do expensive work or invoke server functions; use restricted credentials and disable auto-run when appropriate.

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

Use the connection sidebar to create/edit/delete profiles, or edit this file directly for advanced settings. Deleting a profile keeps database files, saved SQL, and notes. Literal `password` fields in this shared file are rejected; prompted passwords are saved separately in `private/passwords/<connection-fingerprint>.json` as plaintext, with owner-only file permissions on Unix and local Git ignore rules. The last successful connection ID/fingerprint is saved in project-private `private/session.json` and selected/reconnected on normal entry or a new console; saved passwords are reused across restarts. Failed connections show a popup and a **Can't connect** badge; Enter opens details, then Enter retries. Explicit workspace restoration remains disconnected until you choose a connection.

For PostgreSQL, `schemas` may contain multiple schema names; the selected schemas become the session search path, and qualified completion makes schema choice explicit. Optional PostgreSQL `sslmode`/`sslrootcert` and MySQL `ssl_ca` settings pass to the driver; MySQL CA configuration enables certificate/hostname verification.

SQLite paths are relative to the project root unless absolute; missing files are rejected rather than created. Docker is not queried or controlled by the app: use its exposed host/port like any other database.

Saved SQL files live in **`.foxnvim/query/queries/` (including subfolders)** and remain available in the SQL FILES pane after restarting, or through `:FoxQueryOpen`. Unsaved edits still require `:write` to survive a restart. Renaming keeps open edits and connection ownership; saving uses the new path. Delete refuses modified or running queries, and folder deletion includes its contents after confirmation. File actions reject path escapes, symlinks, and existing destinations. SQL, notes, profiles, metadata cache, explicit workspace data, and exports stay under `.foxnvim/query/`. Private/cache/export directories receive local ignore rules. Project/team policy determines whether saved queries and notes are committed. Existing SQLite databases remain at their configured paths.

UI geometry is the explicit global exception: pane proportions, results sizes, and resized connections/help popups are stored in `stdpath('data')/fox/query-layout.json` (Windows: `nvim-data/fox/query-layout.json`). The default diagram split is 30% SQL / 70% diagram; saved proportions override it across projects. Sizes are clamped for smaller terminals. The activity bar stays one line high. Docked terminals and task outputs open below the entire Query dashboard. Closing the last dock pane restores the previous panel sizes and positions; temporary dock-open sizes are not saved as Query defaults. Floating terminals retain their overlay behavior. Only geometry is global; connection identities, SQL, and results are not stored there. Old project-workspace geometry is ignored.

Text values appear in double quotes, while numbers and NULL remain unquoted. Enter on a result row opens full row details in a centered popup the same size as the centered terminal; q or Escape closes it. Quotes affect display only; copied and exported values stay unchanged. Column headers are searchable buffer lines, separate from data rows. When scrolled above the viewport they stay pinned in the fixed bar and follow horizontal scrolling. Multiple result sets show the header for the table at the top of the viewport. Results use Unicode box borders, with result counts, execution details, and shortcut hints below the grid. Header/border lines are not data rows; Enter/y/export/FK navigation retain their original row semantics across multiple result sets. For example:

```text
│ status │
┌────────┐
│ open   │
│ closed │
└────────┘
```

## Commands

| Command | Behavior |
|---|---|
| `:FoxMode [editor/query]` | Choose/switch project workflow. FoxAI remains unimplemented. |
| `:FoxModeToggle` | Cycle Editor / Query directly (F3). |
| `:FoxQueryView [standard/visual]` | Choose/toggle query layout. |
| `:FoxQueryConnections` | Add/edit/connect/disconnect profiles for this console. |
| `:FoxQueryNew [name.sql]`, `:FoxQueryOpen` | Create/open saved and in-memory SQL tabs. |
| `:FoxQueryFiles [create/folder/rename/delete]` | Focus the SQL tree or act on its selected file/folder. |
| `:FoxQueryRun statement` | Execute the statement under the SQL cursor. |
| `:FoxQueryRunPopup [statement/selection/section/file]` | Execute SQL and open its results in a 90% popup. |
| `:FoxQueryBrowsePopup` | Browse the selected table in a 90% results popup. |
| `:FoxQueryAutoRun` | Opt in/out of automatic SELECT execution (disabled by default). |
| `:FoxQueryDialect [mysql/postgres/sqlite]` | Choose the file dialect (persisted as a SQL metadata comment). |
| `:FoxQuerySyntaxCheck` | Toggle general syntax diagnostics for the project (off by default); dialect warnings stay on. |
| `:FoxQueryComplete` | Open cached database completion in Insert mode. |
| `:FoxQueryRun selection` | Execute the last character/line selection; block selections are rejected. |
| `:FoxQueryRun section`, `:FoxQueryRun file` | Execute an explicit section or file, in order, stopping on error. |
| `:FoxQueryParameters` | Focus the current statement’s visible, persistent values. |
| `:FoxQueryClearParameters` | Clear all saved parameter values for this project. |
| `:FoxQueryCancel` | Request cancellation; an uncertain session must reconnect. |
| `:FoxQueryExplorer`, `:FoxQueryInspect` | Search metadata or inspect the selected table. |
| `:FoxQueryGraph all`, `:FoxQueryGraph neighborhood` | Whole-database overview or selected table neighborhood, initially depth 3. |
| `:FoxQueryNotes` | Open local table Markdown notes; new notes start empty. |
| `:FoxQueryDeleteNote` | Delete the open note or selected table's note after typing the prompted random word. Save pending edits first. |
| `:FoxQueryInsertJoin` | Review a foreign-key mapping and insert an undoable JOIN edit. |
| `:FoxQueryColumns` | Set the project diagram column limit (also `C` in the diagram). |
| `:FoxQueryPin` | Pin/unpin the current statement's location for the live diagram. |
| `:FoxQueryResults`, `:FoxQueryActivity` | Show results or submitted SQL/activity. |
| `:FoxQueryExport` | Explicit JSON export of loaded rows only. |
| `:FoxQueryRefresh` | Refresh current connection metadata. |
| `:FoxQueryClearCache` | Clear disposable metadata files; preserve user documents. |
| `:FoxQueryHelp` | Context help, also available with F1 in SQL buffers and `?` in panels. |
| `:FoxQueryErrorDetails` | Expand the last server diagnostic in a temporary buffer; values may appear, and details are never saved automatically. |

All commands are in the Command Palette's **Query** category. The default Run scope is statement; an unresolved statement never falls back to running the whole file.

Each SQL console has its own connection. FoxQuery restores the last successful profile on entry, or uses the only configured profile when none is remembered. Running disconnected SQL reconnects to that profile and runs the requested statement after connecting; a run requested during connection also waits automatically. The statement is captured when Run is pressed and is discarded if you switch console or project before connection completes. Connections opens only when a profile cannot be chosen unambiguously; connection failures still show their error.

Section example:

```sql
-- @section Customer overview
SELECT c.id, c.name FROM customers c;

-- @section Orders for one customer
SELECT o.id, o.total FROM orders o WHERE o.customer_id = ?;
```

In the default layout, the **Parameters** pane appears beneath Tables while the SQL cursor is in a statement containing `?` bindings. Move between value rows with **j/k**, press **Enter** to edit a visible value, **dd** to unset it, and **q** to return to SQL. **F5** or **Ctrl+Enter** runs with those values directly, without masked prompts or an extra confirmation. Missing values stop execution and focus Parameters. `:FoxQueryParameters` (also in the palette) focuses the pane, including in compact/diagram views.

Values are bound through the driver, never interpolated into SQL. `NULL` means SQL null, blank means empty text, and `text:NULL` means the literal text `NULL`. Repeated qualified equality predicates such as `u.id = ? OR u.id = ?` share one row within the same scope; ambiguous expressions and nested scopes keep separate rows. PostgreSQL JSON `?`, `?|`, and `?&` operators follow the worker's detection rules. A mismatch with the worker's binding count prevents execution.

Values persist as visible plaintext in **`.foxnvim/query/private/parameters.json`**, protected by the existing local ignore rules and owner-only file creation on Unix. They belong to a saved SQL file and its statement contents, ignoring whitespace and comments. Moving a whole statement within the file retains its values across sessions; changing its SQL creates a fresh value set. Identical statements in one file share values. Saving removes entries for deleted statements; deleting or renaming files/folders removes or moves their entries. Unsaved SQL still requires `:write` to survive a restart. `:FoxQueryClearParameters` clears the project's saved values and RAM execution values. List expansion and native/named placeholders are not implemented.

## Visual diagram and navigation

The graph resolves tables from cached metadata and updates after a 200 ms typing pause. Active table boxes are connected by actual SQL JOIN predicates; dotted links mark unfinished predicates. FK neighbors are dim suggestions and do not imply a JOIN exists in the SQL. Column markers are labels, not keyboard actions: `*` selected/output, `k` join key, `f` filter, `?` candidate FK column for an unfinished JOIN. Unused columns remain visible but dimmed. Aliases/self-JOINs remain separate instances. Multiple possible FKs are suggestions; none is silently inserted.

The renderer caps active cards at 40 and context suggestions at 20. Cards show up to **15 columns** by default, placing explicitly selected columns first; explicitly selected columns remain visible even if they exceed that limit. Press **C** in the diagram or use `:FoxQueryColumns` to choose 1?200 columns. This preference persists per project in `.foxnvim/query/settings.json`. Counts disclose hidden content; inspect a table to read its full structure. Incomplete/ambiguous/unsupported SQL is labelled partial; the graph is not an execution plan or validation proof. Pane actions run in the diagram: move to a table box, then Enter inspects or J offers Insert JOIN; Ctrl+h returns to SQL.

Use Enter on a table box to inspect it; the cursor position determines the left/right box. Inspector actions use the relationship card under the cursor (or the inspected table in its property section). Enter opens another table inspector on top; **q** or **Esc** returns to the previous inspector with its cursor and scroll position preserved. Moving focus outside the inspector stack dismisses it. `J` offers Insert JOIN, `n` opens notes, `b` browses rows, **B** browses in the results popup, and `g` opens the neighborhood. Query choices use compact floating lists: j/k or arrows move, Enter selects, Esc cancels, and native `/` searches. They do not use Telescope. A single FK mapping skips the mapping picker; after the alias prompt, one SQL preview list offers INNER and LEFT JOINs and inserts the chosen SQL. JOIN choices display the actual column mapping, such as `PlayerKisses.member_1 = Player.id`, rather than internal FK IDs. The alias defaults to table initials (`p`, then `p2` if occupied). MySQL and SQLite JOINs leave ordinary identifiers unquoted; keywords and names with special characters remain quoted so the generated SQL stays valid. PostgreSQL retains its existing quoting. Joining always requires an explicit reviewed edit; clicking a node does not rewrite or execute SQL.

The database explorer keeps action hints below the table list, separated by a line. Enter inspects and `b` browses rows. **B** runs the same table browse in the results popup. The explorer, live diagram, and relationship map retain native Neovim `/`, `?`, `n`, and `N` search. In the explorer, **gn** or **gN** opens the selected table’s note and **gD** deletes the selected table’s note after you type the randomly chosen confirmation word. Blank, incorrect, or canceled input keeps the note. MySQL explorer labels omit the database prefix; queries retain qualified names.

The inspector fits its contents up to the editor's available width and height. Each property stays on one line; oversized metadata scrolls horizontally with `zh`/`zl` and vertically with normal movement. The key legend is right-aligned above the column headings. Headings use the theme's title color; column names remain dimmed, while types, primary keys, foreign keys, not-null flags, and UNIQUE keywords use distinct semantic highlight groups. FK links use diagnostic-info colors. Its relationship section includes the selected table and immediate FK neighbors, with PK/FK markers on individual columns and no repeated column legend in each card. The separate relationship map starts at depth 3 and redraws on resize: the focused table sits between neighbors on wide screens and above them on narrow screens. Incoming and outgoing links connect across rows; the edge list retains the full column mappings.

SQL FILES uses Neo-tree's tree renderer, directory expansion, and font icons in a dedicated Query source. File creation, renaming, and deletion still use Query's validation and modified-buffer checks. The source includes unsaved SQL consoles. The editor sidebar remains separate, and environment switches restore the last editor window before reopening Query panels. Delayed Neo-tree navigation and renders stay in their owning tab.

The statement at the SQL cursor is marked with theme-accent horizontal lines above and below it. Markers do not add side edges or change SQL text.

Results and diagram cards use Unicode box borders. Popup results share the normal row, copy, and export actions.

Results: **Shift+h/l** moves between columns and **Shift+j/k** moves between data rows (skipping borders and footers, including across result sets). Use arrows/hjkl, native `/` and `?` search over loaded rows and column headers (headers stay pinned when scrolled offscreen and are excluded from row actions and exports), Enter to expand a row, `y` to copy, and `e` to export loaded JSON. Grid cells are visually clipped to 32 display cells; expanded rows retain fetched values. Binary fields carry a capped base64 preview with byte length. `gR` follows a verified table-browse result's FK, previewing the generated bound SQL. Arbitrary SQL projections do not get guessed row origins.

## Sessions, workspaces, and limits

Each SQL console has its own session and explicit profile; the project permits up to four open sessions. Switching a profile clears old results and RAM execution parameters; the SQL file’s saved parameter values remain available. Switching layouts/projects keeps sessions with their original owner. A busy console cannot reconnect or be closed until its query finishes or is canceled. Closing modified documents offers save/discard/cancel.

`:write` saves queries and notes locally with atomic replacement and external-change detection. WorkspaceSave requires saved query documents. Query workspace state is stored under the project's private directory, and generic/global session files exclude query buffers. Explicit workspace load reopens saved SQL and layout while disconnected, without parameter/result replay or automatic execution. Normal startup does not open query tabs.

ShaDa is suspended while Query is active; registers/input/search histories are restored on returning to Editor, and query file paths are excluded from file-mark persistence. This means a yank intended for later editor use should be deliberately copied to the system clipboard instead of relying on query-local registers. Query buffers disable swap, persistent undo, modelines, and automatic backup writes.

Fetching stops at 1,000 rows or 8 MiB for a run; table browsing requests 200 rows and orders by a known primary key when available. Without a key, row order is not guaranteed. The grid replaces the previous result; submitted SQL/timing belong to that execution, while the diagram follows the editable draft. Client fetch caps do not limit server work, and a single huge field can require more transient driver memory than the display cap.

The worker requests cancellation after 30 seconds. For MySQL, a truncated unbuffered result closes the session instead of draining arbitrary remaining rows; reconnect before another query. If cancellation cannot be verified, the UI disconnects the worker and requires reconnection. Metadata queries are bounded at 20,000 objects per catalog query and report an error rather than silently claiming complete coverage.

Read-only behavior is enforced with SQLite read-only URI/query-only mode, MySQL session transaction read-only mode, and PostgreSQL read-only transactions. Use restricted database credentials too: SELECT functions and external server effects are not comprehensively controlled by statement classification. SQL writes, editable grids, transaction UI, routine execution, native placeholder formats, automatic recovery drafts, full SQL history, and virtual relationships remain outside this first implementation. Session settings/temporary objects cannot be created through the read-only SQL guard.

## Validation and remaining platform checks

Latest focused Linux validation: Go backend tests passed, including the MariaDB primary-key regression, and **81 Query Mode tests passed**.

Automated tests use disposable SQLite fixtures for binding, batches, metadata, read-only enforcement, row limits, cancellation, and actual Neovim-to-Go transport. Lua tests cover scopes, aliases, composite JOINs, diagram roles, project storage, view switching, and session exclusion.

Database execution uses the bundled Go worker. Backend tests use real disposable SQLite files and cover binding, Unicode, numeric precision, binary cells, SQL guards, metadata, engine-enforced read-only access, attachment rejection, missing-file handling, row/byte caps, cancellation, protocol recovery, and full error diagnostics. Lua tests exercise the bundled executable using a committed SQLite fixture.

Validation of the UI and environment update on Windows: **823 repository tests passed**, including **62 Query tests**. Changed Lua files pass StyLua/Luacheck, and all 787 Lua files parse. The backend and bundled executables are unchanged by this update.

Linux validation against local MariaDB 10.11.19 passed through Neovim and the bundled Go worker: engine-enforced read-only setup, bound constants, and metadata for 132 tables and 200 foreign keys, including primary-key detection. No production records were read or exported. MariaDB uses the `mysql` profile engine. Live MySQL/PostgreSQL checks, Windows execution, and physical terminal key behavior remain unverified for this revision; cross-compilation alone does not validate runtime behavior.

Run from the configuration root:

```text
nvim --headless -u NONE -i NONE -l config/tests/run.lua query --only-failure
```

Run from `config/tools/repos/foxquery/`:

```text
go test -mod=vendor ./...
./build.ps1        # PowerShell
bash build.sh      # Bash
```

Driver references: [embedded pure-Go SQLite](https://pkg.go.dev/modernc.org/sqlite), [Go MySQL driver](https://github.com/go-sql-driver/mysql), [pgx database/sql integration](https://pkg.go.dev/github.com/jackc/pgx/v5/stdlib).
