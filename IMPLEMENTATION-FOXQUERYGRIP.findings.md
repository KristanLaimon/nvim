1.  Some observations

SELECT pk.member_2 
FROM PlayerKisses pk
INNER JOIN Player p;


---

LIVE QUERY DIAGRAM
Draft SQL; no execution | cache 18:47

+--------------------------+       +--------------------------+
| pk                       ........> p                        |
| PlayerKisses             |       | Player                   |
| *   member_2             |       | (no selected columns)    |
   < it should show the               <if no ON of inner join yet
  other columns here but              here should be the candidate column(s)
  fainted color, like                 to make the inner join if i havent written it yet!
  not selected, only member_2
  will have the selected
  color normal as it currently
  has>
+--------------------------+       +--------------------------+

[pk] -- INNER --> [p]: pending predicate
[p] .... [LiveStreamSession] related, not joined
[p] .... [Match_Player_TeamColor_Played] related, not joined
[p] .... [PlayerSecondarynames] related, not joined
[p] .... [Player_Player_Trust] related, not joined
[p] .... [Player_Season_Plays] related, not joined
[p] .... [Player_Titles] related, not joined
[p] .... [TournamentMatch] related, not joined
[p] .... [TournamentMatchup_Player_Played] related, not joined
[p] .... [Tournament_Player_Subscriptions] related, not joined
pk: Possible M:N bridge (composite PK consists of FK columns)
p: Entity | 0 outgoing / 12 incoming FK(s)
* SELECT | k JOIN | f filter | Enter inspect | J Insert JOIN


2. The query should be automatically executed ONLY if it stats with SELECT,
not with update, delete, insert, as they are dangerous operations, this applies
in both submodes of query modes, and result should be in panel below the
code editing panel.

3. Ctrl + space still doesnt work for intelisense, idk if its my powerhsell problem or
something.


4. i don't understand this:
pk: Possible M:N bridge (composite PK consists of FK columns)
p: Entity | 0 outgoing / 12 incoming FK(s)
* SELECT | k JOIN | f filter | Enter inspect | J Insert JOIN
optiosn where should i execute them? wtf


5. There should be a left sidebar with a section with all the connection, the full crud of connections should be there, and by default
always select the last session connection opened if once.
If connection now invalid or can't connect, show popup letting user know that and, make the connection entry text with badge (Can't connect)


6. Important, i can't run the queries!

RESULTS | No execution
Enter: expand row | y: copy row | e: export | gR: follow foreign key

1. gC: choose or add a connection (SQLite opens the file explorer).
2. Write SELECT SQL above; Ctrl+Space opens column/table completion in Insert mode.
3. Ctrl+Enter: run the statement at the cursor; results appear here.
Typing updates the Visual diagram only; it never runs SQL.
gV: Standard / Visual | gN: new query | F3: Editor / Query | F1: help

wtff... with nothing, i can't when using ctrl + enter, nothing happens

7. why this msg?
ACTIVITY | ready | 27 visible tables/views
SQL is never executed while typing

8. instead of 2 separate submodes, better


Make sidebar the actual width for tables in db, is ok, and great

a shortcut to open visual mode wich is the visual submode, which will make no sidebar and instead 1/2 1/2 screen being right the dynamic tables, and that.

---

## Implemented follow-up

Latest shortcut/status-bar update: **F3** cycles Editor / Query; **F2** retains rename. **Shift+F3** or **gV** toggles the diagram. The status bar shows `[Editor | Query]` in all themes, using normal color for the current workflow and dimmed color for the other.

1. Diagram shows unused columns dimmed, retaining selected/JOIN/filter emphasis. Missing JOIN predicates show `?` on candidate FK columns on both tables; these remain hints, never silently inserted predicates. Card limits disclose hidden columns; Enter inspects the complete table.
2. New execution preference applied: SELECT at the cursor auto-runs after 900 ms without typing, in both layouts. Writes/WITH/EXPLAIN never auto-run; worker read-only checks still reject SELECT INTO. Unfinished JOIN predicates wait; bound parameters require manual run. Unchanged SQL is deduplicated; requests remain serialized. `:FoxQueryAutoRun` toggles this project setting in RAM.
3. Ctrl+Space explicitly invokes cached database completion via Blink, including common terminal escape sequences. Ctrl+X Ctrl+O is an Insert-mode fallback; `:FoxQueryComplete` is discoverable in the palette.
4. Removed unexplained entity/M:N descriptions from the live diagram. Footer distinguishes column markers from actions and says where to use Enter/J: move the cursor onto a table in the diagram pane. Inspector retains detailed relationship information.
5. Default left connection sidebar: a add, e edit, d delete profile, Enter connect/retry, D disconnect. Last successful profile ID/fingerprint stays project-local in `private/session.json`; normal entry/new consoles restore it without persisting passwords. Failed attempts show a popup and Can't connect badge. Deleting profiles preserves database files/notes/queries. Explicit workspace restore remains disconnected.
6. Ctrl+Enter maps both native keys and common CSI sequences in Normal/Insert mode. F5 is the manual-run fallback in Query SQL buffers. Fixture tests verify actual SQLite execution plus key callbacks; physical terminal delivery is not yet confirmed.
7. Activity now shows submitted SQL or a useful waiting/run hint; removed the obsolete “never executed while typing” message.
8. One Query workspace: Shift+F3 (or gV in Normal mode) toggles the diagram. Default has connections left, SQL center, tables right; diagram layout removes the connection sidebar and splits SQL/diagram half and half. Results remain beneath SQL in both layouts. Initial table-sidebar width accounts for cached table names within screen limits.

Validation: 783 repository tests passed, including 25 Query tests. Regression fixtures cover SELECT debounce/read-only rejection/parameter handling, connection CRUD/restore/failure badges, layouts, dim columns/FK candidates, and native/CSI key callbacks. Changed Lua files pass StyLua/Luacheck. Worker shutdown and Query autocmd setup are now idempotent. No production queries were used for this follow-up.

Restart Neovim. If modified keys still do not arrive from Windows Terminal, rerun `./scripts/setup-powershell.ps1` and reopen Windows Terminal; use F5 and Ctrl+X Ctrl+O in the meantime. Physical terminal behavior, Linux, and live PostgreSQL remain unverified. SELECT can be expensive or invoke server functions despite read-only access.

