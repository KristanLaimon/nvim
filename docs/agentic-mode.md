# Agentic Mode (Codex)

[Back to Wiki](index.md)

Run plain **`codex`** in a new local FoxVim terminal to start tracking automatically in the background. **F2** opens the activity already collected for that terminal; it is not required to start observation. Outside a terminal, F2 uses the selected terminal slot. **F3** opens Query; **F4** retains its terminal/Git/media behavior. Rename moved to **`:FoxRename`** and the Command Palette.

## Terminal ownership

Bindings belong to terminal buffers, not project folders or reusable slot numbers. Terminal 1 and terminal 2 can observe different Codex sessions in the same project without sharing counters or selection.

- **Plain `codex`, without arguments:** local Bash and PowerShell terminals receive a terminal-only launcher in PATH. It creates a session using your Codex configuration, persists it with the initial display name `Codex / <project>`, registers its exact ID with the owning terminal, starts the observer, and opens the normal Codex TUI through `codex resume <id>`. No dashboard opens and no shell profile, authentication setting, or approval policy is changed. Other shells and terminals outside FoxVim keep their usual command.
- **Start in another terminal slot:** `:FoxAgenticCodex` or **Agentic: Start Codex in New Terminal** starts observation immediately in an unused slot, also without requiring F2.
- **Terminals already open before this update:** recreate the shell after finishing the current work, or restart FoxVim, to receive the terminal-local integration. Existing running sessions retain the explicit picker/`:FoxAgenticBind` fallback. Nothing interrupts the current Codex process.
- **Other Codex invocations:** commands with arguments, including help, exec, custom flags, and resume pickers, pass through unchanged. They do not establish an automatic new binding; use `s`/`:FoxAgenticBind` for those sessions. FoxVim does not infer identity from recency, title, or folder, even if only one candidate exists.
- **No matching candidate / changed directory:** obtain the session ID from Codex `/status`, open Agentic from that terminal, then run `:FoxAgenticBind <id>`. The selected session's reported directory becomes the dashboard's Git root.
- **Different chat in the same terminal:** press `s` and rebind. A manually started CLI switching chats does not expose a verified terminal-to-thread mapping; the observer cannot detect that switch automatically.

Destroying a terminal buffer disposes its observer. A new buffer in the same slot starts without the old binding. Hiding Agentic or a terminal never stops Codex. Exiting a tracked CLI allows a final history refresh, disconnects observation, and retains collected activity in RAM. Running plain `codex` again binds the new session and resets that terminal's counters. Binding tokens are not inherited by Codex tools or child agents.

## Dashboard and review

The left pane shows file cards with read/edit counts and cumulative observed patch additions/deletions. Current Git changes also appear as cards when Codex has not reported corresponding file operations; these explicitly say **Workspace change; agent attribution unavailable**. This avoids an empty graph while keeping human/build changes distinct from agent observations. An empty attached session shows how many history turns/items were scanned. The middle pane lists observed reads, with instruction/skill filenames labeled as context candidates. This is not proof that a skill was activated. The right pane lists **all current Git changes**, including changes made by you or other processes, plus the exact session ID, metadata, and usage.

Use native Vim motions (`h/j/k/l`, `gg/G`, `Ctrl-d/u`, `/`), **Tab / Shift-Tab** to cycle panels, and **Ctrl-h/j/k/l** to navigate split panes. Narrow terminals show one panel at a time; Tab switches the visible panel. Reread files use a green highlight and an explicit count.

**Enter** on a currently changed file opens the existing before/after Git modal, focused on that path and staged/unstaged variant. Its file switching still includes all repository changes. **F2**, **q**, or **Esc** closes this Agentic-origin diff and returns to the dashboard.

Enter on a file without a current change opens it in the editor (**SubEditor**). F2 returns to the dashboard and restores its panel/cursor/scroll position. Unsaved editor text is preserved; inspecting a file opens a split when the editor buffer is modified. Missing files show a warning. Without Git, read-file inspection still works and the change pane explains that Git is unavailable.

Cards are an activity list in this first implementation. Import/function-call dependency edges and a spatial dependency graph are not implemented.

## Telemetry and limits

The adapter starts a local **stdio App Server** as a read-only history client. It polls selected-thread metadata and up to the latest 100 persisted turns once per second. Git status updates every two seconds while the dashboard exists. Provider persistence can delay visibility. Detaching stops the observer, not the CLI. Session discovery is limited to the requested exact directory and up to 1,000 candidates.

The observer never sends turns, resumes threads, changes approval policies, or answers approvals. `:FoxAgenticCodex` is the separate explicit action that creates a thread and launches its TUI.

- **Reads** use Codex's best-effort command classification and successful exit status. Shell commands not classified as reads, MCP reads, truncated/missing history, and implicit instruction loading may be absent. Listings and searches do not count as reads.
- **Per-file estimates** are returned-output characters divided by four, rounded up, only for commands classified as exactly one read. They include output formatting, exclude unknown/multi-file attribution, and are labeled `~`. These are not exact model tokens or billing. Totals with incomplete coverage remain partial estimates.
- **Reported session usage, model, and collaboration mode** use supported notifications when supplied, plus a version-sensitive fallback that reads only the last 512 KiB of the attached session's JSONL transcript. Missing/changed schemas, partial records, and older telemetry outside that tail show unavailable or retain the last observed value. No transcript, prompt, or tool output is copied into project storage.
- Cached input/reasoning are displayed as categories without adding them again to the reported total. Last-request tokens versus model context capacity are shown when reported; this is not a guaranteed current remaining-context estimate.
- Replayed items are deduplicated by turn/item/operation identity. Cards describe observed session history; the Git list describes current workspace state. A reverted file can remain on a card after leaving the Git list.

State is in RAM and is not restored after restarting Neovim. Workspace saves suspend the dashboard while serializing editor state; environment/workspace switches hide it without mixing terminal bindings. Claude, OpenCode, remote Codex servers, and other providers are deferred. The provider module owns protocol parsing; the dashboard consumes normalized observations and can accept future adapters.

## Commands

| Command | Action |
|---|---|
| `:FoxMode agentic` / `:FoxAgenticToggle` | Open / toggle the dashboard. |
| `:FoxAgenticCodex` | Start a new Codex session in an unused terminal with an exact binding. |
| `:FoxAgenticSessions` | Pick a session for this dashboard's terminal (`s`). |
| `:FoxAgenticBind <id>` | Bind an exact ID from Codex `/status`. |
| `:FoxAgenticReturn` | Return from inspection to the last dashboard. |
| `:FoxAgenticRefresh` | Refresh or reconnect (`r`). |
| `:FoxAgenticDetach` | Disconnect observation while leaving Codex running. |
| `:FoxAgenticHelp` | Show controls and telemetry limits (`F1`). |

Requires a recent Codex CLI providing `app-server`, `thread/read`, and `thread/turns/list` with full items. Live metadata/history retrieval was verified on the installed Windows Codex during development. See [official App Server documentation](https://developers.openai.com/codex/app-server); transcript parsing is a compatibility fallback rather than a stable API contract.
