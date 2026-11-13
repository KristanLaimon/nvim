"""Exercise real Qt DevTools with a temporary profile (no user browser changes)."""
import os
import sys
import traceback
sys.excepthook = lambda *args: traceback.print_exception(*args)
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace

with tempfile.TemporaryDirectory(prefix='fox-devtools-') as directory:
    os.environ.update(XDG_CACHE_HOME=directory, XDG_CONFIG_HOME=directory, XDG_DATA_HOME=directory)
    script = Path(__file__).resolve().parents[3] / 'config/scripts/setup-qutebrowser.sh'
    subprocess.run(['bash', str(script)], check=True, capture_output=True)
    from qutebrowser.qt.widgets import QApplication
    from qutebrowser.qt.core import QTimer, qInstallMessageHandler
    qInstallMessageHandler(lambda kind, context, message: print(message, flush=True))
    from qutebrowser.qt.webenginewidgets import QWebEngineView
    app = QApplication(['fox-devtools-test'])
    page, tools = QWebEngineView(), QWebEngineView()
    config = SimpleNamespace(load_autoconfig=lambda: None, bind=lambda *a, **kw: None)
    c = SimpleNamespace(url=SimpleNamespace(searchengines={}))
    namespace = {'config': config, 'c': c, '__name__': 'fox_devtools_test'}
    filename = Path(directory) / 'qutebrowser/config.py'
    exec(compile(filename.read_text(), str(filename), 'exec'), namespace)
    # A config-source reload must also succeed.
    exec(compile(filename.read_text(), str(filename), 'exec'), namespace)
    tab = SimpleNamespace(data=SimpleNamespace(inspector=None))
    def show(position):
        tools.page().setInspectedPage(page.page())
        tools.show()
        tab.data.inspector = SimpleNamespace(_widget=tools, isVisible=tools.isVisible)
    tab.private_api = SimpleNamespace(toggle_inspector=show)
    page.setHtml('<html><body><div id="fox">Test</div></body></html>')
    import json
    state = {'step': 0, 'done': False}
    query = """
    (async () => {
        if (!globalThis.DevToolsAPI) return;
        const UI = await import(new URL('./ui/legacy/legacy.js', location.href).href);
        let e = document.activeElement;
        while (e && e.shadowRoot && e.shadowRoot.activeElement) e = e.shadowRoot.activeElement;
        window.foxTest = JSON.stringify({panel:UI.InspectorView.InspectorView.instance().currentPanelDeprecated()?.name, tag:e?.tagName, placeholder:e?.getAttribute('placeholder'), editable:e?.isContentEditable});
    })().catch(() => {});
    """
    def check():
        tools.page().runJavaScript(query)
        tools.page().runJavaScript('window.foxTest', result)
    def result(value):
        if not value or state['done']:
            return
        current = json.loads(value)
        if state['step'] == 0 and current.get('panel') == 'console':
            assert current['editable'], current
            state['step'] = 1
            namespace['fox_devtools'](tab, 'elements')
        elif state['step'] == 1 and current.get('panel') == 'elements' and current['tag'] == 'INPUT':
            assert current['placeholder'] == 'Find by string, selector, or XPath', current
            state['step'] = 2
            namespace['fox_devtools'](tab, 'console')
        elif state['step'] == 2 and current.get('panel') == 'console':
            state['done'] = True
            print('Console, DOM search, panel switching and config reload OK.', flush=True)
            app.exit(0)
    timer = QTimer()
    timer.timeout.connect(check)
    timer.start(200)
    QTimer.singleShot(15000, lambda: app.exit(1))
    namespace['fox_devtools'](tab, 'console')
    status = app.exec()
    tools.close()
    page.close()
    raise SystemExit(status)
