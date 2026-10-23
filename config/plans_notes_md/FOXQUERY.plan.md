# FoxQuerier: a database workspace inside FoxVim

Portability revision: Python/pip and the project driver installer have been removed. FoxQuery now uses bundled Go workers for Windows/Linux amd64. Source, pinned dependency lockfiles, tests, and build.ps1/build.sh live under config/tools/repos/foxquery (vendor is generated locally when missing, reused, and Git-ignored); final executables live under config/tools/foxquery. Existing profiles, SQL, caches, and passwords retain their formats. See config/tools/repos/foxquery/README.md. Earlier production validation applies to the previous backend; live server and Linux checks must be repeated.

Status: **initial read-only implementation available**. See [the usage and validation guide](../../docs/query-mode.md) for commands, implemented behavior, and current limitations. This document retains the intended product design; unchecked acceptance items and suggested follow-ups are not claims of completed validation.

Latest follow-up: results are bordered ASCII tables; SELECT auto-execution follows the current caret across statements. Diagram default is now 30% SQL / 70% diagram. Resized UI geometry is explicitly global in `stdpath('data')/fox/query-layout.json`; SQL/profiles/results/cache remain project-local. This overrides older project-only split-geometry proposals below.

Latest usability revision: connections sidebar with CRUD and last-successful-connection restore; Shift+F3 toggles a 30% SQL / 70% live diagram without that sidebar; results stay beneath SQL in both layouts. Unused columns are dimmed and unfinished JOINs show FK candidates. The user's new observations supersede the earlier manual-only execution preference: SELECT runs after a 900 ms typing pause, subject to worker read-only checks; parameterized queries and unfinished JOIN predicates require manual action. Ctrl+Enter/F5 runs manually; Ctrl+Space/Ctrl+X Ctrl+O opens completion. See `IMPLEMENTATION-FOXQUERYGRIP.findings.md` and `FOXQUERYGRIP_history.md` for the latest decisions.

Implementation coverage: Standard/Visual views, project-local profiles/documents/cache, SQLite/MySQL/PostgreSQL driver paths, bounded read-only execution, RAM parameters, cached completion, FK JOIN previews, connected ASCII diagrams, table notes, explicit workspace integration, and Command Palette actions. Advanced graph syntax, persisted SQL history, drafts, virtual relationships, and write/admin features remain follow-ups. Live PostgreSQL and Linux checks are outstanding.

Production validation: the application account confirmed **MySQL 5.7.44** and engine-enforced read-only setup. Bound constants and a zero-row catalog query passed; no business records were read or production query results saved. The earlier "MySQL 5.3" report is superseded by this verified version.

FoxQuerier is the working name for query mode. Requirements and user answers are marked as confirmed. Layouts, commands, extra features, and suggested defaults are proposals for review.

## 1. What I want to solve

I work with a database of about 122 tables. I enjoy SQL, but understanding the database and switching between Neovim and DBeaver takes too much time and breaks my focus. My work computer is slow; running a database GUI alongside Docker and Neovim can exhaust its resources.

I want a lightweight place inside FoxVim to find tables, understand relationships, write queries with useful completion, inspect results, and save what I learn. I am visual: diagrams and readable structure views matter as much as executing SQL.

[DATAGRIP-FUNCIONALIDADES.md](DATAGRIP-FUNCIONALIDADES.md) is an inspiration/reference inventory, not a requirement to reproduce all of DataGrip. DBeaver's relationship browsing is another reference. The goal is to cover my actual work without turning FoxVim into a heavy database IDE.

## 2. Confirmed requirements and decisions

| Area | Confirmed direction |
|---|---|
| Scope | Plan query mode now. FoxAI implementation is outside this work. |
| Project | Editor, query, and future AI modes are views of the same open project. |
| Databases | SQLite, MySQL, and PostgreSQL must support the core workflow. |
| First target | Work server verified as MySQL 5.7.44 through the authorized minimal validation. |
| Platforms | Neovim on Linux and Windows. |
| Connection workflow | Usually local, including Docker-exposed databases. Use host/port/credentials; remain Docker agnostic. |
| Access | Read-only first; add writes later. |
| Relationships | Most relationships already have foreign keys. |
| Storage | All FoxQuerier-owned files and persisted SQL state under the owning project's `.foxnvim/`; no global SQL store or `nvim-data` SQL state. |
| Discovery | Right sidebar, fuzzy table search, table structure, and relationship exploration. |
| Query views | Keep the existing layout as Standard view; add an alternative Visual view with SQL on the left and a diagram that follows the SQL on the right. |
| Visual feedback | Resolve FROM tables while typing, show related tables dimly, emphasize selected columns, and connect joined tables dynamically. |
| Visual columns | Highlight SELECT columns; mark join/filter columns separately. |
| Diagram interaction | Selecting a table/relationship inspects it and offers an explicit Insert JOIN action; insertion requires a reviewed text edit, never an automatic rewrite or execution. |
| Diagrams | Configurable neighborhood depth, default 3, plus a whole-database relationship map. |
| Notes | Persistent table notes for business rules, gotchas, and examples. |
| SQL | Saved query tabs; run selection, current statement, explicit section, or whole file. |
| Parameters | Prompt for `?` values; keep values in RAM by default. |
| Startup | Reopen query tabs only through an explicitly saved workspace. |
| Navigation | Comfortable, available two-hand mode-switch shortcuts, plus Command Palette actions. |
| Performance | Low idle CPU, bounded memory, responsive typing on a slow computer. |
| Production testing | A production database is currently available through Docker. Necessary validation queries are allowed, with minimal information access and no unrelated data collection. |

Unanswered decisions stay open. Suggested defaults are not treated as accepted merely because they appear here.

## 3. Three views of one project

- **FoxEditor**: the existing coding environment.
- **FoxQuerier**: SQL buffers, database explorer, results, notes, and relationships.
- **FoxAI**: future mode; unavailable until separately implemented.

