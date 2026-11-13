# FoxVim for VS Code: feasibility and implementation plan

Status: analysis and planning only. No extension, configuration changes, dependency installations, or migrations are implemented by this document.

Analysis date: 2026-11-12. Repository source is the behavioral reference; API references below were checked while preparing this plan. Effort and architecture decisions are proposals, not measured implementation results.

## 1. Goal and feasibility verdict

Build a VS Code extension that preserves FoxVim's keyboard workflow, Vim editing motions, Git Center, and the functionality of its custom plugins. A user should be able to open a project, edit, navigate, manage Git, run tasks, debug, query databases, and use Fox tools without reaching for the mouse.

**Feasible as a substantial extension project.** Most workflows can be reproduced through VS Code's native editor, task, terminal, debug, command, and view APIs. Fox-specific behavior needs TypeScript implementations and new interfaces. Installing a Vim extension and loading this Neovim configuration will not reproduce FoxVim.

**Exact replication has limits.** Neovim floating windows, buffer/tab semantics, arbitrary UI layout, and independent language-server lifecycles cannot simply be transferred to VS Code. VS Code does not expose its workbench DOM to extensions. Preserve operations and keyboard access while adapting presentation to supported views. See [extension capabilities and restrictions](https://code.visualstudio.com/api/extension-capabilities/overview).

The hardest unresolved requirement is nine concurrent environments with hidden inactive tabs, isolated language servers, and continuing background jobs inside one window. Treat this as an early feasibility gate, not a feature to promise after the easier work.

## 2. What the repository actually contains

The existing wiki is useful but some paths describe older layouts. The current implementation is organized under `lua/plugins/fox/{dev,editor,git,tools,ui}/`, with shared behavior under `lua/fox/`. Use actual source paths when implementing.

| Evidence | Consequence for the extension |
|---|---|
| `lua/plugins/fox/tools/command_palette.lua` exposes a command registry with Ex-command, key-feeding, and Lua-function actions. | Port the action intent to named `fox.*` VS Code commands; Lua callbacks and fed Neovim keys are not portable commands. |
| `lua/keymaps/{editor,fox,debug,lsp,search}.lua` and plugin-local `M.settings.keys` both define mappings. | Inventory both sources, resolve duplicate aliases, and test effective behavior instead of copying only the keybind wiki. |
| `lua/plugins/fox/git/git_center/` separates configuration, queries, actions, layout, rendering, graph, and dialogs. | Git operation semantics are useful references; the buffer/window presentation needs replacement. |
| `lua/fox/git/` contains status/diff parsing, blame, conflicts, submodules, and merge/rebase simulation. | Git parity is broader than staging and committing; track each capability separately. |
| `lua/plugins/fox/dev/{tasks,terminal,launch_profiles,dap_breakpoints,dev_server}.lua` coordinate project execution. | Use VS Code tasks, terminals, and debug sessions as execution owners; port FOX discovery, slots, and forms. |
| `lua/plugins/fox/tools/environments.lua` promises nine RAM-resident environments, scoped terminals/LSPs, and isolated visible buffers. | Multi-root folders alone do not meet the existing contract. |
| `lua/plugins/fox/tools/workspaces.lua` uses an index plus Neovim session files. | JSON metadata may be importable; Neovim session scripts must never be executed as VS Code sessions. |
| `lua/fox/core/project.lua` resolves roots and searches `.foxnvim`, `.vscode`, `.foxlocal`, `.nvimfox` in that order. | Preserve lookup intent, test nested roots/submodules, and distinguish incompatible FOX and native VS Code schemas. |
| `lua/fox/langs/<language>/init.lua` centralizes language tooling and runtime behavior. | Retain per-language ownership in the port; Mason identifiers are not VS Code extension identifiers. |
| `lua/fox/query/client.lua` talks UTF-8 JSONL to a standalone Go worker. | FoxQuery has a genuinely reusable backend; rewrite its transport/UI rather than its database drivers. |
| `config/tools/repos/foxquery/README.md` documents bundled Windows/Linux amd64 workers, cancellation, read-only guards, and result limits. | Initial database support can match those platforms; macOS/ARM require builds and verification. |
| `lua/fox/{editor,lsp,ui,markdown,wakatime}/` and `lua/plugins/ui/` contain more local replacements. | Scope includes local behavior outside the `plugins/fox` tree, not just the older inventory table. |

Useful local references: [plugin inventory](docs/plugins.md), [keyboard shortcuts](docs/keybinds.md), [Git Center](docs/git-center.md), [environments](docs/environments.md), [VS Code compatibility](docs/vscode-support.md), [Query Mode](docs/query-mode.md), and [language registration rules](AGENTS.md).

## 3. Vim motions: reuse an existing engine

Do not implement a new Vim emulator. Build FOX commands and views independently of the motion provider.

| Approach | Benefit | Limitation | Decision |
|---|---|---|---|
| `vscode-neovim` | Real Neovim-backed editing, close to the existing operator/motion model. | Requires Neovim; insert mode and UI integration remain VS Code-specific. Existing floating-window plugins do not become workbench views. | Preferred starting point for this user's parity goal. |
| VSCodeVim | Vim emulation with configurable remaps and Ctrl-key delegation. | Exact motion, macro, text-object, and Ex behavior must be checked against FoxVim expectations. | Supported alternative after the primary workflow passes. |
| New FOX motion engine | Complete ownership. | Huge unrelated editing-engine project with ongoing compatibility work. | Reject. |

The [vscode-neovim documentation](https://github.com/vscode-neovim/vscode-neovim) recommends a minimal configuration and disabling redundant UI/LSP plugins. Start with an isolated clean configuration; do not load FoxVim's current `init.lua` into the embedded instance. The [VSCodeVim documentation](https://github.com/VSCodeVim/Vim) describes `vim.handleKeys` for delegating conflicting shortcuts. Enable only one motion provider in a window.

Vim mode in text editors is separate from keyboard navigation in trees, pickers, terminals, and webviews. FOX must implement navigation for its own custom views. A Git commit title field must accept literal `j`, `k`, `q`, and `/` while the surrounding Git list can use them as commands.

Phase 0 must verify counts, operators, text objects, visual/block selection, registers, macros, repeat, search, undo/redo, clipboard, completion acceptance, and transitions between editor and FOX views. Record concrete differences instead of claiming complete Vim compatibility.

## 4. Feature coverage and proposed destination

Every feature family below remains in the full parity backlog. Using native functionality is a valid implementation only when the complete keyboard workflow is demonstrated. A deferred feature is not a completed feature.

Difficulty: **low** = mostly native wiring; **medium** = custom behavior/forms; **high** = substantial UI/domain port; **limited** = known host mismatch or unresolved parity.

### Commands, navigation, and projects

| Current module / behavior | VS Code approach | Difficulty |
|---|---|---|
| `tools/command_palette.lua` | Native Command Palette contributions with `Fox:` categories; optional FOX-only Quick Pick for grouped favorites. | Low |
| `tools/context_help.lua`, root `context_help.lua`, `ui/help_modal.lua` | Contextual help command and searchable shortcut reference. Consolidate overlapping entry points. | Medium |
| `tools/file_explorer.lua`, `tools/wsl.lua` | Native Explorer plus FOX project/favorites picker; remote WSL folder opening for Linux projects. Preserve explicit desktop browsing. | Medium |
| `editor/neotree_{center,hidden,mover,wrap}.lua` | Native navigation/file operations; FOX-only filtered tree if custom hidden-path behavior cannot be expressed without changing global exclusions. | Medium / limited |
| `tools/workspaces.lua`, `fox.projects.history`, `fox.projects.favorites` | Named project/session picker, numbered slots, recent/favorite paths, native workspace reopening, best-effort layout metadata. | Medium |
| `tools/environments.lua` | Prototype active-project slots over multi-root; separately evaluate native workspace windows for stronger isolation. | High / limited |
| `tools/project_replace.lua`, `fox.core.project_replace`, `preview_tab` | Native Search for discovery; port guarded preview/apply semantics with `WorkspaceEdit` where FOX behavior differs. Preserve dirty-file handling. | Medium |
| `tools/lsp_references.lua`, `tools/usages_picker.lua`, `fox.lsp.symbol_usage` | Native reference/definition providers and keyboard pickers; retain FOX grouping where useful. | Low / medium |
| `tools/notes.lua`, `ui/wiki_modal.lua`, `tools/doc_manager.lua` | Notes folder picker, bundled wiki browser, offline index/search and explicit downloads. | Medium |

### Git Center and the Git toolset

| Current module / behavior | VS Code approach | Difficulty |
|---|---|---|
| `git/git_center/` status, stage/unstage, diff, commit title/description/tag, restore, push | FOX Git Center with keyboard list navigation, native diff editors, draft preservation, and serialized repository writes. | High |
| Git Center branch/log/graph/stash and submodule views | Dedicated FOX views over asynchronous Git queries; active repository identity carried into every action. | High |
| `git/diff_mode.lua`, `git/log_diff.lua`, `git_center/diff_menu.lua` | Native diff documents plus FOX history/sidebar commands and focus restoration. | Medium / high |
| `git/conflict_resolver.lua`, `fox.git.conflicts` | Evaluate native merge editor; port FOX per-conflict choices/result editing if native interactions do not cover the contract. | High |
| `fox.git.simulate`, `fox.git.submodules` | Port merge/rebase preview semantics after checking current implementation and isolation guarantees. No preview may mutate the user's active checkout. | High |
| `git/git_accounts.lua` | Identity selection and repository Git config; use credential tooling/secret storage for credentials. Identity is separate from authentication. | Medium |
| `fox.git.inline_blame`, `fox.git.blame` | Asynchronous blame annotations, toggle, copy, and detail commands. | Medium |
| `git/secondary_git.lua`, `fox.git.secondary` | Expose equivalent history/branch operations through native or FOX views; Neogit/Diffview themselves are Neovim integrations. | Medium |

### Execution, debugging, and language tooling

| Current module / behavior | VS Code approach | Difficulty |
|---|---|---|
| `dev/tasks.lua` | Task Provider for FOX/discovered tasks; reuse native tasks; preserve defaults, dependencies/chains, cancellation, and four logical output slots. | Medium / high |
| `dev/terminal.lua`, `fox.core.dock` | Native terminal instances, nine lazy slots per FOX environment, toggle/focus and explicit disposal. Native panel sizing may differ. | Medium |
| `dev/launch_profiles.lua`, `fox.launch.runtimes` | Translate supported FOX run/debug profiles into native execution/debug configurations; preserve CRUD, args, env, cwd, and prelaunch behavior. | High |
| `dev/dev_server.lua` | Start/reuse a tracked dev-server task and resolve its URL; stop only FOX-owned processes. | Medium |
| `dev/dap_breakpoints.lua` | Native breakpoint APIs, conditional/enabled state, explicit FOX import/export with deduplication. | Medium |
| `dev/bun_dap.lua`, `debuggers/*`, per-language DAP exports | Prefer maintained VS Code debug extensions. Verify each runtime, especially Bun; add a FOX adapter descriptor only if a concrete gap remains. | Medium / high |
| `dev/launch_cmp.lua` | JSON schema/completion for FOX launch files; native IntelliSense for native `launch.json`. | Low / medium |
| `tools/installer.lua`, `fox.core.installer`, `fox.lsp.tooling`, `fox.langs/*` | Optional Language Manager maps each language to tested extensions/tools and diagnoses missing runtimes. No Mason cloning. | Medium |
| `tools/vscode_settings.lua`, `tools/buffer_language.lua` | Native settings and document language APIs; explicit compatibility import only where FOX defaults add value. | Low |
| `tools/type_injector*.lua` | Port file/type generation and package actions; separately verify how each installed language extension consumes generated definitions. | Medium / high |
| `tools/nuget.lua`, `tools/dotnet_creator.lua`, `fox.langs.typescript.packages` | Keyboard package/project forms over explicit `dotnet` and package-manager commands. | Medium |
| `fox.langs.php.{blade,laravel}`, `fox.langs.csharp.navigation` | Evaluate native language extensions; port FOX navigation/completion/caches when they provide missing behavior. | High |

### Editor helpers, appearance, and additional tools

| Current module / behavior | VS Code approach | Difficulty |
|---|---|---|
| `tools/query.lua`, `fox.query/*` | Reuse Go JSONL backend; SQL text editor, schema tree, keyboard results grid, connection/parameter forms, FK diagrams, notes, export, activity, cache and cancellation. | High |
| `tools/snippet_manager.lua`, `fox.lsp.snippets` | Native snippet syntax and contributions plus FOX CRUD/override manager. Check format compatibility before sharing files. | Medium |
| `editor/tailwind_organizer.lua` | Port class detection/sort/wrapping rules with document edits; avoid double formatting with installed tools. | Medium |
| `editor/line_endings.lua` | Native EOL support for current documents; explicit previewed repository conversion preserving encoding and dirty files. | Medium |
| `editor/relative_path.lua`, `editor/hover_links.lua`, `editor/folding.lua` | Native commands, document links, folding providers/commands with FOX shortcuts. | Low / medium |
| `editor/buffer_cleaner.lua`, `ui/pinned_tabs.lua`, `fox.core.file_buffers` | Native tabs/pinning, rename edits and dirty-file prompts; define a FOX close action without taking over every native close operation. | Medium / limited |
| `editor/smart_check.lua`, `editor/caps_lock.lua` | Inspect exact checks and port useful commands; OS Caps Lock behavior needs a platform-specific feasibility check. | Medium / limited |
| `fox.editor.{autopairs,autotag}`, `fox.lsp.file_operations`, code actions, hover, completion, diagnostics | Use native editor/language-extension behavior first; acceptance scenarios decide whether FOX-specific logic remains necessary. | Low / medium |
| `fox.ui.{dashboard,tabline,statusline}`, `ui/statusline_picker.lua` | Welcome/dashboard view, status bar items and native editor tabs. The six statusline layouts need adapted designs. | Medium / limited |
| `ui/{theme_picker,colorscheme_preview,ryoku_theme,omarchy_theme}.lua`, `fox.ui.{icons,devicons,color_highlights}` | VS Code color/icon themes, picker, rollback on cancel, native document colors or FOX provider. No workbench CSS injection. | Medium / limited |
| `ui/font.lua`, `ui/input_modal.lua`, `fox.core.notify` | Native settings, input/Quick Pick, notifications, FOX notification history/progress. Pixel geometry and click behavior can differ. | Low / medium |
| `ui/image_viewer.lua`, `fox.markdown/*` | Native image/Markdown preview first; evaluate existing Mermaid support and port missing preview interactions. Terminal pixel art is presentation-specific. | Medium |
| `tools/wakatime.lua`, `fox.wakatime/*` | Prefer the maintained tracker integration; reproduce FOX statistics commands/views if required. | Medium |
| OS, clipboard, window picker, z-index, Kitty/terminal helpers, Lua utility library | Replace needed behavior with host APIs; retain no-op/unsupported entries in the ledger for terminal-specific capabilities. | Low / limited |

The separate [Folio plan](PLAN-FOLDIO-MD.md) describes future work, not an implemented plugin to count as existing parity. Likewise, Query Mode currently identifies FoxAI as unimplemented; it is not a port requirement unless separately requested.

## 5. Proposed extension architecture

Start with one desktop/workspace extension, tentatively **FoxVim for VS Code**, written in TypeScript. Keep the Neovim distribution intact. A future implementation can live in a separate repository; no move or extraction is needed now.

Suggested feature directories: `commands`, `keyboard`, `projects`, `git`, `tasks`, `terminals`, `launch`, `languages`, `query`, `editor`, and `docs`. Add files only when implementing their feature. Keep activation thin, register disposables, and construct collaborators explicitly. Introduce small IO contracts only at boundaries that need replacement in tests: Git/process execution, persistence, and the query worker.

Use native Quick Picks and input boxes for selection/forms, Tree Views for navigation, text documents for editing, and native diff editors for review. Use a webview for a screen only when native primitives cannot provide its required interaction. Git Center's combined form/list/graph and Query's result grid are candidates; prototype keyboard access before committing to either layout. The [webview API](https://code.visualstudio.com/api/extension-guides/webview) provides isolated content and message exchange, not automatic Vim editing inside that content.

Reuse contracts, not the Lua runtime:

- Port parsers, root rules, task discovery, profile translation, and formatting algorithms where needed.
- Convert existing Lua test cases into behavior fixtures; do not expect Neovim mocks to test VS Code integration.
- Reuse FoxQuery's worker and protocol directly after packaging/license checks.
- Reuse compatible JSON, snippet catalogs, schemas, icons and documentation after checking provenance. Lua callbacks and Neovim UI modules require replacements.
- Let native language extensions own their language servers/debuggers. Do not activate a second FOX LSP/DAP stack alongside them.

VS Code exposes tasks, debugging, terminals, edits, storage and views through its [API reference](https://code.visualstudio.com/api/references/vscode-api). Prefer stable public APIs. Built-in command identifiers and any Git extension exports used by the port need explicit version checks and integration tests.

### Git operation ownership

The [Source Control API](https://code.visualstudio.com/api/extension-guides/scm-provider) supplies SCM presentation; it does not execute Git for us. Prefer the existing built-in Git provider and native diff views. Implement FOX-specific operations with asynchronous Git CLI calls where needed, without registering a duplicate SCM provider for the same repository.

Use argument arrays, explicit repository cwd, exit-code handling, cancellation and per-repository write serialization. Parse machine-readable status with NUL delimiters so renamed files, Unicode, spaces, and unusual filenames survive. Keep index and working-tree diffs distinct. Refresh after writes and external changes; discard stale preview responses after navigation.

Preserve unsaved commit drafts and honor Git hooks, signing, authentication, submodules and operation failures. Destructive restore/branch operations need precise previews and confirmation matching their data-loss risk. Do not copy the current Git command helper's blanket `safe.directory=*` behavior into the port.

### State and compatibility

1. Read project files lazily. Preserve `.foxnvim`, `.vscode`, `.foxlocal`, `.nvimfox` lookup intent, with tests for projects containing several candidates. Native `.vscode/tasks.json` and `launch.json` retain their own schemas.
2. Identify source format explicitly. Native VS Code files support JSONC; FOX files use their documented JSON structures. Validate before translating, report unsupported fields, and never execute a value merely because it was present in a workspace file.
3. Preserve existing source files by default. An explicit import previews its destination/diff, backs up overwritten content, and leaves unknown fields intact where round-tripping is supported.
4. FOX sessions store URIs, open files, selections, groups, pinned state and supported view state. Import useful workspace-index metadata; do not run `.vim` session scripts. Exact layout reconstruction remains best effort until demonstrated.
5. Keep personal recents, slots and UI preferences in extension storage. Keep secrets out of committed project files; offer explicit migration to `SecretStorage` without deleting existing data silently.
6. Avoid dual breakpoint/session authorities. Define import/export direction and deduplication before enabling persistence. Do not assume live terminal processes survive extension-host reloads or project-window switches.

### Language Manager

Preserve FoxVim's minimal-fresh-setup rule: no automatic optional language/server/formatter/SDK installations. Select All, Select None and per-language selection remain keyboard-accessible. Recommend/install optional extensions only through explicit user actions; document which extensions may themselves download tools.

Each language owns its extension recommendations, external requirements, formatter choice, runtime translation, schemas and health checks. Generic aggregation stays generic. Respect `.editorconfig` and repository formatter configuration before FOX defaults. Lua support may use a recommended Lua extension and explicit formatter setup; VS Code's built-in languages remain available without FOX installing anything.

## 6. Keyboard interaction contract

The deliverable is a mouse-free workflow, not just a package of editor remaps. Every FOX action needs a stable command ID, searchable title, and a route back to the editor.

- Keep `Ctrl+Shift+P` as the native palette and contribute all FOX actions there; no required leader mappings.
- Offer an opt-in FoxVim shortcut profile. Do not rewrite user keybindings without a reviewed action. Provide a conflict report and documented fallback chords.
- Scope bindings with native focus conditions and FOX contexts such as `fox.gitCenterFocus` or `fox.activeEnvironment`; include the selected motion provider's documented contexts where appropriate. See [when-clause contexts](https://code.visualstudio.com/api/references/when-clause-contexts).
- In FOX-owned list views, support `j/k`, arrows, first/last, search, Enter, Tab/Shift+Tab and help. Escape backs out one level; closing returns to the originating editor/selection.
- In text fields, typing wins. Do not intercept plain motion keys, normal copy/paste or IME composition. Retain full terminal input unless an explicit shortcut is reserved for FOX.
- Implement keyboard behavior inside webviews explicitly, with visible focus, accessible labels and no focus traps. Neither motion provider automatically owns webview controls.
- Test Windows US and Spanish/Latam layouts, including AltGr/dead keys. Do not port terminal escape aliases as desktop shortcut definitions.

| FoxVim action | Candidate shortcut | Conflict / requirement |
|---|---|---|
| Palette | `Ctrl+Shift+P` | Native palette already matches. |
| Git Center | `Ctrl+Shift+G` | Conflicts with native Source Control; FOX profile must make the choice explicit. |
| Stage all | Existing `Ctrl+Shift+X` / `Alt+S` aliases | Extensions view/menu conflicts; prefer palette or a reviewed fallback. |
| Task menu / default task | `Ctrl+Shift+T` / `Ctrl+Shift+A` | Closed-editor reopening and other bindings may conflict. |
| Task output 1..4 | `Ctrl+1..4` | Editor group focus conflict. |
| Terminal slots 1..9 | `Alt+1..9` | OS, layout, terminal and user bindings must be checked. |
| Toggle terminal | `Ctrl+;` | Verify desktop/layout dispatch and focused terminal behavior. |
| Launch / profile menu | `Ctrl+Shift+S` / `Ctrl+Shift+Q` | Save As and OS/user conflicts. |
| Environments / numbered slots | `Ctrl+Shift+E` / `Ctrl+Shift+1..9` | Explorer and layout-dependent symbol conflicts. |
| Workspaces | `Ctrl+Shift+W` | Native close-window conflict. |
| Explorer | `Ctrl+/` in current `lua/keymaps/fox.lua` | Native comment conflict; some wiki references still list `Ctrl+Shift+F`. |
| Query view | `F3` / `Ctrl+Alt+O` | Find-next and other extension bindings may conflict. |
| Breakpoint toggle | Current FOX aliases / `F9` alternative | Verify actual debug maps; do not assume wiki shortcuts equal effective bindings. |
| Window/editor navigation | Current `Ctrl+H/L/J`, `Alt+H/L`, close action | Native replace/panel/focus and Vim-key conflicts; scope by focus and mode. |

Exact candidate mappings must be resolved in Phase 0 and recorded in a checked keyboard matrix. No global override of every Ctrl key.

## 7. Environments: explicit feasibility gate

Current FoxVim behavior includes concurrent background terminals, per-project buffer visibility, and explicit LSP stopping on environment closure. Native multi-root support does not give FOX ownership over arbitrary third-party language servers or a general API to hide arbitrary native tabs.

Prototype two supported designs:

1. **Single-window active-project slots:** all roots remain in the workspace, FOX scopes its tasks, terminals, Git and custom file views. Save/restore editor selections/layout as supported. Native tabs and language servers may remain shared; never close dirty editors merely to imitate hidden buffers.
2. **Native workspace windows:** stronger project separation managed by VS Code, with a FOX project picker. Cross-window slot switching and background-job behavior need testing; they are not equivalent to RAM slots in one Neovim process.

Choose after a keyboard demo with two projects, unsaved files, independent terminals, separate Git repositories and two language extensions. If neither reaches the desired isolation, document the gap and keep exact environment parity open. A VS Code fork or private workbench hacks are outside this extension plan.

## 8. Desktop, remote, and FoxQuery boundaries

Target desktop VS Code on Windows first, then Linux and Remote WSL. Run Git, tasks, package managers and FoxQuery next to the workspace in the appropriate extension host. Resolve resources as URIs; do not treat a remote Linux path as a local Windows executable path. Prefer a remote WSL workspace over translating every operation through Windows UNC paths. See [remote extension guidance](https://code.visualstudio.com/api/advanced-topics/remote-extensions).

A desktop workspace extension can render views in the client while executing workspace operations remotely. Verify where the selected motion engine runs and which Neovim executable it requires in each supported topology. Local Desktop browsing from a remote host needs an explicit design; it is not automatically available through the remote filesystem.

FoxQuery should keep its existing read-only protections, parameters, cancellation, timeouts, row/byte limits and driver behavior. Port JSONL framing across partial/multiple chunks, request IDs, events, pending-request failure on process exit and reconnect. Keep credentials and full errors out of logs/webview messages unless deliberately displayed. SQL editing stays in a native editor; the result grid and FK views receive their own keyboard model.

Existing binaries cover Windows/Linux amd64 only. Verify checksums, executable permissions, notices, packaging and worker version compatibility. Browser-only `vscode.dev` cannot run this native-worker design; macOS/ARM support remains a separately tested build target.

Honor [Workspace Trust](https://code.visualstudio.com/api/extension-guides/workspace-trust): inspecting configuration/help may work in restricted mode, while task execution, package installs, worker startup and workspace-driven subprocesses require a trusted execution path. Webviews need a restrictive CSP, validated messages and escaped workspace-derived content.

## 9. Phased implementation with exit criteria

All items below are unchecked future work. Each feature is complete only after its keyboard workflow, failure path and persistence behavior are verified.

### Phase 0 — Resolve the architectural risks

- [ ] Produce a source-based feature/command/keymap ledger; assign every local module to port, native equivalent, internal replacement or documented host limitation.
- [ ] Build a disposable extension prototype using one motion provider and a clean isolated configuration.
- [ ] Demonstrate editor -> Git list -> diff -> commit field -> editor using only keyboard, including cancel and focus restoration.
- [ ] Test motion behavior, conflicting shortcuts, terminal focus and target keyboard layouts.
- [ ] Evaluate environment designs with dirty files and continuing background jobs.
- [ ] Exchange requests/events with the existing FoxQuery worker from a Node extension host on Windows and Remote WSL.
- [ ] Select stable APIs, supported VS Code/provider versions and initial platforms from the results.

Exit: working evidence for the risky interactions, a chosen environment contract, and an explicit list of remaining differences. If exact single-window isolation is mandatory and unsupported, report that before the main port.

### Phase 1 — Foundation and navigation

- [ ] Create extension packaging, thin activation, command contributions, settings and cleanup.
- [ ] Implement project/root resolution, safe config loading, state storage and trust handling.
- [ ] Provide opt-in shortcut profile, conflict diagnostics, contextual help and focus restoration.
- [ ] Implement project/recent/favorite pickers, basic workspace slots, explorer actions and native editor navigation.

Exit: keyboard-only project opening, file editing, switching and safe closing with unsaved changes preserved.

### Phase 2 — Git Center, first daily-use milestone

- [ ] Implement repository/submodule selection, status refresh, stage/unstage, staged/unstaged diff and persistent commit drafts.
- [ ] Add commit, restore with preview, fetch/pull/push, identity selection and useful error/progress output.
- [ ] Add branch/stash/log/graph flows, historical diffs, blame and conflict resolution.
- [ ] Port simulation only after proving it leaves the active checkout/index unchanged.

Exit: keyboard-only review -> stage -> commit -> push, plus branch/history/conflict scenarios against temporary repositories. The basic milestone can ship before advanced Git parity, but its missing operations stay visible in the ledger.

### Phase 3 — Tasks, terminals and launch/debug

- [ ] Implement nine terminal slots, four task-output slots, ownership and cancellation.
- [ ] Port discovery/defaults/chains and integrate existing native tasks without duplication using a [Task Provider](https://code.visualstudio.com/api/extension-guides/task-provider).
- [ ] Add FOX launch/profile CRUD, runtime translation, prelaunch handling, server URL discovery and native debug start/stop.
- [ ] Add breakpoint compatibility and explicitly selected language/debug integrations, including Bun validation.

Exit: an existing FOX project can build, run, debug, stop, switch projects and return to the correct output using only the keyboard.

### Phase 4 — Remaining custom editor and language tools

- [ ] Deliver the chosen environment/session behavior and document exact isolation limits.
- [ ] Port guarded replace, snippets, Type Injector, Tailwind, line endings, references/usages and language-specific navigation.
- [ ] Port optional Language Manager, package managers and .NET creation without background installs.
- [ ] Add notes, offline docs/wiki, themes/icons, status layouts, notification history, image/Markdown behavior and statistics.
- [ ] Close every remaining row in the coverage ledger with tested behavior or an explicit limitation; do not silently drop small helpers.

Exit: all non-Query custom feature families have keyboard acceptance evidence and supported configuration round-trips.

### Phase 5 — FoxQuery parity

- [ ] Package verified worker assets and implement lifecycle/protocol compatibility.
- [ ] Add connections/schema exploration, saved SQL, parameters/completion, results, export and activity.
- [ ] Add Standard/Visual workflow equivalents, FK maps, notes, pin/column controls, cache refresh and error details.
- [ ] Verify read-only guards, cancellation, disconnect/reconnect, large-result limits and keyboard grid navigation.

Exit: SQLite fixture tests plus disposable MySQL/MariaDB/PostgreSQL integration scenarios pass on supported hosts without database writes.

### Phase 6 — Release readiness

- [ ] Package a VSIX with licenses, schemas, docs and platform assets; test in a clean VS Code profile.
- [ ] Verify Windows/Linux/Remote WSL support, extension reload, native Git coexistence and both supported motion-provider configurations independently.
- [ ] Publish a parity ledger and migration guide, including environment/session/platform differences.
- [ ] Complete a full keyboard-only daily-work scenario and screen-reader/focus checks.
- [ ] Establish CI for pure logic, extension-host integration and worker compatibility.

Exit: reproducible installation and demonstrated workflow coverage. Publishing is a separate action when implementation is ready.

## 10. Validation strategy

Test ported behavior at its actual boundary: real temporary Git repositories for staging, renames, hooks, conflicts and submodules; fixture project files for detection/translation; temporary files and dirty documents for edits; actual extension-host commands/views for focus and lifecycle. Reuse relevant cases from `tests/` as specifications.

Add targeted unit tests for parsers/translators and meaningful extension-host integration tests. Keyboard automation or repeatable manual scripts must cover list navigation, input fields, Escape, return focus and terminal routing; pure unit tests cannot establish mouse-free usability. Record native/provider-specific gaps alongside the scenario.

Include malformed/unknown configuration fields, JSONC native files, nested projects, duplicate task names across roots, non-ASCII paths, CRLF, unsaved buffers, stale async responses, repository changes outside FOX, worker crashes and extension-host reloads. Confirm no optional tooling is installed by activation alone.

Measure activation cost, large-repository status/graph latency, rapid selection preview latency and large result rendering on named fixtures. Set release budgets after Phase 0 measurements rather than inventing performance guarantees now.

This planning change does not need the Neovim runtime gates because it changes no executable behavior. Future Lua changes must follow this repository's required CLI checks and `--only-failure` default; extension tests require their own runner.

## 11. Effort and decisions to carry forward

This is a product port, not a configuration export. A planning estimate for one experienced developer is **several months**: roughly 1–2 weeks for feasibility prototypes, 4–8 additional weeks for foundation/basic Git/tasks/terminals, and another 8–16+ weeks for advanced Git, debugging, custom tools, Query and hardening. These are unvalidated ranges with substantial uncertainty; environment parity and UI work can increase them. Re-estimate after Phase 0 and the first Git milestone.

Recommended direction: one FOX workspace extension, `vscode-neovim` as the initial motion provider, native VS Code services for editor/language/debug execution, TypeScript ports of FOX behavior, and direct reuse of the FoxQuery worker. Make the environment decision first, then deliver Git Center as the first substantial proof that FoxVim's keyboard workflow transfers successfully.

Outstanding decisions are implementation gates, not prerequisites for writing this plan: acceptable environment isolation differences, precise Git Center surface, primary provider versions, supported remote topologies, and whether macOS/ARM belong in the first release. Full feature parity remains the destination; no percentage of compatibility is claimed before implementation and testing.
