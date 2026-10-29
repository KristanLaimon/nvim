#!/usr/bin/env bash
# Remove only the configuration added by setup-qutebrowser.sh.
set -euo pipefail

python3 - <<'PY'
import os
import shutil
import time
from pathlib import Path

config = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'qutebrowser/config.py'
text = config.read_bytes().decode('utf-8') if config.exists() else ''
start = '\n# >>> FOXVIM QUTEBROWSER >>>\n'
end = '# <<< FOXVIM QUTEBROWSER <<<\n'
if start.strip() not in text and end.strip() not in text:
    print('No FoxVim qutebrowser configuration found.')
else:
    if text.count(start) != 1 or text.count(end) != 1 or text.index(start) > text.index(end):
        raise SystemExit('Malformed FoxVim block; config.py was not changed.')
    updated = text[:text.index(start)] + text[text.index(end) + len(end):]
    backup = config.with_name(f'config.py.bak.{time.time_ns()}')
    shutil.copy2(config, backup)
    print(f'Backup: {backup}')
    if updated:
        config.write_bytes(updated.encode('utf-8'))
    else:
        config.unlink()
    print(f'Removed FoxVim configuration from {config}')
PY

echo 'Restart qutebrowser to restore the previous configuration.'