A mode is a layout/workflow within a FoxVim environment, not a new project, new Neovim process, or Vim Normal/Insert mode. Switching modes preserves the project root, unsaved buffers, running editor tasks, and terminal slots.

Proposed behavior:

1. A mode picker is available from the dashboard and Command Palette. Switching modes does not require returning to the dashboard.
2. Query shows its SQL layout; returning to Editor restores the previous editor layout and focus.
3. Query tabs, results, and sessions survive mode switches in RAM. They do not automatically reopen after restart.
4. Each environment owns its mode and SQL state. Project A cannot accidentally execute against Project B's connection.
5. A running query stays bound to its original project, console, connection, and execution even after a project switch.
6. Queries may finish in the background when switching views/projects. Closing their environment offers explicit cancel/wait behavior.

### Proposed mode picker

```text
+----------------------------------------------------------+
| Project: /work/orders-service                             |
| Choose how to work in this project                        |
|                                                          |
| > FoxEditor     Code, files, tasks, debugging              |
|   FoxQuerier    SQL, database structure, results, notes     |
|   FoxAI         Planned; unavailable                      |
|                                                          |
| Enter: open   Esc: return   ?: help                        |
+----------------------------------------------------------+
```

Reuse current environment slots and workspace concepts. Do not create a parallel project manager for Query.

## 4. Daily workflow

1. Open my project and switch to FoxQuerier.
2. Choose/create a project connection, test it, and explicitly connect.
3. Search the right sidebar for a table; inspect columns/keys and read my notes.
4. Open its relationship neighborhood to understand nearby tables.
5. Create/reopen saved SQL; choose the query's connection and database/schema.
6. Write SQL with schema-aware suggestions and FK-based JOIN assistance.
   Optionally switch from Standard to Visual view to see the query's tables, columns, and JOINs develop beside the SQL while typing.
7. Run the chosen scope; provide parameter values when prompted.
8. Inspect results, expand a cell/row, and navigate related records.
9. Save useful SQL and notes. Explicitly save a workspace when I want those tabs/layout restored later.

The first release should make this path comfortable before adding administrative tools.

## 5. Layouts to review

These are terminal sketches, not screenshots or fixed dimensions. Names are examples. Provide ASCII fallbacks for Unicode/icons and textual state labels rather than relying on color alone.

### A. Standard view: confirmed layout direction

The user has confirmed this arrangement is suitable. Keep it as the normal query workspace. Visual view below is an alternative layout within FoxQuerier, not a replacement or a fourth project mode.

```text
+----------------------------------------------------------------------------------------------+
| orders-service | Editor [QUERY] AI(unavailable) | local-mysql / sales | READ ONLY | connected    |
+----------------------------------------------------------------+-----------------------------+
| Queries: [orders.sql *] [customers.sql] [+]                      | DATABASE EXPLORER           |
+----------------------------------------------------------------+-----------------------------+
| -- @section Recent orders                                      | Connection: local-mysql     |
| SELECT o.id, c.name, o.total                                    | Database: sales             |
| FROM orders o                                                  | Find: ord                   |
| JOIN customers c ON c.id = o.customer_id                        |                             |
| WHERE o.created_at >= ?;                                       | > orders          [note]    |
|                                                                |   order_items               |
|                                                                |   order_statuses            |
+----------------------------------------------------------------+-----------------------------+
| RESULTS: run #12 / orders.sql | 200 rows loaded | capped         | INSPECT: orders             |
| id   | name        | total                                      | PK id            bigint     |
| 1042 | Ada         | 28.50                                      | FK customer_id   bigint     |
| 1043 | Luis        | NULL                                       |    total         decimal    |
| ...                                                            |    created_at    datetime   |
+----------------------------------------------------------------+                             |
| ACTIVITY: fetching | elapsed 0.42s | Cancel                      | Parent: customers           |
| Submitted SQL: SELECT o.id, ... WHERE o.created_at >= ?          | Child: order_items          |
|                                                                | Note: totals exclude tax    |
+----------------------------------------------------------------+-----------------------------+
| Run statement / selection / section / file | Results | Relations | Notes | Command Palette     |
+----------------------------------------------------------------------------------------------+
```

- SQL gets most of the width. The right sidebar combines search and selected-object details; do not open a panel for every feature.
- Results occupy the lower main area. Activity is a short strip, expandable for SQL, errors, notices, and timings.
- Explorer selection previews structure only. Fetching rows requires an explicit browse action.
- Every query/result shows its connection. Changing the explorer connection does not silently rebind open queries.
- `*` means unsaved edits. Query tabs represent SQL buffers, not necessarily Neovim tabpages.

### B. Focused table inspection

```text
+----------------------------------------------------------------------------+
| sales.orders | local-mysql | Structure [Relations] Notes Sample              |
+---------------------------------+------------------------------------------+
| Columns / keys                  | Neighborhood: orders | depth 3 | 9 nodes  |
| PK id             bigint        |                                          |
| FK customer_id    bigint        | [customers] 1 <-- N [orders]              |
|    total          decimal       |                         1                |
|    created_at     datetime      |                         |                |
|                                 |                         N                |
| Referencing: order_items        |                    [order_items]         |
| Referenced: customers           |                         N                |
|                                 |                         |                |
| Notes:                          |                         1                |
| total excludes tax.             |                     [products]           |
| Use paid orders for reports.    |                                          |
+---------------------------------+------------------------------------------+
| Enter: inspect node | Recenter | Depth +/- | Path | SQL JOIN | Back         |
+----------------------------------------------------------------------------+
```

Depth 3 means up to three relationship edges from the focused table, following both directions. The sketch shows only part of a possible neighborhood. Focus an edge to inspect its actual column mapping.

### C. Whole-database map

```text
+----------------------------------------------------------------------------+
| Database map: sales | 122 tables | filter: all | columns: keys only          |
+----------------------------------------------------------------------------+
| [customers] -- [orders] -- [order_items] -- [products] -- [categories]       |
|                   |                               |                        |
|               [payments]                     [suppliers]                   |
|                                                                            |
| [users] -- [user_roles] -- [roles]            [audit_log] [settings]         |
|                                                                            |
| ... more nodes outside the viewport ...                                    |
+----------------------------------------------------------------------------+
| /: find table | Pan | Focus neighborhood | Hide columns | Back             |
| Selected: orders | 2 incoming FKs | 1 outgoing FK | note available          |
+----------------------------------------------------------------------------+
```

