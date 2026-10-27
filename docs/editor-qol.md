# 🎛️ Editor Quality of Life

[← Back to Wiki Index](index.md)

The small modules — each one file in `lua/plugins/fox/`, each fixing one specific annoyance.

## Markdown browser preview

With a Markdown, `.mermaid`, or `.mmd` file open, select **Toggle Live Markdown / Mermaid Browser Preview** in
`:CommandPalette`, or run `:MarkdownPreviewToggle`. Use `:MarkdownPreviewStop`
to stop the server. The server and Markdown renderer run in Lua using Neovim's
built-in networking; Node, npm and `markdown-preview.nvim` are not required.
Mermaid diagrams in fenced blocks and standalone files use the attributed local
JavaScript bundle in `config/markdown/`; no CDN or Mermaid CLI is used. Source
buffers stay untouched. Edits update the same browser tab without saving.
Restart Neovim after migrating from the old plugin, then run `:MarkdownPreview`.

The browser also renders GitHub Flavored Markdown tables (including alignment
and escaped pipes), task lists (`- [ ]` / `- [x]`), strikethrough (`~~text~~`),
automatic URL/email links, fenced code and HTML `<details>` sections. These can
be mixed with Mermaid blocks in the same document. Quotes, dashes and ellipses
stay literal. The focused Lua renderer is not a complete CommonMark engine:
nested lists, reference links, arbitrary HTML, syntax highlighting and math
extensions are not implemented. Only safe `<details>`/`<summary>` HTML is accepted.
Legacy `g:mkdp_preview_options` settings from the former renderer are not used.

FoxVim opens the system browser through its native handler (Explorer on Windows,
`open` on macOS, `xdg-open` on Linux, or `wslview` when available under WSL).
The preview URL is also printed in `:messages`. If the handler fails, FoxVim
reports the error with that URL so you can open it manually. Explicit
`g:mkdp_browser` and `g:mkdp_browserfunc` overrides are respected.
The server binds only to `127.0.0.1` on a random port with a random URL token.
Relative raster images inside the document directory are served (up to 10 MiB);
parent directories and SVG/HTML files are not exposed. Browser scroll position
is preserved across updates; editor-to-browser cursor synchronization is not provided.

---

## 🚪 Buffer Cleaner & Smart Quit (`buffer_cleaner.lua`)

`:q` in a normal Neovim quits the window, which in practice means "quit the editor" more often than you meant it. Here `:q` and `:q!` are overridden to answer *what did you actually want to close?*:

```
window is one of several splits?  → close the split
several tabs/buffers open?        → close the current tab, move to the previous
last real file?                   → delete the buffer, land on the dashboard
already on the dashboard?         → quit Neovim
```

`<C-q>` does the same thing.

It also sweeps empty, unmodified `[No Name]` buffers as soon as a real file opens — the ones that pile up from `:e`, from opening a folder, or from a plugin that created a scratch buffer and forgot it.

And it keeps `_G.OpenedFolders`, the record of folders you've opened as projects that feeds the pickers.

---

## 💡 Help Menu & Cheatsheet Manager (`help_modal.lua`)

Press `<F1>` (or run `:FoxHelp`, `:Cheatsheet`, `:HelpMenu`, or pick from the Command Palette `<C-S-p>`) to open the **Help Menu & Cheatsheet Manager**.

A dual-pane modal mirroring the Wiki UI:
- **Left Panel (Topic Index)**: Categorized domains:
  - `🌐 Environments` — Multi-CWD project slots (`<C-S-1..9>`), CRUD menu (`<C-S-e>`, `<leader>ee`).
  - `🐙 Git-Center` — Git Center (`<C-S-g>`), staging (`<C-S-x>` / `<A-s>`), diff navigation (`[d`/`]d`).
  - `📁 Neo-tree` — Sidebar file explorer (`<C-e>`), file operations, desktop explorer (`<C-/>`).
  - `📑 InTab` — Buffer tab hopping (`<A-h>` / `<A-l>`), pin tabs (`<C-p>`), buffer cleaner (`<C-w>`).
  - `🖥️ Terminal` — Multi-terminal drawer (`<C-;>`), terminal slots (`<A-1..9>`), resize keys.
  - `🛠️ Task Runner` — Tasks picker (`<C-S-t>`), default task (`<C-S-a>`), output drawers (`<C-1..4>`).
  - `🚀 Launch & Debug` — Launch profiles (`<C-S-q>`), default runner (`<C-S-s>`), DAP debugging (`<F5>`).
  - `🗂️ Workspaces` — Workspaces UI (`<C-S-w>`), project session persistence.
  - `🧰 Command Palette` — Fuzzy actions (`<C-S-p>`), recent projects (`<C-S-r>`), find files (`<C-S-f>`).
  - `✂️ Editor & Navigation` — Save, clipboard bridge, undo/redo, comment toggling, and code folding.
