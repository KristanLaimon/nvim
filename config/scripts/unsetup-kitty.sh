#!/usr/bin/env bash
# Remove only the FoxVim Kitty shortcut and padding overrides.
set -euo pipefail

python3 - <<'PY'
import os
import re
from pathlib import Path
import shutil
import time

config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'kitty/kitty.conf'
main_text = config.read_text() if config.exists() else ''
# Ryoku loads this dedicated, unshipped override last.
if re.search(r'^\s*(?:globinclude|include)\s+user\.conf\s*$', main_text, re.M):
    config = config.with_name('user.conf')
text = config.read_text() if config.exists() else ''
maps = ''.join(f'map ctrl+shift+{slot}\n' for slot in range(1, 10))
legacy = '# Pass environment shortcuts through to Neovim instead of focusing Kitty windows.\n' + maps
old_block = '# >>> FOXVIM KITTY ENVIRONMENTS >>>\n' + maps + '# <<< FOXVIM KITTY ENVIRONMENTS <<<\n'
# Unmapping preserves Kitty's negotiated keyboard protocol in Neovim.
shortcuts = maps + 'map ctrl+shift+enter\nmap ctrl+shift+p\n'
previous_block = '# >>> FOXVIM KITTY SHORTCUTS >>>\n' + shortcuts + '# <<< FOXVIM KITTY SHORTCUTS <<<\n'
# Override the sequence prefix itself, so Kitty does not wait for another key.
prefix_block = previous_block.replace('map ctrl+shift+p\n', 'map ctrl+shift+p no_op\n')
previous_letters_block = prefix_block.replace('map ctrl+shift+p no_op\n', 'map ctrl+shift+p no_op\nmap ctrl+shift+a no_op\nmap ctrl+shift+q no_op\n')
previous_navigation_block = previous_letters_block.replace('map ctrl+shift+q no_op\n', 'map ctrl+shift+q no_op\nmap ctrl+shift+h no_op\nmap ctrl+shift+l no_op\n')
comment_maps = ''.join(
    f'map ctrl+{shift}{key} send_text all \\x1b[39;{mod}u\n'
    for shift, mod in (('', 5), ('shift+', 6))
    for key in ('apostrophe', 'dead_acute')
)
previous_comment_block = previous_navigation_block.replace('# <<< FOXVIM KITTY SHORTCUTS <<<', comment_maps + '# <<< FOXVIM KITTY SHORTCUTS <<<')
replace_map = 'map ctrl+alt+r send_text all \\x1b[114;7u\n'
block = previous_comment_block.replace('# <<< FOXVIM KITTY SHORTCUTS <<<', replace_map + '# <<< FOXVIM KITTY SHORTCUTS <<<')
previous_replace_block = block
block = block.replace('# <<< FOXVIM KITTY SHORTCUTS <<<', 'allow_remote_control password\nremote_control_password "" set-spacing\n# <<< FOXVIM KITTY SHORTCUTS <<<')
updated = text.replace(block, '').replace(previous_replace_block, '').replace(previous_comment_block, '').replace(previous_navigation_block, '').replace(previous_letters_block, '').replace(prefix_block, '').replace(previous_block, '').replace(old_block, '').replace(legacy, '')
if updated == text:
    print('No FoxVim Kitty shortcut overrides found.')
else:
    backup = config.with_name(f'kitty.conf.bak.{time.time_ns()}')
    shutil.copy2(config, backup)
    config.write_text(updated)
    print(f'Backup: {backup}')
    print(f'Removed FoxVim shortcut overrides from {config}')
PY

if command -v pkill >/dev/null && pkill -USR1 -u "$(id -u)" -x kitty; then
    echo 'Reloaded Kitty.'
else
    echo 'Open a new Kitty window or press Ctrl+Shift+F5 to load the config.'
fi
