# FoxQuerier / FOXQUERYGRIP — resume notes

Updated: 2026-10-22. Repository: `C:/Users/USER/AppData/Local/nvim`.

## Resume here

Read this file, `AGENTS.md`, `docs/query-mode.md`, then `IMPLEMENTATION-FOXQUERYGRIP.findings.md`. Check current code and `git status` before editing; existing staged work belongs to the user. Do not reset, unstage, or overwrite it. No commits were requested.

`PLAN-FOXQUERYGRIP.md` is the broader design, including ASCII layouts and unfinished proposals. **It is not a completed-feature checklist.** The usage guide and code describe actual behavior. Latest full validation: **783 repository tests**.

## Intent and confirmed decisions

- Lightweight database workspace inside FoxVim, inspired by DataGrip/DBeaver; useful on a slow work machine with roughly 122 tables. Visual understanding and discoverability matter.
- Editor and Query are views of the same project. Future AI mode is outside this implementation.
- All SQL profiles, documents, notes, cache, drivers, exports, and workspace state belong under the project's `.foxnvim/query/`, never global Neovim data. Existing SQLite databases can remain at their configured locations.
- Support SQLite, MySQL, PostgreSQL; Windows and Linux; connect by normal host/port credentials, Docker agnostic.
- Read-only first; writes later. Most relationships have declared FKs.
- Default layout: connections far left, SQL center, explorer/inspector right, results/activity beneath SQL. Shift+F3 toggles a half-width SQL/diagram layout with no connection sidebar; results stay beneath SQL. Compact terminals use panel toggles.
- **Latest observations supersede the earlier manual-only preference:** SELECT auto-runs after a 900 ms typing pause in both layouts. Only the cursor statement is considered; never automatically execute writes, WITH, or EXPLAIN. Incomplete JOIN predicates and parameterized SQL wait for manual action. Worker validation/read-only enforcement still applies. `:FoxQueryAutoRun` toggles the project setting in RAM.
- SELECT columns highlighted; JOIN/filter columns marked separately; related context tables dimmed. Clicking/selecting a table inspects it. JOIN insertion requires an explicit preview/action.
- Use the existing file explorer for file selection, particularly SQLite; no blind path-entry prompt.
- No Editor / Query entry on the dashboard (removed at user request).

## Current behavior

- F3 cycles Editor ↔ Query directly, preserving SQL buffers/sessions. Ctrl+Alt+O also cycles; `:FoxMode` retains a picker, and `:FoxMode editor/query` selects explicitly. `:FoxModeToggle` is registered in the palette.
- Latest shortcut decision: F3 switches workflow, F2 keeps rename, Shift+F3 (or gV) toggles the Query diagram. F9 is no longer the workflow binding. Every statusline theme shows `[Editor | Query]`, current tab's workflow in normal color and the other dimmed; querying the indicator does not load Query or create project state.
- Ctrl+Enter or F5 runs the statement in Normal/Insert mode. Ctrl+Space or Ctrl+X Ctrl+O opens completion in Insert mode; native and common CSI sequences map explicitly, and completion loads Blink with the database provider. Physical terminal behavior remains unverified. Cached completion supports aliases, unique bare columns, qualified ambiguous columns, and dot triggering in the current statement.
- Query-local Ctrl+h/j/k/l navigate panes; Ctrl+k overrides the editor's file finder locally.
- Normal-mode hints: gC connections, gV diagram toggle (also Shift+F3), gN new query, gE explorer/diagram, gR results, F1 help. Empty results explain setup/execution. Inspector uses a bordered UML-style card with PK/FK/NN flags and columns/indexes/relationships sections. Diagram includes dim unused columns and `?` FK candidate columns for pending JOINs; markers are labels, and Enter/J act in the diagram pane. Removed unexplained entity/M:N descriptions from the live diagram (still available in inspection).
- Connection sidebar: a add, e edit, d delete profile, Enter connect/retry, D disconnect. Delete keeps databases/notes/SQL. The last successful profile ID/fingerprint is project-local `private/session.json`; normal entry/new consoles reconnect without storing credentials. Failure shows a popup and Can't connect badge. Explicit workspace restoration stays disconnected until an explicit connection choice. Worker shutdown is idempotent; Query autocmd setup is idempotent.
- SQLite profile creation opens the existing explorer at the project root; Enter enters folders/selects a file. Cancel leaves the profile unsaved. Selection does not change the project root or open DB bytes in an editor buffer.
- SQL supports statement/selection/section/file execution, bound RAM parameters, cancellation, result provenance, explicit JSON export, table browsing, verified FK row navigation, notes, and schema maps.
- Persistent Python JSONL worker; SQL/passwords travel through stdin, not shell arguments. SQLite standard library; optional PyMySQL/psycopg installed explicitly into project-private drivers. Nothing heavy auto-installs.
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
- `lua/fox/query/client.lua` — async Neovim/Python JSONL transport, worker lifecycle/cancellation, local driver lookup.
- `scripts/query_bridge.py` — driver adapters, read-only enforcement, binding, bounded fetches, metadata, cancellation.

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
- `scripts/setup-powershell.ps1`, `scripts/unsetup-powershell.ps1` — Windows Terminal forwarding and removal for Ctrl+Alt+O, Ctrl+Enter, Ctrl+Space, alongside existing bindings. Actual files are `.ps1`, despite earlier requests calling them `.sh`.

