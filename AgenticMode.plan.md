# Agentic Mode — implementation plan and decision questionnaire

Status: implementation started with confirmed F2 shortcut and Codex-only scope. The user authorized implementation and confirmed terminal-specific session ownership: terminal 1 opens its own Codex session; terminal 2 opens its own. Remaining unanswered choices retain their proposed defaults.
Source: [PROMPT.md](PROMPT.md). Repository and provider documentation reviewed on 2026-11-09.

Implementation checkpoint: the Codex adapter, terminal-buffer bindings, F2 mode navigation, adaptive three-panel activity dashboard, Git modal integration, SubEditor return, reported telemetry fallback, read-output estimates, and focused tests are implemented. Plain `codex` in new local Bash/PowerShell terminals starts observation automatically, without opening F2. `:FoxAgenticCodex` also establishes an exact binding and starts observation before launching a new CLI session. Existing terminals and argument-bearing invocations retain the explicit binding fallback; no directory/recency guessing. Observation uses a separate read-only stdio App Server. Spatial dependency graphs, additional providers, persistent dashboard history, and remote attachment remain deferred. See [the current usage guide](docs/agentic-mode.md) for behavior and limits.

Follow-up implementation: plain `codex` in new local Bash/PowerShell terminals now establishes an exact binding and starts observation before opening the Codex TUI. F2 only displays collected activity. This uses a terminal-local launcher, a short-lived headless-Neovim RPC bridge, and the existing Codex adapter; no global shell-profile edits or native-hook trust bypass. Argument-bearing CLI invocations retain their original behavior and manual binding fallback. Previously open terminals need recreation to receive the integration. The dashboard now includes clearly labeled, unattributed workspace-change cards when Codex supplies no file-operation evidence, plus session ID and history-scan counts. Background ownership, real local RPC, PATH resolution, shell argument/exit-code preservation, token isolation, and fallback behavior have focused tests. Scope is local terminals only.

Launcher bug fixed: a blank `thread/start` response did not by itself guarantee a persisted conversation. Closing its temporary server made a later CLI resume fail with “no rollout found”; an independent observer also returned “thread not loaded.” Creation now persists the display name through `thread/name/set` and closes the creator gracefully before launching the TUI. A real regression test uses an isolated temporary Codex home and independently reads/resumes the blank thread without sending a prompt or model turn. Current focused Agentic checks: 16 passed. The broader background checkpoint reported 1,109 passed / the same 5 unresolved full-suite failures listed below. No WSL implementation is included.

Validation checkpoint (Windows): 9 Agentic tests pass, including focused-terminal ownership, independent terminal sessions, replay deduplication, usage semantics, read-only attachment, compact panels, workspace suspension, and SubEditor inspection preserving unsaved text. Related statusline (17), Query UI (4), Git Center (40), terminal focus (2), environments (11), and workspaces (9) checks pass. Live read-only Codex metadata/history access and reported usage fallback were verified; model metadata was outside the bounded transcript tail during that probe and correctly remained unavailable. The full gate passed lint (0 warnings/errors) and syntax, then reported 1,102 passing / 5 failing tests at that checkpoint: dashboard startup timeout, Git Blame palette expectations, Git zip palette expectations, mixed-line-ending replacement, and WakaTime tracking. The two palette expectations reference actions already commented out in HEAD. Replacement (18 tests) and tracking (5 tests) pass in isolation; their full-suite failures remain unresolved. No claim of a fully green full suite or validated Linux/remote workflow.

User requirements below reflect PROMPT.md plus the user's follow-up: use F2 instead of F4; implement only Codex now; keep provider integration modular enough to add Claude, OpenCode, and others later. The follow-up supersedes the original shortcut and provider scope. Recommendations and unanswered questions are not accepted decisions.

## 1. Intended experience

Agentic is FoxVim's third project view alongside Editor and Query. It visualizes work performed by AI CLI agents: files read and changed, context and skills loaded, session/model state, and token usage. It updates while agents work and lets the user inspect their changes without losing their place.

The dashboard has three areas matching the original sketch:

