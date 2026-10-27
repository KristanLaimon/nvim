# FoxQuerier / FOXQUERYGRIP — resume notes

Current backend: FoxQuery uses bundled Go workers for Windows/Linux amd64. Source, pinned dependency lockfiles, tests, and build.ps1/build.sh live under config/tools/repos/foxquery (vendor is generated locally when missing, reused, and Git-ignored); final executables live under config/tools/foxquery. SQLite, MySQL/MariaDB, and PostgreSQL drivers are compiled into those binaries. MariaDB uses the mysql connection engine and SQL dialect. Existing profiles, SQL, caches, and passwords retain their formats. See config/tools/repos/foxquery/README.md.

Updated: 2026-10-27. Repository: the Neovim configuration root.

Current Linux validation: Go backend tests and **81 Query Mode tests passed**. The bundled Go worker connected to local MariaDB 10.11.19 using the application account, verified engine-enforced read-only setup and bound constants, and loaded metadata for 132 tables / 200 foreign keys with primary-key detection. No production records were read or exported. MariaDB profiles use `engine: "mysql"`. The primary-key catalog join omits `table_catalog`, which MariaDB does not expose in `TABLE_CONSTRAINTS`; a fixture regression covers that catalog shape. Arch Linux builds also resolve the Go license from its packaged location outside GOROOT.


## Resume here

Read this file, `AGENTS.md`, `docs/query-mode.md`, then `IMPLEMENTATION-FOXQUERYGRIP.findings.md`. Check current code and `git status` before editing; existing staged work belongs to the user. Do not reset, unstage, or overwrite it. Follow the current user instructions for commits and pushes.

`PLAN-FOXQUERYGRIP.md` is the broader design, including ASCII layouts and unfinished proposals. **It is not a completed-feature checklist.** The usage guide and code describe actual behavior. Latest full validation: **785 repository tests**.

## Intent and confirmed decisions

- Lightweight database workspace inside FoxVim, inspired by DataGrip/DBeaver; useful on a slow work machine with roughly 122 tables. Visual understanding and discoverability matter.
- Editor and Query are views of the same project. Future AI mode is outside this implementation.
- All SQL profiles, documents, notes, cache, drivers, exports, and workspace state belong under the project's `.foxnvim/query/`, never global Neovim data. Existing SQLite databases can remain at their configured locations.
- Latest exception requested by user: UI geometry only is global in `stdpath('data')/fox/query-layout.json`; persist resized panes and inspector/connections/help popup sizes across projects. Default diagram split is 30% SQL / 70% diagram. SQL/profiles/results/cache remain project-local; legacy workspace geometry is ignored.
- Support SQLite, MySQL, PostgreSQL; Windows and Linux; connect by normal host/port credentials, Docker agnostic.
- Read-only first; writes later. Most relationships have declared FKs.
- Default layout: connections far left, SQL center, explorer/inspector right, results/activity beneath SQL. Shift+F3 toggles a 30% SQL / 70% diagram layout with no connection sidebar; results stay beneath SQL. Compact terminals use panel toggles.
- **Latest observations supersede the earlier manual-only preference:** SELECT auto-runs after a 900 ms typing pause in both layouts. Only the cursor statement is considered; never automatically execute writes, WITH, or EXPLAIN. Incomplete JOIN predicates and parameterized SQL wait for manual action. Worker validation/read-only enforcement still applies. `:FoxQueryAutoRun` toggles the project setting in RAM.
- SELECT columns highlighted; JOIN/filter columns marked separately; related context tables dimmed. Clicking/selecting a table inspects it. JOIN insertion requires an explicit preview/action.
- Use the existing file explorer for file selection, particularly SQLite; no blind path-entry prompt.
- No Editor / Query entry on the dashboard (removed at user request).

## Current behavior