An ER-style relationship map provides the requested UML-like understanding. Search jumps to a node; pan navigates a text canvas; selecting a table opens its readable neighborhood. The overview need not show every column. Grouping/clipping must disclose hidden counts; do not squeeze 122 detailed boxes into unreadable text.

### D. Small terminal / focused SQL

```text
+----------------------------------------------------+
| QUERY | local-mysql / sales | READ ONLY              |
| [SQL] [Results] [Explorer] [Relations] [Activity]     |
+----------------------------------------------------+
| SELECT ...                                         |
|                                                    |
| One primary pane; toggle the pane you need.         |
| Connection and execution state remain visible.      |
+----------------------------------------------------+
```

Resizing preserves SQL, selection, running queries, and panel state. Proposed wide layout: sidebar around 30% width, results around 35% height, both resizable/hideable. Validate this on my real screen before fixing minimum sizes.

### E. Visual view: SQL on the left, live query diagram on the right

Confirmed intent: I want to see the query take shape as I write it. Typing a valid `FROM table` brings that table into the diagram and reveals related tables dimly. Selecting columns emphasizes those columns; adding JOINs brings the other tables into focus and connects them. Edits update the graph dynamically.

This is SQL-driven visualization inside FoxQuerier, separate from Neovim's Visual selection mode. Shift+F3 toggles a 30% SQL / 70% diagram layout. The connection sidebar and normal explorer are hidden here; results/activity remain beneath SQL, using the same execution controls as the default layout.

```text
+------------------------------------------------------------------------------------------+
| QUERY | Standard [VISUAL] | local-mysql / sales | READ ONLY | diagram: current statement     |
+------------------------------------------+-----------------------------------------------+
| SQL: orders.sql *                        | LIVE QUERY DIAGRAM                            |
|                                          |                                               |
| SELECT o.id, c.name, o.total              | +----------------+    +--------------------+  |
| FROM orders o                            | | customers AS c |    | orders AS o        |  |
| JOIN customers c                         | | * name         |    | * id               |  |
|   ON c.id = o.customer_id                 | | k id           |<---| k customer_id      |  |
| WHERE o.created_at >= ?;                 | +----------------+    | * total            |  |
|                                          |                       | f created_at       |  |
|                                          |                       +--------------------+  |
|                                          |                            :                  |
|                                          |                     [order_items]             |
|                                          |                     related, not joined       |
+------------------------------------------+-----------------------------------------------+
| * output column | k join key | f filter column | solid: SQL JOIN | dotted/dim: suggested FK |
| Diagram follows draft SQL; existing results still describe their own executed SQL snapshot |
+------------------------------------------------------------------------------------------+
```

ASCII shows status text and markers; the actual terminal UI can use highlights for selected columns, dim highlights for context tables, and distinct edge styles. Meaning must remain readable without color.

#### How the graph develops

| SQL edit | Expected visual response |
|---|---|
| `SELECT ...` before a FROM exists | Show that the source table is not resolved yet; do not guess a table or fetch data. |
| `FROM orders o` resolves | Show one active table instance labelled `orders AS o`; reveal FK-related context tables dimly. |
| `SELECT o.id, o.total` | Highlight output columns; proposed default hides unrelated columns, keeping needed join/filter columns separately marked. |
| `JOIN customers c` without ON yet | Show the second active table and a pending JOIN indication. A suggested FK edge stays visibly provisional. |
| `ON c.id = o.customer_id` | Draw a confirmed query edge labelled with the SQL JOIN type/predicate and identify its endpoint columns. |
| `WHERE o.created_at >= ?` | Optionally show the referenced filter column with a different marker; this does not make it an output column. |
| Remove a selected column or JOIN | Update emphasis/edges; a removed JOIN target returns to dim context only if still related, otherwise disappears. |
| Unknown/ambiguous table or column | Mark unresolved/ambiguous references. Do not present them as verified schema objects. |

#### Meaning of nodes, columns, and connections

- Active nodes represent table instances in the query. Dim nodes are schema context, not tables included in the SQL. Proposed live context depth: 1, bounded and expandable; the standalone relationship inspector keeps its confirmed default depth 3.
- Schema FKs and actual SQL JOIN predicates are different evidence. Draw solid query edges and dotted/dim FK suggestions with labels. A valid SQL JOIN may have no declared FK; an FK alone does not prove the SQL contains a JOIN.
- Preserve the typed JOIN kind, including LEFT/RIGHT/INNER/CROSS and dialect-supported forms. Do not imply an outer JOIN filters rows like an inner JOIN. Label complex/range predicates rather than inventing an equality/FK mapping.
- Show independent instances for config/aliases/self-JOINs, such as `employees manager` and `employees report`. Never collapse them into one node just because the physical table matches.
- Confirmed column mode: highlight SELECT output columns, mark join/filter columns separately, and dim unused columns. Pending JOINs mark candidate FK columns. If a column has multiple roles, retain each role's indication. Inspect reveals all columns beyond card limits.
- `SELECT *`/`alias.*` expands known columns within rendering limits and discloses hidden counts. Expressions/aggregates retain their output aliases and reference available source columns; computed outputs must not masquerade as stored table columns.
- The display explains the draft query's structure; it is not a query execution plan, result preview, or proof that the SQL is valid or safe.

#### Behavior while SQL is incomplete

