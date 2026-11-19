# Fox Reader: remaining delivery steps

The native reader replaces the Folio integration. A Lua server, command, palette entry, filtered file list and initial browser page exist, but the feature is not yet complete or fully validated.

1. [x] Replace the flat file list with a filterable, collapsible folder tree. Preserve expanded folders while refreshing and verify nested, Unicode and spaced names.
2. [ ] Finish document navigation: relative links and heading anchors, browser history, local images, configurable extensions, changes on disk, missing files and workspace switching. Keep unsaved buffers authoritative and preserve a structural reading position during refresh.
3. [ ] Store preferences and per-document positions in FoxVim state outside projects, independent of server ports. Add font, line spacing and content width controls and restore state across restarts; handle corrupt and unwritable state.
4. [ ] Add **Open in Neovim**, validating origin, capability and document identity before targeting the originating session.
5. [ ] Implement offline math and code highlighting, verify Mermaid and other supported Markdown, and retain only necessary licensed assets and notices.
6. [ ] Investigate and verify focusing an existing reader tab in the default browser on Windows and other supported platforms. Report platform limitations instead of claiming unsupported behavior.
7. [ ] Harden and test HTTP parsing, request and origin boundaries, traversal and symlinks, hostile Markdown, resource limits, repeated sessions, errors and shutdown. Add meaningful tests for the server and browser behavior.
8. [ ] Update `docs/editor-qol.md` with commands, behavior, lifecycle and limitations. Run all applicable quality gates and integration tests after the final code change with `--only-failure`; report OS-dependent exclusions and blockers separately.