- F3 cycles Editor ↔ Query directly, preserving SQL buffers/sessions. Ctrl+Alt+O also cycles; `:FoxMode` retains a picker, and `:FoxMode editor/query` selects explicitly. `:FoxModeToggle` is registered in the palette.
- Latest shortcut decision: F3 switches workflow, F2 keeps rename, Shift+F3 (or gV) toggles the Query diagram. F9 is no longer the workflow binding. Every statusline theme shows `[Editor | Query]`, current tab's workflow in normal color and the other dimmed; querying the indicator does not load Query or create project state.
- Ctrl+Enter or F5 runs the statement in Normal/Insert mode. Ctrl+Space or Ctrl+X Ctrl+O opens completion in Insert mode; native and common CSI sequences map explicitly, and completion loads Blink with the database provider. Physical terminal behavior remains unverified. Cached completion supports aliases, unique bare columns, qualified ambiguous columns, and dot triggering in the current statement.
- Query-local Ctrl+h/j/k/l navigate panes; Ctrl+k overrides the editor's file finder locally.
- Results are bordered ASCII tables with explicit row mapping so border/header lines do not trigger row actions. Automatic SELECT also follows caret movement between statements after 900 ms; moving within unchanged SQL is deduplicated. Default-view Ctrl+Enter execution is covered by a real SQLite fixture.
- Normal-mode hints: gC connections, gV diagram toggle (also Shift+F3), gN new query, gE explorer/diagram, gR results, F1 help. Empty results explain setup/execution. Inspector uses a bordered UML-style card with PK/FK/NN flags and columns/indexes/relationships sections. Diagram includes dim unused columns and `?` FK candidate columns for pending JOINs; markers are labels, and Enter/J act in the diagram pane. Removed unexplained entity/M:N descriptions from the live diagram (still available in inspection).
- Connection sidebar: a add, e edit, d delete profile, Enter connect/retry, D disconnect. Delete keeps databases/notes/SQL. The last successful profile ID/fingerprint is project-local `private/session.json`; normal entry/new consoles reconnect without storing credentials. Failure shows a popup and Can't connect badge. Explicit workspace restoration stays disconnected until an explicit connection choice. Worker shutdown is idempotent; Query autocmd setup is idempotent.
- SQLite profile creation opens the existing explorer at the project root; Enter enters folders/selects a file. Cancel leaves the profile unsaved. Selection does not change the project root or open DB bytes in an editor buffer.
- SQL supports statement/selection/section/file execution, bound RAM parameters, cancellation, result provenance, explicit JSON export, table browsing, verified FK row navigation, notes, and schema maps.
- Persistent Go JSONL worker; SQL/passwords travel through stdin, not shell arguments. SQLite, MySQL/MariaDB, and PostgreSQL drivers are compiled into the bundled executables.
- Engine-enforced read-only sessions plus SQL guard; use restricted credentials. SELECT functions/server side effects are not comprehensively sandboxed.
- Query buffers use local storage hooks and avoid swap/undo/backup leaks. Generic editor sessions exclude Query content; explicit query workspace restore starts disconnected and never replays SQL/parameters/results. Query mode suppresses global history persistence and restores editor privacy state on exit.

## Feature file map

Core:

- `lua/fox/query/init.lua` — per-project/per-console state, layouts, mappings, profiles, execution, inspection, notes, JOIN preview, workspace/privacy lifecycle.
- `lua/fox/query/sql.lua` — SQL lexer, execution scopes, limited diagram analysis, safe identifier/JOIN construction.
- `lua/fox/query/completion.lua` — cached Blink SQL completion.
- `lua/fox/query/diagram.lua` — connected ASCII table cards and column-role highlights.
- `lua/fox/query/render.lua` — explorer, UML inspector, schema maps, result formatting.
- `lua/fox/query/storage.lua` — project paths, atomic writes, profiles/cache validation, document buffers, fingerprints.
- `lua/fox/query/layout.lua` — global geometry persistence via the house store; validated/clamped pane ratios and popup sizes, geometry only; tests use isolated temporary paths.
- `lua/fox/query/client.lua` — async Neovim/Go JSONL transport, worker lifecycle/cancellation, local driver lookup.
- `config/tools/repos/foxquery/` — Go driver adapters, read-only enforcement, binding, bounded fetches, metadata, cancellation, and JSONL protocol.

Integration:

- `lua/plugins/fox/tools/query.lua` — lazy loading, Ex commands, F3/Ctrl+Alt+O bindings.
- `lua/plugins/fox/tools/command_palette.lua` — Query actions.
- `lua/plugins/fox/tools/file_explorer.lua` — reusable `on_select_file` callback; preserved through directory navigation; existing folder callbacks unchanged.
- `lua/plugins/fox/tools/workspaces.lua` — explicit project Query snapshots; exclusion from generic sessions.
- `lua/plugins/fox/tools/environments.lua` — project transitions and session exclusion.
- `lua/plugins/fox/editor/buffer_cleaner.lua` — Query-aware close/save/discard handling.
- `lua/plugins/ui/bufferline.lua` — mode-specific buffer visibility and labels.
- `lua/plugins/fox/ui/statusline_picker.lua` — `[Editor | Query]` indicator in all six layouts, theme-aware inactive color, no Query autoload.
- `lua/plugins/ui/dashboard.lua` — Query dashboard entry removed; no current Query entry.
- `lua/plugins/lsp/blink_sources.lua` — register cached database completion source.
- `lua/fox/langs/sql/init.lua`, `lua/fox/langs/init.lua` — optional SQL LanguageManager bundle and registration; fresh installs remain Lua-only.
- `config/scripts/setup-powershell.ps1`, `config/scripts/unsetup-powershell.ps1` — Windows Terminal forwarding and removal for Ctrl+Alt+O, Ctrl+Enter, Ctrl+Space, alongside existing bindings. Actual files are `.ps1`, despite earlier requests calling them `.sh`.