- **Right Panel (Live Runtime Shortcuts)**:
  - **Zero Hardcoded Keys**: Introspects Neovim's active runtime keymap registry on the fly.
  - **Clean & Filtered**: All `<leader>###` keymaps are suppressed (except `<leader>ee`), focusing on clean chords.
- **Controls**:
  - `j` / `k` / `Down` / `Up`: Navigate topics (live-updates cheatsheet in right panel).
  - `<Tab>` / `<Right>`: Focus reader cheatsheet pane.
  - `<S-Tab>` / `<Left>`: Return focus to left index.
  - `/` or `<C-f>`: Search text within pane.
  - `q` / `<Esc>` / `<F1>`: Dismiss help modal.

---

## ❓ Context Help (`context_help.lua`)

`?` shows a quick notification cheatsheet for **whatever window is currently focused** without opening a modal.

Four contexts, detected from the filetype and buffer name:

| Context | Shows |
| :--- | :--- |
| Neo-tree | create / rename / delete / copy / cut / paste, reveal in system explorer |
| Git (Git Center, Neogit, Diffview) | section jumps, stage/unstage, commit, diff modal, preview scrolling |
| Telescope / file explorer / task runner | create, rename, delete, copy, move, open-as-project, favourite, multi-select |
| Anything else (editor) | find file, split-find, live grep, explorer, task menu, comment, terminals |

---

## 🎨 Live Colorscheme Preview (`colorscheme_preview.lua`)

Themes apply **while you tab through** `:colorscheme <Tab>`, so you pick by looking rather than by name.

It listens on `CmdlineChanged`, matches `^colo%S*%s+(%S+)%s*$`, remembers the original theme the first time it previews, and applies each candidate with `pcall` so an unloadable theme doesn't throw mid-typing. On `CmdlineLeave` it checks `vim.v.event.abort`: `<Esc>` restores what you had, `<Enter>` keeps what you're looking at.

See [Color Palette](color-palette.md) for the palette itself.

---

## 🖼️ Image Viewer (`image_viewer.lua`)

In a Kitty terminal, opening an image automatically shows it using Kitty's native
`icat` graphics, including GIF animation. Videos show a frame preview; PDFs show
the first page. Other binary files show their size and a hex preview of the first
4 KiB. Ordinary text files continue opening in the editor.

Media previews use the full editor window. File details and shortcuts appear in
a brief toast (900 ms). Alt+H/Alt+L cycles media tabs and restores their previews.

For image zoom, use the **mouse wheel**, **Ctrl+wheel**, or **`+` / `-`**.
Pan a zoomed image with **`h/j/k/l`**, arrow keys, or **left-button drag**.
Press **`0`** to reset to fit. Each media tab remembers its view. The image stays visible while the next zoom or
pan frame renders, and while focus moves to Neo-tree. Zoom and pan use
ImageMagick (`magick`); GIFs show a still frame while zoomed, and reset-to-fit
restores animation. Controls apply only to previews, so raw text keeps its normal
editing keys.

Press **`F4`** to toggle between the preview and the original file's byte/text
content. The preview is read-only; switching to bytes loads the full original file
in binary mode. The same action is available through `:MediaPreviewToggle` and
the Command Palette. `:ImageViewer` previews the current media file explicitly.

For video playback, use `:MediaPlay` (or **Play Video in Kitty** in the palette).
It runs mpv with its Kitty graphics output; **`q`** returns to the editor preview.
`<C-S-Enter>` opens the original file in its OS default app from either view.
`:OpenRootInExplorer` opens the project root in the system file manager.