- Update the diagram after 200 ms using local SQL analysis and cached metadata. A separate 900 ms debounce attempts only SELECT execution; it never executes writes or introspects/samples rows merely to draw the graph.
- Follow the statement under the SQL cursor by default. A diagram focus change must not change execution scope. When the cursor moves to the diagram, keep tracking the last active SQL statement; offer an explicit pin/follow action.
- Keep valid portions visible through partial edits. If showing the last resolved graph, label it stale/pending and distinguish it from any newly parsed portion. Never pretend the old graph describes incomplete new text exactly.
- Stabilize node positions as edges/columns change; update affected elements instead of constantly relaying out the canvas. Selection, pan, and pinned focus should not jump on every keystroke.
- Treat fade-in primarily as a change from dim context to active emphasis. A brief optional highlight transition is a later polish choice; no continuous animation or redraw loop, and reduced-motion/static behavior must work.
- Identify queries the analyzer cannot represent fully. CTEs/subqueries can become labelled derived nodes when supported; UNIONs, correlated scopes, and complex dialect forms must show partial/unsupported status until correctly handled. Basic tables, aliases, selected columns, equality JOINs, and incremental incomplete input form the first supported subset.
- Switching Standard/Visual preserves the same SQL buffer, cursor, connection, and executed results. Confirmed interaction: selecting a table/relationship inspects it and offers an explicit Insert JOIN action. Preview the target statement, aliases, join type, and full key mapping before applying an undoable text edit; insertion never executes SQL. For ambiguous relationships, require choosing a mapping; if no supported mapping exists, explain why insertion is unavailable. Clicking a node alone never rewrites SQL.
- Diagram work pauses when hidden and respects graph/column limits. On a small terminal offer a pane toggle or Standard view without losing state. Cached/offline diagrams visibly inherit metadata age and permission limits.

Confirmed: SELECT columns are highlighted, join/filter columns are marked separately, and selection inspects an object with an explicit Insert JOIN action. Dim-context depth and statement pin/follow behavior remain proposals for review.

## 6. Connections, drivers, and sessions

| Engine | Required baseline |
|---|---|
| SQLite | Existing local file; relative paths from project root. Never silently create a database because of a typo. |
| MySQL | Host, port, database, user, authentication, explicit connection test. Validate my work setup first. |
| PostgreSQL | Host, port, database, schema/search-path context, user, authentication, explicit connection test. |

Docker is irrelevant to connection logic: use the exposed address and credentials. No container discovery, Docker API, startup, or automatic `docker exec`. Windows and Linux support require actual checks on both platforms.

Profiles need stable IDs, readable labels, engine, and optional local/staging/production labels. Check server capabilities; explain unsupported features instead of faking them. The reported "MySQL 5.3" version was checked through the authorized minimal validation and resolved to MySQL 5.7.44; no server upgrade was needed.

Proposed session model:

- Each SQL console owns a persistent execution session, opened on demand. Avoid a connection per panel.
- Temporary tables/session settings belong to that console; execution must not silently move between sessions.
- Serialize runs within a console. A second Run reports busy; another console may use another session within a small connection limit.
- Use a separate bounded metadata connection only where necessary. Metadata must not alter console context or block cancellation behind running SQL.
- Report disconnects. Reconnect explicitly, clear stale session assumptions, and never automatically rerun SQL.
- Prompt for passwords by default; keep them in RAM. Optional environment-variable references must not copy secrets into files/logs.
- Profiles are data, not executable shell snippets. Never execute project SQL on connect, project open, or workspace restore.
- Support TLS settings when required. Built-in SSH management stays deferred unless needed; external tunnels can be ordinary host/port connections.

### Driver feasibility check before UI implementation

Selected implementation: a small structured Python driver process, using standard-library SQLite and explicit project-local PyMySQL/psycopg installations for the other engines. The following requirements remain the verification criteria; this is not a universal database framework.

The approach must demonstrate on all three engines:

- Structured metadata and typed rows, without parsing pretty-printed CLI tables.
- Safe parameter binding, persistent sessions, and reliable SQL/error encoding.
- Async work, bounded fetching, multiple result sets where supported, and cancellation/timeouts.
- Password handling without secret-bearing command arguments or persistent client history outside the project.
- Installation on Linux/Windows and compatibility with the actual work server.

Document gaps before implementation expands. Core support for three engines is required; advanced capability parity across every server version is not assumed.

## 7. Explorer, completion, and JOIN assistance

Required explorer behavior:

- Fuzzy-search cached tables/views without server queries on each keystroke.
- Browse connection -> database/schema -> object -> columns, PKs, FKs, unique constraints, indexes.
- Show types, nullability, defaults, and comments where available.
- Distinguish outgoing references from incoming references.
- Expose metadata age and stale/offline status; refresh a table/chosen schema explicitly. No continuous full-database introspection.
- Distinguish permissions, unsupported metadata, stale cache, and missing objects. Incomplete metadata is not proof that a table is an orphan.

Required SQL assistance:

- Use the query's connection, dialect, database/schema, metadata, and visible SQL scope.
- Complete qualified tables, columns, aliases, and keywords; distinguish identical names across schemas.
- Suggest FK-backed JOINs in both directions, including all composite-key predicates.
- Show alternatives for multiple FKs between the same tables. Preview mappings, alias, and join type before insertion; never execute suggestions.
- Keep typing/completion local; refresh metadata separately. Ignore late responses after buffer/connection changes.
- Address CTEs, nested queries, quoted identifiers, and alias scope explicitly. Start with a documented subset rather than promising full SQL understanding from regular expressions.
- Fit highlighting, optional formatting, diagnostics, and completion into existing language-module/blink.cmp patterns. Diagnostics are assistance, not complete validation or a security boundary.

Suggested improvements for my workflow:

| Idea | Value | Priority |
|---|---|---|
| Relationship path between two tables | Answers "how can I join these?"; show alternative paths for review. | First follow-up |
| Generate SELECT with chosen columns | Reduces repetitive typing while learning tables. | Early |
| Favorite tables/queries; business-area tags | Keeps the important subset of 122 tables close. | Early if useful |
| Search notes and object names together | Find business concepts when names are unfamiliar. | Early |
| Follow a result FK to related rows | Connect a value to its meaning; preview generated SQL first. | Early |
| Local virtual relationships | Document links absent from server FKs without changing the server. | Follow-up |
| EXPLAIN viewer | Investigate slow queries. Execution-based analysis is a separate explicit action. | Later |

