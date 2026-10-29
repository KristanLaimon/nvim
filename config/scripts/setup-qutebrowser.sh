#!/usr/bin/env bash
# Add FoxVim keyboard navigation to qutebrowser on Linux.
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
original = text
if start.strip() in text or end.strip() in text:
    if text.count(start) != 1 or text.count(end) != 1 or text.index(start) > text.index(end):
        raise SystemExit('Malformed FoxVim block; config.py was not changed.')
    text = text[:text.index(start)] + text[text.index(end) + len(end):]

block = start
if not text.strip():
    block += 'config.load_autoconfig()\n'
block += '''from qutebrowser.api import cmdutils, apitypes, message
from qutebrowser.misc import objects
from qutebrowser.qt.core import QTimer

# Config reloads must replace our command rather than register it twice.
objects.commands.pop('fox-devtools', None)

@cmdutils.register(name='fox-devtools')
@cmdutils.argument('tab', value=cmdutils.Value.cur_tab)
@cmdutils.argument('panel', choices=['console', 'elements'])
def fox_devtools(tab: apitypes.Tab, panel='console'):
    """Focus the console or open DOM search."""
    inspector = tab.data.inspector
    if inspector is None or not inspector.isVisible():
        tab.private_api.toggle_inspector(apitypes.InspectorPosition.bottom)
    inspector = tab.data.inspector
    # shortcut: qutebrowser exposes no panel API; revisit on Qt DevTools changes.
    view = inspector._widget
    view.setFocus()
    script = """
    (() => {
        if (location.protocol !== 'devtools:') return false;
        const UI = globalThis.foxDevtoolsUI;
        if (!UI) {
            import(new URL('./ui/legacy/legacy.js', location.href).href)
                .then(module => globalThis.foxDevtoolsUI = module).catch(console.error);
            return false;
        }
        try {
            if (!UI.InspectorView.InspectorView.instance().currentPanelDeprecated()) return false;
        } catch {
            return false;
        }
        (async () => {
            await UI.ViewManager.ViewManager.instance().showView('%s');
            if ('%s' === 'elements') {
                UI.InspectorView.InspectorView.instance().currentPanelDeprecated()
                    .searchableView().handleFindShortcut();
            }
        })().catch(console.error);
        return true;
    })()
    """ % (panel, panel)

    def select(attempt=0):
        def ready(ok):
            if ok:
                return
            if attempt < 100:
                QTimer.singleShot(100, lambda: select(attempt + 1))
            else:
                message.error('DevTools did not become ready; try the shortcut again.')
        try:
            view.page().runJavaScript(script, ready)
        except RuntimeError:
            pass  # The tab may have closed while DevTools was loading.
    select()

# Browser shortcuts also work while typing in a form.
for mode in ('normal', 'insert'):
    for key, command in {
        '<Alt-h>': 'tab-prev',
        '<Alt-Left>': 'tab-prev',
        '<Alt-l>': 'tab-next',
        '<Alt-Right>': 'tab-next',
        '<Ctrl-w>': 'tab-close',
        '<Ctrl-Shift-t>': 'undo',
        '<Ctrl-k>': 'cmd-set-text -s :buffer',
        '<Ctrl-h>': 'back',
        '<Ctrl-l>': 'forward',
        '<F12>': 'devtools bottom',
        '<Ctrl-Shift-i>': 'devtools bottom',
        '<Ctrl-Alt-o>': 'devtools-focus ;; mode-enter passthrough',
    }.items():
        config.bind(key, command, mode=mode)

for mode in ('normal', 'insert', 'passthrough'):
    config.bind('<Ctrl-;>', 'fox-devtools console ;; mode-enter passthrough', mode=mode)
    config.bind('<Ctrl-Shift-f>', 'fox-devtools elements ;; mode-enter passthrough', mode=mode)

for key, command in {
    'h': 'scroll left',
    'j': 'scroll down',
    'k': 'scroll up',
    'l': 'scroll right',
    'gg': 'scroll-to-perc 0',
    'G': 'scroll-to-perc',
    '/': 'cmd-set-text /',
    'n': 'search-next',
    'N': 'search-prev',
    'f': 'hint',
    'o': 'cmd-set-text -s :open',
    'a': 'open -t',
}.items():
    config.bind(key, command)

# Let DevTools receive its own editing, console and DOM shortcuts.
config.bind('<Ctrl-Alt-o>', 'devtools-focus ;; mode-enter normal', mode='passthrough')
config.bind('<F12>', 'devtools bottom ;; mode-enter normal', mode='passthrough')
config.bind('<Ctrl-Shift-i>', 'devtools bottom ;; mode-enter normal', mode='passthrough')

c.url.searchengines['DEFAULT'] = 'https://www.google.com/search?q={}'
c.url.start_pages = ['https://www.google.com/']
c.url.default_page = 'https://www.google.com/'
'''
updated = text + block + end
compile(updated, str(config), 'exec')
if updated == original:
    print('FoxVim qutebrowser configuration is already set up.')
else:
    config.parent.mkdir(parents=True, exist_ok=True)
    if config.exists():
        backup = config.with_name(f'config.py.bak.{time.time_ns()}')
        shutil.copy2(config, backup)
        print(f'Backup: {backup}')
    config.write_bytes(updated.encode('utf-8'))
    print(f'Configured {config}')
PY

echo 'Restart qutebrowser to apply the configuration.'
