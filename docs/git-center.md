# 🐙 Interactive Git Control Center (`plugins.fox.git.git_center`)

[← Back to Wiki Index](index.md)

The **Git Control Center** (`<C-S-g>`) is a high-speed, interactive floating Git interface with live VSCode-style diff previews, branch status tracking, and one-key staging/commit/push operations.

While Git Diff Mode is active, notifications appear in the upper left. They return to the upper right when review mode closes. Diff colors survive theme changes.

Review annotations appear as colored virtual rectangles below their source line,
with a `[SUGGESTION]`, `[NOTE]`, or `[ISSUE]` title and line number. They stay out
of the source file and persist in `.foxnvim/review/`. In code panels, Normal-mode
keys are `c` to add, `C` to copy annotations, `da` to delete, `U` to manage sessions,
and `q` / `r` for the previous / next annotation. These keys are listed beneath
the sidebar shortcuts; sidebar keys retain their own actions.

`C` copies **every annotation in the active session across all files**, including
files that are not open. The export includes the session name and total count.
`U` opens a centered menu showing the active session and annotation count. It
offers new/load sessions, clearing the current session, deleting one saved
session, and deleting all saved sessions and annotations. Delete actions require
confirmation. Deleting all sessions starts a fresh empty session; other project
configuration remains intact.

The annotation input shows its type, line number, and controls in the border.
Use `Tab` / `Shift-Tab` to change type, `Enter` to save, `Ctrl-J` for a newline,
and `Esc` to cancel.

Git Center and the multi-terminal pane are mutually exclusive. Opening Git Center hides the terminal without stopping its jobs; opening or selecting a terminal closes Git Center and preserves its cached view. Other windows keep their normal stacking behavior.

---

## ⚡ Highlights

- **Instant Opening (< 30ms)**: Asynchronous status parsing without heavy background Git log scans.
- **Git Submodules & Repository Tabs**: Aesthetic tab bar integrated directly at the top of the control panel with support for Git submodules. Root repository is always on the far-left tab, followed by submodules sorted alphabetically.
- **Persistent Active Tab**: Active submodule tab is saved per-project in `.foxnvim/git-center.json` so re-opening Git Center returns directly to the last active submodule repository.
- **VSCode Live Side-by-Side Diff Preview**: Right-hand preview window and full-screen diff modal (`d`) display side-by-side comparisons (left = before with soft red `-` highlights, right = after with soft green `+` highlights).
- **Branch Management & Checkout (`b`)**: Switch/checkout branches, create new branches, delete branches (with `-D` force delete fallback), and rename branches (`b`).
- **Lazygit-Style Visual Aesthetics**: Vibrant section headers, status badges (`✓` staged green, `M` modified yellow, `?` untracked cyan, `D` deleted red), color-coded keybind badges `[c]`, `[s]`, `[u]`, `[P]`, `[b]`, `[l]`, and capsule repository tab indicators.
- **Commit Log & History Viewer (`l`/`L`) & Full-Page Commit Diff**: Open floating commit history showing `git log --all`. Pressing `<CR>` or `d` on any file listed under "Files Changed" opens the full-screen side-by-side diff modal (`open_diff_modal`) showing that commit file's diff full page!
- **GitKraken-Style Commit Graph Viewer (`g` / `:GitGraph`)**: Interactive dual-pane commit graph with 2 modes (🌿 Current Branch only vs 🌐 `--all` branches, toggleable via `a`). Renders GitKraken visual aesthetics with 8-color branch lanes, circular commit nodes (`●`), pill badges (`[🌿 branch]`, `[☁️ remote]`, `[🏷️ tag]`), short SHA, and relative dates. Supports on-the-fly lazy loading / infinite scroll when navigating down using Vim half-page motions (`d`, `u`, `<C-d>`, `<C-u>`, `j`, `k`, `G`, `gg`). Right preview pane displays full commit metadata, author details, changed files list with status badges, and interactive side-by-side diffs.
- **Staging & Unstaging**: Single file staging/unstaging (`s`/`u`) and bulk staging/unstaging (`S`/`U`) scoped to the selected submodule repository.
- **File & Section Restore**: Discard changes for single file (`r`) or entire section (`R`) with confirmation dialogs.
- **Remote Push**: Execute `git push` (`P`) with automatic upstream tracking detection or interactive remote branch selection.
- **Commit & Tag Box**: Multi-line commit title (`c`), description (`m`), and optional tag (`t`) via the `input_modal` component.
- **VSCode 3-Way Merge Conflict Resolver (`M` / `:GitConflictResolve` / `<leader>gm`)**: Opens a full-screen tiled workspace (like the DAP debugger) with 4 synchronized panels: Left Sidebar (conflicted files with live decreasing counts `(2)` -> `(1)` -> `(0)` and locked to Neo-tree width), Top-Left Current/Ours (highlighted in Green), Top-Right Incoming/Theirs (highlighted in Blue), Bottom editable Result (clean merged code with unlimited undo). Panel jumps: `<C-h>` (Sidebar), `<C-k>` (Current), `<C-l>` (Incoming), `<C-j>` (Result), `<Tab>`/`<S-Tab>`. Conflict actions: Accept Ours (`<C-1>`/`<C-o>`), Accept Theirs (`<C-2>`/`<C-t>`), Accept Both (`<C-3>`/`<C-b>`), Undo resolution (`<C-z>`/`u` - repeatable back to initial state), navigate (`<C-n>`/`<C-p>`), and stage (`<C-s>`).
- **RAM Screen Caching (`<C-S-g>`)**: Closing Git Center while on any subscreen (such as the Commit History Log or Branch Modal) using `<C-S-g>` caches the view and cursor position in RAM. Re-opening with `<C-S-g>` restores you directly to the exact screen where you left off. Closing with `q` or `<Esc>` returns to the main control panel.
- **Git Diff Mode (Same Branch) (`V` / `:GitDiffSameBranch`)**: In-buffer diff comparison highlighting added lines in green and displaying deleted lines via red virtual lines (`-`). By default, compares live working tree changes (both staged & unstaged) against the `HEAD` commit. Supports configurable diff ranges via `c` (`HEAD~N` + working tree, committed history only `HEAD~N..HEAD`, or between 2 chosen commits). Features a docked right sidebar file list with status markers. Selecting a file (`<CR>`, `<Space>`, or click) loads the diff while keeping focus in the sidebar. Navigate between diff modifications directly from the sidebar using `J`/`K`, `n`/`p`, or `]c`/`[c` quietly without toast notifications; the diff sidebar instead displays `<1/# Changes in file>` and `<1/# Changes in total>`, alongside real-time Total diffs (`+`/`-`) and file Subtotal diffs (`+`/`-`) in the bottom diff bar. Return focus to the code editor using `h` or `<Esc>`. Opening changed files from Neo-tree also refreshes the active diff, its selection and the green/red highlights; Neo-tree keeps the diff sidebar available for navigation.