## 8. Relationship diagrams and table notes

### Graph behavior

- Default neighborhood depth **3**, adjustable per view, following incoming/outgoing FKs.
- Handle cycles, self-references, multiple edges, composite keys, disconnected components, and schemas.
- Show key columns first; expand other columns on demand. Expose edge direction and mappings.
- Support keyboard selection, search, recenter, back/history, and pan. Mouse support is optional.
- Depth 3 can reach most of a highly connected database. Proposed visible budget: 40 nodes; disclose omitted counts and offer explicit expansion.
- Whole-database navigation/search must reach every introspected table, even with a simplified overview or viewport rendering.
- Offline maps use cached metadata with visible age/coverage. Drawing relationships requires no data-row downloads.

### Classifications should describe evidence

| Label | Meaning |
|---|---|
| Entity/table | Ordinary table; can also participate in relationships. |
| No known relationships | No edges in available metadata. Only call it an orphan if coverage is known complete. |
| N:1 / 1:N | Child FK references a key; nullability/uniqueness refine optionality/cardinality. |
| 1:1 | FK uniqueness supports at most one matching child; names alone do not establish it. |
| Possible M:N bridge | Linking-table pattern inferred from constraints; explain the inference and allow correction. |
| Documented relationship | Local user-defined link, visibly different from an enforced FK. |

A bridge table may have business fields and its own identity. Do not force every table into exactly one category or show guesses as database facts.

### Notes: required

- Editable Markdown per qualified table, scoped by project and stable connection identity.
- Capture business meaning, gotchas, important columns, example queries, and related-note links.
- Show note badges; make notes readable offline.
- Do not modify server comments or constraints.
- Refresh/cache cleanup never deletes notes. Dropped/renamed tables leave detached notes that can be explicitly relinked.
- Business notes can describe suspected links without claiming actual FKs.
- Column-level notes/formal local relationships are follow-ups if table Markdown proves insufficient.

## 9. Execution, parameters, and live activity

### Execution scopes: required

Provide separate **selection**, **current statement**, **section**, and **whole-file** actions. Convenient Run may use the active selection, otherwise the current statement, but must show the resolved scope.

- Proposed section marker: `-- @section Name`, ending at the next marker or EOF.
- Execute exactly the selected text; invalid fragments return clear errors. Reject rectangular/block selections initially rather than accidentally concatenating them.
- Respect strings, comments, quoted identifiers, and dialect syntax. Semicolons inside strings/routine bodies are not generic separators.
- If scope is ambiguous, request explicit selection. Never fall back to executing the whole file.
- Preserve batch order, report multiple result sets/messages, and stop on error by default. Batches are not automatically atomic.
- Execute a captured snapshot; edits during execution do not change submitted SQL or result provenance.

### Parameters: required

- Recognize `?` placeholders at valid positions; prompt by position, allow review, distinguish NULL/empty string, and cancel the run if input is canceled.
- Do not prompt for `?` in strings/comments or dialect operators. Blind replacement is not sufficient for PostgreSQL.
- Use actual driver binding or a verified engine-aware binding mechanism. Never insert raw input into SQL or shell commands.
- Keep values in RAM, scoped to console/connection. Show/reconfirm reused values and offer a clear-values action.
- Clear on console/environment close or connection change. No automatic persistence in SQL/history/workspaces/result metadata.
- Named/native placeholders and list expansion are possible follow-ups. One scalar placeholder must not turn comma-separated text into SQL syntax.

### Activity: required, with honest limits

- Show connection, execution ID, scope, submitted SQL template, elapsed time, loaded rows, and queued/running/fetching/completed/failed/canceled states.
- Keep placeholders visible; reveal values only explicitly in the current session.
- Show errors, source locations where available, and server messages/notices.
- Provide Cancel and configurable timeout, with a cancellation-pending state.
- "Real time" initially means client activity and incremental rows where supported. Do not invent server percentages, internal stages, or live query plans.
- Hiding results does not cancel SQL. If terminating the client cannot confirm server cancellation, say so and discard/reset the uncertain session before reuse.

## 10. Results and browsing data

- Keyboard-navigable read-only grid, headers, horizontal scrolling, explicit NULL display.
- Distinguish NULL, empty string, zero, missing, and truncated values. Preserve large-ID/decimal/timestamp fidelity instead of converting everything through floating point.
- Expand cells for long text/JSON and rows for vertical inspection. Bound huge values/blobs and label truncation.
- Copy cells/rows/selections. FK navigation requires the necessary key values to be available.
- Tie results to execution ID, SQL template, connection/database/schema, source buffer, timestamp, and status. Never silently adopt the latest buffer text.
- Replace the active unpinned result on a new run by default. Allow a small bounded number of pinned results; no unlimited result tabs.
- Local search covers loaded rows only and says so. Server filtering/sorting is a separate reviewed rerun.
- Table browsing generates explicit bounded SELECT; use stable ordering where a suitable key exists, otherwise label instability.
- Cap fetched rows/bytes and report truncation. Client caps do not guarantee cheap server execution; do not blindly append LIMIT to arbitrary SQL.
- Proposed tuning defaults: 200 browse rows; arbitrary-query fetching capped at 1,000 rows or 8 MiB, whichever arrives first. These are reviewable proposals, not benchmark results.
- Do not promise arbitrary-query resume/pagination without driver support. A rerun may return different rows and must be labelled.
- Suggested export: explicit CSV/JSON into `.foxnvim/query/exports/`, with overwrite confirmation and a loaded-rows-only label where applicable. No automatic result persistence.

## 11. Read-only first and production validation

Confirmed: browsing, querying, learning, and notes first. Editable cells, schema changes, and write/transaction UI are deferred.