```text
+------------------------------------+----------------------+---------------------+
| Agentic / selected session          | Context / Skills     | Files Changed       |
|                                    |                      |                     |
| File cards and relationships        | Context cards        | path        +12 -3  |
| Read/change status and activity     | Read counts          | path         +4 -0  |
| Per-file read estimates, if known   | Evidence / estimates |                     |
|                                    |                      | Session / model     |
|                                    |                      | Context / usage     |
+------------------------------------+----------------------+---------------------+
| Panel subtotals, session totals, connection / freshness / help                  |
+-------------------------------------------------------------------------------+
```

Cards must have a clear meaning before their arrows are implemented: activity relationships and code dependencies are different kinds of evidence. See Q3.

## 2. Confirmed requirements

- F2 toggles Agentic Mode; F3 remains the Query shortcut. Migrate conflicting F2 actions as described below; F4 keeps its current behavior.
- Codex is the only provider implemented and validated in this delivery. Keep its transport and payload parsing behind a small provider boundary so Claude, OpenCode, and other providers can be added later.
- Show file creations, edits, deletions, additions, model, context availability, and tokens as the source reports updates.
- Track repeated reads and cumulative per-file read usage where feasible; green emphasis was suggested for rereads.
- Navigate files using Vim motions.
- Enter on a changed file opens the existing before/after Git dashboard, with all changed files available and the selected file focused.
- Enter on a context/skill file that was only read opens it in the normal editor.
- Agentic has two submodes: Default (dashboard) and SubEditor (an editor excursion with a quick return action).
- Preserve the selected session, card, viewport, and focus when returning.

## 3. Feasibility and evidence rules

### Observation is not attribution

Filesystem/Git observation proves that a path changed. It cannot prove which agent changed it, which paths were read, or how many tokens those reads consumed. It also sees human edits, formatters, builds, and unrelated jobs.

Use provider events to attribute activity to a session. Unattributed changes remain visible as workspace changes, with an explicit unknown/external label. A proposed patch is pending until successful execution or disk reconciliation confirms it. Failed and declined operations never become successful reads/writes.

### Three telemetry labels

| Label | Meaning | Display |
|---|---|---|
| Reported | The provider supplied this metric for this session/turn | `12,345 reported input tokens` |
| Estimated | Derived from captured content with a named method | `~430 read tokens` |
| Unknown | Missing capability, missing history, or uncertain attribution | `Unavailable`, never `0` |

An exact read-event count does not imply exact billed tokens per file. Reading a file twice can yield two observable reads, but caching, truncation, tool wrappers, conversation replay, and compaction affect actual request usage.

- Count content actually returned by a successful read, not full file size. Partial reads, search snippets, and truncated results need explicit coverage labels.
- If returned content is unavailable, show the read count and unknown token usage. Do not reread full files merely to manufacture an estimate.
- Do not infer a read from a command mentioning a path, a file listing, or a filesystem watcher.
- Separate cumulative session usage from current context occupancy. Historical file reads do not prove the file is still in context after compaction.
- Show used/remaining context and percentages only when compatible occupancy and capacity are known. Model names alone are insufficient to establish capacity.
- Preserve provider input/output/cache/reasoning categories and overlap semantics. Do not add overlapping categories twice.
- Panel estimates are informational subtotals, not extra billable usage. Never add them to provider totals.
- Parent/subagent usage needs documented inclusive/exclusive semantics before aggregation; otherwise show separate totals.
- Model changes split usage by model. Unknown pricing means no invented monetary cost.

Example: a file read twice with returned chunks estimated at 300 and 120 tokens shows `Reads: 2 | ~420 observed read tokens`. A provider session total of 5,000 stays 5,000; the dashboard does not display 5,420.

## 4. Codex integration and provider boundary

### Current delivery: Codex only

Prefer Codex's documented local App Server interface for structured session, lifecycle, command/file-change, and usage observations. Phase 1 must prove attachment to the user's existing interactive Codex session for the installed version. Starting a new App Server does not automatically attach it to an existing CLI.

Record the installed Codex version and validate its protocol using captured, sanitized fixtures. Prefer supported structured events over transcript internals; treat transcript formats as versioned fallbacks only if needed. Terminal text scraping is a detection aid, never the source of exact metrics. Do not inject prompts or silently launch a second agent to obtain telemetry.

Detection order proposal: explicit session attachment, verified Codex handshake/session metadata, then terminal process/command hints. Shell aliases, wrappers, SSH, and terminal titles are not authoritative session IDs. Never scan unrelated session content just to guess the match.

