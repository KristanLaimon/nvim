# Folio integration plan for FoxVim

Status: planning only. This document does not authorize or implement the integration.

## Goal

Bring Folio's calm, book-like Markdown reading experience into FoxVim's workflow. Launch the reader from Neovim, read in the browser, and browse Markdown files from the current working directory without importing them into a separate application or maintaining duplicate copies.

Selected base: [timsamart/folio](https://github.com/timsamart/folio).

The target experience preserves Folio's appearance: paper and night themes, comfortable typography, adjustable fonts, spacing and width, focus mode, document outlines, bookmarks, saved reading positions, highlighted code, Mermaid diagrams, and math. These are existing upstream features; adapting and validating them for FoxVim remains work to do.

References:

- [Folio web reader](https://timsamart.github.io/folio/)
- [Reading features](https://github.com/timsamart/folio#read-your-way)
- [Document storage](https://github.com/timsamart/folio#your-documents-stay-on-your-device)
- [Implementation and verification](https://github.com/timsamart/folio#implementation-and-verification)

## Proposed user workflow

| Action | Result |
|---|---|
| Run `:FoxReader` from a Markdown buffer | Open the browser reader on the current document, with the current cwd as its library. |
| Run `:FoxReader` outside a Markdown buffer | Open the Markdown library for the current cwd. |
| Browse the library | Navigate Markdown files and subfolders without opening every document in Neovim. |
| Follow a relative Markdown link | Open the target document inside the reader, including heading anchors. |
| Click **Open in Neovim** | Open the document in the originating FoxVim session. |
| Edit a document in Neovim | Refresh its browser rendering while preserving the reading position. |
| Quit Neovim | Stop the local reader server. |

Register the reader in the Command Palette as well as providing the explicit Ex command. Follow FoxVim's command registration conventions; no new leader shortcut is needed.

The reader runs in the browser but belongs to the active FoxVim workflow. It should require no separate app installation, manual document import, or browser folder picker.

## Reading interface

Keep Folio's appearance close to the original rather than redesigning it around FoxVim branding.

- Quiet reading page with paper, light and dark appearances supported by the adapted upstream UI.
- Adjustable reading font, font size, line spacing and content width.
- Focus mode that hides navigation and leaves the document visible.
- Collapsible cwd folder tree with filename filtering.
- Navigable heading outline.
- Relative document links and browser navigation between documents.
- Remembered reading position for each document.
- Small **Open in Neovim** action.
- Readable code blocks, tables, images, Mermaid diagrams and math.

Start with continuous scrolling. Page-turning is outside the initial scope because long code blocks and tables complicate pagination.

## Document loading and live updates

Folio currently imports documents into a browser library. Replace that loading path with a connection to FoxVim's actual files:

1. Capture the cwd when the reader session opens.
2. Discover Markdown documents beneath that root.
3. When opening a document, use its loaded Neovim buffer when available; otherwise read the file from disk.
4. Include unsaved edits from loaded buffers in the reader.
5. Refresh changed content while preserving the reader's position.
6. Resolve relative Markdown links and local assets against the current document's directory, within the reader's allowed root.

Do not import project document contents into an independent browser library. The files and Neovim buffers remain the source of truth.

Reading should be independent of the editor cursor. Moving around Neovim must not scroll the reader automatically. Preserve the existing cursor-following behavior of the separate Markdown preview feature unless a later decision explicitly changes it.

Pin each reader session to its starting cwd. Changing editor workspaces must not silently replace the library or document being read.

## Persistent state

Store reader preferences and per-document reading positions in FoxVim's local state, outside project source files.

The existing preview server uses a random port. Browser storage is scoped to the origin, so browser storage alone would not reliably preserve preferences across Neovim sessions that use different ports.

State should identify the workspace and document consistently. Decide the exact path normalization and position representation during implementation. Prefer a position that survives ordinary content updates over relying only on an absolute pixel offset.

Evaluate Folio's bookmarks and other existing reading state after the basic loading path works. Preserve useful upstream features where practical without making them prerequisites for the first working integration.

## Technical approach

Folio uses vanilla JavaScript and Vite and supports a static production build. Adapt its browser frontend and serve the built assets from Neovim.

- Build frontend assets during development or packaging.
- Ship the resulting assets with FoxVim so everyday use does not require Node/npm or a separate frontend server.
- Bundle required runtime assets locally where supported by upstream.
- Use Neovim for workspace discovery, buffer/file access, editor navigation and persistent reader state.
- Run the reader service locally and stop it when Neovim exits.

Existing integration points to inspect and reuse where suitable:

| Existing file or area | Relevance |
|---|---|
| `lua/fox/markdown/browser.lua` | Browser launching, user commands and lifecycle hooks. |
| `lua/fox/markdown/server.lua` | Local HTTP transport, asset serving and preview lifecycle. |
| `lua/plugins/editor/markdown.lua` | Lazy loading and Markdown feature registration. |
| `lua/plugins/fox/tools/command_palette.lua` | User-facing Command Palette actions. |
| `config/markdown/` | Existing browser preview assets and attribution conventions. |
| `docs/editor-qol.md` | Documentation for the current browser preview. |

The existing server is tied to individual buffers and serves rendered HTML. A cwd reader needs a workspace-oriented document interface and Folio's rendering path. Inspect the server before deciding whether to extend it or add a small reader-specific service. Reuse suitable code without forcing both features into an unsuitable lifecycle.

Keep document access scoped to the selected workspace, including resolved paths and symlinks. Editor-opening actions must target the originating FoxVim session and use validated document identities. Retain the local server's appropriate request and content protections while adapting them to Folio's assets.

## Implementation stages

### 1. Establish reuse terms and inspect the source

- Find a clear license or permission covering Folio's own code and assets.
- Inspect the renderer, document loading, storage, UI and production build.
- Identify the smallest changes needed to load documents from FoxVim.
- Confirm the attribution and third-party notices required for redistributed assets.

### 2. Complete one document end to end

- Add `:FoxReader` and a Command Palette action.
- Launch the browser from FoxVim.
- Serve an adapted Folio production build locally.
- Display the current Markdown document using Folio's rendering and appearance.
- Read unsaved content from the editor buffer.
- Refresh content without forcing the reading position to follow the cursor.
- Shut down the service on Neovim exit.

This stage proves the complete path: command → current document → Folio rendering → live update.

### 3. Add the cwd library

- Capture and retain the opening cwd as the session root.
- Add folder navigation and filename filtering.
- Read unopened documents directly from disk.
- Support relative Markdown links, heading anchors and local images.
- Define sensible exclusions and scanning behavior for large folders.
- Handle missing, renamed or deleted documents with a readable message.

### 4. Complete editor integration and persistence

- Add **Open in Neovim** for the current document.
- Persist typography, theme and reading position through FoxVim's local state.
- Restore state across server restarts and changing ports.
- Preserve reading position across live updates and document navigation.
- Evaluate retaining Folio bookmarks and other useful upstream reading features.

### 5. Validate and document

- Verify the browser experience on the user's Windows setup.
- Check cwd browsing, relative links, local images and filenames containing spaces or Unicode.
- Check unsaved buffer updates, unopened files, document deletion and workspace switching.
- Check rendering of code, tables, Mermaid and math.
- Check persistent state across Neovim restarts.
- Check request/path boundaries and server shutdown.
- Run focused automated checks for nontrivial integration logic, then the required applicable repository quality gates.
- Use `--only-failure` by default for test runs.
- Document commands, lifecycle, supported content and known limitations.

## Initial scope boundaries

Keep the current Markdown preview available while the reader is developed. The reader serves sustained reading and cwd navigation; the existing preview already serves cursor-following editing workflows.

Defer custom bookshelves, tags, annotations, page-turn animations, browser editing, cloud services, mobile packaging and library import/export workflows. Do not expand the project into a separate application.

## Open questions

| Question | Proposed direction |
|---|---|
| Can Folio's own code and assets be copied and redistributed? | Establish explicit reuse terms before committing to vendoring them. |
| Extend the existing server or create a reader-specific service? | Decide after inspecting the required routing and lifecycle changes. |
| How should large cwd trees be scanned and filtered? | Use bounded or incremental discovery and sensible exclusions; settle details during implementation. |
| What should happen when the current Markdown file is outside cwd? | Choose explicit behavior without silently exposing files outside the selected root. |
| How should repeated opens and multiple workspaces behave? | Keep sessions pinned to their original roots; decide tab reuse during implementation. |
| Which upstream reading features survive the storage adaptation? | Prioritize appearance, outlines and reading position, then assess bookmarks and other features. |

## Current findings and limits

FoxVim's local browser launcher and Lua preview server have been inspected. Folio's published documentation describes a static browser build and the desired reading features, making the approach plausible.

No local Folio build, source audit or integration test has been completed. A clear license for Folio's own code was not found in the repository pages inspected; public source visibility alone does not establish reuse permission. Reuse terms and coupling to Folio's imported-library storage are the first unresolved items.
