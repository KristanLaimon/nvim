# 🖥️ Multi-Terminal Manager (`plugins.fox.dev.terminal`)

[← Back to Wiki Index](index.md)

The **Lazy-Loading Multi-Terminal Manager** manages up to 9 independent terminal buffers with instant switching, split height persistence, and clean window focus navigation.

---

## ⚡ Key Capabilities

1. **9 Independent Buffers**: Switch between terminals 1 through 9 instantly using `<Alt + 1..9>`.
2. **Toggle Key**: Press `<Ctrl + ;>` to toggle open or hidden state for the currently selected terminal.
3. **Floating & Docked Layouts**: Toggle between Docked Split (bottom, default on fresh install) and Floating Overlay ("on top", centered popup or bottom overlay) so the buffers and dashboard above do not resize or shift.
4. **Height & Layout Persistence**: Remembers mouse-dragged split height (`terminal_height`) and layout selection (`terminal_layout`).
5. **WSL Interop**: Automatically spawns terminal in WSL when working inside a WSL filesystem path.

---

## ⌨️ Terminal Shortcuts & Commands

- `<Alt + 1..9>`: Select & switch to terminal #1..9 (Normal, Insert, and Terminal modes)
- `<Ctrl + ;>`: Toggle show/hide for selected terminal
- `<Ctrl + Up>`: Stretch terminal bigger (stretching upwards from top edge in bottom float / docked split; centered expansion in center float)
- `<Ctrl + Down>`: Shrink terminal smaller (anchored at bottom edge in bottom float / docked split; centered shrink in center float)
- `<C-w>` (inside terminal): Standard Neovim window navigation prefix
- `:TerminalToggle`: Toggle show/hide for selected terminal
- `:TerminalToggleLayout`: Toggle between Docked Split and Floating Overlay
- `:TerminalLayout [dock|float|bottom_float]`: Set or switch terminal layout mode
- `:TerminalIncreaseHeight`: Stretch terminal bigger (`<Ctrl+Up>`)
- `:TerminalDecreaseHeight`: Shrink terminal smaller (`<Ctrl+Down>`)
- **Command Palette (`<Ctrl+Shift+P>`)**: Search `Terminal` for instant toggle, layout selection, and resize options

---

## 💾 Global Persistence (State Directory)

Terminal preferences are persisted globally in Neovim's state directory (`stdpath("state")`), preserving your environment across sessions without modifying project `.foxnvim/*.json` files:
- Layout choice: `terminal_layout` (`dock`, `float`, or `bottom_float`)
- Docked height: `terminal_height`
- Bottom floating height: `terminal_bottom_float_height`
- Centered floating height: `terminal_float_height`


## Fastfetch images in Unix terminals

Neovim prepends `scripts/terminal-bin` from this config to its own `PATH` via
`fox.core.terminal_fastfetch`. The bundled `fastfetch` wrapper finds the real
Fastfetch executable through `PATH`; it needs no machine-specific binary path.
Inside Neovim, it uses Fastfetch's Chafa renderer when `--list-features` lists
`chafa`, otherwise it clears the image source and uses the distro's built-in
ASCII logo. Fastfetch must be installed separately; the standalone `chafa`
command is not required. The wrapper does not start Fastfetch automatically.

This covers `:terminal`, Alt + number terminal slots, and shell startup greetings
that invoke `fastfetch` through `PATH` (including `ryoku-fastfetch`). It leaves
Fastfetch's global configuration and terminals launched outside Neovim alone.
Restart Neovim after installing or updating this integration. Keep the wrapper
executable when copying this config to another Unix system. Native Windows and
WSL sessions launched from Windows Neovim are not configured by this integration.
Shell startup files that replace `PATH` must preserve `scripts/terminal-bin` for
the wrapper to be used. Absolute calls to a different Fastfetch binary bypass it.
