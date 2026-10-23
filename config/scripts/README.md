# FoxVim scripts

Choose one setup/undo pair for terminal shortcuts:

| Target | Setup | Undo |
|---|---|---|
| PowerShell / Windows Terminal | `setup-powershell.ps1` | `unsetup-powershell.ps1` |
| Bash / supported terminal emulators | `setup-bash.sh` | `unsetup-bash.sh` |
| Kitty shortcuts | `setup-kitty.sh` | `unsetup-kitty.sh` |

From the Neovim config directory, run `bash config/scripts/setup-kitty.sh` for Kitty, or `bash config/scripts/unsetup-kitty.sh` to undo it. The Kitty pair requires Python 3. The Bash pair accepts a terminal name such as `foot` or `alacritty`; use `bash config/scripts/setup-bash.sh --check` to detect the current terminal without changing config.

These scripts configure terminal shortcuts, not Bash or Fish profiles. Kitty setup enables Ctrl+Shift+Enter, Ctrl+Shift+P and Ctrl+Shift+1..9 passthrough; the Bash and PowerShell pairs configure a broader set of FoxVim shortcuts.

Other tools live separately:

- `dependencies/install.sh` and `dependencies/install.ps1`: system tool and language runtime installers (previously `setup.sh` and `setup.ps1`). They install packages; there is no automatic uninstall script.
- `extra/setup-terminals.ps1`: the additional PowerShell configurator for multiple terminal emulators (previously `setup-shell.ps1`).
- `omarchy-backup.sh`: export/import Omarchy configuration.

Kitty reserves Ctrl+Shift+Enter for a new window and Ctrl+Shift+P for a shortcut sequence. Run the Kitty setup to pass them to Neovim using its negotiated keyboard protocol. It overrides the Ctrl+Shift+P sequence prefix with `no_op`, so the command palette opens immediately without pressing Space or another key. Rerunning setup upgrades older FoxVim blocks; unsetup also recognizes those older blocks. When `kitty.conf` includes `user.conf` (as Ryoku does), setup writes the overrides there so system updates preserve them. Undo removes only the FoxVim block.

On Windows, rerun `./config/scripts/setup-powershell.ps1` in PowerShell to forward Ctrl+Shift+Enter, Ctrl+Enter (run SQL), Ctrl+Space (completion), and Ctrl+Alt+O (Editor / Query cycle) from Windows Terminal. F3 also cycles Editor / Query directly. Restart Windows Terminal afterward. PowerShell itself does not control shortcuts while Neovim is running. `:OpenWithSystemApp`, `:FoxMode`, and `:CommandPalette` also work without terminal shortcut support.
