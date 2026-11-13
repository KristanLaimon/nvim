| Requirements  |  Technical Design  |  Delivery Steps

Overview & Goals
Add a code review annotation system to Git Diff Mode and Git Log Diff Mode, inspired by tuicr.dev. Users can place typed notes (annotations) on any line while reviewing diffs, persist them per-project, and export them as structured Markdown to the clipboard for sharing with AI agents.

User Stories
1. As a reviewer, I want to press a single key on any line in diff mode to create an annotation, so I can leave inline review comments.
2. As a reviewer, I want annotations to have a type tag ([SUGGESTION], [ISSUE], [NOTE]), so I can classify my feedback.
3. As a reviewer, I want annotations to persist across sessions in .foxnvim/review/, so I don't lose my notes.
4. As a reviewer, I want to copy all annotations to my clipboard as structured Markdown, so I can paste them to an AI agent or chat.
5. As a reviewer, I want to see annotation markers in the diff view, so I know which lines have notes.

Functional Requirements
• Create annotation: Press a in diff mode (editor window) to open a prompt for the annotation text. A type selector ([SUGGESTION], [ISSUE], [NOTE]) appears.
• Annotation data: Each annotation stores: file path, line number, type tag, text, and a timestamp.
• Persistence: Annotations saved to .foxnvim/review/<unique_id>.json per project, linked to the current diff context (staged/unstaged or commit hash).
• Visual markers: Annotated lines show a colored virtual text badge (e.g., 📝 SUGGESTION) in the gutter.
• Export to clipboard: Press A (Shift+a) to copy all annotations as formatted Markdown to clipboard (works on Windows & Linux via + and * registers).
• Delete annotation: Hover over an annotation marker and press d to delete it.
• Jump between annotations: ]a / [a to navigate to next/previous annotated line.

Export Format (Markdown to Clipboard)
## Session: <random_name> | <unique_id>
I reviewed your code and have the following comments. Please address them.
======================================================================
Reviewing unstaged changes:
1. [SUGGESTION] `src/auth.rs:49` - Silent swallow of expiry context
   when claims.exp <= now. Surface the timestamp so the
   error message can include it.
2. [ISSUE] `src/auth.rs:102` - Pull TOKEN_TTL_SECS into a config
   struct so tests can override it without recompiling.
======================================================================

Scope
• In Scope: Git Diff Mode (same_branch + between_branches), Git Log Diff Mode, new lua/plugins/fox/git/review.lua module, .foxnvim/review/ JSON storage, clipboard export.
• Out of Scope: Pushing annotations to GitHub/GitLab PRs (tuicr-style forge integration), multi-line range annotations (line-level only for v1).

Non-Functional Requirements
• Cross-platform clipboard (Windows + register, Linux * register).
• Annotations survive Neovim restarts within the same project.
• No impact on fresh setup (no extra Mason packages needed).
















 Requirements  Technical Design  Delivery Steps

Current Implementation
• lua/plugins/fox/git/diff_mode.lua (3728 lines): Manages Git Diff Mode with sidebar file list, editor window highlights, blame column, and buffer-local keymaps. Uses namespaces (M.namespace) for extmarks/virtual text. Shortcuts in sidebar: j/k/CR/Space/J/K/h/q/s/c/B/e/<,>/]c/[c. Editor (between branches): J/K/H/L.
• lua/plugins/fox/git/log_diff.lua (1521 lines): 4-panel dashboard with files, logs, before/after code panels. Buffer-local keymaps on all 4 buffers. Shortcuts: j/k/J/K/f/l/b/a/y/K/r/]c/[c.
• lua/fox/core/project.lua: config_path() resolves .foxnvim/<name> per-project; config_dir() ensures .foxnvim/ exists.
• Clipboard pattern: vim.fn.setreg("+", text) + vim.fn.setreg("*", text) (used in log_diff.lua:1395 and graph_viewer.lua:1212).
• input_modal (lua/plugins/fox/ui/input_modal.lua): Reusable floating prompt with label, default_value, callback.

Key Decisions
1. Shortcut: a (lowercase) to create annotation, A (Shift+a) to export to clipboard, ]a/[a to jump between annotations. These letters are not used in either diff_mode or log_diff.
2. Separate module: lua/plugins/fox/git/review.lua — keeps the annotation logic isolated and reusable by both diff_mode.lua and log_diff.lua.
3. Storage: .foxnvim/review/<context>.json where <context> is unstaged, staged, or <commit_hash>. Each JSON file is an array of annotation objects.
4. Visual markers: Virtual text (extmarks) in a dedicated namespace (fox_git_review) on the annotation line, showing a colored badge like 📝 SUGGESTION.
5. Type selection: vim.ui.select prompt with 3 options (SUGGESTION, ISSUE, NOTE), defaulting to SUGGESTION.

Proposed Changes
New Module: lua/plugins/fox/git/review.lua
• State: M.annotations = {} (in-memory), M.namespace for extmarks.
• M.add_annotation(file_path, line_nr, cwd): Opens type selector → input modal → saves annotation.
• M.export_to_clipboard(cwd, mode): Gathers all annotations for current context, formats as Markdown, copies to + and * registers.
• M.render_annotations(bufnr, file_path, cwd): Draws virtual text badges on annotated lines.
• M.delete_annotation(file_path, line_nr, cwd): Removes the annotation under cursor.
• M.jump_next_annotation() / M.jump_prev_annotation(): Navigate between annotated lines.
• M.load_annotations(context, cwd) / M.save_annotations(context, cwd): JSON persistence.
• M.get_context_key(mode, state): Returns "unstaged", "staged", or <commit_hash>.

Integration in diff_mode.lua
• Require review module.
• Add buffer-local keymaps in editor windows (same_branch and between_branches):
• a → review.add_annotation()
• A → review.export_to_clipboard()
• da → review.delete_annotation()
• ]a / [a → jump next/prev
• Call review.render_annotations() after apply_same_branch_highlights() and in open_file_between_branches().
• Call review.render_annotations() in close() cleanup.

Integration in log_diff.lua
• Require review module.
• Add buffer-local keymaps on before_buf and after_buf:
• a → review.add_annotation()
• A → review.export_to_clipboard()
• da → review.delete_annotation()
• ]a / [a → jump next/prev
• Call review.render_annotations() after loading file content.

Data Model (JSON)
[
  {
    "file": "src/auth.rs",
    "line": 49,
    "type": "SUGGESTION",
    "text": "Silent swallow of expiry context...",
    "timestamp": 1719000000
  }
]

File Structure
lua/plugins/fox/git/review.lua          [NEW]  — Core annotation module
lua/plugins/fox/git/diff_mode.lua       [MOD]  — Integrate review keymaps + rendering
lua/plugins/fox/git/log_diff.lua        [MOD]  — Integrate review keymaps + rendering

Architecture Diagram
┌─────────────┐         ┌───────────┐           ┌──────────────────────┐
│diff_mode.lua├─require►│ review.lua├─save/load►│.foxnvim/review/*.json│
└─────────────┘         └─────┬─────┘           └──────────────────────┘
                          extmarks
┌─────────────┐               │                 ┌──────────────────────┐
│ log_diff.lua├────requireclipboard────────────►│    Editor Buffer     │
└─────────────┘               │                 └──────────────────────┘
                              │
                              │                 ┌──────────────────────┐
                              └────────────────►│     +/* register     │
                                                └──────────────────────┘

Risks
• Namespace collision: review.lua uses its own namespace (fox_git_review), separate from diff highlights and blame, so no conflict.
• Performance on large files: Virtual text extmarks are lightweight; rendering only touches annotated lines.
• Log Diff context: In log_diff, the "context" is a commit hash, so annotations are tied to specific commits — this is correct behavior.






















 Requirements  Technical Design  Delivery Steps

Step 1: Create review.lua annotation module
Build the core lua/plugins/fox/git/review.lua module with all annotation logic.

• Create M.namespace for extmarks and M.annotations in-memory state.
• Implement M.add_annotation(file_path, line_nr, cwd): opens vim.ui.select for type (SUGGESTION/ISSUE/NOTE, default SUGGESTION), then input_modal for text, saves to state and disk.
• Implement M.export_to_clipboard(cwd, context_label): gathers annotations, formats as structured Markdown with session header, copies to + and * registers.
• Implement M.render_annotations(bufnr, file_path, cwd): draws colored virtual text badges on annotated lines using extmarks.
• Implement M.delete_annotation(file_path, line_nr, cwd): removes annotation under cursor.
• Implement M.jump_next_annotation() / M.jump_prev_annotation(): navigate between annotated lines in current buffer.
• Implement M.load_annotations(context, cwd) / M.save_annotations(context, cwd): JSON persistence to .foxnvim/review/<context>.json.
• Implement M.get_context_key(mode, state): returns "unstaged", "staged", or <commit_hash>.
• Implement M.clear_buffer(bufnr): clears extmarks from a buffer on close.

Step 2: Integrate annotations into Git Diff Mode
Wire review.lua into diff_mode.lua for both same_branch and between_branches modes.

• Require review module at the top of diff_mode.lua.
• Add buffer-local keymaps in editor windows (same_branch via open_file_same_branch, between_branches via open_file_between_branches):
• a → create annotation at cursor line
• A → export all annotations to clipboard
• da → delete annotation at cursor
• ]a / [a → jump to next/previous annotated line
• Call review.render_annotations() after apply_same_branch_highlights() in same_branch mode.
• Call review.render_annotations() in open_file_between_branches() for both left and right buffers.
• Call review.clear_buffer() in M.close() cleanup for all buffers.
• Add :GitReviewExport user command for clipboard export.

Step 3: Integrate annotations into Git Log Diff Mode
Wire review.lua into log_diff.lua for the before/after code panels.

• Require review module at the top of log_diff.lua.
• Add buffer-local keymaps on before_buf and after_buf:
• a → create annotation at cursor line
• A → export all annotations to clipboard (context = commit hash)
• da → delete annotation at cursor
• ]a / [a → jump to next/previous annotated line
• Call review.render_annotations() after loading file content in both before and after panels.
• Call review.clear_buffer() in M.close() cleanup.
• Add :GitLogReviewExport user command.