Native Codex approvals, credentials, and permissions remain owned by Codex. Attachment observes work; it must not submit turns, approve operations, or change sandbox settings. Any integration setup must describe its local changes and removal.

### Small extension contract

Keep Codex-specific endpoint selection, protocol handshake, session discovery, event decoding, recovery, and version handling in `lua/fox/agentic/providers/codex.lua`. Dashboard, accounting, Git review, and navigation consume normalized observations rather than Codex payloads.

The provider-facing contract needs only:

- `id` and `capabilities`: supported observations and recovery features.
- `list_sessions(root, callback)`: discover candidate sessions for the requested root without assuming terminal process identity equals session identity.
- `attach(session, emit, on_status)`: establish observation and return a connection with an idempotent `detach()` operation.

Session listing and attachment must report errors asynchronously. Capabilities cover identity, lifecycle, model, reads, writes, context/skills, usage, context capacity, child sessions, and replay/recovery. Unsupported fields render as unavailable. Add further operations only when a real integration requires them.

Inject the selected provider at the Agentic composition boundary; initially that concrete provider is always Codex. Preserve a provider ID in session/event identity. Do not add a provider picker, plugin registry, stub adapters, extra installations, or speculative hook infrastructure for this delivery.

### Later providers

Claude, OpenCode, and others can implement the same observation contract in sibling files. Adding one should require its adapter, composition registration, fixtures/tests, and documentation; it should not require changing dashboard rendering or accounting rules. Any provider-specific feature can remain a capability rather than forcing all providers to implement it.

Other-provider telemetry research and live validation are deferred. No Claude, OpenCode, agy, or Gemini implementation belongs in the current milestones or acceptance gates.

## 5. Navigation and mode lifecycle

F2 is confirmed. Other transition details below are proposed defaults pending Q5–Q6:

| Starting view | Action | Result |
|---|---|---|
| Editor or Query | F2 | Agentic Default for the same project |
| Agentic Default | F2 | Editor |
| Agentic Default | F3 | Query |
| Query | F3 | Editor, preserving current behavior |
| Agentic Default | Enter on changed file | Existing before/after diff with return origin saved |
| Agentic Default | Enter on read-only context/file | SubEditor at that path |
| SubEditor or Agentic-origin diff | Agentic Return / F2 | Restore dashboard selection and viewport |
| Any view | `:FoxMode editor/query/agentic` | Explicit destination |

Here “read-only” describes the observed agent activity; whether SubEditor itself allows edits is Q6.

- Give return behavior an excursion identity scoped to the origin project/tab/window. Do not leak temporary mappings into unrelated editor windows or existing user mappings.
- Nested inspections must have deterministic return behavior. Deleted/closed origin windows fall back to the owning project's dashboard or editor.
- Navigation and UI hiding do not terminate agents. A disconnected adapter and an exited agent are distinct states.
- Preserve unsaved editor buffers, splits, cursor positions, project CWD, and Query sessions.
- Show `[Editor | Query | Agentic]` in the existing view indicator and `Default / SubEditor` when relevant.
- Proposed dashboard controls: `h/j/k/l`, `gg/G`, `Ctrl-d/u`, `/`, Enter; Ctrl-h/j/k/l between panes; Tab/Shift-Tab to cycle panes. Spatial card motion needs a defined nearest-card rule with deterministic tie breaking.
- Keep selection stable during updates; incoming activity must not steal focus or reorder the user's selected card unexpectedly. Follow-latest can be explicit.
- F1/help and palette actions explain the active view's controls. Status, labels, and symbols carry meaning independently of color; provide plain icons when Nerd Fonts are absent.

### Existing shortcut conflicts

F2 currently performs contextual rename in `lua/keymaps/lsp.lua`, picks file history in Git Center, and renames environment/workspace rows in their local pickers. These must be audited so buffer-local or lazy mappings cannot silently shadow the confirmed Agentic shortcut.

Migration plan: reserve F2 for Agentic entry/toggle/return across Editor, Query, terminals, and Agentic-origin inspection buffers. Keep rename available through its existing Ex commands and palette actions; inspect contextual rename's callers and add an explicit command if that action currently exists only as a keybinding. Git file history remains available as `:GitFileHistory` and in the palette. Environment/workspace pickers retain their existing `r` rename actions. Update local F2 mappings, help, palette labels, documentation, and affected tests together. Picker behavior on F2 is an open detail in Q4; the recommendation is to dismiss the picker cleanly and enter Agentic.