- Prefer actual read-only credentials and engine-enforced read-only settings where available. UI labels and keyword filters cannot guarantee protection.
- SELECT may call functions or have effects. A statement classifier is not a security boundary.
- Show enforcement honestly: "read-only not verified" when protection cannot be established.
- No auto-execution, automatic write retries, or hidden DDL/DML from browsing/graph actions.
- Before future writes, define session ownership, autocommit, transactions, pending indicators, disconnect behavior, and engine-specific limits.
- Editable grids require reliable row identity and conflict handling; never guess UPDATE predicates for tables without suitable keys.

### User-authorized production testing

The user has offered the current production database in Docker for necessary functionality checks, with an explicit instruction to access no extra information. This is limited validation access, not a reason to explore business data.

- Planning needed no production access. Implementation validation used only read-only session setup, version/capability checks, bound constants, and a zero-row catalog query; no business records were read.
- During implementation, first use disposable SQLite/MySQL/PostgreSQL fixtures for parsing, binding, errors, cancellation, and load tests.
- Use production only where needed to verify the real setup: exact version/capabilities, scoped object/column/key metadata, or a narrowly justified read-only functionality check.
- State the purpose and scope of each production check. Fetch only the minimum fields/objects needed; do not dump config/schemas/data, sample records merely for curiosity, or collect sensitive results in files/logs.
- Do not run stress tests, broad scans/counts, execution-based analysis, writes, DDL, or speculative routines against production. LIMIT does not make an expensive query harmless.
- Do not change/start/stop containers. Docker availability does not change the connection design or the production data boundary.
- If access details are missing, request only the required connection information through an appropriate private mechanism; do not search unrelated files for credentials.

## 12. Project-local storage

**Every file and persisted SQL state FoxQuerier owns belongs under the owning project's `.foxnvim/`. No global SQL store or `nvim-data`.**

Proposed organization; create each part only when its feature needs it:

```text
<project>/
  .foxnvim/
    query/
      connections.json             # Shareable IDs and non-secret settings
      queries/
        recent-orders.sql          # Explicitly saved SQL
      notes/
        <connection-id>/...md      # Qualified table identity
      relationships.json           # Only if local links are implemented
      private/
        connections.local.json     # Local overrides; no passwords by default
        history.json               # Optional bounded execution metadata
        workspaces/                # Explicitly saved query tabs/layout
      cache/
        <connection-id>/...json    # Disposable metadata
      exports/                     # Explicit exports only
      recovery/                    # Optional draft recovery; decision open
```

Storage rules:

1. Queries/notes are user documents. Clearing cache cannot delete them, profiles, exports, or saved workspaces.
2. Use canonical project root and stable connection/database/schema/object identity. Scratch/UI buffers inherit an owner; never infer it from the later active buffer/cwd.
3. Changing a profile's server/database invalidates incompatible cache and requires explicit note/workspace rebinding. Labels alone do not establish identity.
4. Separate shareable/private files. Before private persistence, offer project-local Git ignore entries while preserving existing ignore rules. Notes and SQL text can themselves be sensitive.
5. Proposed history default: status/timing and a saved-query reference. Full executed SQL is opt-in because literals may be sensitive. Never automatically save passwords, parameter values, or result rows.
6. Corrupt state gets actionable recovery/rebuild choices. Never silently overwrite the only copy of notes/workspaces. Durable documents need safe writes and external-edit conflict detection.
7. Unwritable projects may offer an explicitly temporary RAM session, with saving unavailable. No silent global fallback.
8. Installed drivers/clients are dependencies, not SQL state. Existing SQLite DB files stay at their configured locations and are not moved into `.foxnvim/`.
9. Audit indirect persistence: workspace/environment snapshots, ShaDa histories/registers, swap/undo/backups, logs/notifications, driver history/temp output. Redirect or exclude FoxQuerier-owned SQL content/state from global writers; a local folder alone does not prove compliance.
10. Do not rewrite unrelated editor storage. Generic recent-project records can still name projects, but cannot become another store for SQL tabs, connections, notes, results, or layout state.

## 13. Tabs, restart, and saved workspaces

| Event | Proposed behavior |
|---|---|
| Switch Editor/Query | Preserve RAM buffers, results, layouts, sessions; restore focus. |
| Switch environment | Hide old view; state remains with its original project. |
| Save SQL | Write under `.foxnvim/query/queries/`; exclude results/parameters. |
| Close modified SQL | Offer save/discard/cancel; never silently discard edits. |
| Exit without workspace save | Query tabs remain closed on startup; saved SQL/notes remain available. |
| Explicit workspace save | Locally save query-file references, active query, connection IDs, selected objects, mode, graph focus/depth, pane sizes. |
| Standard/Visual selection | Keep view, split sizes, graph pan/focus, and pin/follow state in RAM; persist only with explicit project-local workspace save. Rebuild the draft diagram from restored SQL and metadata. |
| Load saved workspace | Reopen layout/files while disconnected; no SQL replay or RAM parameter/result restoration. |
| Crash with scratch SQL | Optional project-local recovery remains an open choice; it need not auto-open tabs. |
| Missing query/profile | Offer locate/rebind/skip; no arbitrary fallback connection. |
| Close environment with active SQL | Cancel/wait, clean up owned jobs/sessions, report uncertain cancellation. |

Integrate with current Workspace commands/UI. Exclude SQL UI/results/state from generic session serialization and restore it through project-local query workspace files. Do not add a competing workspace manager.

## 14. Commands and navigation

Every action needs a descriptive Command Palette entry and Ex command. The table below retains the planned interface; see the usage guide for the implemented command set and exact syntax.

| Proposed command | Action |
|---|---|
| `:FoxMode [editor/query]` | Pick/switch project view. |
| `:FoxQueryView [standard/visual]` | Switch layout within Query, preserving the SQL buffer/session/results; expose both choices in the palette. |
| `:FoxQueryConnections` | Manage/test/connect/disconnect profiles. |
| `:FoxQueryNew` / `:FoxQueryOpen` | Create console/open saved SQL. |
| `:FoxQueryRun statement/selection/section/file` | Run explicit scope; slash-separated words denote alternatives, not literal syntax. |
| `:FoxQueryCancel` | Cancel selected execution. |
| `:FoxQueryExplorer` / `:FoxQueryInspect` | Search objects/inspect a table. |
| `:FoxQueryGraph` / `:FoxQueryNotes` | Explore relationships/edit notes. |
| `:FoxQueryRefresh` / `:FoxQueryResults` | Refresh metadata/focus results. |
| `:FoxQueryClearParameters` / `:FoxQueryClearCache` | Clear named transient state, preserving user documents. |

