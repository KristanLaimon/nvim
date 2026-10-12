# FoxVim scripts

Choose one setup/undo pair for terminal shortcuts:

| Target | Setup | Undo |
|---|---|---|
| PowerShell / Windows Terminal | `setup-powershell.ps1` | `unsetup-powershell.ps1` |
| Bash / supported terminal emulators | `setup-bash.sh` | `unsetup-bash.sh` |
| Kitty environment shortcuts | `setup-kitty.sh` | `unsetup-kitty.sh` |

From the Neovim config directory, run `bash scripts/setup-kitty.sh` for Kitty, or `bash scripts/unsetup-kitty.sh` to undo it. The Kitty pair requires Python 3. The Bash pair accepts a terminal name such as `foot` or `alacritty`; use `bash scripts/setup-bash.sh --check` to detect the current terminal without changing config.

These scripts configure terminal shortcuts, not Bash or Fish profiles. Kitty setup enables Ctrl+Shift+1..9 passthrough; the Bash and PowerShell pairs configure a broader set of FoxVim shortcuts.

Other tools live separately:

- `dependencies/install.sh` and `dependencies/install.ps1`: system tool and language runtime installers (previously `setup.sh` and `setup.ps1`). They install packages; there is no automatic uninstall script.
- `extra/setup-terminals.ps1`: the additional PowerShell configurator for multiple terminal emulators (previously `setup-shell.ps1`).
- `omarchy-backup.sh`: export/import Omarchy configuration.