F4 terminal/Git/media behavior remains unchanged. Git Center's local F3 history action also remains unchanged unless a separate mode-routing decision requires otherwise. No new leader shortcuts.

## 6. File cards, context, and diff behavior

- Stable file identity combines project/worktree identity and canonical path; agent/session links are separate. Preserve display spelling and OS case rules. Distinguish equal relative paths in different roots.
- A file can be both read and changed. Represent both roles without double-counting totals. Enter prioritizes the diff when a current change exists; an explicit Open File action handles direct editing.
- Read counts and event history survive a rename when the rename is known. Uncertain rename detection must not merge unrelated files.
- Distinguish successful reads, search matches, listed paths, loaded instructions, and activated skills. Finding or reading `SKILL.md` does not prove a provider activated that skill.
- Node previews should be bounded metadata/snippets, not a full-file render per card. External/missing/binary paths need meaningful fallback actions.
- Additions/deletions are separate from token estimates. Binary changes show a binary badge, not fabricated line counts.
- A changed-then-reverted file can remain in session history while disappearing from the current Files Changed list.
- Default diff recommendation: current repository changes, staged + unstaged + untracked, using existing Git semantics. Agent activity is a filter/annotation, not proof that all current changes belong to the agent.
- Current Git modal can show staged and unstaged entries for the same path separately. Choose combined HEAD-to-working-tree versus separate index/worktree review before modifying it.
- No-Git projects, repositories without HEAD, deleted files, submodules, merge conflicts, and missing historical content require explicit fallback states.
- An agent-specific start-of-session diff requires baseline snapshots, especially for an already dirty tree and untracked files. Do not promise that view using HEAD alone.
- If an open buffer is modified while the agent edits its disk file, show a conflict/staleness warning and preserve unsaved text; never silently reload or overwrite it.
- Enter on a missing read-only file explains that it is unavailable. A deleted changed file opens available before content with an empty/deleted after side.
- Large graphs need bounded rendering, lazy detail, filtering, and a small-terminal list alternative. Avoid a separate floating window for every card.

## 7. Minimal architecture and repository integration

Start with Lua and the existing terminal, async process, project-path, UI, and Git helpers. Add no backend or dependency without an observed need. Query's diagram/layout code is a reference; reuse genuinely generic pieces without coupling Agentic to SQL state.

Suggested ownership, with file boundaries chosen as implementation requires:

- `lua/fox/agentic/`: state reduction, dashboard rendering, and excursion lifecycle; `providers/codex.lua` owns the only live provider and receives transport dependencies for isolated fixture tests.
- `lua/plugins/fox/tools/agentic.lua`: lazy registration and user-facing commands.
- Existing `lua/plugins/fox/tools/query.lua`: coordinate shared `FoxMode` routing without making Query depend on Agentic internals. Extract the smallest shared route owner only when necessary to prevent duplicate command registration.
- `lua/plugins/fox/tools/command_palette.lua`: discoverable Agentic actions. This is the current path, despite the older top-level path in AGENTS.md.
- `lua/plugins/fox/dev/terminal.lua`: attachment notifications and F2 mode switching in terminal context, preserving PTY output/job callbacks and existing F4 behavior.
- `lua/keymaps/lsp.lua`, Git Center panel mappings, environment/workspace picker mappings: migrate conflicting F2 actions while retaining rename/history commands and palette access.
- `lua/plugins/fox/git/git_center/modals.lua`: reuse `open_diff_modal(...)`; extend narrowly for reliable selected-path matching, return handling, and agreed diff scope. The separate Log Diff dashboard currently opens commit history, not live working-tree changes.
- Existing statusline/view-indicator owners, project/environment lifecycle, workspace serialization, help, keybind docs, and terminal forwarding: audit and update affected paths.
- `config/tests/spec/agentic_*_spec.lua`, existing Query/Git/terminal specs, and focused integration coverage.
- `docs/agentic-mode.md`, `docs/keybinds.md`, `docs/terminals.md`, `docs/command-palette.md`, wiki/plugin inventories as needed.