Tests:

- `config/tests/spec/query_spec.lua` — lexer/scopes, roles, joins, diagrams, project storage/validation.
- `config/tests/spec/query_ui_spec.lua` — layouts, direct mode cycling, shortcuts/navigation, session exclusion, real SQLite worker, JOIN insertion, compact mode.
- `config/tests/spec/query_usability_spec.lua` — completion/ambiguity/current statement, UML alignment, SQLite profile picker, shared explorer navigation/callback.
- `config/tests/spec/query_live_spec.lua` — SELECT debounce/guard/parameters, real SQLite execution/restore/failure badges, connection CRUD, key delivery aliases, both layouts, dim columns/FK candidates.
- `config/tests/spec/statusline_spec.lua` — workflow label/highlights/current-tab handling and presence in all statusline themes.
- `config/tools/repos/foxquery/driver_test.go` — disposable SQLite/binding/read-only/caps/cancellation/transport tests.

Docs/design:

- `docs/query-mode.md` — usage, profiles, commands, limits, validation.
- `docs/languages/sql.md` — optional SQL tooling.
- `docs/keybinds.md`, `docs/plugins.md`, `docs/index.md`, `docs/languages.md` — feature discovery/index entries.
- `config/scripts/README.md` — terminal setup instructions.
- `PLAN-FOXQUERYGRIP.md` — rewritten design and ASCII layouts.
- `IMPLEMENTATION-FOXQUERYGRIP.findings.md` — user's usability findings, plus implemented fixes and validation record.
- `DATAGRIP-FUNCIONALIDADES.md` — inspiration inventory, not a requirement to implement all DataGrip features.
- `FOXQUERYGRIP_history.md` — this handoff.

## Validation and production boundary

Latest changes: **785 repository tests passed**, including 27 Query tests; changed Lua files pass StyLua/Luacheck. Temporary Windows Terminal fixtures verified exact escape sequences, idempotent setup, existing shortcut override, uninstall, and unrelated shortcut preservation. Physical keyboard behavior remains unverified; F5 and Ctrl+X Ctrl+O provide alternatives independent of modified Enter/Space.

Earlier authorized production check used the application account, not root: verified **MySQL 5.7.44** (supersedes the initial “5.3” report), read-only setup, bound constants, and a zero-row catalog query. **No business rows read, no production dumps/results saved, no Docker changes.** Credentials were provided in chat; do not copy them into code, notes, profiles, commands, or logs. The latest usability fixes used fixtures only. Do not broaden production checks beyond the user's minimal-information restriction.

Useful commands from repository root:

```text
nvim --headless -u NONE -i NONE -l config/tests/run.lua query
nvim --headless -u NONE -i NONE -l config/tests/run.lua
cd config/tools/repos/foxquery && go test -mod=vendor ./...
```

Never run terminal setup against actual user settings just to test it; use temporary LOCALAPPDATA fixtures.

For the user to activate mappings: restart Neovim; run `./scripts/setup-powershell.ps1` in PowerShell and reopen Windows Terminal for Ctrl+Enter/Ctrl+Space forwarding. F3 needs no custom forwarding.

Latest terminal repair: the active stable Windows Terminal settings had neither forwarding binding. Added only Ctrl+Enter (`ESC[13;5u`) and Ctrl+Space (`ESC[32;5u`) to its actions, preserving other settings and creating a timestamped `.foxquerygrip-*.backup` beside settings.json. No full terminal-setup/visual changes were applied. Reopen Windows Terminal; physical delivery remains unverified. Fixture tests confirm default-view manual execution.

## Known limits / future work

- Live PostgreSQL and Linux integration untested. MySQL/PG driver import was checked on Windows; SQLite fixture integration is exercised.
- Diagram analysis is deliberately partial for CTEs, subqueries, UNION, and complex SQL; not a full semantic SQL parser. Live-analysis cap 128 KiB; cards cap 40 nodes/12 columns with disclosed omissions.
- Four sessions per project. Fetch cap 1,000 rows / 8 MiB per run; table browsing 200 rows; 30-second cancellation timer; metadata cap 20,000 objects per catalog query. Caps do not bound server work or every transient field allocation.
- MySQL truncation closes the unbuffered session to avoid draining unlimited results; reconnect. Uncertain cancellation also requires reconnecting.
- FK result navigation only for verified table-browse origins. JSON export only. Parameters are bound values, not list expansion/native named placeholders.
- Deferred: SQL writes/admin/editable grids/transaction UI, full persistent SQL history, crash-recovery drafts, virtual relationships, CSV export, full complex-SQL diagrams.
- Follow repository rules: language config stays in its language module; optional tools need explicit selection; prefer palette/Ex commands; reuse house UI/explorer; no new leader bindings. Ponytail full: smallest complete fix, meaningful regression checks, report untested limits.


