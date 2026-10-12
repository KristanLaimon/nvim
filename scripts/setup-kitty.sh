#!/usr/bin/env bash
# Pass Ctrl+Shift+1..9 through Kitty to FoxVim.
set -euo pipefail

python3 - <<'PY'
import os
from pathlib import Path
import shutil
import time

config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'kitty/kitty.conf'
text = config.read_text() if config.exists() else ''
maps = ''.join(f'map ctrl+shift+{slot}\n' for slot in range(1, 10))
legacy = '# Pass environment shortcuts through to Neovim instead of focusing Kitty windows.\n' + maps
block = '# >>> FOXVIM KITTY ENVIRONMENTS >>>\n' + maps + '# <<< FOXVIM KITTY ENVIRONMENTS <<<\n'
if block in text:
    print('FoxVim Kitty shortcuts are already set up.')
else:
    updated = text.replace(legacy, '')
    if updated and not updated.endswith('\n'):
        updated += '\n'
    updated += block
    config.parent.mkdir(parents=True, exist_ok=True)
    if config.exists():
        backup = config.with_name(f'kitty.conf.bak.{time.time_ns()}')
        shutil.copy2(config, backup)
        print(f'Backup: {backup}')
    config.write_text(updated)
    print(f'Enabled Ctrl+Shift+1..9 passthrough in {config}')
PY

if command -v pkill >/dev/null && pkill -USR1 -u "$(id -u)" -x kitty; then
    echo 'Reloaded Kitty.'
else
    echo 'Open a new Kitty window or press Ctrl+Shift+F5 to load the config.'
fi