Suggested commands: `:FoxMode agentic`, `:FoxAgenticToggle`, `:FoxAgenticSessions`, `:FoxAgenticAttach`, `:FoxAgenticDetach`, `:FoxAgenticReturn`, `:FoxAgenticRefresh`, `:FoxAgenticHelp`. All actions appear in the Command Palette. Clear/persistence commands depend on Q23–Q24.

### Normalized observation contract

Use a small versioned record: provider, session ID, optional parent/turn/tool ID, source event ID or cursor, project/worktree root, source timestamp, receipt time, event kind, and payload. Kinds cover lifecycle, read, proposed/completed change, context/skill, usage, and model. Attach provenance and estimate method where applicable.

Reducers must distinguish absolute usage snapshots from deltas, deduplicate replayed events, and reject invalid field types/oversized payloads without breaking other sessions. One source adapter normalizes events; dashboard code should not parse provider payloads.

Do not assume a total ordering across providers. Preserve known per-source order, mark gaps/stale data, and reconcile current disk/Git state after reconnect. Reconciliation cannot reconstruct missed reads; retain that uncertainty.

## 8. Session scope, storage, and performance

Recommended initial scope: one selected session in one project/worktree, with a session picker and separate state for simultaneous sessions. Cross-session aggregation follows after ownership and accounting rules are proven. Agent control/chat composition is outside the observation-first recommendation pending Q1.

- Switch environments without mixing roots, CWDs, sessions, or return targets. A directory name alone is not project identity.
- Keep observations in RAM initially. If persistence is requested, store minimal versioned metadata under the project's `.foxnvim/agentic/`, excluded from Git; never copy prompts, secrets, complete tool outputs, or credentials there by default.
- Existing provider histories remain provider-owned. Reads outside the workspace should be limited to deliberately attached session sources and relevant context paths, not unrestricted home-directory indexing.
- Raw agent output and paths are untrusted display data: sanitize control sequences, use argv-based process calls and safe path handling, and avoid interpreting model-generated text as editor commands or modelines.
- Use async updates, bounded buffers, and debounced incremental refresh. No full repository Git scan for every stream chunk; avoid watching generated/vendor trees recursively.
- Proposed target: cards update within 500 ms of a received event, Git stats within 1 second after a quiet interval. Provider emission delays are displayed separately and cannot be eliminated by the UI.
- When hidden, preserve observation state with coalesced rendering; choose whether to pause expensive watching in Q25.
- Proposed visible history cap: 1,000 recent events, with aggregate counts retained. Eviction/truncation must be disclosed. Verify performance on 1,000 files/10,000 incoming events before choosing final limits.
- Adapter errors retain last-known state, show its age and an actionable message, and support retry. Neovim shutdown disposes owned timers/connections; attached external agents keep running.

## 9. Delivery phases and exit checks

1. **Codex feasibility spike.** F2 and Codex-only scope are settled. Resolve remaining architectural choices in Q1–Q8; verify attachment against the installed Codex CLI without reading unrelated sessions. Record version/capability fixtures, attachment steps, observed reads/writes/usage, and a reconnect case. If existing-terminal observation lacks required telemetry, present the concrete integration tradeoff before UI implementation.
2. **Mode shell and navigation.** Implement F2/FoxMode/palette/status indicators, migrate conflicting F2 bindings, add the adaptive three-panel layout and Default/SubEditor return lifecycle using fixtures. Verify Editor–Query–Agentic transitions, F2 precedence, mapping cleanup, unsaved buffers, project switching, and unchanged F4 behavior.
3. **Live Codex adapter.** Implement the small provider contract with Codex as the sole concrete provider. Show session identity, capabilities, connection health, and incremental file/context activity. Reconcile Git state. Test duplicate/partial events, failures, reconnect, Codex exit, and changes made by humans alongside Codex.
4. **Review and accounting.** Integrate full before/after diff with selected file and return behavior; implement available reported usage and clearly labeled read estimates. Verify staged/unstaged, untracked/deleted/renamed/binary files, repeat reads, compaction, and child-session accounting.
5. **Provider boundary verification.** Use a small in-memory fixture source to verify that dashboard/accounting/navigation consume normalized observations and capabilities without Codex payload parsing. Document the steps to add a later provider. This is contract verification, not another live adapter or a plugin framework.
6. **Hardening and documentation.** Validate real Windows/Linux Codex workflows, compact terminals, worktrees, Codex upgrades, bounded memory, and workspace restore behavior. Update docs and affected inventories.