## Implemented follow-up

Latest shortcut/status-bar update: **F3** cycles Editor / Query; **F2** retains rename. **Shift+F3** or **gV** toggles the diagram. The status bar shows `[Editor | Query]` in all themes, using normal color for the current workflow and dimmed color for the other.

1. Diagram shows unused columns dimmed, retaining selected/JOIN/filter emphasis. Missing JOIN predicates show `?` on candidate FK columns on both tables; these remain hints, never silently inserted predicates. Card limits disclose hidden columns; Enter inspects the complete table.
2. New execution preference applied: SELECT at the cursor auto-runs after 900 ms without typing, in both layouts. Writes/WITH/EXPLAIN never auto-run; worker read-only checks still reject SELECT INTO. Unfinished JOIN predicates wait; bound parameters require manual run. Unchanged SQL is deduplicated; requests remain serialized. `:FoxQueryAutoRun` toggles this project setting in RAM.
3. Ctrl+Space explicitly invokes cached database completion via Blink, including common terminal escape sequences. Ctrl+X Ctrl+O is an Insert-mode fallback; `:FoxQueryComplete` is discoverable in the palette.
4. Removed unexplained entity/M:N descriptions from the live diagram. Footer distinguishes column markers from actions and says where to use Enter/J: move the cursor onto a table in the diagram pane. Inspector retains detailed relationship information.
5. Default left connection sidebar: a add, e edit, d delete profile, Enter connect/retry, D disconnect. Last successful profile ID/fingerprint stays project-local in `private/session.json`; normal entry/new consoles restore it without persisting passwords. Failed attempts show a popup and Can't connect badge. Deleting profiles preserves database files/notes/queries. Explicit workspace restore remains disconnected.
6. Ctrl+Enter maps both native keys and common CSI sequences in Normal/Insert mode. F5 is the manual-run fallback in Query SQL buffers. Fixture tests verify actual SQLite execution plus key callbacks; physical terminal delivery is not yet confirmed.
7. Activity now shows submitted SQL or a useful waiting/run hint; removed the obsolete “never executed while typing” message.
8. One Query workspace: Shift+F3 (or gV in Normal mode) toggles the diagram. Default has connections left, SQL center, tables right; diagram layout removes the connection sidebar and splits SQL/diagram 30% / 70% by default. Results remain beneath SQL in both layouts. Initial table-sidebar width accounts for cached table names within screen limits.

Validation: 785 repository tests passed, including 27 Query tests. Regression fixtures cover SELECT debounce/read-only rejection/parameter handling, connection CRUD/restore/failure badges, layouts, dim columns/FK candidates, and native/CSI key callbacks. Changed Lua files pass StyLua/Luacheck. Worker shutdown and Query autocmd setup are now idempotent. No production queries were used for this follow-up.

Restart Neovim. If modified keys still do not arrive from Windows Terminal, rerun `./scripts/setup-powershell.ps1` and reopen Windows Terminal; use F5 and Ctrl+X Ctrl+O in the meantime. Physical terminal behavior, Linux, and live PostgreSQL remain unverified. SELECT can be expensive or invoke server functions despite read-only access.

## Latest table / caret / geometry follow-up

- Results now use bordered ASCII tables, with exact data-row mapping for expand/copy/FK actions across multiple result sets. Borders and headers are not selectable data.
- Automatic SELECT follows the statement at the current caret after 900 ms of typing or caret movement, in either layout. Moving within unchanged SQL does not re-run it; moving to another SELECT does. Read-only/parameter/pending-JOIN guards remain.
- Default Visual distribution is 30% SQL / 70% diagram. Resized pane proportions and inspector/connections/help popup sizes persist across projects in `stdpath('data')/fox/query-layout.json`. Only geometry moved globally; SQL/profiles/cache/results stay project-local. Old workspace-specific geometry no longer overrides global preferences.
- Actual Windows Terminal settings were missing both Ctrl+Enter and Ctrl+Space forwarding. Added only those two `sendInput` bindings, with a timestamped backup beside settings.json; other settings were preserved. Reopen Windows Terminal and restart Neovim. Default-view Ctrl+Enter execution is verified with SQLite; physical key delivery still needs user confirmation.
- Validation: 785 repository tests passed, including 27 Query tests. New checks cover caret movement across statements, manual execution in the default view, ASCII tables/row mapping, and geometry restoration across projects. Changed Lua files pass StyLua/Luacheck. No production SQL was run.