No new `<leader>` shortcuts. The requested two-hand mode-switch shortcut remains open: audit configured/runtime mappings across Normal/Insert/Visual/Terminal and terminal/OS interception on Linux/Windows before declaring a combination free. Preserve existing workspace/environment/terminal/task/launch bindings.

Panel-local keys should be familiar: arrows or `h/j/k/l`, Enter to inspect, `/` to find, `q`/Esc to return, `?` for contextual help. Explain graph panning versus node selection. Palette commands remain available if a terminal cannot transmit the chosen shortcut.

## 15. Performance and FoxVim integration

### Performance requirements

- Lazy-load UI/drivers. Editor-only startup does not connect, introspect, or fetch data.
- Run DB work asynchronously; typing and Cancel remain responsive.
- Cache object/relationship metadata with on-demand details; no eager row counts, samples, or full-table scans on selection.
- Bound rows/bytes, result retention, connections, history, graph size, and rendering work. Release resources when their environment closes.
- No continuous idle polling/redrawing unchanged graphs.
- Diagram drawing uses local debounced SQL analysis; SELECT execution has a separate 900 ms debounce. No work for hidden projects or continuous fade animations.
- Measure connect time, warm search, completion responsiveness, mode switches, and RAM overhead on my slow computer. Proposed limits are not measured guarantees.

### Existing integration points inspected

| Existing area | Planned use / constraint |
|---|---|
| `lua/fox/core/project.lua`, `path.lua` | Reuse root/path handling with explicit SQL ownership. Generic config fallback paths cannot override `.foxnvim/query/`. |
| `lua/fox/core/ui.lua`, `zindex.lua`, current UI components | Reuse native buffers/splits/floats, layering, house conventions. |
| `lua/fox/core/store.lua` | Reuse suitable JSON handling after checking durability; current writer does not provide atomic replacement. |
| `lua/plugins/fox/tools/command_palette.lua` | Actual current palette location; add to `M.commands`. Older wiki links use the previous path. |
| `lua/plugins/fox/tools/workspaces.lua` | Add query hooks/exclusions; current global storage must not receive SQL state. |
| `lua/plugins/fox/tools/environments.lua` | Integrate ownership/lifecycle; review serialization to avoid global SQL persistence or saving another project's SQL under the primary project. |
| `lua/plugins/fox/editor/buffer_cleaner.lua`, bufferline | Preserve ownership, unsaved edits, close behavior, and visible tabs. |
| `lua/plugins/lsp/lsp.lua`, `blink_sources.lua` | Reuse completion; keep SQL-specific configuration in its language module. |
| `lua/fox/langs/` | SQL tooling in `sql/init.lua`, registered in `langs/init.lua`, optional LanguageManager bundle. |
| `config/tests/`, `docs/` | Focused behavior/integration checks and dedicated SQL/query-mode docs during implementation. |

Suggested ownership: domain/session/cache logic under `lua/fox/query/`, thin FOX plugin entry following current grouping, language-tooling settings in `lua/fox/langs/sql/init.lua`. Create modules only when responsibilities justify them. Never scatter SQL language settings across aggregators.

Fresh setups stay Lua-core-only. No optional SQL config/tools/parsers/drivers install in the background; explain missing dependencies and offer explicit selection/installation.

## 16. Build order and acceptance checks

The following build sequence describes the intended delivery gates. Current implementation/verification coverage is recorded above and in the usage guide; unavailable live-engine/platform checks must not be assumed complete.

| Phase | Deliverable | Evidence before continuing |
|---|---|---|
| 0. Foundations | Verify server/version; validate driver, ownership, local persistence. | Three-engine connect/metadata/binding/cancel/disconnect checks; Windows/Linux coverage. Use fixtures, production only as narrowly needed. |
| 1. Useful query mode | Mode switch, profiles, sidebar, SQL tabs, scopes, parameters, activity, bounded read-only results, basic cached completion. | Real work queries fit the workflow without blocking UI, leaking projects, connecting on startup, or auto-restoring tabs. |
| 2. Understand the DB | Structure, notes, FK JOIN suggestions, depth-3 graph, searchable/pannable whole-DB map, diagram toggle, and initial live SQL analysis. | Real 122-table metadata is usable; ambiguity/clipping visible; notes survive refresh; diagrams update locally and SELECT execution follows its separate debounce. |
| 3. Daily persistence | Explicit workspace integration, history policy, exports, related-row navigation, final layouts/shortcuts. | No SQL state escapes local storage through save/exit/restore; user documents survive failures/cleanup. |
| Later, separate review | Writes/transactions and selected follow-ups. | Define behavior/safety before enabling each capability. |

**Phases 1-3 together cover the requested initial read-only product.** Phase 1 is an intermediate checkpoint; graphs, notes, and workspace integration remain in scope.

Implementation acceptance checks:

