"""Run with: python3 tests/integration/kitty_shortcuts.py (requires Kitty)."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MAPS = ''.join(f'map ctrl+shift+{slot}\n' for slot in range(1, 10))
PREVIOUS = ('# >>> FOXVIM KITTY SHORTCUTS >>>\n' + MAPS
            + 'map ctrl+shift+enter\nmap ctrl+shift+p\n'
            + '# <<< FOXVIM KITTY SHORTCUTS <<<\n')
BASE = 'font_size 12\nmap ctrl+shift+x copy_to_clipboard\n'


class KittyShortcuts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='fox-kitty-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.config = self.root / 'kitty/kitty.conf'
        self.config.parent.mkdir()
        commands = self.root / 'bin'
        commands.mkdir()
        # Test setup/undo without reloading the user's running terminals.
        pkill = commands / 'pkill'
        pkill.write_text('#!/bin/sh\nexit 1\n')
        pkill.chmod(0o755)
        self.environment = dict(os.environ, XDG_CONFIG_HOME=str(self.root),
                                PATH=str(commands) + os.pathsep + os.environ['PATH'])

    def run_script(self, name):
        subprocess.run(['bash', str(ROOT / 'scripts' / name)],
                       env=self.environment, check=True, capture_output=True, text=True)

    def assert_passthrough(self, enabled):
        # Use Kitty's real parser and key selection, including default sequences.
        check = f'''
from kitty.config import load_config
from kitty.keys import Mappings
from kitty.options.utils import parse_shortcut
errors = []
config = load_config({str(self.config)!r}, accumulate_bad_lines=errors)
assert not errors, errors
mappings = Mappings.__new__(Mappings)
mappings.get_active_window = lambda: None
keymap = config.keyboard_modes[''].keymap
selected = mappings.matching_key_actions(keymap[parse_shortcut('ctrl+shift+p')])
assert selected, 'Missing Ctrl+Shift+P mapping'
assert all(not item.is_sequence and not item.definition for item in selected) == {enabled!r}, selected
assert bool(keymap[parse_shortcut('ctrl+shift+x')]), 'Unrelated shortcut was removed'
'''
        subprocess.run(['kitty', '+runpy', check], check=True, capture_output=True, text=True)

    def test_upgrades_old_blocks_and_undo_preserves_other_settings(self):
        older_blocks = [
            PREVIOUS,
            '# >>> FOXVIM KITTY ENVIRONMENTS >>>\n' + MAPS + '# <<< FOXVIM KITTY ENVIRONMENTS <<<\n',
            '# Pass environment shortcuts through to Neovim instead of focusing Kitty windows.\n' + MAPS,
        ]
        for previous in older_blocks:
            with self.subTest(previous=previous.splitlines()[0]):
                self.config.write_text(BASE + previous)
                self.run_script('setup-kitty.sh')
                configured = self.config.read_text()
                self.assertEqual(configured.count('# >>> FOXVIM KITTY'), 1)
                self.assert_passthrough(True)
                self.run_script('setup-kitty.sh')
                self.assertEqual(self.config.read_text(), configured)
                self.config.write_text(configured + 'background_opacity 0.95\n')
                self.run_script('unsetup-kitty.sh')
                self.assertEqual(self.config.read_text(), BASE + 'background_opacity 0.95\n')
                self.assert_passthrough(False)

    def test_undo_also_removes_previous_shortcut_block(self):
        self.config.write_text(BASE + PREVIOUS)
        self.run_script('unsetup-kitty.sh')
        self.assertEqual(self.config.read_text(), BASE)
        self.assert_passthrough(False)

    def test_updates_user_include_without_changing_main_config(self):
        self.config.write_text('include user.conf\n')
        user = self.config.with_name('user.conf')
        user.write_text(BASE)
        self.run_script('setup-kitty.sh')
        self.assertEqual(self.config.read_text(), 'include user.conf\n')
        self.assert_passthrough(True)
        self.run_script('unsetup-kitty.sh')
        self.assertEqual(user.read_text(), BASE)
        self.assert_passthrough(False)


if __name__ == '__main__':
    unittest.main()