The **Working Tree + Commits until a Branch** scope compares against the merge base with the selected branch, excluding that base commit. Five commits made after branching from `main` contribute only those five commits plus working tree changes. Later commits on `main` are excluded too.

The picker includes local and remote branches. If a local base branch is behind its remote, select the remote ref (for example, `origin/ubuntu`) to exclude changes already present there. Remote refs reflect your last fetch.

`:GitDiffMode` opens a floating card menu. Its three main cards start **Working Tree vs HEAD**, **Working Tree + Last N Commits**, and **Working Tree + Commits until a Branch**. Press `1`–`5` to highlight a card, then `Enter` to confirm; arrows and `Tab` also change the selection. Other Git Diff Modes contains branch comparisons, two commits, and committed history. Advanced contains scope settings, resume, and close. Cards reflow on smaller terminals; `Esc` cancels without changing the diff.
- **Git Diff Mode (Between 2 Branches) (`v` / `:GitDiffBetweenBranches`)**: Dual synchronized split view comparing the same file across two branches or refs (selected via dual Base & Target floating menus with custom branch/ref input prompt). Supports synchronized scrolling (`scrollbind`/`cursorbind`), side-by-side color highlights, and jumping between modifications with `]c`/`[c` or `]d`/`[d`.
- **In-Buffer GitSigns Integration (`gitsigns.nvim`)**: Real-time signcolumn diff indicators (`▎`, ``) and hunk navigation (`]c`/`[c`). See [Keybinds](keybinds.md#git--gitsigns) for full list.

---

## ⌨️ Git Center Shortcuts

| Key | Mode | Action |
| :--- | :---: | :--- |
| `<C-S-g>` / `<Esc>` / `q` | All | Close Git Control Center or active modal |
| `<C-h>` / `<C-H>` | All | Focus Left Panel / Switch to Previous Submodule Tab |
| `<C-l>` / `<C-L>` | All | Focus Right Panel / Switch to Next Submodule Tab |
| `<A-h>` / `<M-h>` | Normal, Visual, Insert, Terminal | Switch to Previous Submodule Tab (Left) |
| `<A-l>` / `<M-l>` | Normal, Visual, Insert, Terminal | Switch to Next Submodule Tab (Right) |
| `M` | Normal | Open 3-Way Merge Conflict Resolver |
| `<leader>gm` | Normal | Open 3-Way Merge Conflict Resolver from anywhere |
| `b` | Normal | Open Branch Management Modal (Create, Delete, Switch, Rename, Dry-Run) |
| `l` / `L` | Normal | Open GitKraken Commit Graph Viewer (`:GitGraph`, 2 modes: Current / `--all`, on-the-fly fetch) |
| `H` / `<F3>` | Normal | Open the Log Diff dashboard for the repository |
| `<F2>` | Normal | Pick a file with the Ctrl+k file finder and open its commit history in Log Diff |
| `t` | Normal | 🧪 Dry-Run Merge simulation (predict conflicts between branches without touching CWD) |
| `T` | Normal | 🧪 Dry-Run Rebase simulation (predict conflicts between branches without touching CWD) |
| `<CR>` (Commit Log) | Normal | Press Enter on file in "Files Changed" to jump directly to its diff |
| `s` | Normal, Visual | Stage selected file or selection |
| `S` | Normal, Visual | Stage all files |
| `u` | Normal, Visual | Unstage selected file or selection |
| `U` | Normal, Visual | Unstage all files |
| `r` | Normal | Discard changes / Restore selected file (with confirmation) |
| `R` | Normal | Discard changes / Restore entire section (with confirmation) |
| `P` | Normal | Push to remote (with confirmation and remote branch selector) |
| `F` | Normal | Fetch |
| `gp` | Normal | Pull using the configured strategy |
| `gP` | Normal | Pull with rebase |
| `gr` | Normal | Rebase current branch onto a selected branch/ref |
| `gc` / `ga` | Normal | Continue / Abort rebase |
| `c` | Normal | Edit Commit Title via `input_modal` |
| `m` | Normal | Edit Commit Description via `input_modal` |
| `t` | Normal | Edit Optional Tag via `input_modal` |
| `C` | Normal | Execute Commit & Tag |
| `<Tab>` / `<S-Tab>` | Normal, Graph | Open full-size details popup / dismiss popup and focus left |
| `<C-S-j>` / `<C-S-k>` | Normal | Scroll right live diff preview window |
| `v` | Normal | Open Git Diff Mode Manager menu (Same branch, 2 branches, commits) |
| `V` | Normal | Toggle Git Diff Mode (Same branch: Live working tree vs HEAD) |
| `<CR>` / `<Space>` / `<LeftMouse>` (Diff Sidebar) | Normal | Select and open file in code window while keeping focus in sidebar |
| `J` / `K` (Diff Sidebar) | Normal | Jump to next / previous diff modification in current viewing file |
| `n` / `p` / `N` (Diff Sidebar) | Normal | Jump to next / previous diff modification in current viewing file |
| `]c` / `[c` or `]d` / `[d` | Normal | Jump to next / previous modification in active diff buffer |
| `c` (Diff Sidebar) | Normal | Configure diff scope / commits behind range |
| `e` / `E` / `z` (Diff Sidebar) | Normal | Export currently diffed files with current code into a `.zip` archive |
| `i` / `I` (Diff Sidebar) | Normal | Import & 3-way merge diff files from a compatible FOX `.zip` archive (with automatic conflict markers `<<<<<<<` / `>>>>>>>` when conflicts occur) |
| `h` / `<Esc>` (Diff Sidebar) | Normal | Return focus to code editor |
| `<F5>` / `<C-r>` | Normal | Refresh Git status |

Fetch, pull, and rebase shortcuts are shown below Commit/Push in section 1 and
work from the main panel and preview for the selected repository. The `F4`
Git actions menu remains available.

---

## Preview layout and Git actions

Git Graph (`l`/`L`) opens at full Git Center width with word wrap so long commit messages and branch names
remain readable. Each commit uses **Hash → Author → Subject → Branches / Tags**;
long branch badges no longer shift the author or message columns. Dates remain
available in commit details. `$` and `0` move to the end and start of the complete
commit line. Press **Space** to peek at changed files, their status, and added/deleted
line counts. The popup loads asynchronously without patches and caches each
commit's result. Space, Esc, or q dismisses it without losing your graph position.
Enter opens the existing full Log Diff dashboard.
Shift+Tab on the graph exits logs mode and returns to Git Center. In the details
popup, Shift+Tab dismisses the popup first; press it again to leave logs.

Normal Git Center opens with full-width browsing and automatically shows its
branch-history sidebar when a branch is selected. F6 toggles the preview manually;
that choice stays active until Git Center closes. Tab opens the details as a full-size popup in front of Git Center; Shift+Tab dismisses it and returns focus to the same selection.

| Key | Action in normal Git Center and graph |
| :--- | :--- |
| `F2` / `F3` | File history picker / repository Log Diff (normal Git Center) |
| `F4` | Git actions menu |
| `F6` | Toggle sidebar preview |
| `F7` | Expand details to the entire Git Center area; press again or Esc to return |
| `F8` | Toggle maximized Git Center geometry |

`H` and `F3` open repository Log Diff; `F2` opens file history. `h` keeps its Vim motion.
Graph's former f canvas shortcut is now F6, preserving the f motion.

In the Diff Mode sidebar, press `s` (or run `:GitDiffRendering`) to toggle Classic
and **Before | After** rendering while keeping the same comparison and selected
file. Press `q` to return to Diff Mode Manager, then `q` again to return to Git Center.

All new actions are also available in the Command Palette and as explicit commands:
`:GitFetch`, `:GitPull`, `:GitPullRebase`, `:GitRebase [branch-or-ref]`,
`:GitRebaseContinue`, `:GitRebaseAbort`, and `:GitActions`. Rebase without an argument
opens a branch picker labelled with the current branch and the destination.
Fetch and pull use the selected repository/submodule's configured remote/upstream.
Pull respects Git's configured strategy; Pull with Rebase explicitly requests rebase.
Operations run asynchronously and refresh open status/history views, including on
failure so conflict state is visible. Continue/Abort are available through the
same menu and palette when a rebase is interrupted. Errors retain Git's diagnostics.

Layout commands are `:GitCenterPreview`, `:GitCenterExpand`, and
`:GitCenterMaximize`; `:GitCommitFiles` peeks at the selected graph commit.

## File history

The logs graph (`l`) uses aligned **📌 Hash**, **👤 Author**, and **💬 Subject**
columns, followed by branch and tag badges; colored
commit dots, merge lanes, and vertical connector rows preserve the graph.

The graph title shows `[b]: Select branches`, `[a]: Mode`, and `[?]: Help`.
The bottom border lists files (`Space`), full diff (`Enter`), details (`Tab`), and
Git actions (`F4`). Press `?` for all shortcuts, including:

| Key | Action in logs graph |
| :--- | :--- |
| `b` | Select branches to display (Space toggles, `s` applies) |
| `a` | Switch between current branch and all branches |
| `L` | Show color legend |
| `t` | Toggle topological/date order |
| `m` | Show/hide lane spacer rows |
| `y` | Copy selected commit SHA |
| `K` | Checkout selected commit |
| `D` | Open full-screen file diff |
| `r` / `F5` | Refresh graph |
| `q` / `Esc` / `Shift+Tab` | Return to Git Center |

In the current-branch graph (`l`), peach-colored **base: branchname** badges mark
shared ancestor commits with other local and remote branches, even when those
branches have advanced beyond that commit. Normal branch-tip badges keep their
usual colors. The current branch and its upstream, symbolic remote aliases,
and branches sharing only the current tip are excluded. Bases remain visible
as older commits load; all-branches mode keeps the normal ref badges only.

These are inferred merge bases, not recorded parent branches: later merges or
rebases can change them. Deleted branches cannot be labeled, and remote names
reflect the last fetch. Press `L` in the graph for the color legend.

In Neo-tree, press `gH` on a file to open its commit history in the existing
four-panel Log Diff dashboard. Directories are ignored. In Git Center, `F2`
opens the same file finder as `Ctrl+k`, rooted at the active repository or
submodule. Select a file with Enter to open its history.

The Command Palette also provides **Git File History (Select File)**.
Use `:GitFileHistory` to pick a file, or `:GitFileHistory path/to/file` directly.
History is limited to commits touching that exact path (up to 120 commits,
matching Log Diff); it does not follow earlier names after a rename. Branch
selection, all-branches mode, refresh, and commit navigation retain the file filter.
Files without commits show an informational message.

## 🔧 Customizing

Everything tunable lives in `M.settings` at the top of
[`lua/plugins/fox/git_center.lua`](../lua/plugins/fox/git_center.lua)
— sizes, filenames, delays. To make the panel take up (almost) the whole
screen instead of the default 92%×85%:

```lua
-- lua/plugins/fox/git_center.lua
M.settings = {
    width_ratio = 0.98,   -- was 0.92
    height_ratio = 0.95,  -- was 0.85
    left_ratio = 0.30,    -- unchanged: file list stays 30% of that width
    -- ...
}
```

Save, restart (or `:Lazy reload fox_git_center`), reopen with `<C-S-g>`. Same
pattern for `modal_width_ratio`/`modal_height_ratio` (the full-screen diff
modal opened with `d`) or `editor_width_ratio`/`editor_height` (the commit
message box opened with `c`/`m`/`t`).

To change a keybind (e.g. `P` for push feels wrong), search this same file for
the key's *current* mapping — Git Center's keys are wired inside its own
buffer-local `map_keys` function rather than a flat `M.settings.keys` table
(too many context-dependent bindings for that to stay simple), so `grep -n
'"P"' lua/plugins/fox/git_center.lua` finds the exact `vim.keymap.set` call to
edit directly.

---

## 🔍 Inline Git Blame (local)

FoxVim implements inline blame in `fox.git.inline_blame`, using the shared FOX Git command builder. Queries run asynchronously against the file’s repository, including nested repositories and WSL paths, and include unsaved buffer text. Late responses are discarded after edits or buffer changes.

### Features:
- **Inline Virtual Text**: Displays `  <author>, <date> • <summary>` at the end of the active cursor line.
- **Relative Dates**: Shows relative time format (e.g., `2 hours ago`, `3 days ago`) matching VS Code.
- **Smart Highlighting**: Italicized, subtle text dynamically linked to the active colorscheme's `Comment` highlight.
- **Filetype Gating**: Automatically suppressed in explorer, picker, help, and popup buffers (`neo-tree`, `TelescopePrompt`, `alpha`, `dashboard`, `help`, `gitcommit`, `lazy`, `mason`).

### Commands & Palette Actions:
- `:GitBlameToggle` — Toggle inline virtual text on / off.
- `:GitBlameOpenCommitURL` — Open commit in web browser.
- `:GitBlameCopySHA` — Copy commit SHA hash to clipboard.
- `:GitBlameCopyCommitURL` — Copy web commit URL to clipboard.
- `:GitBlameOpenFileURL` — Open file at commit in web browser.
- All actions are discoverable via Command Palette (`<C-S-p>`).

---

## 📦 Binary Files Blacklist & Safe Preview

Git repositories frequently track binary assets (e.g. `.zip`, `.img`, `.png`, `.jpg`, `.pdf`, `.exe`, `.tar.gz`, `.sqlite3`). In text-based diff viewers, attempting to read raw bytes causes NUL-byte encoding exceptions, corrupted buffer rendering, or infinite parsing loops.

Git Center implements an internal **Binary Blacklist & Safe Preview Handler**:
- **Blacklisted Extensions**:
  - Archives: `.zip`, `.tar`, `.gz`, `.tgz`, `.bz2`, `.7z`, `.rar`, `.xz`, `.zst`, `.iso`, `.jar`, `.apk`
  - Images: `.img`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.bmp`, `.ico`, `.webp`, `.tiff`, `.psd`
  - Executables & Bytecode: `.exe`, `.dll`, `.so`, `.dylib`, `.bin`, `.class`, `.pyc`, `.wasm`, `.o`
  - Documents & Media: `.pdf`, `.epub`, `.mp3`, `.mp4`, `.wav`, `.avi`, `.mov`, `.mkv`
  - Databases: `.db`, `.sqlite`, `.sqlite3`, `.pcap`, `.dat`
- **Safe Rendering**:
  - Automatically identifies blacklisted extensions via `diff.is_binary_file(filename)`.
  - Detects `Binary files ... differ` git output headers and embedded NUL bytes (`\0`).
  - Renders clean fallback banners: `[ 📦 Binary File: <filename> - Preview & diff analysis disabled ]`.
  - Suppresses Tree-sitter parsing and line diff highlighting on binary files to ensure rock-solid stability.


### Git Diff file preview tab

Browsing files in Same Branch Diff Mode uses one temporary **[Diff]** buffer tab.
Selecting another entry replaces that preview. Closing Diff Mode removes its
temporary tab; previously open, edited, and pinned files stay open. The existing
Git Diff sidebar, navigation, highlights, and two-branch comparison panes keep
their behavior.