Native previews require Neovim 0.12+, Kitty/`kitten`. Python 3 is used when available to read terminal pixel
geometry via ioctl, without competing for keyboard input. If the TTY or pixel
dimensions are unavailable, previews use Neovim screen dimensions with estimated
cell pixels; image sizing may be less precise. Video frames use
FFmpeg, PDF pages use `pdftoppm`, and playback uses mpv with Kitty output. No tools
are installed automatically. Missing renderers or unsupported formats leave a
readable preview message with the byte-view and external-app actions. Native
previews are enabled only for a direct Kitty TUI, not Neovide, headless sessions,
or tmux. Other terminals retain the Chafa floating preview.

---

## 🔤 Font Sizing (`font_size.lua`)

`<C-+>` / `<C-=>` increases font size, `<C-->` decreases, `<C-0>` resets, and the chosen size is saved to `font_config.json` in `nvim-data` (`stdpath("data")`) so it survives restarts.

Defaults to JetBrainsMono Nerd Font at 14pt, clamped to 6–40. It sets `guifont` and, under Neovide, the scale factor — so it does nothing useful in a plain terminal, where font size belongs to the terminal emulator. `<C-MouseWheel>` also works.

---

## 📦 Nuget Manager (`nuget.lua`)

`:NugetManager` opens a Telescope picker over the `<PackageReference>` entries of the project's `.csproj`: `a` adds a package, `u` updates the selected one, `d` removes it.

Every operation shells out to `dotnet add/remove package` rather than editing the XML, so the `.csproj` stays formatted the way the SDK wants it. If the project has no `.csproj`, it says so and does nothing.

---

## 🐘 PHP Tools Check (`php_tools_modal.lua`)

`:PHPCheckTools` probes for PHP, Composer, Intelephense, Pint and the debug adapter — **on the Windows host and inside WSL** — and shows a floating modal with install steps for whatever is missing.

The dual probe is the point: on Windows it's completely normal to have PHP in WSL and nothing on the host, and "command not found" doesn't tell you which side is empty.

---

## 🐧 WSL Helpers (`wsl.lua`)

Distro detection and path translation, used by anything that needs to know whether a path lives inside `\\wsl.localhost\<Distro>\`:

- the [WSL file explorer](file-explorer.md) (`:TelescopeFileBrowserWSL`)
- the [terminal manager](terminals.md), which launches `wsl.exe -d <Distro> --cd <path>` instead of the Windows shell when the `cwd` is inside a distro
- the dashboard, which only shows the WSL button when `wsl.available()` is true

## Notifications

FoxVim renders notifications locally through `fox.core.notify`. Desktop toasts fade
and slide. Expiring or individually closing a desktop toast slides it out through
the right edge over 250 ms; **Dismiss Notifications** uses the same exit.
Mobile environments use compact static notifications. Toasts queue when
the screen is full and retain their full messages in session history.

**Left-click a notification to copy its full message to the system clipboard and
close that notification.** This copies the clicked message, including text clipped
or wrapped on screen. Keyboard focus stays in your editor. Clipboard copying uses
Neovim's `+` register and its configured provider on Windows or Linux.

Try it in a fresh editor instance:

```vim
:lua vim.notify("Click this notification to copy and close it", vim.log.levels.INFO, { title = "Copy test" })
```

Click the toast, then paste into another application to check the copied text.

The Command Palette provides **Show Notification History**, **Copy Last
Notification**, **Dismiss Notifications**, and **Clear Notification History**.
The equivalent commands are `:Notifications`, `:NotifyCopyLast`, `:NotifyDismiss`
(or `:ClearToasts`), and `:NotificationsClear`. `:Telescope notify` opens the
searchable history picker. History lasts for the current editor session.

Existing `require("notify")` callers use a local compatibility entrypoint. Progress
updates keep the same window and can remain open until completion or cancellation.

## Caps Lock warning

FoxVim shows one warning when Caps Lock stays on for about three seconds while
Neovim is focused. Switching it off starts a new activation; leaving the editor
pauses polling and resets the delay. `:CapsLockCheck` reports the current state
immediately. The delay and polling interval are configured in
`plugins.fox.editor.caps_lock.settings` (`delay_ms` and `poll_interval_ms`).

Windows reads the Win32 keyboard state. Linux reads keyboard LED brightness under
`/sys/class/leds`, including local Wayland, X11 and console sessions, without shell
commands or elevated permissions. Linux requires readable Caps Lock LED entries;
it cannot infer the keyboard state of a remote SSH client. macOS does not yet have
a state backend.
