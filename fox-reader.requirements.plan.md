# Fox Reader: requirements

## Purpose

Make repository Markdown comfortable to read for extended periods, inspired by the user's experience with KOReader on Kindle. Build a FoxVim-native browser reader with a quiet, book-like appearance. KOReader is an inspiration for comfort, not a requirement to copy its interface or features.

## Functional Requirements

- `As a` FoxVim user, `I want` to open the existing Command Palette with Ctrl+Shift+P and select **Fox Reader**, or run `:FoxReader`, `so` I can launch the reader from my editor.
- `As a` FoxVim user, `I want` the reader page to open automatically in the operating system's default browser and, when the relevant page is already open, focus its existing tab instead of opening a duplicate, `so` I can return to reading quickly.
- `As a` FoxVim user, `I want` the reader to open the current Markdown document when it is inside cwd, or otherwise open the cwd library, `so` I can start reading in context. If the Markdown buffer is outside cwd, show an explicit message and offer the library without exposing the outside file.
- `As a` FoxVim user, `I want` the entire captured cwd tree available as the default library, filtered by an editable array of included extensions near the beginning of the feature's Lua configuration, `so` I can choose which files appear. Default to `{ ".md", ".txt" }`, allow extensions to be added or removed, and render included text files as Markdown.
- `As a` FoxVim user, `I want` to browse a collapsible folder tree, filter filenames, open documents, follow relative Markdown links and heading anchors, and use browser back and forward, `so` I can navigate the repository while reading.
- `As a` FoxVim user, `I want` paper, light and dark themes, adjustable font, size, line spacing and width, a focus mode and a heading outline, `so` I can read comfortably. Use continuous scrolling initially.
- `As a` FoxVim user, `I want` code, tables, local images, Mermaid diagrams and math rendered in the reader, `so` repository documents remain understandable. Consider bookmarks after the core reader works.
- `As a` FoxVim user, `I want` loaded Neovim buffers, including unsaved edits, reflected in the reader and unopened files read from disk, `so` I see current content. Updates retain my reading place and do not follow editor cursor movement.
- `As a` FoxVim user, `I want` **Open in Neovim** to open the current document in the originating session, `so` I can edit it. Keep the library pinned to the cwd captured when launched, even when FoxVim changes workspace.
- `As a` FoxVim user, `I want` reading preferences and document positions restored across Neovim restarts and changing server ports, `so` I can resume reading. Store state outside project source files.

## Non-Functional Requirements

- Implement the HTTP server in Lua using Neovim's APIs. The feature must not require Node.js, Python or Go at runtime; no separate app, document import, browser folder picker, account or separate frontend server. Frontend build tools may be used during development or packaging.
- Ship the static frontend assets, including locally bundled dependencies needed for offline rendering, in `config/tools/fox-reader/`.
- Serve only on loopback; restrict document and asset access to resolved paths inside the selected root. Editor actions must use validated document identities and target the originating session.
- Handle missing, deleted or renamed files with a useful message; handle spaces and Unicode in paths. Scan large trees incrementally or with bounded work without silently excluding directories from the cwd library.
- Keep the existing cursor-following Markdown preview intact. Stop the reader service on Neovim exit.
- Do not add a new leader shortcut.
- Verify the reading workflow on Windows and run all applicable repository quality gates, including integration tests; report OS-dependent exclusions separately.

## Scope and exclusions

- The initial reader uses continuous scrolling and the selected cwd as its library; it preserves the separate Markdown preview.
- Pagination, annotations, tags, cloud sync, browser editing, custom bookshelves, import/export and mobile packaging are deferred.

## Acceptance

The palette and Ex command work from Markdown and non-Markdown buffers; the reader supports the workflow above, including unsaved edits, links, persistence, workspace isolation and shutdown. Core reading features work offline with shipped assets. All third-party notice requirements are met for bundled dependencies.