Acceptance: F2 enters/toggles/returns from Agentic as specified; F4 retains existing behavior; the live Codex dashboard reflects received events without focus jumps; unsupported metrics are unavailable; file review returns to the correct card; mode switching preserves the editor and Query; no duplicated usage on reconnect; no optional CLI/toolchain installs happen automatically. The Codex adapter is isolated behind the documented observation contract, and no other live provider is implemented.

Testing during implementation: focused `nvim -l config/tests/run.lua <filter> --only-failure`, then relevant Query/Git/terminal regression checks. Before completion, run repository lint, syntax, and tests via the documented `run_me.lua --all --only-failure` entry. Record live-validated capabilities separately from fixture-only behavior and unverified platform workflows.

## 10. Questions and edge cases for the user

Answer by ID; short answers are enough. F2 and Codex-only initial scope are confirmed and do not need reconfirmation. Recommendations on remaining details are offered to reduce decision work, not treated as consent. Q1–Q8 determine architecture and interaction; later questions can be answered in batches.

### First decisions

1. **Q1 — Observer or agent host?** Observe agents you run in terminals, or also launch/send prompts/stop them from this screen? Recommendation: observe first; keep interaction in the existing terminal.
2. **Q2 — Codex session attachment?** Codex-only is confirmed. Observe Codex in FoxVim terminals only, external terminals too, or both? Recommendation: FoxVim terminals first, explicit attachment when identity is ambiguous. Other providers and their launch commands are deferred.
3. **Q3 — Meaning of cards/arrows?** Are cards files, agents, or both? Do arrows mean function/import dependencies, chronological reads/edits, or agent-to-file activity? Recommendation: file cards plus agent activity; code dependency analysis is a separate optional view with its own evidence.
4. **Q4 — F2 inside temporary pickers?** F2 is confirmed and conflicting rename/history actions will retain command/palette access. When an environment/workspace picker is open, should F2 dismiss it and enter Agentic or be inactive until it closes? Recommendation: dismiss cleanly and enter Agentic. F4 retains existing behavior.
5. **Q5 — Cross-mode return?** Should Agentic F2 always return to Editor or to the previously active Editor/Query view? Should F3 from Agentic open Query directly? Recommendation: the transition table above, with F2 available in terminal/insert/visual modes too.
6. **Q6 — SubEditor behavior?** Can you freely edit inspected files, and should Enter on any read-only source file use this submode, or only skills/context? Recommendation: editable normal buffer, F2 returns, excursion exists only for Agentic-origin inspections. What should q/Esc do, and should returning restore unsaved edits in place?
7. **Q7 — Which diff and baseline?** Is Git Center's before/after modal the intended dashboard? Should it show all repository changes, only observed agent files, or session-start changes? Recommendation: all current repository changes first, focused on the selected path; session-start review requires snapshots. Should staged+unstaged be separate entries or one combined comparison?
8. **Q8 — Token precision?** Are labeled per-file estimates acceptable, or should per-file tokens appear only when reported exactly? Recommendation: allow `~estimated`, show unknown when content is unavailable. Does “Total (all)” mean current session plus subagents, all sessions in this project, or all projects?

### Agent/session identity

9. **Q9 — Parallel work?** One selected session, split dashboards, or an aggregate of simultaneous agents? Recommendation: selected session plus picker; separate child agents and optional aggregate only when totals are non-overlapping.
10. **Q10 — Existing sessions?** When attaching halfway through, load earlier history or observe from now? Recommendation: replay only that selected session when supported, label incomplete history, and never add cumulative totals twice. Should resumed/forked chats share history or start new dashboard identities?
11. **Q11 — Wrappers and remote hosts?** Must aliases, WSL, SSH, tmux, containers, or remote agents work in v1? Which do you use? Recommendation: local Windows/Linux first; remote needs explicit host/path mappings and a verified event channel.
12. **Q12 — Model and mode changes?** Does “mode” mean provider plan/build/approval mode as well as FoxVim's view? Recommendation: show them separately, with unknown when not exposed; display per-model usage after model switches.

### File behavior and graph