Tests:

- `tests/spec/query_spec.lua` — lexer/scopes, roles, joins, diagrams, project storage/validation.
- `tests/spec/query_ui_spec.lua` — layouts, direct mode cycling, shortcuts/navigation, session exclusion, real SQLite worker, JOIN insertion, compact mode.
- `tests/spec/query_usability_spec.lua` — completion/ambiguity/current statement, UML alignment, SQLite profile picker, shared explorer navigation/callback.
- `tests/spec/query_live_spec.lua` — SELECT debounce/guard/parameters, real SQLite execution/restore/failure badges, connection CRUD, key delivery aliases, both layouts, dim columns/FK candidates.
- `tests/spec/statusline_spec.lua` — workflow label/highlights/current-tab handling and presence in all statusline themes.
- `tests/query/test_bridge.py` — disposable SQLite/binding/read-only/caps/cancellation/transport tests.
- `tests/query/remote_check.py` — explicitly authorized minimal remote smoke check; privately prompts for password.

Docs/design:

- `docs/query-mode.md` — usage, profiles, commands, limits, validation.
- `docs/languages/sql.md` — optional SQL tooling.
- `docs/keybinds.md`, `docs/plugins.md`, `docs/index.md`, `docs/languages.md` — feature discovery/index entries.
- `scripts/README.md` — terminal setup instructions.
- `PLAN-FOXQUERYGRIP.md` — rewritten design and ASCII layouts.
- `IMPLEMENTATION-FOXQUERYGRIP.findings.md` — user's usability findings, plus implemented fixes and validation record.
- `DATAGRIP-FUNCIONALIDADES.md` — inspiration inventory, not a requirement to implement all DataGrip features.
- `FOXQUERYGRIP_history.md` — this handoff.

## Validation and production boundary

Latest changes: **783 repository tests passed**, including 25 Query tests; changed Lua files pass StyLua/Luacheck. Earlier driver validation passed **9 Python tests** and parsed **780 Lua files**. Temporary Windows Terminal fixtures verified exact escape sequences, idempotent setup, existing shortcut override, uninstall, and unrelated shortcut preservation. Physical keyboard behavior remains unverified; F5 and Ctrl+X Ctrl+O provide alternatives independent of modified Enter/Space.

Earlier authorized production check used the application account, not root: verified **MySQL 5.7.44** (supersedes the initial “5.3” report), read-only setup, bound constants, and a zero-row catalog query. **No business rows read, no production dumps/results saved, no Docker changes.** Credentials were provided in chat; do not copy them into code, notes, profiles, commands, or logs. The latest usability fixes used fixtures only. Do not broaden production checks beyond the user's minimal-information restriction.

Useful commands from repository root:

```text
nvim --headless -u NONE -i NONE -l tests/run.lua query
nvim --headless -u NONE -i NONE -l tests/run.lua
python -B -m unittest discover -s tests/query -v
```

Windows sandbox can block Python subprocess/temp-file access; the successful fixture runs needed reviewed escalation. This is not evidence of a product failure. Never run terminal setup against actual user settings just to test it; use temporary LOCALAPPDATA fixtures.

For the user to activate mappings: restart Neovim; run `./scripts/setup-powershell.ps1` in PowerShell and reopen Windows Terminal for Ctrl+Enter/Ctrl+Space forwarding. F3 needs no custom forwarding.

## Known limits / future work

- Live PostgreSQL and Linux integration untested. MySQL/PG driver import was checked on Windows; SQLite fixture integration is exercised.
- Diagram analysis is deliberately partial for CTEs, subqueries, UNION, and complex SQL; not a full semantic SQL parser. Live-analysis cap 128 KiB; cards cap 40 nodes/12 columns with disclosed omissions.
- Four sessions per project. Fetch cap 1,000 rows / 8 MiB per run; table browsing 200 rows; 30-second cancellation timer; metadata cap 20,000 objects per catalog query. Caps do not bound server work or every transient field allocation.
- MySQL truncation closes the unbuffered session to avoid draining unlimited results; reconnect. Uncertain cancellation also requires reconnecting.
- FK result navigation only for verified table-browse origins. JSON export only. Parameters are bound values, not list expansion/native named placeholders.
- Deferred: SQL writes/admin/editable grids/transaction UI, full persistent SQL history, crash-recovery drafts, virtual relationships, CSV export, full complex-SQL diagrams.
- Follow repository rules: language config stays in its language module; optional tools need explicit selection; prefer palette/Ex commands; reuse house UI/explorer; no new leader bindings. Ponytail full: smallest complete fix, meaningful regression checks, report untested limits.
