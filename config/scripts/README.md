# FoxVim scripts

Choose one setup/undo pair for terminal shortcuts:

| Target | Setup | Undo |
|---|---|---|
| PowerShell / Windows Terminal | `setup-powershell.ps1` | `unsetup-powershell.ps1` |
| Bash / supported terminal emulators | `setup-bash.sh` | `unsetup-bash.sh` |
| Kitty shortcuts | `setup-kitty.sh` | `unsetup-kitty.sh` |

From the Neovim config directory, run `bash config/scripts/setup-kitty.sh` for Kitty, or `bash config/scripts/unsetup-kitty.sh` to undo it. The Kitty pair requires Python 3. The Bash pair accepts a terminal name such as `foot` or `alacritty`; use `bash config/scripts/setup-bash.sh --check` to detect the current terminal without changing config.

These scripts configure terminal shortcuts, not Bash or Fish profiles. Kitty setup enables Ctrl+Shift+Enter, Ctrl+Shift+P/A/Q/H/L and Ctrl+Shift+1..9 passthrough; rerun it to upgrade an existing setup. Ctrl+Shift+H/L then reach Neovim instead of opening Kitty scrollback or changing its layout. The Bash and PowerShell pairs configure a broader set of FoxVim shortcuts.

## qutebrowser (Linux)

Requires Bash and Python 3; works independently of the Linux distribution, desktop and terminal. From the Neovim config directory:

```bash
bash config/scripts/setup-qutebrowser.sh
# Undo:
bash config/scripts/unsetup-qutebrowser.sh
```

Restart qutebrowser after either command. The scripts respect `XDG_CONFIG_HOME` (default `~/.config`), back up existing `qutebrowser/config.py` before changes, and add/remove only the marked FoxVim block. Repeating setup does not duplicate it. Undo preserves unrelated settings and subsequent edits outside the block; if nothing remains, it removes `config.py` so qutebrowser resumes loading `autoconfig.yml`. Bookmarks, history and `autoconfig.yml` are untouched. An existing `config.py` keeps its own autoconfig loading policy; fresh configurations load autoconfig before applying our overrides.

| Keys | Action |
|---|---|
| `h/j/k/l`, `gg/G` | Scroll left/down/up/right, top/bottom (normal mode) |
| `/`, `n/N` | Search page, next/previous match (normal mode) |
| `f` | Show link hints (normal mode) |
| `o` | Enter URL or Google search (normal mode) |
| `a` | Open a new tab on Google (normal mode) |
| `Alt+h/l`, `Alt+Left/Right` | Previous/next tab |
| `Ctrl+w` | Close tab |
| `Ctrl+Shift+t` | Restore closed tab |
| `Ctrl+k` | Search open tabs by title or URL; select with Tab/Shift+Tab and Enter |
| `Ctrl+h/l` | Back/forward in the current tab's history |
| `F12` / `Ctrl+Shift+i` | Toggle DevTools docked at the bottom |
| `Ctrl+Alt+o` | Focus DevTools / return to the page |
| `Ctrl+;` | Open and focus the JavaScript console directly |
| `Ctrl+Shift+f` | Open Elements and focus DOM search directly |

The modified-key shortcuts also work in insert mode while typing in forms, reserving those shortcuts for browser actions. Press Escape to return to normal mode before using `/`, motions or hints. Google is the default search engine, start page and new-tab page. Other default qutebrowser bindings remain available. A desktop/window manager shortcut can intercept a key before it reaches qutebrowser.

### Development from the keyboard

Press `Ctrl+;` for the JavaScript console, or `Ctrl+Shift+f` for Elements with DOM search already focused. Both shortcuts open DevTools when needed and select the requested panel even when already open. They work in normal, insert and passthrough modes. `F12` also opens/closes DevTools; `Ctrl+Alt+o` alternates focus with the page. DevTools uses passthrough mode so `Ctrl+l` clears the console instead of navigating the page. `Ctrl+Alt+o` returns to normal mode; `F12` closes DevTools. These focus shortcuts assume docked tools.

- Console: `Ctrl+;` opens the console ready to type JavaScript; Escape toggles the console drawer.
- DOM: `Ctrl+Shift+f` opens search by text, CSS selector or XPath. Use Enter/Shift+Enter for results and arrows to navigate/expand the DOM tree. `Ctrl+f` reopens search within Elements.
- Inspect picker: `Ctrl+Shift+c` toggles element selection; selecting an element on the rendered page uses the pointer. Use the DOM search/tree above for a fully keyboard workflow.
- Source search: DevTools command menu (`Ctrl+Shift+p`) → `Search all files`. `Ctrl+Shift+f` is reserved for DOM search.

The local `:fox-devtools console` / `:fox-devtools elements` command selects panels through the Qt DevTools frontend because qutebrowser only exposes [open/close and focus commands](https://qutebrowser.org/doc/help/commands.html#devtools). Panel selection depends on frontend internals and may need updating after a Qt upgrade. Other [native DevTools shortcuts](https://developer.chrome.com/docs/devtools/shortcuts/) remain available. If the existing browser is still using old bindings, run `:config-source` or restart it. After unsetup, restart to remove the registered local command too.

Optional real-engine regression check (requires qutebrowser and its Qt dependencies):

```bash
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_STYLE_OVERRIDE=Fusion QT_IM_MODULE= \
  python3 config/tests/integration/qutebrowser_devtools_check.py --only-failure
```

## Other tools

Other tools live separately:

- `setup-qutebrowser.sh` / `unsetup-qutebrowser.sh`: apply or remove FoxVim browser shortcuts and Google defaults on Linux (see below).
- `dependencies/install.sh` and `dependencies/install.ps1`: system tool and language runtime installers (previously `setup.sh` and `setup.ps1`). They install packages; there is no automatic uninstall script.
- `extra/setup-terminals.ps1`: the additional PowerShell configurator for multiple terminal emulators (previously `setup-shell.ps1`).
- `omarchy-backup.sh`: export/import Omarchy configuration.

Kitty reserves Ctrl+Shift+Enter for a new window and Ctrl+Shift+P for a shortcut sequence. Run the Kitty setup to pass them to Neovim using its negotiated keyboard protocol. It overrides the Ctrl+Shift+P sequence prefix with `no_op`, so the command palette opens immediately without pressing Space or another key. Rerunning setup upgrades older FoxVim blocks; unsetup also recognizes those older blocks. When `kitty.conf` includes `user.conf` (as Ryoku does), setup writes the overrides there so system updates preserve them. Undo removes only the FoxVim block.

On Windows, rerun `./config/scripts/setup-powershell.ps1` in PowerShell to forward Ctrl+Shift+Enter, Ctrl+Enter (run SQL), Ctrl+Space (completion), and Ctrl+Alt+O (Editor / Query cycle) from Windows Terminal. F3 also cycles Editor / Query directly. Restart Windows Terminal afterward. PowerShell itself does not control shortcuts while Neovim is running. `:OpenWithSystemApp`, `:FoxMode`, and `:CommandPalette` also work without terminal shortcut support.