13. **Q13 — Human/build changes?** Show every workspace change or only agent-attributed changes? Recommendation: retain both with labels, and never credit a watcher event to an agent without evidence. How should multiple agents editing one file be represented?
14. **Q14 — Already dirty workspace?** Include pre-existing edits and edits committed during the session? Recommendation: current Git state plus observed activity history, clearly separated. Historical session diffs require a captured baseline and a retention decision.
15. **Q15 — Missing Git/binary/conflicted files?** Recommendation: metadata/direct-open fallback without Git; binary badge; deleted before content where available; existing merge tools for conflicts. Is a no-Git before/after viewer required in v1?
16. **Q16 — Unsaved buffers?** What should happen when an agent changes a disk file you have unsaved edits in? Recommendation: preserve your buffer and surface the conflict, requiring an explicit comparison/reload/merge action.
17. **Q17 — Renames and reversions?** Keep read history across known renames and show reverted files in activity history? Recommendation: yes; the live changed list only contains current changes.
18. **Q18 — Graph density and motion?** How many files do you typically expect? Spatial h/j/k/l or a linear file order? Autoscroll as new cards arrive? Recommendation: spatial card movement, stable placement, explicit follow-latest, compact list fallback and search.
19. **Q19 — Card contents?** File name/status/read count only, code preview, or last action text? Recommendation: compact metadata by default, selected-card detail preview, no raw reasoning transcript.

### Context and usage semantics

20. **Q20 — Context categories?** Include only skills/instructions or every read file, search snippet, MCP result, and web source? Recommendation: separate source files, instructions/skills, and non-file resources; “read” and “activated” remain distinct.
21. **Q21 — Reread meaning/color?** Count every successful partial read or only whole-file rereads? Recommendation: count successful read operations with partial/full labels, green accent plus `Reads ×N`; color alone is insufficient. Should estimates show both total read volume and unique observed content?
22. **Q22 — Context compaction and billing?** Show historical reads dimmed after context resets, or remove them? Recommendation: preserve history with current-context status unknown unless reported. Do you also want money estimates, cache breakdowns, rate limits, and budget alerts, or just tokens? Money/alerts are outside the initial recommendation.

### Persistence, privacy, and lifecycle

23. **Q23 — Retention?** RAM only, reopen last session after restarting Neovim, or searchable history? Recommendation: RAM first; later persist minimal project metadata with an explicit clear action. Must original before-content survive an editor restart?
24. **Q24 — Sensitive/external paths?** Show global skills and files outside the project? Include ignored files such as `.env`? Recommendation: relevant external paths may appear as metadata, no secret-content preview/storage by default, no broad home scan. Should Clear remove only FoxVim state or also provider-owned history? Recommendation: only FoxVim state.
25. **Q25 — Hidden/closed UI?** Keep collecting while Editor/Query is active? Recommendation: yes while FoxVim runs, rendering only on demand. Closing the dashboard never kills the agent. Should detach discard or retain observations?
26. **Q26 — Multiple projects/worktrees?** Should each environment keep its own selected session and graph, including when two Neovim instances view one project? Recommendation: isolate project/worktree and instance state; shared sessions need deduplication, not shared mutable dashboard files.
27. **Q27 — Failure states?** On disconnect, unsupported CLI version, missing permission, or missed events, should the dashboard retain stale data? Recommendation: yes, prominently show last-update time/gaps and retry; never silently replace unknown usage with zero.
28. **Q28 — Small screens and platforms?** Minimum terminal size and must-have hosts? Recommendation: Windows and Linux; collapse sidebars into switchable panels when narrow, keeping the selected file and session summary reachable.

## 11. Sources and boundaries

- [Codex App Server](https://developers.openai.com/codex/app-server): documented event types support a structured adapter investigation; existing-terminal attachment still needs validation.
- Earlier research into other providers is background only; their adapters, integration setup, and live validation are deferred beyond this Codex-only delivery.
- Local references: `docs/query-mode.md`, `docs/git-center.md`, `lua/plugins/fox/tools/query.lua`, `lua/fox/query/init.lua`, `lua/plugins/fox/dev/terminal.lua`, `lua/plugins/fox/git/git_center/modals.lua`, and `lua/plugins/fox/git/log_diff.lua`.

Not yet verified: live Codex attachment/payloads on this machine, installed Codex version compatibility, remote workflows, and runtime performance. These are feasibility/hardening checks, not promised capabilities. Other providers are outside current delivery scope.