- [ ] Switching modes preserves unsaved buffers, editor tasks, terminals, and focus.
- [ ] Identical profile/table names across projects stay isolated; late results return to the original owner.
- [ ] Core SQLite/MySQL/PostgreSQL workflows work on Windows/Linux; record tested versions/platforms.
- [ ] Scope/parameters cover comments, strings, identifiers, dialect operators, NULL, empty input, and canceled prompts; ambiguity never broadens execution.
- [ ] Binding treats malicious-looking input as data; no SQL/credential shell interpolation.
- [ ] Disconnects, timeout, cancellation, errors, limited metadata permissions, and multiple results have clear outcomes.
- [ ] Huge results/high-degree cyclic graphs remain bounded, disclose truncation, and do not freeze typing.
- [ ] Composite/ambiguous JOINs show mappings; bridge classification explains evidence.
- [ ] Standard view keeps its confirmed layout; Visual view preserves the same SQL/session/results and shows resolved FROM sources, selected columns, and actual JOINs separately from dim FK suggestions.
- [ ] Visual columns retain distinct output/join/filter roles, including overlapping roles; selecting a graph object only inspects it, while explicit Insert JOIN previews an undoable SQL edit and never executes it.
- [ ] Live diagrams cover partial edits, ambiguous columns, config/aliases/self-JOINs, wildcard/expression outputs, JOIN kinds, cursor-follow/pinning, stale metadata, and explicit unsupported syntax; updates never execute SQL or issue per-keystroke DB requests.
- [ ] Cache cleanup preserves documents/profiles/workspaces; renamed/dropped tables do not erase notes.
- [ ] Startup stays clean; explicit workspace restore remains disconnected and does not replay SQL/results/parameters.
- [ ] Every SQL persistence path, including editor/session/driver side effects, remains project-local.
- [ ] Corrupt/unwritable files, external edits, missing references, and modified-tab closure avoid silent loss.
- [ ] Preserve numeric precision, Unicode, long values, NULL, and duplicate names across schemas.
- [ ] Fresh/editor-only startup remains minimal with no database access or optional installs.
- [ ] Production checks collect only necessary metadata/information; no record dumps, stress tests, or mutation.

Use focused scope/binding/identity tests, headless UI/lifecycle checks, and real-engine integration tests for driver behavior. Run repository quality gates when implementing code. This documentation-only rewrite does not require the Lua suite.

## 17. Deferred ideas and scope judgment

Outside the first read-only release unless a concrete need changes priorities:

- Editable grids, visual schema designers, migrations, backup/restore, bulk import.
- Cloud discovery, Docker management, built-in SSH administration, universal driver/plugin APIs.
- Charts/GIS, full UML editing, browser/GUI requirements for diagrams.
- Global SQL/connection/cache/notes sharing, which conflicts with project isolation.
- Agentic SQL execution, sending config/schemas/data to AI services, implementing FoxAI.
- Exhaustive SQL refactoring/validation and the entire DataGrip inventory.

This request is reasonable as a focused database workspace. Reproducing every database-admin/IDE feature would be a much larger project. The hardest parts are reliable drivers/sessions, SQL context handling, readable terminal graphs, and keeping existing persistence from capturing SQL globally. Validate those before polishing the dashboard.

## 18. Questions for the next review

Already answered: local MySQL first, Windows/Linux, Docker agnostic; read-only first; most links have FKs; production checks may access only necessary information; the existing Standard layout is suitable and a separate SQL-driven Visual layout is wanted. These answers are incorporated above.

### Foundations: settle before implementation

1. **Exact server — answered:** the authorized version check returned MySQL 5.7.44. No private credentials belong in this plan.
2. **Session sharing:** should tabs share temporary tables/session settings? Proposal: independent session per console, explicit sharing later.
3. **Multiple connections:** do I compare local/staging/production in one project? Proposal: multiple profiles with explicit per-console binding.
4. **Storage boundary:** does the rule include engine-managed SQLite journals/WAL and OS/client temp files, or FoxQuerier-owned files/cache/state? Proposal: constrain every FoxQuerier-controlled output; existing DB files and engine-managed sidecars stay at configured locations.

### Layout and learning

5. **Screen/input:** terminal/GUI, approximate columns x rows, keyboard layout, preferred left-hand modifier/right-hand key? Needed for a comfortable, conflict-free mode switch.
6. **Table details:** sidebar preview or large inspector by default? Proposal: sidebar first, dedicated view for deeper inspection/graphs.
7. **Map detail:** orientation overview or all columns at once? Proposal: keys-only overview plus focused neighborhoods.
8. **Notes:** table-level enough, or rules attached to columns/relationships? Proposal: table Markdown with saved-query links first.
9. **Related rows:** immediately fetch FK data or preview SQL first? Proposal: preview and preserve a Back trail.

### Persistence and execution edge cases

10. **Crash recovery:** opt-in local scratch drafts while startup tabs remain closed? Proposal: offer recovery without auto-opening tabs.
11. **History:** metadata/file references enough, or full SQL essential? Proposal: full text opt-in; no automatic parameter/result storage.
12. **Team sharing:** saved SQL/notes in Git or private? Proposal: ignore cache/private/exports and explicitly choose document visibility.
13. **Live execution:** SQL + elapsed time + arriving rows enough, or server lock/session/progress inspection? Proposal: client activity first; monitoring depends on engine/version/permissions.
14. **Parameters:** scalar values including dates/NULL, or `IN (...)` list expansion too? Proposal: scalar binding first.
15. **Concurrent editing:** will two Neovim instances use the project? If yes, define session identity/conflict handling; never overwrite notes silently.
16. **SQLite:** need `:memory:`, attached databases, or network-share files? Proposal: existing local files first.
17. **Long queries:** finish in the background when switching projects? Proposal: yes on switch, cancel/wait on close.

### Visual view refinements

18. **Column visibility — answered:** highlight SELECT columns and mark join/filter columns separately. Hide unrelated columns by default; preserve multiple role indicators when a column is both projected and used in a predicate.
19. **Context tables:** how many related-but-not-joined tables should surround the active SQL tables? Proposal: depth 1 with a visible limit and explicit expansion; preserve depth 3 for the separate table-neighborhood inspector.
20. **Diagram interaction — answered:** inspect the selected object and offer explicit Insert JOIN. Preview the SQL edit before applying it; never silently rewrite SQL. The updated SELECT auto-run policy can execute the resulting draft after its debounce.
21. **Statement tracking:** follow the statement under the SQL cursor, or keep a selected statement pinned while editing elsewhere? Proposal: follow by default with a pin option; graph focus preserves the last SQL location.

Review these in small groups. Driver, ownership, and storage decisions matter before code; the rest can be refined through layouts and daily use.
